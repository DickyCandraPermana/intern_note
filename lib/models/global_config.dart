import 'dart:convert';
import 'package:flutter/material.dart';

class GlobalConfig {
  static const List<String> defaultQuickPresets = [
    'Daily Scrum 7E',
    'Join Daily Stand-Up CK',
  ];

  int id; // Always 1
  String picConsultant;
  String role;
  String createdByName;
  String approvedByName;
  String approvedByLeadName;
  double defaultBaseHours;
  String themeMode;
  int cutoffDay;
  String defaultModul;
  String defaultProject;
  List<String> quickPresets;
  bool includeSignature;

  GlobalConfig({
    this.id = 1,
    required this.picConsultant,
    required this.role,
    required this.createdByName,
    required this.approvedByName,
    required this.approvedByLeadName,
    required this.defaultBaseHours,
    this.themeMode = 'system',
    int cutoffDay = 24,
    this.defaultModul = '',
    this.defaultProject = '',
    List<String> quickPresets = defaultQuickPresets,
    this.includeSignature = true,
  })  : cutoffDay = cutoffDay.clamp(1, 28),
        quickPresets = List<String>.from(quickPresets);

  factory GlobalConfig.defaults() {
    return GlobalConfig(
      id: 1,
      picConsultant: '',
      role: '',
      createdByName: '',
      approvedByName: '',
      approvedByLeadName: '',
      defaultBaseHours: 8.0,
      themeMode: 'system',
      cutoffDay: 24,
      defaultModul: '',
      defaultProject: '',
      quickPresets: defaultQuickPresets,
      includeSignature: true,
    );
  }

  ThemeMode get flutterThemeMode {
    switch (themeMode) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  GlobalConfig copyWith({
    int? id,
    String? picConsultant,
    String? role,
    String? createdByName,
    String? approvedByName,
    String? approvedByLeadName,
    double? defaultBaseHours,
    String? themeMode,
    int? cutoffDay,
    String? defaultModul,
    String? defaultProject,
    List<String>? quickPresets,
    bool? includeSignature,
  }) {
    return GlobalConfig(
      id: id ?? this.id,
      picConsultant: picConsultant ?? this.picConsultant,
      role: role ?? this.role,
      createdByName: createdByName ?? this.createdByName,
      approvedByName: approvedByName ?? this.approvedByName,
      approvedByLeadName: approvedByLeadName ?? this.approvedByLeadName,
      defaultBaseHours: defaultBaseHours ?? this.defaultBaseHours,
      themeMode: themeMode ?? this.themeMode,
      cutoffDay: (cutoffDay ?? this.cutoffDay).clamp(1, 28),
      defaultModul: defaultModul ?? this.defaultModul,
      defaultProject: defaultProject ?? this.defaultProject,
      quickPresets: quickPresets ?? this.quickPresets,
      includeSignature: includeSignature ?? this.includeSignature,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'pic_consultant': picConsultant,
      'role': role,
      'created_by_name': createdByName,
      'approved_by_name': approvedByName,
      'approved_by_lead_name': approvedByLeadName,
      'default_base_hours': defaultBaseHours,
      'theme_mode': themeMode,
      'cutoff_day': cutoffDay.clamp(1, 28),
      'default_modul': defaultModul,
      'default_project': defaultProject,
      'quick_presets': jsonEncode(quickPresets),
      'include_signature': includeSignature ? 1 : 0,
    };
  }

  factory GlobalConfig.fromMap(Map<String, dynamic> map) {
    final rawTheme = (map['theme_mode'] ?? 'system').toString();
    final normalizedTheme =
        (rawTheme == 'light' || rawTheme == 'dark' || rawTheme == 'system')
            ? rawTheme
            : 'system';

    return GlobalConfig(
      id: (map['id'] as num?)?.toInt() ?? 1,
      picConsultant: (map['pic_consultant'] ?? '').toString(),
      role: (map['role'] ?? '').toString(),
      createdByName: (map['created_by_name'] ?? '').toString(),
      approvedByName: (map['approved_by_name'] ?? '').toString(),
      approvedByLeadName: (map['approved_by_lead_name'] ?? '').toString(),
      defaultBaseHours: (map['default_base_hours'] as num?)?.toDouble() ?? 8.0,
      themeMode: normalizedTheme,
      cutoffDay: ((map['cutoff_day'] as num?)?.toInt() ?? 24).clamp(1, 28),
      defaultModul: (map['default_modul'] ?? '').toString(),
      defaultProject: (map['default_project'] ?? '').toString(),
      quickPresets: _parseQuickPresets(map['quick_presets']),
      includeSignature: _parseBool(map['include_signature'], fallback: true),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'pic_consultant': picConsultant,
      'role': role,
      'created_by_name': createdByName,
      'approved_by_name': approvedByName,
      'approved_by_lead_name': approvedByLeadName,
      'default_base_hours': defaultBaseHours,
      'theme_mode': themeMode,
      'cutoff_day': cutoffDay.clamp(1, 28),
      'default_modul': defaultModul,
      'default_project': defaultProject,
      'quick_presets': List<String>.from(quickPresets),
      'include_signature': includeSignature,
    };
  }

  factory GlobalConfig.fromJson(Map<String, dynamic> json) {
    return GlobalConfig.fromMap(json);
  }

  static List<String> _parseQuickPresets(dynamic raw) {
    if (raw == null) return List<String>.from(defaultQuickPresets);
    if (raw is List) {
      return raw
          .map((e) => e.toString().trim())
          .where((s) => s.isNotEmpty)
          .toList();
    }
    if (raw is String) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) return List<String>.from(defaultQuickPresets);
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is List) {
          return decoded
              .map((e) => e.toString().trim())
              .where((s) => s.isNotEmpty)
              .toList();
        }
      } catch (_) {
        return List<String>.from(defaultQuickPresets);
      }
    }
    return List<String>.from(defaultQuickPresets);
  }

  static bool _parseBool(dynamic value, {bool fallback = true}) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      if (normalized == 'true' || normalized == '1') return true;
      if (normalized == 'false' || normalized == '0') return false;
    }
    return fallback;
  }
}
