import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:intern_noter/models/daily_log.dart';
import 'package:intern_noter/models/global_config.dart';
import 'package:intern_noter/services/backup_service.dart';
import 'package:intern_noter/services/database_helper.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<(DatabaseHelper, Directory)> createTempHelper() async {
    final dir = await Directory.systemTemp.createTemp('intern_noter_backup_test_');
    final helper = DatabaseHelper.forPath(p.join(dir.path, 'intern_noter.db'));
    addTearDown(() async {
      await helper.close();
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    });
    return (helper, dir);
  }

  test('encode -> parse -> applyRestore Merge keeps existing dates and adds missing dates', () async {
    final (helper, _) = await createTempHelper();

    await helper.updateGlobalConfig(
      GlobalConfig.defaults().copyWith(
        picConsultant: 'Local PIC',
        role: 'Analyst',
        approvedByName: '',
        includeSignature: true,
      ),
    );
    await helper.createDailyLog(
      DailyLog(
        date: '2026-11-10',
        baseHours: 8.0,
        overworkHours: 2.0,
        lines: [
          ActivityLine(modul: 'Core', project: '7E', description: 'Local kept', sortOrder: 0),
        ],
      ),
    );

    final backupConfig = GlobalConfig.defaults().copyWith(
      picConsultant: 'Backup PIC',
      approvedByName: 'Backup Approver',
      includeSignature: false,
    );
    final backupLogs = [
      DailyLog(
        date: '2026-11-10',
        baseHours: 8.0,
        overworkHours: 0.0,
        lines: [
          ActivityLine(modul: 'Other', project: 'CK', description: 'Should be skipped', sortOrder: 0),
        ],
      ),
      DailyLog(
        date: '2026-11-11',
        baseHours: 8.0,
        overworkHours: 1.0,
        lines: [
          ActivityLine(modul: 'Pay', project: '7E', description: 'Added 1', sortOrder: 0),
          ActivityLine(modul: 'Pay', project: '7E', description: 'Added 2', sortOrder: 1),
        ],
      ),
    ];

    final jsonText = BackupService.encodeBackupJson(
      backupConfig,
      backupLogs,
      exportedAt: DateTime(2026, 11, 24, 13, 45),
    );
    final payload = BackupService.parseAndValidateBackupJson(jsonText);
    expect(payload.schemaVersion, 3);
    expect(payload.dailyLogs.length, 2);

    final result = await BackupService.applyRestore(helper, payload, RestoreMode.merge);
    expect(result.mode, RestoreMode.merge);
    expect(result.addedLogs, 1);
    expect(result.skippedLogs, 1);
    expect(result.totalLogsAfter, 2);

    final existingLog = await helper.readDailyLogByDate('2026-11-10');
    expect(existingLog!.overworkHours, 2.0);
    expect(existingLog.lines.single.description, 'Local kept');

    final addedLog = await helper.readDailyLogByDate('2026-11-11');
    expect(addedLog, isNotNull);
    expect(addedLog!.lines.map((l) => l.description).toList(), ['Added 1', 'Added 2']);
    expect(addedLog.lines.map((l) => l.sortOrder).toList(), [0, 1]);

    final mergedConfig = await helper.readGlobalConfig();
    expect(mergedConfig.picConsultant, 'Local PIC');
    expect(mergedConfig.approvedByName, 'Backup Approver');
  });

  test('encode -> parse -> applyRestore Replace wipes old rows and restores global_config including includeSignature', () async {
    final (helper, _) = await createTempHelper();

    await helper.updateGlobalConfig(
      GlobalConfig.defaults().copyWith(
        picConsultant: 'Old PIC',
        themeMode: 'light',
        cutoffDay: 24,
        includeSignature: true,
      ),
    );
    await helper.createDailyLog(
      DailyLog(
        date: '2026-11-01',
        baseHours: 8.0,
        overworkHours: 0.0,
        lines: [
          ActivityLine(modul: 'Old', project: 'Old', description: 'Old entry', sortOrder: 0),
        ],
      ),
    );

    final backupConfig = GlobalConfig.defaults().copyWith(
      picConsultant: 'Restored PIC',
      role: 'Senior Analyst',
      themeMode: 'dark',
      cutoffDay: 20,
      defaultModul: 'Payment',
      defaultProject: 'EVOQ 7E',
      quickPresets: ['Stand-Up CK'],
      includeSignature: false,
    );
    final backupLogs = [
      DailyLog(
        date: '2026-11-24',
        baseHours: 8.0,
        overworkHours: 1.5,
        lines: [
          ActivityLine(modul: 'Payment', project: 'EVOQ 7E', description: 'Restored line', sortOrder: 0),
        ],
      ),
    ];

    final jsonText = BackupService.encodeBackupJson(backupConfig, backupLogs);
    final payload = BackupService.parseAndValidateBackupJson(jsonText);
    final result = await BackupService.applyRestore(helper, payload, RestoreMode.replace);

    expect(result.mode, RestoreMode.replace);
    expect(result.addedLogs, 1);
    expect(result.skippedLogs, 0);
    expect(result.totalLogsAfter, 1);

    expect(await helper.readDailyLogByDate('2026-11-01'), isNull);
    final restoredLog = await helper.readDailyLogByDate('2026-11-24');
    expect(restoredLog, isNotNull);
    expect(restoredLog!.overworkHours, 1.5);
    expect(restoredLog.lines.single.description, 'Restored line');

    final restoredConfig = await helper.readGlobalConfig();
    expect(restoredConfig.picConsultant, 'Restored PIC');
    expect(restoredConfig.role, 'Senior Analyst');
    expect(restoredConfig.themeMode, 'dark');
    expect(restoredConfig.cutoffDay, 20);
    expect(restoredConfig.defaultModul, 'Payment');
    expect(restoredConfig.defaultProject, 'EVOQ 7E');
    expect(restoredConfig.quickPresets, ['Stand-Up CK']);
    expect(restoredConfig.includeSignature, isFalse);
  });

  test('parseAndValidateBackupJson throws FormatException on invalid date or empty description', () {
    const invalidDateJson = '''
{
  "schema_version": 3,
  "exported_at": "2026-11-24T13:45:00",
  "global_config": { "include_signature": true },
  "daily_logs": [
    {
      "date": "2026-11-24T09:00:00",
      "base_hours": 8.0,
      "overwork_hours": 0.0,
      "lines": [
        { "modul": "Pay", "project": "7E", "description": "Valid", "sort_order": 0 }
      ]
    }
  ]
}
''';
    expect(
      () => BackupService.parseAndValidateBackupJson(invalidDateJson),
      throwsA(isA<FormatException>()),
    );

    const invalidCalendarJson = '''
{
  "schema_version": 3,
  "exported_at": "2026-11-24T13:45:00",
  "global_config": { "include_signature": true },
  "daily_logs": [
    {
      "date": "2026-02-30",
      "base_hours": 8.0,
      "overwork_hours": 0.0,
      "lines": []
    }
  ]
}
''';
    expect(
      () => BackupService.parseAndValidateBackupJson(invalidCalendarJson),
      throwsA(isA<FormatException>()),
    );

    const emptyDescriptionJson = '''
{
  "schema_version": 3,
  "exported_at": "2026-11-24T13:45:00",
  "global_config": { "include_signature": true },
  "daily_logs": [
    {
      "date": "2026-11-24",
      "base_hours": 8.0,
      "overwork_hours": 0.0,
      "lines": [
        { "modul": "Pay", "project": "7E", "description": "   ", "sort_order": 0 }
      ]
    }
  ]
}
''';
    expect(
      () => BackupService.parseAndValidateBackupJson(emptyDescriptionJson),
      throwsA(isA<FormatException>()),
    );

    const badSchemaVersionJson = '''
{
  "schema_version": 4,
  "exported_at": "2026-11-24T13:45:00",
  "global_config": { "include_signature": true },
  "daily_logs": []
}
''';
    expect(
      () => BackupService.parseAndValidateBackupJson(badSchemaVersionJson),
      throwsA(isA<FormatException>()),
    );

    expect(
      () => BackupService.parseAndValidateBackupJson('{not valid json'),
      throwsA(isA<FormatException>()),
    );

    expect(
      () => BackupService.parseAndValidateBackupJson('{"schema_version": 3, "daily_logs": []}'),
      throwsA(isA<FormatException>()),
    );
  });

  test('writeBackupFile writes intern_noter_backup_YYYYMMDD_HHmm.json and round-trips', () async {
    final (_, dir) = await createTempHelper();
    final file = await BackupService.writeBackupFile(
      GlobalConfig.defaults().copyWith(picConsultant: 'Dicky'),
      [
        DailyLog(
          date: '2026-11-24',
          baseHours: 8.0,
          overworkHours: 0.0,
          lines: [
            ActivityLine(modul: 'API', project: '7E', description: 'Sync', sortOrder: 0),
          ],
        ),
      ],
      directory: dir,
      now: DateTime(2026, 11, 24, 9, 5),
    );

    expect(p.basename(file.path), 'intern_noter_backup_20261124_0905.json');
    expect(await file.exists(), isTrue);

    final parsed = BackupService.parseAndValidateBackupJson(await file.readAsString());
    expect(parsed.globalConfig.picConsultant, 'Dicky');
    expect(parsed.dailyLogs.single.lines.single.description, 'Sync');
  });
}
