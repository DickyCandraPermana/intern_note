import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:intern_noter/models/daily_log.dart';
import 'package:intern_noter/models/global_config.dart';
import 'package:intern_noter/providers/app_provider.dart';
import 'package:intern_noter/screens/main_screen.dart';
import 'package:intern_noter/screens/tabs/settings_tab.dart';
import 'package:intern_noter/services/backup_service.dart';
import 'package:intern_noter/services/database_helper.dart';
import 'package:intern_noter/services/widget_sync_service.dart';
import 'package:intern_noter/theme/app_theme.dart';
import 'package:intern_noter/utils/date_formatters.dart';
import 'package:intern_noter/widgets/daily_log_sheet.dart';

class _FakeWidgetSync extends WidgetSyncService {
  String? pendingRoute;
  int updateCount = 0;

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

class _InMemoryDbHelper extends DatabaseHelper {
  GlobalConfig _config;
  final List<DailyLog> _logs = [];
  int _nextId = 1;
  Duration readDelay = Duration.zero;

  _InMemoryDbHelper({GlobalConfig? initialConfig})
      : _config = initialConfig ?? GlobalConfig.defaults(),
        super.forPath(':memory:');

  @override
  Future<List<DailyLog>> readAllDailyLogs() async {
    if (readDelay > Duration.zero) {
      await Future<void>.delayed(readDelay);
    }
    return _logs
        .map(
          (log) => log.copyWith(
            lines: log.lines.map((line) => line.copyWith()).toList(),
          ),
        )
        .toList();
  }

  @override
  Future<GlobalConfig> readGlobalConfig() async {
    return _config.copyWith();
  }

  bool failConfigWrite = false;

  @override
  Future<int> updateGlobalConfig(GlobalConfig config) async {
    if (failConfigWrite) {
      throw StateError('Simulated config write failure');
    }
    _config = config.copyWith();
    return 1;
  }

  @override
  Future<List<String>> getDistinctModules() async {
    return _logs
        .expand((l) => l.lines)
        .map((l) => l.modul.trim())
        .where((m) => m.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
  }

  @override
  Future<List<String>> getDistinctProjects() async {
    return _logs
        .expand((l) => l.lines)
        .map((l) => l.project.trim())
        .where((p) => p.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
  }

  @override
  Future<DailyLog> appendQuickNote({
    required String isoDate,
    required String description,
    String modul = '',
    String project = '',
    double? defaultBaseHours,
  }) async {
    final normalized = normalizeIsoDate(isoDate);
    final idx = _logs.indexWhere((l) => normalizeIsoDate(l.date) == normalized);
    if (idx >= 0) {
      final existing = _logs[idx];
      final nextOrder = existing.lines.length;
      final updated = existing.copyWith(
        lines: [
          ...existing.lines,
          ActivityLine(
            id: _nextId++,
            dailyLogId: existing.id,
            modul: modul.trim(),
            project: project.trim(),
            description: description.trim(),
            sortOrder: nextOrder,
          ),
        ],
      );
      _logs[idx] = updated;
      return updated;
    }

    final logId = _nextId++;
    final created = DailyLog(
      id: logId,
      date: normalized,
      baseHours: defaultBaseHours ?? _config.defaultBaseHours,
      overworkHours: 0.0,
      lines: [
        ActivityLine(
          id: _nextId++,
          dailyLogId: logId,
          modul: modul.trim(),
          project: project.trim(),
          description: description.trim(),
          sortOrder: 0,
        ),
      ],
    );
    _logs.add(created);
    return created;
  }

  @override
  Future<void> replaceAllData(GlobalConfig config, List<DailyLog> logs) async {
    _config = config.copyWith();
    _logs
      ..clear()
      ..addAll(
        logs.map(
          (l) => l.copyWith(
            id: l.id ?? _nextId++,
            lines: l.lines.map((line) => line.copyWith()).toList(),
          ),
        ),
      );
  }

  @override
  Future<BackupMergeCounts> mergeBackupData(
    GlobalConfig config,
    List<DailyLog> logs,
  ) async {
    return const BackupMergeCounts(addedLogs: 0, skippedLogs: 0);
  }

  @override
  Future<void> close() async {}
}

void main() {
  Future<(_InMemoryDbHelper, _FakeWidgetSync, AppProvider)> createHarness({
    GlobalConfig? initialConfig,
  }) async {
    final helper = _InMemoryDbHelper(initialConfig: initialConfig);
    final fakeSync = _FakeWidgetSync();
    final provider = AppProvider(
      dbHelper: helper,
      widgetSync: fakeSync,
      autoLoad: false,
    );
    await provider.refreshFromDisk();
    return (helper, fakeSync, provider);
  }

  testWidgets(
    'SettingsTab updates controllers cleanly without build-phase setState exception',
    (WidgetTester tester) async {
      final (_, _, provider) = await createHarness(
        initialConfig: GlobalConfig.defaults().copyWith(
          picConsultant: 'Initial PIC',
          defaultBaseHours: 8.0,
        ),
      );
      addTearDown(provider.dispose);

      await tester.pumpWidget(
        ChangeNotifierProvider<AppProvider>.value(
          value: provider,
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const SettingsTab(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('PIC Consultant'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      expect(
        find.widgetWithText(TextFormField, 'Initial PIC'),
        findsOneWidget,
      );

      await provider.updateGlobalConfig(
        provider.effectiveConfig.copyWith(picConsultant: 'Updated PIC'),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        find.widgetWithText(TextFormField, 'Updated PIC'),
        findsOneWidget,
      );

      final payload = BackupPayload(
        schemaVersion: 3,
        exportedAt: DateTime(2026, 11, 24),
        globalConfig: GlobalConfig.defaults().copyWith(
          picConsultant: 'Restored PIC',
          defaultBaseHours: 7.0,
        ),
        dailyLogs: const [],
      );
      await provider.restoreBackup(payload, RestoreMode.replace);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(
        find.widgetWithText(TextFormField, 'Restored PIC'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'SettingsTab instant controls update only target field without persisting unsaved or invalid inputs',
    (WidgetTester tester) async {
      final (helper, _, provider) = await createHarness(
        initialConfig: GlobalConfig.defaults().copyWith(
          picConsultant: 'Saved PIC',
          defaultBaseHours: 7.5,
          includeSignature: true,
          themeMode: 'system',
        ),
      );
      addTearDown(provider.dispose);

      await tester.pumpWidget(
        ChangeNotifierProvider<AppProvider>.value(
          value: provider,
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const SettingsTab(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('Default Base Hours'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      final picField = find.widgetWithText(TextFormField, 'Saved PIC');
      await tester.enterText(picField, 'Unsaved Draft PIC');
      final hoursField = find.widgetWithText(TextFormField, '7.5');
      await tester.enterText(hoursField, '0');
      await tester.pump();

      await tester.scrollUntilVisible(
        find.text('Dark'),
        -200,
        scrollable: find.byType(Scrollable).first,
      );
      final darkSegment = find.text('Dark');
      await tester.ensureVisible(darkSegment);
      await tester.tap(darkSegment);
      await tester.pumpAndSettle();

      final sigSwitch = find.widgetWithText(
        SwitchListTile,
        'Include Signature (XLSX & PDF)',
      );
      await tester.scrollUntilVisible(
        sigSwitch,
        150,
        scrollable: find.byType(Scrollable).first,
      );
      await Scrollable.ensureVisible(
        tester.element(sigSwitch),
        alignment: 0.5,
      );
      await tester.pumpAndSettle();
      await tester.tap(sigSwitch);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);

      final persisted = await helper.readGlobalConfig();
      expect(persisted.themeMode, 'dark');
      expect(persisted.includeSignature, isFalse);
      expect(persisted.picConsultant, 'Saved PIC');
      expect(persisted.defaultBaseHours, 7.5);
      await tester.scrollUntilVisible(
        find.text('Default Base Hours'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        find.widgetWithText(TextFormField, 'Unsaved Draft PIC'),
        findsOneWidget,
      );
      expect(find.widgetWithText(TextFormField, '0'), findsOneWidget);
    },
  );

  testWidgets(
    'MainScreen awaits refreshFromDisk before reading today log on resume for open_today route',
    (WidgetTester tester) async {
      final (helper, fakeSync, provider) = await createHarness(
        initialConfig: GlobalConfig.defaults().copyWith(
          picConsultant: 'Dicky',
          defaultBaseHours: 8.0,
        ),
      );
      addTearDown(provider.dispose);

      await tester.pumpWidget(
        ChangeNotifierProvider<AppProvider>.value(
          value: provider,
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const MainScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final today = DateTime.now();
      await helper.appendQuickNote(
        isoDate: formatIsoDate(today),
        description: 'Widget note on disk',
        modul: 'Core',
        project: 'EVOQ 7E',
      );
      helper.readDelay = const Duration(milliseconds: 50);
      fakeSync.pendingRoute = 'open_today';

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(DailyLogSheet), findsOneWidget);
      expect(find.text('Edit Daily Log'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(DailyLogSheet),
          matching: find.text('Widget note on disk'),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'SettingsTab shows error SnackBar when instant preset or toggle write fails',
    (WidgetTester tester) async {
      final (helper, _, provider) = await createHarness(
        initialConfig: GlobalConfig.defaults().copyWith(
          picConsultant: 'Dicky',
          defaultBaseHours: 8.0,
        ),
      );
      addTearDown(provider.dispose);

      await tester.pumpWidget(
        ChangeNotifierProvider<AppProvider>.value(
          value: provider,
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const SettingsTab(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      helper.failConfigWrite = true;
      await tester.tap(find.text('Dark'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.textContaining('Gagal mengubah tema'), findsOneWidget);
    },
  );
}
