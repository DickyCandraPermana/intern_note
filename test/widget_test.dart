import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:intern_noter/main.dart';
import 'package:intern_noter/models/daily_log.dart';
import 'package:intern_noter/models/global_config.dart';
import 'package:intern_noter/providers/app_provider.dart';
import 'package:intern_noter/screens/main_screen.dart';
import 'package:intern_noter/screens/pdf_preview_screen.dart';
import 'package:intern_noter/services/database_helper.dart';
import 'package:intern_noter/services/widget_sync_service.dart';
import 'package:intern_noter/theme/app_theme.dart';
import 'package:intern_noter/widgets/daily_log_sheet.dart';
import 'package:intern_noter/widgets/export_dialog.dart';

class _FakeWidgetSyncService extends WidgetSyncService {
  int updateCount = 0;

  @override
  Future<void> updateWidget() async {
    updateCount++;
  }

  @override
  Future<String?> consumePendingRoute() async => null;
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  Future<(DatabaseHelper, _FakeWidgetSyncService, AppProvider)>
      createTestHarness(
    WidgetTester tester, {
    GlobalConfig? initialConfig,
    List<DailyLog> initialLogs = const [],
  }) async {
    final dir = Directory.systemTemp.createTempSync('intern_noter_widget_');
    final helper = DatabaseHelper.forPath(p.join(dir.path, 'intern_noter.db'));
    final fakeSync = _FakeWidgetSyncService();

    await tester.runAsync(() async {
      if (initialConfig != null) {
        await helper.updateGlobalConfig(initialConfig);
      }
      for (final log in initialLogs) {
        await helper.upsertDailyLog(log, mergeIfExists: false);
      }
    });

    final provider = AppProvider(
      dbHelper: helper,
      widgetSync: fakeSync,
      autoLoad: false,
    );

    addTearDown(() async {
      provider.dispose();
      await helper.close();
      if (dir.existsSync()) {
        dir.deleteSync(recursive: true);
      }
    });

    await tester.runAsync(() => provider.refreshFromDisk());
    return (helper, fakeSync, provider);
  }

  void setViewport(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }

  testWidgets(
    'renders Dashboard in both Light and Dark themes without overflow and shows empty CTA',
    (WidgetTester tester) async {
      setViewport(tester, const Size(500, 844));
      final (_, _, provider) = await createTestHarness(
        tester,
        initialConfig: GlobalConfig.defaults().copyWith(
          themeMode: 'light',
          picConsultant: 'Dicky Candra',
        ),
      );

      await tester.pumpWidget(
        ChangeNotifierProvider<AppProvider>.value(
          value: provider,
          child: const InternNoterApp(),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Dashboard'), findsAtLeastNWidgets(1));
      expect(find.text('Belum ada catatan hari ini'), findsOneWidget);
      expect(find.text('Tambah Catatan'), findsAtLeastNWidgets(1));

      final lightContext = tester.element(find.byType(MainScreen));
      expect(Theme.of(lightContext).brightness, Brightness.light);
      expect(AppColors.of(lightContext).canvas, AppColors.light.canvas);

      await tester.runAsync(
        () => provider.updateGlobalConfig(
          provider.effectiveConfig.copyWith(themeMode: 'dark'),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      final darkContext = tester.element(find.byType(MainScreen));
      expect(Theme.of(darkContext).brightness, Brightness.dark);
      expect(AppColors.of(darkContext).canvas, AppColors.dark.canvas);
      expect(find.text('Belum ada catatan hari ini'), findsOneWidget);
      expect(find.text('Tambah Catatan'), findsAtLeastNWidgets(1));
    },
  );

  testWidgets(
    'shows Perlu tag modul/project pill when today has uncategorized quick note',
    (WidgetTester tester) async {
      setViewport(tester, const Size(500, 844));
      final (_, _, provider) = await createTestHarness(
        tester,
        initialConfig: GlobalConfig.defaults().copyWith(themeMode: 'light'),
      );

      await tester.runAsync(
        () => provider.quickAddTodayNote(
          description: 'Cek pipeline deploy harian',
          modul: '',
          project: '',
        ),
      );

      await tester.pumpWidget(
        ChangeNotifierProvider<AppProvider>.value(
          value: provider,
          child: const InternNoterApp(),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Cek pipeline deploy harian'), findsOneWidget);
      final pillFinder = find.text('Perlu tag modul/project');
      expect(pillFinder, findsAtLeastNWidgets(1));

      await tester.tap(pillFinder.first);
      await tester.pumpAndSettle();

      expect(find.byType(DailyLogSheet), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(DailyLogSheet),
          matching: find.text('Cek pipeline deploy harian'),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'DailyLogSheet renders vertical stacked cards, reorders lines, and detects existing log on same date',
    (WidgetTester tester) async {
      setViewport(tester, const Size(390, 844));
      final (helper, _, provider) = await createTestHarness(
        tester,
        initialConfig: GlobalConfig.defaults().copyWith(
          defaultBaseHours: 8.0,
          quickPresets: ['Daily Scrum 7E', 'Join Daily Stand-Up CK'],
        ),
        initialLogs: [
          DailyLog(
            date: '2026-11-19',
            baseHours: 8.0,
            overworkHours: 0.0,
            lines: [
              ActivityLine(
                modul: 'Core',
                project: 'EVOQ 7E',
                description: 'Seed suggestion',
                sortOrder: 0,
              ),
            ],
          ),
        ],
      );

      Finder cardForLine(int number) => find.ancestor(
            of: find.text('Aktivitas #$number'),
            matching: find.byType(JournalCard),
          );

      await tester.pumpWidget(
        ChangeNotifierProvider<AppProvider>.value(
          value: provider,
          child: MaterialApp(
            theme: AppTheme.light(),
            home: Builder(
              builder: (context) => Scaffold(
                body: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    FilledButton(
                      onPressed: () {
                        showModalBottomSheet<void>(
                          context: context,
                          isScrollControlled: true,
                          builder: (_) => DailyLogSheet(
                            initialDate: DateTime(2026, 11, 20),
                          ),
                        );
                      },
                      child: const Text('Open Sheet'),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: () {
                        showModalBottomSheet<void>(
                          context: context,
                          isScrollControlled: true,
                          builder: (_) => DailyLogSheet(
                            initialDate: DateTime(2026, 11, 21),
                          ),
                        );
                      },
                      child: const Text('Open Sheet Nov 21'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Sheet'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(RawAutocomplete<String>), findsNWidgets(2));
      expect(cardForLine(1), findsOneWidget);

      // Tap quick preset on line 1 (Modul/Project remain optional and blank).
      final presetChip = find.descendant(
        of: cardForLine(1),
        matching: find.text('Daily Scrum 7E'),
      );
      await tester.ensureVisible(presetChip);
      await tester.tap(presetChip);
      await tester.pumpAndSettle();

      // Add a second line card.
      final addLineBtn = find.text('Tambah Aktivitas');
      await tester.ensureVisible(addLineBtn);
      await tester.tap(addLineBtn);
      await tester.pumpAndSettle();

      expect(cardForLine(1), findsOneWidget);
      expect(cardForLine(2), findsOneWidget);

      // Verify stacked vertical layout: card 2 sits below card 1.
      final card1Bottom = tester.getBottomLeft(cardForLine(1)).dy;
      final card2Top = tester.getTopLeft(cardForLine(2)).dy;
      expect(card2Top, greaterThanOrEqualTo(card1Bottom));

      // Fill line 2 description without requiring modul/project.
      final line2DescField = find.descendant(
        of: cardForLine(2),
        matching: find.widgetWithText(TextFormField, 'Aktivitas'),
      );
      await tester.ensureVisible(line2DescField);
      await tester.enterText(line2DescField, 'Review PR OOXML');
      await tester.pumpAndSettle();

      // Reorder line 2 upward so it becomes line 1.
      final moveUpLine2 = find.descendant(
        of: cardForLine(2),
        matching: find.byIcon(Icons.arrow_upward),
      );
      await tester.ensureVisible(moveUpLine2);
      await tester.tap(moveUpLine2);
      await tester.pumpAndSettle();

      // Save and verify persisted sortOrder and normalized date in SQLite.
      final saveBtn = find.text('Simpan Catatan');
      await tester.ensureVisible(saveBtn);
      await tester.tap(saveBtn);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(DailyLogSheet), findsNothing);

      final savedNov20 = await tester.runAsync(
        () => helper.readDailyLogByDate('2026-11-20'),
      );
      expect(savedNov20, isNotNull);
      expect(savedNov20!.date, '2026-11-20');
      expect(savedNov20.lines.length, 2);
      expect(savedNov20.lines[0].description, 'Review PR OOXML');
      expect(savedNov20.lines[0].sortOrder, 0);
      expect(savedNov20.lines[1].description, 'Daily Scrum 7E');
      expect(savedNov20.lines[1].sortOrder, 1);

      // Open create mode again on the same date (2026-11-20) -> collision detection!
      await tester.tap(find.text('Open Sheet'));
      await tester.pumpAndSettle();

      expect(
        find.text('Menambahkan ke catatan tanggal ini yang sudah ada'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(TextFormField, 'Review PR OOXML'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(TextFormField, 'Daily Scrum 7E'),
        findsOneWidget,
      );

      // Add a third line and save; must update without duplicate-date UNIQUE error.
      await tester.ensureVisible(find.text('Tambah Aktivitas'));
      await tester.tap(find.text('Tambah Aktivitas'));
      await tester.pumpAndSettle();

      final line3DescField = find.descendant(
        of: cardForLine(3),
        matching: find.widgetWithText(TextFormField, 'Aktivitas'),
      );
      await tester.ensureVisible(line3DescField);
      await tester.enterText(line3DescField, 'Deploy staging build');
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Simpan Catatan'));
      await tester.tap(find.text('Simpan Catatan'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      final updatedNov20 = await tester.runAsync(
        () => helper.readDailyLogByDate('2026-11-20'),
      );
      expect(updatedNov20, isNotNull);
      expect(updatedNov20!.lines.length, 3);
      expect(
        updatedNov20.lines.map((l) => l.description).toList(),
        ['Review PR OOXML', 'Daily Scrum 7E', 'Deploy staging build'],
      );
      expect(
        updatedNov20.lines.map((l) => l.sortOrder).toList(),
        [0, 1, 2],
      );

      // Open create mode on Nov 21 (empty), type an unsaved line with RawAutocomplete,
      // then switch date picker to Nov 20 (existing) -> preserves unsaved line & merges!
      await tester.tap(find.text('Open Sheet Nov 21'));
      await tester.pumpAndSettle();

      expect(
        find.text('Menambahkan ke catatan tanggal ini yang sudah ada'),
        findsNothing,
      );

      final nov21ModulField = find.descendant(
        of: cardForLine(1),
        matching: find.widgetWithText(TextFormField, 'Modul'),
      );
      await tester.tap(nov21ModulField);
      await tester.pumpAndSettle();
      expect(find.text('Core'), findsOneWidget);
      await tester.tap(find.text('Core'));
      await tester.pumpAndSettle();

      final nov21DescField = find.descendant(
        of: cardForLine(1),
        matching: find.widgetWithText(TextFormField, 'Aktivitas'),
      );
      await tester.enterText(nov21DescField, 'Unsaved draft work');
      await tester.pumpAndSettle();

      final datePickerTrigger = find.byIcon(Icons.calendar_today_outlined);
      await tester.ensureVisible(datePickerTrigger);
      await tester.tap(datePickerTrigger);
      await tester.pumpAndSettle();

      await tester.tap(find.text('20'));
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(
        find.text('Menambahkan ke catatan tanggal ini yang sudah ada'),
        findsOneWidget,
      );
      expect(cardForLine(4), findsOneWidget);
      expect(
        find.widgetWithText(TextFormField, 'Unsaved draft work'),
        findsOneWidget,
      );

      await tester.ensureVisible(find.text('Simpan Catatan'));
      await tester.tap(find.text('Simpan Catatan'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      final mergedNov20 = await tester.runAsync(
        () => helper.readDailyLogByDate('2026-11-20'),
      );
      expect(mergedNov20, isNotNull);
      expect(mergedNov20!.lines.length, 4);
      expect(mergedNov20.lines[3].modul, 'Core');
      expect(mergedNov20.lines[3].description, 'Unsaved draft work');
      expect(mergedNov20.lines[3].sortOrder, 3);
    },
  );

  testWidgets(
    'ExportDialog defaults to 25-24 cycle, auto-checks Approved by when present, syncs Include Signature, and disables export when 0 logs',
    (WidgetTester tester) async {
      setViewport(tester, const Size(390, 844));

      const printingChannel = MethodChannel('net.nfet.printing');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(printingChannel, (call) async {
        if (call.method == 'printingInfo') {
          return <String, dynamic>{
            'canPrint': true,
            'canShare': true,
            'canRaster': false,
          };
        }
        return null;
      });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(printingChannel, null);
      });

      // Scenario A: 0 logs in cycle, approvedByName present, includeSignature = false.
      final (_, _, providerA) = await createTestHarness(
        tester,
        initialConfig: GlobalConfig.defaults().copyWith(
          picConsultant: 'Dicky Candra',
          role: 'System & Data Analyst',
          createdByName: 'Dicky Candra',
          approvedByName: 'Ardya Pusaka',
          approvedByLeadName: 'Joko Setiyo',
          cutoffDay: 24,
          includeSignature: false,
        ),
      );

      await tester.pumpWidget(
        ChangeNotifierProvider<AppProvider>.value(
          value: providerA,
          child: MaterialApp(
            theme: AppTheme.light(),
            home: Scaffold(
              body: ExportDialog(targetMonth: DateTime(2026, 11, 15)),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.textContaining('25 Okt - 24 Nov 2026'), findsOneWidget);

      final approvedCheckbox = tester.widget<CheckboxListTile>(
        find.widgetWithText(CheckboxListTile, 'Add Approved By (2nd Approver)'),
      );
      expect(approvedCheckbox.value, isTrue);
      expect(find.widgetWithText(TextField, 'Ardya Pusaka'), findsOneWidget);

      final sigFinder = find.widgetWithText(
        CheckboxListTile,
        'Include Signature',
      );
      expect(tester.widget<CheckboxListTile>(sigFinder).value, isFalse);

      await tester.ensureVisible(sigFinder);
      await tester.tap(sigFinder);
      await tester.pumpAndSettle();
      expect(tester.widget<CheckboxListTile>(sigFinder).value, isTrue);

      final exportXlsxBtn = tester.widget<ButtonStyleButton>(
        find.ancestor(
          of: find.text('Export XLSX'),
          matching: find.bySubtype<ButtonStyleButton>(),
        ),
      );
      final previewPdfBtn = tester.widget<ButtonStyleButton>(
        find.ancestor(
          of: find.text('Preview PDF'),
          matching: find.bySubtype<ButtonStyleButton>(),
        ),
      );
      final sharePdfBtn = tester.widget<ButtonStyleButton>(
        find.ancestor(
          of: find.text('Share PDF'),
          matching: find.bySubtype<ButtonStyleButton>(),
        ),
      );
      expect(exportXlsxBtn.enabled, isFalse);
      expect(previewPdfBtn.enabled, isFalse);
      expect(sharePdfBtn.enabled, isFalse);

      // Scenario B: 1 matching log in 25 Okt - 24 Nov cycle, empty approvedByName, includeSignature = true.
      await tester.runAsync(() async {
        await providerA.updateGlobalConfig(
          providerA.effectiveConfig.copyWith(
            approvedByName: '',
            includeSignature: true,
          ),
        );
        await providerA.addDailyLog(
          DailyLog(
            date: '2026-10-28',
            baseHours: 8.0,
            overworkHours: 0.0,
            lines: [
              ActivityLine(
                modul: 'OMS',
                project: 'Kraft Heinz (OMS)',
                description: 'Verify billing cycle boundaries',
                sortOrder: 0,
              ),
            ],
          ),
        );
      });

      await tester.pumpWidget(
        ChangeNotifierProvider<AppProvider>.value(
          value: providerA,
          child: MaterialApp(
            theme: AppTheme.light(),
            home: Builder(
              builder: (ctx) => Scaffold(
                body: Center(
                  child: FilledButton(
                    onPressed: () {
                      showDialog<void>(
                        context: ctx,
                        builder: (_) => ExportDialog(
                          targetMonth: DateTime(2026, 11, 15),
                        ),
                      );
                    },
                    child: const Text('Open Export'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open Export'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.textContaining('1 hari tercatat'), findsOneWidget);

      final approvedUnchecked = tester.widget<CheckboxListTile>(
        find.widgetWithText(CheckboxListTile, 'Add Approved By (2nd Approver)'),
      );
      expect(approvedUnchecked.value, isFalse);

      final sigChecked = tester.widget<CheckboxListTile>(
        find.widgetWithText(CheckboxListTile, 'Include Signature'),
      );
      expect(sigChecked.value, isTrue);

      final enabledXlsx = tester.widget<ButtonStyleButton>(
        find.ancestor(
          of: find.text('Export XLSX'),
          matching: find.bySubtype<ButtonStyleButton>(),
        ),
      );
      final enabledPreview = tester.widget<ButtonStyleButton>(
        find.ancestor(
          of: find.text('Preview PDF'),
          matching: find.bySubtype<ButtonStyleButton>(),
        ),
      );
      final enabledShare = tester.widget<ButtonStyleButton>(
        find.ancestor(
          of: find.text('Share PDF'),
          matching: find.bySubtype<ButtonStyleButton>(),
        ),
      );
      expect(enabledXlsx.enabled, isTrue);
      expect(enabledPreview.enabled, isTrue);
      expect(enabledShare.enabled, isTrue);

      await tester.tap(find.text('Preview PDF'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(PdfPreviewScreen), findsOneWidget);
    },
  );

  testWidgets(
    'DailyLogSheet and ExportDialog support Dark theme, defaults, delete/move-down, edit collision, and export error SnackBar',
    (WidgetTester tester) async {
      setViewport(tester, const Size(390, 844));
      final (helper, _, provider) = await createTestHarness(
        tester,
        initialConfig: GlobalConfig.defaults().copyWith(
          themeMode: 'dark',
          defaultModul: 'Finance',
          defaultProject: 'CK',
          picConsultant: 'Dicky Candra',
          createdByName: 'Dicky Candra',
        ),
        initialLogs: [
          DailyLog(
            date: '2026-11-10',
            baseHours: 8.0,
            overworkHours: 0.0,
            lines: [
              ActivityLine(
                modul: 'Finance',
                project: 'CK',
                description: 'Line One',
                sortOrder: 0,
              ),
              ActivityLine(
                modul: 'Core',
                project: '7E',
                description: 'Line Two',
                sortOrder: 1,
              ),
            ],
          ),
          DailyLog(
            date: '2026-11-11',
            baseHours: 8.0,
            overworkHours: 0.0,
            lines: [
              ActivityLine(
                modul: 'Core',
                project: '7E',
                description: 'Separate Day Entry',
                sortOrder: 0,
              ),
            ],
          ),
        ],
      );

      Finder cardForLine(int number) => find.ancestor(
            of: find.text('Aktivitas #$number'),
            matching: find.byType(JournalCard),
          );

      // Verify fresh line seeding from defaultModul/defaultProject in Dark theme.
      await tester.pumpWidget(
        ChangeNotifierProvider<AppProvider>.value(
          value: provider,
          child: MaterialApp(
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            themeMode: ThemeMode.dark,
            home: Builder(
              builder: (ctx) => Scaffold(
                body: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FilledButton(
                        onPressed: () {
                          showModalBottomSheet<void>(
                            context: ctx,
                            isScrollControlled: true,
                            builder: (_) => DailyLogSheet(
                              initialDate: DateTime(2026, 11, 12),
                            ),
                          );
                        },
                        child: const Text('New Nov 12'),
                      ),
                      FilledButton(
                        onPressed: () {
                          final nov10 = provider.getDailyLogForDate(
                            DateTime(2026, 11, 10),
                          );
                          showModalBottomSheet<void>(
                            context: ctx,
                            isScrollControlled: true,
                            builder: (_) => DailyLogSheet(log: nov10),
                          );
                        },
                        child: const Text('Edit Nov 10'),
                      ),
                      FilledButton(
                        onPressed: () {
                          showDialog<void>(
                            context: ctx,
                            builder: (_) => ExportDialog(
                              targetMonth: DateTime(2026, 11, 10),
                            ),
                          );
                        },
                        child: const Text('Open Export Dark'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      // 1. Fresh line seeded with defaultModul='Finance' and defaultProject='CK'.
      await tester.tap(find.text('New Nov 12'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        find.descendant(
          of: cardForLine(1),
          matching: find.widgetWithText(TextFormField, 'Finance'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: cardForLine(1),
          matching: find.widgetWithText(TextFormField, 'CK'),
        ),
        findsOneWidget,
      );
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      // 2. Edit Nov 10: test edit-mode date collision guard, move-down, and delete.
      await tester.tap(find.text('Edit Nov 10'));
      await tester.pumpAndSettle();
      expect(find.text('Edit Daily Log'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.calendar_today_outlined));
      await tester.pumpAndSettle();
      await tester.tap(find.text('11'));
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.textContaining('sudah memiliki catatan terpisah'), findsOneWidget);

      // Move line 1 down -> Line Two becomes #1, Line One becomes #2; then delete #1.
      await tester.tap(
        find.descendant(
          of: cardForLine(1),
          matching: find.byIcon(Icons.arrow_downward),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: cardForLine(1),
          matching: find.byIcon(Icons.delete_outline),
        ),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Simpan Perubahan'));
      await tester.tap(find.text('Simpan Perubahan'));
      await tester.pumpAndSettle();

      final savedNov10 = await tester.runAsync(
        () => helper.readDailyLogByDate('2026-11-10'),
      );
      expect(savedNov10!.lines.length, 1);
      expect(savedNov10.lines.single.description, 'Line One');
      expect(savedNov10.lines.single.sortOrder, 0);

      // 3. Open ExportDialog in Dark theme and verify safe SnackBar on export failure.
      await tester.tap(find.text('Open Export Dark'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Export XLSX'));
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 250)),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.textContaining('Export XLSX gagal'), findsOneWidget);
    },
  );
}
