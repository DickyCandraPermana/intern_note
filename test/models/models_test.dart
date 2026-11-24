import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intern_noter/models/daily_log.dart';
import 'package:intern_noter/models/global_config.dart';

void main() {
  test('ActivityLine persists sortOrder and detects uncategorized state', () {
    final line = ActivityLine(modul: '', project: 'EVOQ 7E', description: 'Sync', sortOrder: 2);
    expect(line.isUncategorized, isTrue);
    final roundTrip = ActivityLine.fromMap(line.toMap());
    expect(roundTrip.sortOrder, 2);
    expect(ActivityLine.fromMap({'modul': 'Pay', 'project': '7E', 'description': 'Fix'}).sortOrder, 0);

    final emptyProject = ActivityLine(modul: 'Payment', project: '  ', description: 'Fix');
    expect(emptyProject.isUncategorized, isTrue);

    final categorized = emptyProject.copyWith(project: 'EVOQ 7E', sortOrder: 1);
    expect(categorized.isUncategorized, isFalse);
    expect(categorized.sortOrder, 1);
  });

  test('DailyLog computes totals, hasUncategorizedLines, and copyWith', () {
    final log = DailyLog(
      id: 10,
      date: '2026-11-24',
      baseHours: 8.0,
      overworkHours: 2.0,
      lines: [
        ActivityLine(modul: 'Payment', project: 'EVOQ 7E', description: 'API sync'),
        ActivityLine(modul: '', project: 'EVOQ 7E', description: 'Quick note'),
      ],
    );
    expect(log.totalHours, 10.0);
    expect(log.totalDays, 1.25);
    expect(log.hasUncategorizedLines, isTrue);

    final updated = log.copyWith(
      lines: [
        ActivityLine(modul: 'Payment', project: 'EVOQ 7E', description: 'API sync'),
      ],
    );
    expect(updated.hasUncategorizedLines, isFalse);
    expect(updated.date, '2026-11-24');
  });

  test('GlobalConfig serializes v3 fields, clamps cutoffDay, and falls back on bad presets JSON', () {
    final cfg = GlobalConfig.defaults().copyWith(
      themeMode: 'dark',
      cutoffDay: 31,
      includeSignature: false,
      quickPresets: ['Daily Scrum 7E', 'Stand-Up CK'],
    );
    final map = cfg.toMap();
    expect(map['cutoff_day'], 28);
    expect(map['include_signature'], 0);
    final decoded = GlobalConfig.fromMap({...map, 'quick_presets': 'not-json'});
    expect(decoded.flutterThemeMode, ThemeMode.dark);
    expect(decoded.includeSignature, isFalse);
    expect(decoded.quickPresets, GlobalConfig.defaultQuickPresets);

    final jsonRoundTrip = GlobalConfig.fromJson(cfg.toJson());
    expect(jsonRoundTrip.themeMode, 'dark');
    expect(jsonRoundTrip.cutoffDay, 28);
    expect(jsonRoundTrip.includeSignature, isFalse);
    expect(jsonRoundTrip.quickPresets, ['Daily Scrum 7E', 'Stand-Up CK']);
    expect(GlobalConfig.defaults().copyWith(themeMode: 'light').flutterThemeMode, ThemeMode.light);
    expect(GlobalConfig.defaults().flutterThemeMode, ThemeMode.system);
  });
}
