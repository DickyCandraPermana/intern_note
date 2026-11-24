import 'dart:math' as math;
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import '../models/daily_log.dart';
import '../models/global_config.dart';
import '../utils/date_formatters.dart';

class BackupMergeCounts {
  final int addedLogs;
  final int skippedLogs;

  const BackupMergeCounts({
    required this.addedLogs,
    required this.skippedLogs,
  });
}

class DatabaseHelper {
  static const int databaseVersion = 3;
  static const String databaseFileName = 'intern_noter.db';

  static final DatabaseHelper instance = DatabaseHelper._init();

  final String? _customPath;
  Database? _database;
  Future<Database>? _initFuture;

  DatabaseHelper._init() : _customPath = null;

  DatabaseHelper.forPath(String dbPath) : _customPath = dbPath;

  Future<Database> get database async {
    final existing = _database;
    if (existing != null && existing.isOpen) {
      return existing;
    }
    _initFuture ??= _initDB();
    try {
      _database = await _initFuture!;
      return _database!;
    } finally {
      _initFuture = null;
    }
  }

  Future<Database> _initDB() async {
    final String path;
    if (_customPath != null) {
      path = _customPath;
    } else {
      final dbPath = await getDatabasesPath();
      path = join(dbPath, databaseFileName);
    }

    return openDatabase(
      path,
      version: databaseVersion,
      onConfigure: _onConfigure,
      onCreate: _createDB,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onConfigure(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON');
    await db.rawQuery('PRAGMA journal_mode = WAL');
    await db.rawQuery('PRAGMA busy_timeout = 3000');
  }

  Future<void> _createDB(Database db, int version) async {
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
  sort_order INTEGER NOT NULL DEFAULT 0,
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
  default_base_hours REAL NOT NULL,
  theme_mode TEXT NOT NULL DEFAULT 'system',
  cutoff_day INTEGER NOT NULL DEFAULT 24,
  default_modul TEXT NOT NULL DEFAULT '',
  default_project TEXT NOT NULL DEFAULT '',
  quick_presets TEXT NOT NULL DEFAULT '["Daily Scrum 7E","Join Daily Stand-Up CK"]',
  include_signature INTEGER NOT NULL DEFAULT 1
)
''');

    await db.insert('global_config', GlobalConfig.defaults().toMap());
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Create new tables
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

      // Migrate existing data
      final oldActivities = await db.query('activities');
      Map<String, List<Map<String, dynamic>>> grouped = {};
      for (var a in oldActivities) {
        String dateStr = (a['date'] as String).substring(0, 10);
        if (!grouped.containsKey(dateStr)) {
          grouped[dateStr] = [];
        }
        grouped[dateStr]!.add(a);
      }

      for (var dateStr in grouped.keys) {
        final group = grouped[dateStr]!;
        double totalHours = 0;
        for (var a in group) {
          totalHours += (a['hours'] is int) ? (a['hours'] as int).toDouble() : (a['hours'] as double);
        }
        
        double base = totalHours > 8.0 ? 8.0 : totalHours;
        double over = totalHours > 8.0 ? totalHours - 8.0 : 0.0;
        
        int logId = await db.insert('daily_logs', {
          'date': dateStr,
          'base_hours': base,
          'overwork_hours': over,
        });

        for (var a in group) {
          await db.insert('activity_lines', {
            'daily_log_id': logId,
            'modul': a['modul'],
            'project': a['project'],
            'description': a['activity'],
          });
        }
      }

      // Add new columns to global_config
      await db.execute("ALTER TABLE global_config ADD COLUMN approved_by_lead_name TEXT DEFAULT ''");
      await db.execute("ALTER TABLE global_config ADD COLUMN default_base_hours REAL DEFAULT 8.0");
      
      // Rename old table so we don't lose data in case of issues
      await db.execute("ALTER TABLE activities RENAME TO old_activities");
    }

    if (oldVersion < 3) {
      await db.execute(
        'ALTER TABLE activity_lines ADD COLUMN sort_order INTEGER NOT NULL DEFAULT 0',
      );

      await db.execute(
        "ALTER TABLE global_config ADD COLUMN theme_mode TEXT NOT NULL DEFAULT 'system'",
      );
      await db.execute(
        'ALTER TABLE global_config ADD COLUMN cutoff_day INTEGER NOT NULL DEFAULT 24',
      );
      await db.execute(
        "ALTER TABLE global_config ADD COLUMN default_modul TEXT NOT NULL DEFAULT ''",
      );
      await db.execute(
        "ALTER TABLE global_config ADD COLUMN default_project TEXT NOT NULL DEFAULT ''",
      );
      await db.execute(
        'ALTER TABLE global_config ADD COLUMN quick_presets TEXT NOT NULL DEFAULT \'["Daily Scrum 7E","Join Daily Stand-Up CK"]\'',
      );
      await db.execute(
        'ALTER TABLE global_config ADD COLUMN include_signature INTEGER NOT NULL DEFAULT 1',
      );

      final configCount = Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM global_config WHERE id = 1'),
          ) ??
          0;
      if (configCount == 0) {
        await db.insert('global_config', GlobalConfig.defaults().toMap());
      }

      // Deduplicate same-day logs created from ISO timestamps and delete duplicates
      // before normalizing the canonical date to avoid UNIQUE constraint violations.
      final rawLogs = await db.query('daily_logs', orderBy: 'id ASC');
      final Map<String, List<Map<String, dynamic>>> groupedLogs = {};
      for (final row in rawLogs) {
        final rawDate = (row['date'] ?? '').toString();
        final normalizedDate = normalizeIsoDate(rawDate);
        groupedLogs.putIfAbsent(normalizedDate, () => []).add(row);
      }

      for (final entry in groupedLogs.entries) {
        final normalizedDate = entry.key;
        final group = entry.value;
        final canonical = group.first;
        final canonicalId = canonical['id'] as int;

        double maxBaseHours =
            (canonical['base_hours'] as num?)?.toDouble() ?? 8.0;
        double sumOverworkHours =
            (canonical['overwork_hours'] as num?)?.toDouble() ?? 0.0;

        for (int i = 1; i < group.length; i++) {
          final duplicate = group[i];
          final dupId = duplicate['id'] as int;
          final dupBase = (duplicate['base_hours'] as num?)?.toDouble() ?? 0.0;
          final dupOverwork =
              (duplicate['overwork_hours'] as num?)?.toDouble() ?? 0.0;
          maxBaseHours = math.max(maxBaseHours, dupBase);
          sumOverworkHours += dupOverwork;

          await db.update(
            'activity_lines',
            {'daily_log_id': canonicalId},
            where: 'daily_log_id = ?',
            whereArgs: [dupId],
          );
          await db.delete(
            'daily_logs',
            where: 'id = ?',
            whereArgs: [dupId],
          );
        }

        final canonicalRawDate = (canonical['date'] ?? '').toString();
        if (group.length > 1 || canonicalRawDate != normalizedDate) {
          await db.update(
            'daily_logs',
            {
              'date': normalizedDate,
              'base_hours': maxBaseHours,
              'overwork_hours': sumOverworkHours,
            },
            where: 'id = ?',
            whereArgs: [canonicalId],
          );
        }
      }

      // Re-index sort_order per surviving daily_log_id ordered by insertion id.
      final allLines = await db.query(
        'activity_lines',
        columns: ['id', 'daily_log_id'],
        orderBy: 'daily_log_id ASC, id ASC',
      );
      final Map<int, int> nextOrderByLog = {};
      for (final line in allLines) {
        final lineId = line['id'] as int;
        final logId = line['daily_log_id'] as int;
        final order = nextOrderByLog[logId] ?? 0;
        nextOrderByLog[logId] = order + 1;
        await db.update(
          'activity_lines',
          {'sort_order': order},
          where: 'id = ?',
          whereArgs: [lineId],
        );
      }
    }
  }

  Future<List<ActivityLine>> _insertLinesInTxn(
    DatabaseExecutor db,
    int logId,
    List<ActivityLine> lines, {
    int? appendFromOrder,
  }) async {
    final useSequentialFromZero =
        appendFromOrder == null &&
        lines.length > 1 &&
        lines.every((l) => l.sortOrder == 0);
    final inserted = <ActivityLine>[];
    int nextOrder = appendFromOrder ?? 0;

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      final int resolvedOrder;
      if (appendFromOrder != null) {
        resolvedOrder = nextOrder++;
      } else if (useSequentialFromZero) {
        resolvedOrder = i;
      } else {
        resolvedOrder = line.sortOrder;
      }

      final lineId = await db.insert('activity_lines', {
        'daily_log_id': logId,
        'modul': line.modul,
        'project': line.project,
        'description': line.description,
        'sort_order': resolvedOrder,
      });

      line.dailyLogId = logId;
      line.id = lineId;
      line.sortOrder = resolvedOrder;

      inserted.add(
        ActivityLine(
          id: lineId,
          dailyLogId: logId,
          modul: line.modul,
          project: line.project,
          description: line.description,
          sortOrder: resolvedOrder,
        ),
      );
    }

    return inserted;
  }

  Future<DailyLog?> _readLogById(DatabaseExecutor db, int logId) async {
    final logMaps = await db.query(
      'daily_logs',
      where: 'id = ?',
      whereArgs: [logId],
      limit: 1,
    );
    if (logMaps.isEmpty) return null;

    final lineMaps = await db.query(
      'activity_lines',
      where: 'daily_log_id = ?',
      whereArgs: [logId],
      orderBy: 'sort_order ASC, id ASC',
    );
    final log = DailyLog.fromMap(logMaps.first);
    log.lines = lineMaps.map((m) => ActivityLine.fromMap(m)).toList();
    return log;
  }

  Future<DailyLog> _upsertInTxn(
    DatabaseExecutor txn,
    DailyLog log, {
    required bool mergeIfExists,
  }) async {
    final normalizedDate = normalizeIsoDate(log.date);
    final existingRows = await txn.query(
      'daily_logs',
      where: 'date = ?',
      whereArgs: [normalizedDate],
      limit: 1,
    );

    if (existingRows.isEmpty) {
      final logId = await txn.insert('daily_logs', {
        'date': normalizedDate,
        'base_hours': log.baseHours,
        'overwork_hours': log.overworkHours,
      });
      await _insertLinesInTxn(txn, logId, log.lines);
      return (await _readLogById(txn, logId))!;
    }

    final existing = existingRows.first;
    final existingId = existing['id'] as int;

    if (!mergeIfExists) {
      await txn.update(
        'daily_logs',
        {
          'base_hours': log.baseHours,
          'overwork_hours': log.overworkHours,
        },
        where: 'id = ?',
        whereArgs: [existingId],
      );
      await txn.delete(
        'activity_lines',
        where: 'daily_log_id = ?',
        whereArgs: [existingId],
      );
      await _insertLinesInTxn(txn, existingId, log.lines);
      return (await _readLogById(txn, existingId))!;
    }

    final existingBase = (existing['base_hours'] as num?)?.toDouble() ?? 8.0;
    final existingOverwork =
        (existing['overwork_hours'] as num?)?.toDouble() ?? 0.0;
    await txn.update(
      'daily_logs',
      {
        'base_hours': math.max(existingBase, log.baseHours),
        'overwork_hours': existingOverwork + log.overworkHours,
      },
      where: 'id = ?',
      whereArgs: [existingId],
    );

    final maxSortRows = await txn.rawQuery(
      'SELECT COALESCE(MAX(sort_order), -1) AS max_order FROM activity_lines WHERE daily_log_id = ?',
      [existingId],
    );
    final nextOrder =
        ((maxSortRows.first['max_order'] as num?)?.toInt() ?? -1) + 1;
    await _insertLinesInTxn(
      txn,
      existingId,
      log.lines,
      appendFromOrder: nextOrder,
    );
    return (await _readLogById(txn, existingId))!;
  }

  Future<DailyLog> createDailyLog(DailyLog log) async {
    final db = await database;
    final normalizedDate = normalizeIsoDate(log.date);
    return db.transaction((txn) async {
      final logId = await txn.insert('daily_logs', {
        'date': normalizedDate,
        'base_hours': log.baseHours,
        'overwork_hours': log.overworkHours,
      });
      log.id = logId;
      log.date = normalizedDate;
      log.lines = await _insertLinesInTxn(txn, logId, log.lines);
      return (await _readLogById(txn, logId))!;
    });
  }

  Future<DailyLog> upsertDailyLog(
    DailyLog log, {
    bool mergeIfExists = false,
  }) async {
    final db = await database;
    return db.transaction(
      (txn) => _upsertInTxn(txn, log, mergeIfExists: mergeIfExists),
    );
  }

  Future<DailyLog> appendQuickNote({
    required String isoDate,
    required String description,
    String modul = '',
    String project = '',
    double? defaultBaseHours,
  }) async {
    final trimmedDescription = description.trim();
    if (trimmedDescription.isEmpty) {
      throw ArgumentError.value(
        description,
        'description',
        'Quick note description cannot be empty.',
      );
    }

    final db = await database;
    final normalizedDate = normalizeIsoDate(isoDate);

    return db.transaction((txn) async {
      final existingRows = await txn.query(
        'daily_logs',
        columns: ['id'],
        where: 'date = ?',
        whereArgs: [normalizedDate],
        limit: 1,
      );

      final int logId;
      if (existingRows.isNotEmpty) {
        logId = existingRows.first['id'] as int;
      } else {
        double resolvedBaseHours = defaultBaseHours ?? 8.0;
        if (defaultBaseHours == null) {
          final cfgRows = await txn.query(
            'global_config',
            columns: ['default_base_hours'],
            where: 'id = ?',
            whereArgs: [1],
            limit: 1,
          );
          if (cfgRows.isNotEmpty) {
            resolvedBaseHours =
                (cfgRows.first['default_base_hours'] as num?)?.toDouble() ??
                8.0;
          }
        }
        logId = await txn.insert('daily_logs', {
          'date': normalizedDate,
          'base_hours': resolvedBaseHours,
          'overwork_hours': 0.0,
        });
      }

      final maxSortRows = await txn.rawQuery(
        'SELECT COALESCE(MAX(sort_order), -1) AS max_order FROM activity_lines WHERE daily_log_id = ?',
        [logId],
      );
      final nextOrder =
          ((maxSortRows.first['max_order'] as num?)?.toInt() ?? -1) + 1;

      await txn.insert('activity_lines', {
        'daily_log_id': logId,
        'modul': modul.trim(),
        'project': project.trim(),
        'description': trimmedDescription,
        'sort_order': nextOrder,
      });

      return (await _readLogById(txn, logId))!;
    });
  }

  Future<List<DailyLog>> readAllDailyLogs() async {
    final db = await database;
    final logMaps = await db.query('daily_logs', orderBy: 'date DESC');
    if (logMaps.isEmpty) return [];

    final lineMaps = await db.query(
      'activity_lines',
      orderBy: 'daily_log_id ASC, sort_order ASC, id ASC',
    );
    final Map<int, List<ActivityLine>> linesByLogId = {};
    for (final m in lineMaps) {
      final line = ActivityLine.fromMap(m);
      final logId = line.dailyLogId;
      if (logId != null) {
        linesByLogId.putIfAbsent(logId, () => []).add(line);
      }
    }

    return logMaps.map((map) {
      final log = DailyLog.fromMap(map);
      log.lines = linesByLogId[log.id] ?? <ActivityLine>[];
      return log;
    }).toList();
  }

  Future<DailyLog?> readDailyLogByDate(String isoDate) async {
    final db = await database;
    final normalizedDate = normalizeIsoDate(isoDate);
    final logMaps = await db.query(
      'daily_logs',
      where: 'date = ?',
      whereArgs: [normalizedDate],
      limit: 1,
    );
    if (logMaps.isEmpty) return null;

    final log = DailyLog.fromMap(logMaps.first);
    final lineMaps = await db.query(
      'activity_lines',
      where: 'daily_log_id = ?',
      whereArgs: [log.id],
      orderBy: 'sort_order ASC, id ASC',
    );
    log.lines = lineMaps.map((m) => ActivityLine.fromMap(m)).toList();
    return log;
  }

  Future<int> updateDailyLog(DailyLog log) async {
    final logId = log.id;
    if (logId == null) return 0;

    final db = await database;
    final normalizedDate = normalizeIsoDate(log.date);
    return db.transaction((txn) async {
      final count = await txn.update(
        'daily_logs',
        {
          'date': normalizedDate,
          'base_hours': log.baseHours,
          'overwork_hours': log.overworkHours,
        },
        where: 'id = ?',
        whereArgs: [logId],
      );
      if (count == 0) return 0;

      log.date = normalizedDate;
      await txn.delete(
        'activity_lines',
        where: 'daily_log_id = ?',
        whereArgs: [logId],
      );
      log.lines = await _insertLinesInTxn(txn, logId, log.lines);
      return count;
    });
  }

  Future<int> deleteDailyLog(int id) async {
    final db = await database;
    return db.transaction((txn) async {
      await txn.delete(
        'activity_lines',
        where: 'daily_log_id = ?',
        whereArgs: [id],
      );
      return txn.delete(
        'daily_logs',
        where: 'id = ?',
        whereArgs: [id],
      );
    });
  }

  Future<DailyLog> restoreDailyLog(DailyLog log) async {
    return upsertDailyLog(log, mergeIfExists: true);
  }

  Future<List<String>> getDistinctModules() async {
    final db = await database;
    final result = await db.rawQuery(
      "SELECT DISTINCT modul FROM activity_lines WHERE TRIM(modul) != '' ORDER BY modul ASC",
    );
    return result.map((row) => row['modul'] as String).toList();
  }

  Future<List<String>> getDistinctProjects() async {
    final db = await database;
    final result = await db.rawQuery(
      "SELECT DISTINCT project FROM activity_lines WHERE TRIM(project) != '' ORDER BY project ASC",
    );
    return result.map((row) => row['project'] as String).toList();
  }

  Future<GlobalConfig> readGlobalConfig() async {
    final db = await database;
    final maps = await db.query(
      'global_config',
      where: 'id = ?',
      whereArgs: [1],
      limit: 1,
    );
    if (maps.isNotEmpty) {
      return GlobalConfig.fromMap(maps.first);
    }
    return GlobalConfig.defaults();
  }

  Future<int> _writeGlobalConfigInTxn(
    DatabaseExecutor db,
    GlobalConfig config,
  ) async {
    final map = config.toMap()..['id'] = 1;
    final count = await db.update(
      'global_config',
      map,
      where: 'id = ?',
      whereArgs: [1],
    );
    if (count == 0) {
      await db.insert('global_config', map);
      return 1;
    }
    return count;
  }

  Future<int> updateGlobalConfig(GlobalConfig config) async {
    final db = await database;
    return _writeGlobalConfigInTxn(db, config);
  }

  Future<void> replaceAllData(GlobalConfig config, List<DailyLog> logs) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('activity_lines');
      await txn.delete('daily_logs');
      await _writeGlobalConfigInTxn(txn, config);

      for (final log in logs) {
        await _upsertInTxn(txn, log, mergeIfExists: true);
      }
    });
  }

  Future<BackupMergeCounts> mergeBackupData(
    GlobalConfig config,
    List<DailyLog> logs,
  ) async {
    final db = await database;
    return db.transaction((txn) async {
      final existingRows = await txn.query('daily_logs', columns: ['date']);
      final existingDates = existingRows
          .map((row) => normalizeIsoDate((row['date'] ?? '').toString()))
          .toSet();

      int addedLogs = 0;
      int skippedLogs = 0;

      for (final log in logs) {
        final normalizedDate = normalizeIsoDate(log.date);
        if (existingDates.contains(normalizedDate)) {
          skippedLogs++;
          continue;
        }
        await _upsertInTxn(txn, log, mergeIfExists: false);
        existingDates.add(normalizedDate);
        addedLogs++;
      }

      final configRows = await txn.query(
        'global_config',
        where: 'id = ?',
        whereArgs: [1],
        limit: 1,
      );
      if (configRows.isEmpty) {
        await txn.insert('global_config', config.toMap()..['id'] = 1);
      } else {
        final current = GlobalConfig.fromMap(configRows.first);
        final merged = GlobalConfig(
          id: 1,
          picConsultant: current.picConsultant.trim().isNotEmpty
              ? current.picConsultant
              : config.picConsultant,
          role: current.role.trim().isNotEmpty ? current.role : config.role,
          createdByName: current.createdByName.trim().isNotEmpty
              ? current.createdByName
              : config.createdByName,
          approvedByName: current.approvedByName.trim().isNotEmpty
              ? current.approvedByName
              : config.approvedByName,
          approvedByLeadName: current.approvedByLeadName.trim().isNotEmpty
              ? current.approvedByLeadName
              : config.approvedByLeadName,
          defaultBaseHours: current.defaultBaseHours > 0
              ? current.defaultBaseHours
              : config.defaultBaseHours,
          themeMode: current.themeMode,
          cutoffDay: current.cutoffDay,
          defaultModul: current.defaultModul.trim().isNotEmpty
              ? current.defaultModul
              : config.defaultModul,
          defaultProject: current.defaultProject.trim().isNotEmpty
              ? current.defaultProject
              : config.defaultProject,
          quickPresets: current.quickPresets.isNotEmpty
              ? current.quickPresets
              : config.quickPresets,
          includeSignature: current.includeSignature,
        );
        await txn.update(
          'global_config',
          merged.toMap()..['id'] = 1,
          where: 'id = ?',
          whereArgs: [1],
        );
      }

      return BackupMergeCounts(addedLogs: addedLogs, skippedLogs: skippedLogs);
    });
  }

  Future<void> close() async {
    final db = _database;
    _database = null;
    _initFuture = null;
    if (db != null && db.isOpen) {
      await db.close();
    }
  }
}
