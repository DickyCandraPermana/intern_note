import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:intern_noter/models/daily_log.dart';
import 'package:intern_noter/models/global_config.dart';
import 'package:intern_noter/services/database_helper.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<String> createTempDbPath() async {
    final dir = await Directory.systemTemp.createTemp('intern_noter_db_test_');
    addTearDown(() async {
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    });
    return p.join(dir.path, 'intern_noter.db');
  }

  Future<void> seedV2Database(
    String dbPath,
    Future<void> Function(Database db) seeder,
  ) async {
    final db = await openDatabase(
      dbPath,
      version: 2,
      onCreate: (db, version) async {
        await db.execute('''
CREATE TABLE daily_logs (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  date TEXT NOT NULL UNIQUE,
  base_hours REAL NOT NULL,
  overwork_hours REAL NOT NULL
)
''');
        await db.execute('''
CREATE TABLE activity_lines (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  daily_log_id INTEGER NOT NULL,
  modul TEXT NOT NULL,
  project TEXT NOT NULL,
  description TEXT NOT NULL,
  FOREIGN KEY (daily_log_id) REFERENCES daily_logs(id) ON DELETE CASCADE
)
''');
        await db.execute('''
CREATE TABLE global_config (
  id INTEGER PRIMARY KEY,
  pic_consultant TEXT NOT NULL,
  role TEXT NOT NULL,
  created_by_name TEXT NOT NULL,
  approved_by_name TEXT NOT NULL,
  approved_by_lead_name TEXT NOT NULL,
  default_base_hours REAL NOT NULL
)
''');
        await db.insert('global_config', {
          'id': 1,
          'pic_consultant': 'Dicky Candra',
          'role': 'System & Data Analyst',
          'created_by_name': 'Dicky Candra',
          'approved_by_name': '',
          'approved_by_lead_name': 'Lead Project',
          'default_base_hours': 8.0,
        });
      },
    );
    await seeder(db);
    await db.close();
  }

  test('v2 to v3 migration deduplicates timestamped same-day logs and preserves zero-line logs', () async {
    final dbPath = await createTempDbPath();

    await seedV2Database(dbPath, (db) async {
      final log1Id = await db.insert('daily_logs', {
        'date': '2026-11-10T09:00:00.000',
        'base_hours': 8.0,
        'overwork_hours': 1.0,
      });
      await db.insert('activity_lines', {
        'daily_log_id': log1Id,
        'modul': 'Payment',
        'project': 'EVOQ 7E',
        'description': 'A',
      });
      await db.insert('activity_lines', {
        'daily_log_id': log1Id,
        'modul': 'Payment',
        'project': 'EVOQ 7E',
        'description': 'B',
      });

      final log2Id = await db.insert('daily_logs', {
        'date': '2026-11-10T18:30:00.000',
        'base_hours': 8.0,
        'overwork_hours': 0.5,
      });
      await db.insert('activity_lines', {
        'daily_log_id': log2Id,
        'modul': 'Report',
        'project': 'CK',
        'description': 'C',
      });

      await db.insert('daily_logs', {
        'date': '2026-11-11T10:00:00.000',
        'base_hours': 8.0,
        'overwork_hours': 0.0,
      });
    });

    final helper = DatabaseHelper.forPath(dbPath);
    addTearDown(helper.close);

    final logs = await helper.readAllDailyLogs();
    expect(logs.length, 2);

    final nov11 = logs[0];
    expect(nov11.date, '2026-11-11');
    expect(nov11.baseHours, 8.0);
    expect(nov11.overworkHours, 0.0);
    expect(nov11.lines, isEmpty);

    final nov10 = logs[1];
    expect(nov10.date, '2026-11-10');
    expect(nov10.baseHours, 8.0);
    expect(nov10.overworkHours, 1.5);
    expect(nov10.lines.map((l) => l.description).toList(), ['A', 'B', 'C']);
    expect(nov10.lines.map((l) => l.sortOrder).toList(), [0, 1, 2]);

    final config = await helper.readGlobalConfig();
    expect(config.picConsultant, 'Dicky Candra');
    expect(config.approvedByLeadName, 'Lead Project');
    expect(config.cutoffDay, 24);
    expect(config.themeMode, 'system');
    expect(config.includeSignature, isTrue);
    expect(config.quickPresets, GlobalConfig.defaultQuickPresets);
  });

  test('v2 to v3 migration deletes duplicates before normalizing canonical date to avoid UNIQUE collision', () async {
    final dbPath = await createTempDbPath();

    await seedV2Database(dbPath, (db) async {
      final firstId = await db.insert('daily_logs', {
        'date': '2026-11-12T08:00:00.000',
        'base_hours': 6.0,
        'overwork_hours': 0.0,
      });
      await db.insert('activity_lines', {
        'daily_log_id': firstId,
        'modul': 'API',
        'project': '7E',
        'description': 'First',
      });

      final secondId = await db.insert('daily_logs', {
        'date': '2026-11-12',
        'base_hours': 8.0,
        'overwork_hours': 1.0,
      });
      await db.insert('activity_lines', {
        'daily_log_id': secondId,
        'modul': 'API',
        'project': '7E',
        'description': 'Second',
      });
    });

    final helper = DatabaseHelper.forPath(dbPath);
    addTearDown(helper.close);

    final logs = await helper.readAllDailyLogs();
    expect(logs.length, 1);
    expect(logs.first.date, '2026-11-12');
    expect(logs.first.baseHours, 8.0);
    expect(logs.first.overworkHours, 1.0);
    expect(logs.first.lines.map((l) => l.description).toList(), ['First', 'Second']);
    expect(logs.first.lines.map((l) => l.sortOrder).toList(), [0, 1]);
  });

  test('onConfigure enables WAL journal mode, foreign keys, busy_timeout, and v3 schema', () async {
    final dbPath = await createTempDbPath();
    final helper = DatabaseHelper.forPath(dbPath);
    addTearDown(helper.close);

    final db = await helper.database;
    final journalRows = await db.rawQuery('PRAGMA journal_mode');
    expect(journalRows.first.values.first.toString().toLowerCase(), 'wal');

    final fkRows = await db.rawQuery('PRAGMA foreign_keys');
    expect(fkRows.first.values.first, 1);

    final timeoutRows = await db.rawQuery('PRAGMA busy_timeout');
    expect(timeoutRows.first.values.first, 3000);

    final versionRows = await db.rawQuery('PRAGMA user_version');
    expect(versionRows.first.values.first, 3);
  });

  test('appendQuickNote creates day log if missing and appends with incrementing sort_order', () async {
    final dbPath = await createTempDbPath();
    final helper = DatabaseHelper.forPath(dbPath);
    addTearDown(helper.close);

    await helper.appendQuickNote(
      isoDate: '2026-11-24',
      description: 'Daily Scrum 7E',
    );
    await helper.appendQuickNote(
      isoDate: '2026-11-24T17:30:00.000',
      description: 'Fix webhook retry',
      modul: 'Payment',
      project: 'EVOQ 7E',
    );

    final logs = await helper.readAllDailyLogs();
    expect(logs.length, 1);

    final log = await helper.readDailyLogByDate('2026-11-24');
    expect(log, isNotNull);
    expect(log!.date, '2026-11-24');
    expect(log.baseHours, 8.0);
    expect(log.overworkHours, 0.0);
    expect(log.lines.length, 2);
    expect(log.lines[0].description, 'Daily Scrum 7E');
    expect(log.lines[0].sortOrder, 0);
    expect(log.lines[1].description, 'Fix webhook retry');
    expect(log.lines[1].modul, 'Payment');
    expect(log.lines[1].project, 'EVOQ 7E');
    expect(log.lines[1].sortOrder, 1);
  });

  test('upsertDailyLog normalizes ISO timestamps and merges instead of throwing UNIQUE', () async {
    final dbPath = await createTempDbPath();
    final helper = DatabaseHelper.forPath(dbPath);
    addTearDown(helper.close);

    await helper.upsertDailyLog(
      DailyLog(
        date: '2026-11-20T09:00:00.000',
        baseHours: 8.0,
        overworkHours: 1.0,
        lines: [
          ActivityLine(modul: 'Auth', project: 'Portal', description: 'SSO setup', sortOrder: 0),
        ],
      ),
      mergeIfExists: true,
    );

    final merged = await helper.upsertDailyLog(
      DailyLog(
        date: '2026-11-20T19:15:00.000',
        baseHours: 8.0,
        overworkHours: 0.5,
        lines: [
          ActivityLine(modul: 'Auth', project: 'Portal', description: 'Deploy hotfix', sortOrder: 0),
        ],
      ),
      mergeIfExists: true,
    );

    expect(merged.date, '2026-11-20');
    expect(merged.baseHours, 8.0);
    expect(merged.overworkHours, 1.5);
    expect(merged.lines.map((l) => l.description).toList(), ['SSO setup', 'Deploy hotfix']);
    expect(merged.lines.map((l) => l.sortOrder).toList(), [0, 1]);

    final replaced = await helper.upsertDailyLog(
      DailyLog(
        date: '2026-11-20T21:00:00.000',
        baseHours: 7.5,
        overworkHours: 0.0,
        lines: [
          ActivityLine(modul: 'Docs', project: 'Portal', description: 'Replaced line', sortOrder: 0),
        ],
      ),
      mergeIfExists: false,
    );

    expect(replaced.baseHours, 7.5);
    expect(replaced.overworkHours, 0.0);
    expect(replaced.lines.map((l) => l.description).toList(), ['Replaced line']);
  });

  test('updateDailyLog, deleteDailyLog, restoreDailyLog, and distinct queries work cleanly', () async {
    final dbPath = await createTempDbPath();
    final helper = DatabaseHelper.forPath(dbPath);
    addTearDown(helper.close);

    final created = await helper.createDailyLog(
      DailyLog(
        date: '2026-11-18T12:00:00.000',
        baseHours: 8.0,
        overworkHours: 1.0,
        lines: [
          ActivityLine(modul: 'Payment', project: 'EVOQ 7E', description: 'First', sortOrder: 0),
          ActivityLine(modul: 'Billing', project: 'CK', description: 'Second', sortOrder: 1),
        ],
      ),
    );
    expect(created.date, '2026-11-18');
    expect(created.id, isNotNull);

    created.lines = [
      created.lines[1].copyWith(sortOrder: 0),
      created.lines[0].copyWith(sortOrder: 1),
    ];
    await helper.updateDailyLog(created);

    final afterUpdate = await helper.readDailyLogByDate('2026-11-18');
    expect(afterUpdate!.lines.map((l) => l.description).toList(), ['Second', 'First']);
    expect(afterUpdate.lines.map((l) => l.sortOrder).toList(), [0, 1]);

    expect(await helper.getDistinctModules(), ['Billing', 'Payment']);
    expect(await helper.getDistinctProjects(), ['CK', 'EVOQ 7E']);

    await helper.deleteDailyLog(afterUpdate.id!);
    expect(await helper.readDailyLogByDate('2026-11-18'), isNull);

    final restored = await helper.restoreDailyLog(afterUpdate);
    expect(restored.date, '2026-11-18');
    expect(restored.lines.map((l) => l.description).toList(), ['Second', 'First']);
    expect(restored.lines.map((l) => l.sortOrder).toList(), [0, 1]);
  });

  test('appendQuickNote rejects blank descriptions', () async {
    final dbPath = await createTempDbPath();
    final helper = DatabaseHelper.forPath(dbPath);
    addTearDown(helper.close);

    expect(
      () => helper.appendQuickNote(isoDate: '2026-11-24', description: '   '),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('v1 to v3 migration preserves v1 activities and upgrades cleanly to v3', () async {
    final dbPath = await createTempDbPath();
    final v1Db = await openDatabase(
      dbPath,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
CREATE TABLE activities (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  date TEXT NOT NULL,
  modul TEXT NOT NULL,
  project TEXT NOT NULL,
  activity TEXT NOT NULL,
  hours REAL NOT NULL
)
''');
        await db.execute('''
CREATE TABLE global_config (
  id INTEGER PRIMARY KEY,
  pic_consultant TEXT NOT NULL,
  role TEXT NOT NULL,
  created_by_name TEXT NOT NULL,
  approved_by_name TEXT NOT NULL
)
''');
        await db.insert('global_config', {
          'id': 1,
          'pic_consultant': 'Dicky V1',
          'role': 'Intern',
          'created_by_name': 'Dicky V1',
          'approved_by_name': '',
        });
        await db.insert('activities', {
          'date': '2026-11-05T09:00:00.000',
          'modul': 'Report',
          'project': 'CK',
          'activity': 'Draft spec',
          'hours': 6.0,
        });
        await db.insert('activities', {
          'date': '2026-11-05T14:00:00.000',
          'modul': 'API',
          'project': '7E',
          'activity': 'Fix query',
          'hours': 4.0,
        });
      },
    );
    await v1Db.close();

    final helper = DatabaseHelper.forPath(dbPath);
    addTearDown(helper.close);

    final logs = await helper.readAllDailyLogs();
    expect(logs.length, 1);
    expect(logs.single.date, '2026-11-05');
    expect(logs.single.baseHours, 8.0);
    expect(logs.single.overworkHours, 2.0);
    expect(logs.single.lines.map((l) => l.description).toList(), ['Draft spec', 'Fix query']);
    expect(logs.single.lines.map((l) => l.sortOrder).toList(), [0, 1]);

    final config = await helper.readGlobalConfig();
    expect(config.picConsultant, 'Dicky V1');
    expect(config.defaultBaseHours, 8.0);
    expect(config.cutoffDay, 24);
    expect(config.includeSignature, isTrue);
  });
}
