import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:intern_noter/models/daily_log.dart';
import 'package:intern_noter/models/global_config.dart';
import 'package:intern_noter/providers/app_provider.dart';
import 'package:intern_noter/services/backup_service.dart';
import 'package:intern_noter/services/database_helper.dart';
import 'package:intern_noter/services/widget_sync_service.dart';
import 'package:intern_noter/utils/date_formatters.dart';

class FakeWidgetSyncService extends WidgetSyncService {
  int updateCount = 0;
  String? pendingRoute;

  FakeWidgetSyncService({this.pendingRoute});

  @override
  Future<void> updateWidget() async {
    updateCount++;
  }

  @override
  Future<String?> consumePendingRoute() async {
    final route = pendingRoute;
    pendingRoute = null;
    return route;
  }
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<(DatabaseHelper, FakeWidgetSyncService, AppProvider)>
      createTestProvider() async {
    final dir = await Directory.systemTemp.createTemp('intern_noter_prov_test_');
    final helper = DatabaseHelper.forPath(p.join(dir.path, 'intern_noter.db'));
    final fakeSync = FakeWidgetSyncService();
    final provider = AppProvider(
      dbHelper: helper,
      widgetSync: fakeSync,
      autoLoad: false,
    );

    addTearDown(() async {
      provider.dispose();
      await helper.close();
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    });

    await provider.refreshFromDisk();
    return (helper, fakeSync, provider);
  }

  test('quickAddTodayNote creates today log, refreshes state, and notifies widget sync', () async {
    final (_, fakeSync, provider) = await createTestProvider();

    await provider.quickAddTodayNote(
      description: 'Daily Scrum 7E',
      modul: 'Core',
      project: 'EVOQ 7E',
    );

    final todayIso = formatIsoDate(DateTime.now());
    final todayLog = provider.getDailyLogForDate(DateTime.now());
    expect(todayLog, isNotNull);
    expect(normalizeIsoDate(todayLog!.date), todayIso);
    expect(todayLog.lines.length, 1);
    expect(todayLog.lines.first.modul, 'Core');
    expect(todayLog.lines.first.project, 'EVOQ 7E');
    expect(todayLog.lines.first.description, 'Daily Scrum 7E');
    expect(provider.modules, contains('Core'));
    expect(provider.projects, contains('EVOQ 7E'));
    expect(fakeSync.updateCount, 1);
  });

  test('deleteDailyLog returns snapshot and restoreDailyLog brings it back cleanly', () async {
    final (_, fakeSync, provider) = await createTestProvider();

    await provider.addDailyLog(
      DailyLog(
        date: '2026-11-12',
        baseHours: 8.0,
        overworkHours: 1.5,
        lines: [
          ActivityLine(
            modul: 'Payment',
            project: 'EVOQ 7E',
            description: 'Fix webhook retry',
            sortOrder: 0,
          ),
          ActivityLine(
            modul: 'Report',
            project: 'EVOQ 7E',
            description: 'Export verification',
            sortOrder: 1,
          ),
        ],
      ),
    );

    final created = provider.getDailyLogForDate(DateTime(2026, 11, 12));
    expect(created, isNotNull);
    expect(created!.id, isNotNull);
    expect(fakeSync.updateCount, 1);

    final snapshot = await provider.deleteDailyLog(created.id!);
    expect(snapshot, isNotNull);
    expect(snapshot!.overworkHours, 1.5);
    expect(snapshot.lines.length, 2);
    expect(provider.getDailyLogForDate(DateTime(2026, 11, 12)), isNull);
    expect(fakeSync.updateCount, 2);

    await provider.restoreDailyLog(snapshot);
    final restored = provider.getDailyLogForDate(DateTime(2026, 11, 12));
    expect(restored, isNotNull);
    expect(restored!.overworkHours, 1.5);
    expect(restored.lines.map((l) => l.description).toList(), [
      'Fix webhook retry',
      'Export verification',
    ]);
    expect(fakeSync.updateCount, 3);
  });

  test('deleteDailyLog returns null when row is already absent on disk', () async {
    final (helper, _, provider) = await createTestProvider();

    await provider.addDailyLog(
      DailyLog(
        date: '2026-11-13',
        baseHours: 8.0,
        overworkHours: 0.0,
        lines: [
          ActivityLine(
            modul: 'Core',
            project: 'EVOQ 7E',
            description: 'Already deleted on disk',
            sortOrder: 0,
          ),
        ],
      ),
    );

    final created = provider.getDailyLogForDate(DateTime(2026, 11, 13));
    expect(created, isNotNull);
    expect(created!.id, isNotNull);

    final deletedDirectly = await helper.deleteDailyLog(created.id!);
    expect(deletedDirectly, 1);

    final snapshot = await provider.deleteDailyLog(created.id!);
    expect(snapshot, isNull);
    expect(provider.getDailyLogForDate(DateTime(2026, 11, 13)), isNull);
  });

  test('timelineFilter filters by currentCycle and needsTag (uncategorized lines)', () async {
    final (_, _, provider) = await createTestProvider();
    final now = DateTime.now();
    final oldDate = DateTime(now.year, now.month - 3, 10);

    await provider.addDailyLog(
      DailyLog(
        date: formatIsoDate(now),
        baseHours: 8.0,
        overworkHours: 0.0,
        lines: [
          ActivityLine(
            modul: 'Core',
            project: 'EVOQ 7E',
            description: 'Tagged today work',
          ),
        ],
      ),
    );
    await provider.addDailyLog(
      DailyLog(
        date: formatIsoDate(oldDate),
        baseHours: 8.0,
        overworkHours: 0.0,
        lines: [
          ActivityLine(
            modul: '',
            project: '',
            description: 'Uncategorized quick note',
          ),
        ],
      ),
    );

    provider.setTimelineFilter(TimelineFilter.all);
    expect(provider.filteredDailyLogs.length, 2);

    provider.setTimelineFilter(TimelineFilter.currentCycle);
    expect(provider.filteredDailyLogs.length, 1);
    expect(
      provider.filteredDailyLogs.single.lines.single.description,
      'Tagged today work',
    );

    provider.setTimelineFilter(TimelineFilter.needsTag);
    expect(provider.filteredDailyLogs.length, 1);
    expect(
      provider.filteredDailyLogs.single.lines.single.description,
      'Uncategorized quick note',
    );

    provider.setTimelineFilter(TimelineFilter.all);
    provider.setSearchQuery('Tagged');
    expect(provider.filteredDailyLogs.length, 1);
    expect(
      provider.filteredDailyLogs.single.lines.single.description,
      'Tagged today work',
    );
  });

  test('updateGlobalConfig persists themeMode, cutoffDay, includeSignature and triggers widget sync', () async {
    final (helper, fakeSync, provider) = await createTestProvider();

    final updated = GlobalConfig.defaults().copyWith(
      picConsultant: 'Dicky Candra',
      role: 'System & Data Analyst',
      themeMode: 'dark',
      cutoffDay: 20,
      includeSignature: false,
      defaultModul: 'Core',
      defaultProject: '7E',
      quickPresets: ['Stand-Up 7E'],
    );

    await provider.updateGlobalConfig(updated);

    expect(provider.themeMode, ThemeMode.dark);
    expect(provider.globalConfig?.cutoffDay, 20);
    expect(provider.globalConfig?.includeSignature, isFalse);
    expect(provider.globalConfig?.quickPresets, ['Stand-Up 7E']);
    expect(fakeSync.updateCount, 1);

    final persisted = await helper.readGlobalConfig();
    expect(persisted.themeMode, 'dark');
    expect(persisted.cutoffDay, 20);
    expect(persisted.includeSignature, isFalse);
    expect(persisted.defaultModul, 'Core');
    expect(persisted.defaultProject, '7E');
    expect(persisted.quickPresets, ['Stand-Up 7E']);
  });

  test('restoreBackup applies RestoreMode.merge and notifies widget sync', () async {
    final (_, fakeSync, provider) = await createTestProvider();

    final payload = BackupPayload(
      schemaVersion: 3,
      exportedAt: DateTime(2026, 11, 24),
      globalConfig: GlobalConfig.defaults().copyWith(picConsultant: 'Restored PIC'),
      dailyLogs: [
        DailyLog(
          date: '2026-11-18',
          baseHours: 8.0,
          overworkHours: 0.0,
          lines: [
            ActivityLine(
              modul: 'Auth',
              project: 'Portal',
              description: 'SSO check',
              sortOrder: 0,
            ),
          ],
        ),
      ],
    );

    final result = await provider.restoreBackup(payload, RestoreMode.merge);
    expect(result.addedLogs, 1);
    expect(provider.getDailyLogForDate(DateTime(2026, 11, 18)), isNotNull);
    expect(provider.globalConfig?.picConsultant, 'Restored PIC');
    expect(fakeSync.updateCount, 1);
  });

  test('previousCycle, nextCycle, resetCycleToToday, and logsInCycle navigate cutoff windows', () async {
    final (_, _, provider) = await createTestProvider();
    final initial = provider.activeCycle;

    provider.previousCycle();
    final prev = provider.activeCycle;
    expect(prev.end.isBefore(initial.start), isTrue);

    provider.nextCycle();
    expect(provider.activeCycle, initial);

    final midDate = DateTime(prev.end.year, prev.end.month, 10);
    await provider.addDailyLog(
      DailyLog(
        date: formatIsoDate(midDate),
        baseHours: 8.0,
        overworkHours: 0.0,
        lines: [ActivityLine(modul: 'Core', project: '7E', description: 'Prev cycle')],
      ),
    );
    expect(provider.logsInCycle(prev).length, 1);
    expect(provider.logsInCycle(initial), isEmpty);

    provider.previousCycle();
    expect(provider.activeCycle, prev);
    provider.resetCycleToToday();
    expect(provider.activeCycle, initial);
  });

  test('errorMessage captures DB read failures and retryLoad recovers cleanly', () async {
    final dir = await Directory.systemTemp.createTemp('intern_noter_err_test_');
    final flakyDb = _FlakyDbHelper(p.join(dir.path, 'intern_noter.db'));
    final fakeSync = FakeWidgetSyncService();
    final provider = AppProvider(
      dbHelper: flakyDb,
      widgetSync: fakeSync,
      autoLoad: false,
    );
    addTearDown(() async {
      provider.dispose();
      await flakyDb.close();
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    });

    await provider.refreshFromDisk();
    expect(provider.isLoading, isFalse);
    expect(provider.errorMessage, isNotNull);

    flakyDb.shouldFail = false;
    await provider.retryLoad();
    expect(provider.isLoading, isFalse);
    expect(provider.errorMessage, isNull);
  });
}

class _FlakyDbHelper extends DatabaseHelper {
  bool shouldFail = true;

  _FlakyDbHelper(super.dbPath) : super.forPath();

  @override
  Future<List<DailyLog>> readAllDailyLogs() async {
    if (shouldFail) {
      throw StateError('Simulated SQLite read failure');
    }
    return super.readAllDailyLogs();
  }
}
