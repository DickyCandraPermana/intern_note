import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../models/daily_log.dart';
import '../models/global_config.dart';
import '../utils/date_formatters.dart';
import 'database_helper.dart';

enum RestoreMode { merge, replace }

class BackupPayload {
  final int schemaVersion;
  final DateTime exportedAt;
  final GlobalConfig globalConfig;
  final List<DailyLog> dailyLogs;

  const BackupPayload({
    required this.schemaVersion,
    required this.exportedAt,
    required this.globalConfig,
    required this.dailyLogs,
  });
}

class BackupRestoreResult {
  final RestoreMode mode;
  final int addedLogs;
  final int skippedLogs;
  final int totalLogsAfter;

  const BackupRestoreResult({
    required this.mode,
    required this.addedLogs,
    required this.skippedLogs,
    required this.totalLogsAfter,
  });
}

class BackupService {
  static const int currentSchemaVersion = 3;
  static final RegExp _isoDatePattern = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

  static String encodeBackupJson(
    GlobalConfig config,
    List<DailyLog> logs, {
    DateTime? exportedAt,
  }) {
    final timestamp = exportedAt ?? DateTime.now();
    final sortedLogs = List<DailyLog>.from(logs)
      ..sort(
        (a, b) => normalizeIsoDate(a.date).compareTo(normalizeIsoDate(b.date)),
      );

    final serializedLogs = sortedLogs.map((log) {
      final sortedLines = List<ActivityLine>.from(log.lines)
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      return {
        'date': normalizeIsoDate(log.date),
        'base_hours': log.baseHours,
        'overwork_hours': log.overworkHours,
        'lines': sortedLines
            .map(
              (line) => {
                'modul': line.modul,
                'project': line.project,
                'description': line.description,
                'sort_order': line.sortOrder,
              },
            )
            .toList(),
      };
    }).toList();

    final payload = {
      'schema_version': currentSchemaVersion,
      'exported_at': timestamp.toIso8601String(),
      'global_config': config.toJson(),
      'daily_logs': serializedLogs,
    };

    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  static BackupPayload parseAndValidateBackupJson(String jsonString) {
    final dynamic decoded;
    try {
      decoded = jsonDecode(jsonString);
    } on FormatException catch (e) {
      throw FormatException('Invalid JSON backup: ${e.message}');
    }

    if (decoded is! Map) {
      throw const FormatException('Backup root must be a JSON object.');
    }
    final root = Map<String, dynamic>.from(decoded);

    final rawVersion = root['schema_version'];
    if (rawVersion is! num || rawVersion != rawVersion.toInt()) {
      throw const FormatException('Invalid or missing schema_version.');
    }
    final schemaVersion = rawVersion.toInt();
    if (schemaVersion < 1 || schemaVersion > currentSchemaVersion) {
      throw FormatException('Unsupported schema_version: $schemaVersion.');
    }

    final DateTime exportedAt;
    final rawExportedAt = root['exported_at'];
    if (rawExportedAt == null) {
      exportedAt = DateTime.now();
    } else if (rawExportedAt is String) {
      final parsedExported = DateTime.tryParse(rawExportedAt);
      if (parsedExported == null) {
        throw FormatException('Invalid exported_at timestamp: $rawExportedAt.');
      }
      exportedAt = parsedExported;
    } else {
      throw const FormatException('Invalid exported_at timestamp.');
    }

    final rawConfig = root['global_config'];
    if (rawConfig is! Map) {
      throw const FormatException('Missing or invalid global_config object.');
    }
    final configMap = Map<String, dynamic>.from(rawConfig);
    _validateGlobalConfigMap(configMap);
    final globalConfig = GlobalConfig.fromJson(configMap);

    final rawLogs = root['daily_logs'];
    if (rawLogs is! List) {
      throw const FormatException('Missing or invalid daily_logs list.');
    }

    final dailyLogs = <DailyLog>[];
    for (int i = 0; i < rawLogs.length; i++) {
      final rawLog = rawLogs[i];
      if (rawLog is! Map) {
        throw FormatException('daily_logs[$i] must be a JSON object.');
      }
      final logMap = Map<String, dynamic>.from(rawLog);
      dailyLogs.add(_parseAndValidateLog(logMap, i));
    }

    return BackupPayload(
      schemaVersion: schemaVersion,
      exportedAt: exportedAt,
      globalConfig: globalConfig,
      dailyLogs: dailyLogs,
    );
  }

  static void _validateGlobalConfigMap(Map<String, dynamic> configMap) {
    if (configMap.containsKey('default_base_hours')) {
      final rawBase = configMap['default_base_hours'];
      if (rawBase is! num || rawBase.isNaN || rawBase < 0) {
        throw const FormatException('Invalid global_config.default_base_hours.');
      }
    }
    if (configMap.containsKey('cutoff_day')) {
      final rawCutoff = configMap['cutoff_day'];
      if (rawCutoff is! num || rawCutoff != rawCutoff.toInt()) {
        throw const FormatException('Invalid global_config.cutoff_day.');
      }
    }
    if (configMap.containsKey('include_signature')) {
      final rawSig = configMap['include_signature'];
      final isValidBool =
          rawSig is bool ||
          (rawSig is num && (rawSig == 0 || rawSig == 1)) ||
          (rawSig is String &&
              const {'true', 'false', '1', '0'}
                  .contains(rawSig.trim().toLowerCase()));
      if (!isValidBool) {
        throw const FormatException('Invalid global_config.include_signature.');
      }
    }
  }

  static DailyLog _parseAndValidateLog(
    Map<String, dynamic> logMap,
    int logIndex,
  ) {
    final rawDate = logMap['date'];
    if (rawDate is! String) {
      throw FormatException('daily_logs[$logIndex].date must be a string.');
    }
    final match = _isoDatePattern.firstMatch(rawDate);
    if (match == null) {
      throw FormatException(
        'daily_logs[$logIndex].date "$rawDate" must match YYYY-MM-DD.',
      );
    }
    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    final parsedDate = DateTime(year, month, day);
    if (parsedDate.year != year ||
        parsedDate.month != month ||
        parsedDate.day != day) {
      throw FormatException(
        'daily_logs[$logIndex].date "$rawDate" is not a valid calendar date.',
      );
    }

    final rawBaseHours = logMap['base_hours'];
    if (rawBaseHours != null &&
        (rawBaseHours is! num || rawBaseHours.isNaN || rawBaseHours < 0)) {
      throw FormatException('daily_logs[$logIndex].base_hours is invalid.');
    }
    final baseHours = (rawBaseHours as num?)?.toDouble() ?? 8.0;

    final rawOverworkHours = logMap['overwork_hours'];
    if (rawOverworkHours != null &&
        (rawOverworkHours is! num ||
            rawOverworkHours.isNaN ||
            rawOverworkHours < 0)) {
      throw FormatException('daily_logs[$logIndex].overwork_hours is invalid.');
    }
    final overworkHours = (rawOverworkHours as num?)?.toDouble() ?? 0.0;

    final rawLines = logMap['lines'];
    if (rawLines is! List) {
      throw FormatException('daily_logs[$logIndex].lines must be a list.');
    }

    final lines = <ActivityLine>[];
    for (int j = 0; j < rawLines.length; j++) {
      final rawLine = rawLines[j];
      if (rawLine is! Map) {
        throw FormatException(
          'daily_logs[$logIndex].lines[$j] must be a JSON object.',
        );
      }
      final lineMap = Map<String, dynamic>.from(rawLine);

      final rawDesc = lineMap['description'];
      if (rawDesc is! String || rawDesc.trim().isEmpty) {
        throw FormatException(
          'daily_logs[$logIndex].lines[$j].description cannot be empty.',
        );
      }

      final rawModul = lineMap['modul'];
      if (rawModul != null && rawModul is! String) {
        throw FormatException(
          'daily_logs[$logIndex].lines[$j].modul must be a string.',
        );
      }
      final rawProject = lineMap['project'];
      if (rawProject != null && rawProject is! String) {
        throw FormatException(
          'daily_logs[$logIndex].lines[$j].project must be a string.',
        );
      }
      final rawSortOrder = lineMap['sort_order'];
      if (rawSortOrder != null &&
          (rawSortOrder is! num || rawSortOrder != rawSortOrder.toInt())) {
        throw FormatException(
          'daily_logs[$logIndex].lines[$j].sort_order must be an integer.',
        );
      }

      lines.add(
        ActivityLine(
          modul: (rawModul as String?) ?? '',
          project: (rawProject as String?) ?? '',
          description: rawDesc,
          sortOrder: (rawSortOrder as num?)?.toInt() ?? j,
        ),
      );
    }

    return DailyLog(
      date: rawDate,
      baseHours: baseHours,
      overworkHours: overworkHours,
      lines: lines,
    );
  }

  static Future<BackupRestoreResult> applyRestore(
    DatabaseHelper dbHelper,
    BackupPayload payload,
    RestoreMode mode,
  ) async {
    if (mode == RestoreMode.replace) {
      await dbHelper.replaceAllData(payload.globalConfig, payload.dailyLogs);
      final allLogs = await dbHelper.readAllDailyLogs();
      return BackupRestoreResult(
        mode: RestoreMode.replace,
        addedLogs: allLogs.length,
        skippedLogs: 0,
        totalLogsAfter: allLogs.length,
      );
    }

    final counts = await dbHelper.mergeBackupData(
      payload.globalConfig,
      payload.dailyLogs,
    );
    final allLogs = await dbHelper.readAllDailyLogs();
    return BackupRestoreResult(
      mode: RestoreMode.merge,
      addedLogs: counts.addedLogs,
      skippedLogs: counts.skippedLogs,
      totalLogsAfter: allLogs.length,
    );
  }

  static Future<File> writeBackupFile(
    GlobalConfig config,
    List<DailyLog> logs, {
    Directory? directory,
    DateTime? now,
  }) async {
    final timestamp = now ?? DateTime.now();
    final targetDir = directory ?? await getTemporaryDirectory();
    await targetDir.create(recursive: true);

    final datePart =
        '${timestamp.year.toString().padLeft(4, '0')}'
        '${timestamp.month.toString().padLeft(2, '0')}'
        '${timestamp.day.toString().padLeft(2, '0')}';
    final timePart =
        '${timestamp.hour.toString().padLeft(2, '0')}'
        '${timestamp.minute.toString().padLeft(2, '0')}';
    final fileName = 'intern_noter_backup_${datePart}_$timePart.json';

    final file = File(p.join(targetDir.path, fileName));
    final jsonContent = encodeBackupJson(config, logs, exportedAt: timestamp);
    return file.writeAsString(jsonContent, flush: true);
  }
}
