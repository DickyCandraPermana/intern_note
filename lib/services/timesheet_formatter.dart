import 'dart:math';

import '../models/daily_log.dart';
import '../models/global_config.dart';
import '../utils/date_formatters.dart';

class FormattedTimesheetRow {
  final int index;
  final DateTime date;
  final String isoDate;
  final int excelSerial;
  final String modul;
  final String project;
  final String activity;
  final double hours;
  final double totalDays;
  final double estimatedHeight;

  const FormattedTimesheetRow({
    required this.index,
    required this.date,
    required this.isoDate,
    required this.excelSerial,
    required this.modul,
    required this.project,
    required this.activity,
    required this.hours,
    required this.totalDays,
    required this.estimatedHeight,
  });
}

class FormattedTimesheetData {
  final List<FormattedTimesheetRow> rows;
  final double grandTotalHours;
  final double grandTotalDays;

  const FormattedTimesheetData({
    required this.rows,
    required this.grandTotalHours,
    required this.grandTotalDays,
  });
}

class TimesheetFormatter {
  static const int modulColumnChars = 13;
  static const int projectColumnChars = 22;
  static const int activityColumnChars = 47;
  static const double minRowHeight = 48.0;

  static final DateTime _excelEpochUtc = DateTime.utc(1899, 12, 30);

  static FormattedTimesheetData aggregateLogs(List<DailyLog> logs) {
    final indexedLogs = logs
        .asMap()
        .entries
        .map((e) => (pos: e.key, isoDate: normalizeIsoDate(e.value.date), log: e.value))
        .toList()
      ..sort((a, b) {
        final dateCmp = a.isoDate.compareTo(b.isoDate);
        return dateCmp != 0 ? dateCmp : a.pos.compareTo(b.pos);
      });

    final formattedRows = <FormattedTimesheetRow>[];
    var grandTotalHours = 0.0;
    var grandTotalDays = 0.0;

    for (var i = 0; i < indexedLogs.length; i++) {
      final item = indexedLogs[i];
      final log = item.log;
      final date = _parseCalendarDate(item.isoDate);

      final sortedLines = log.lines
          .asMap()
          .entries
          .toList()
        ..sort((a, b) {
          final orderCmp = a.value.sortOrder.compareTo(b.value.sortOrder);
          if (orderCmp != 0) return orderCmp;
          final aId = a.value.id;
          final bId = b.value.id;
          if (aId != null && bId != null) {
            final idCmp = aId.compareTo(bId);
            if (idCmp != 0) return idCmp;
          }
          return a.key.compareTo(b.key);
        });

      final modules = <String>[];
      final projects = <String>[];
      final activityItems = <String>[];

      for (final entry in sortedLines) {
        final line = entry.value;
        final trimmedModul = line.modul.trim();
        if (trimmedModul.isNotEmpty && !modules.contains(trimmedModul)) {
          modules.add(trimmedModul);
        }

        final trimmedProject = line.project.trim();
        if (trimmedProject.isNotEmpty && !projects.contains(trimmedProject)) {
          projects.add(trimmedProject);
        }

        final descParts = line.description
            .split(RegExp(r'\r?\n'))
            .map((part) => part.trim())
            .where((part) => part.isNotEmpty);

        for (final part in descParts) {
          activityItems.add('${activityItems.length + 1}. $part');
        }
      }

      final modulText = modules.isEmpty ? '-' : modules.join(' / ');
      final projectText = projects.isEmpty ? '-' : projects.join(' / ');
      final activityText = activityItems.join('\n');
      final hours = log.totalHours;
      final totalDays = log.totalDays;

      grandTotalHours += hours;
      grandTotalDays += totalDays;

      formattedRows.add(
        FormattedTimesheetRow(
          index: i + 1,
          date: date,
          isoDate: item.isoDate,
          excelSerial: excelSerialDate(date),
          modul: modulText,
          project: projectText,
          activity: activityText,
          hours: hours,
          totalDays: totalDays,
          estimatedHeight: estimateRowHeight(modulText, projectText, activityText),
        ),
      );
    }

    return FormattedTimesheetData(
      rows: formattedRows,
      grandTotalHours: grandTotalHours,
      grandTotalDays: grandTotalDays,
    );
  }

  static int excelSerialDate(DateTime date) {
    final utcDate = DateTime.utc(date.year, date.month, date.day);
    return utcDate.difference(_excelEpochUtc).inDays;
  }

  static int estimateWrappedLines(String text, int maxCharsPerLine) {
    final width = maxCharsPerLine < 1 ? 1 : maxCharsPerLine;
    if (text.isEmpty) return 1;

    final paragraphs = text.split(RegExp(r'\r?\n'));
    var totalLines = 0;

    for (final paragraph in paragraphs) {
      final trimmed = paragraph.trim();
      if (trimmed.isEmpty) {
        totalLines += 1;
        continue;
      }

      final words = trimmed.split(RegExp(r'\s+'));
      var paragraphLines = 1;
      var currentLineLen = 0;

      for (final word in words) {
        if (word.length > width) {
          if (currentLineLen > 0) {
            paragraphLines += 1;
            currentLineLen = 0;
          }
          final extraLines = (word.length - 1) ~/ width;
          paragraphLines += extraLines;
          currentLineLen = word.length - extraLines * width;
        } else if (currentLineLen == 0) {
          currentLineLen = word.length;
        } else if (currentLineLen + 1 + word.length <= width) {
          currentLineLen += 1 + word.length;
        } else {
          paragraphLines += 1;
          currentLineLen = word.length;
        }
      }

      totalLines += paragraphLines;
    }

    return max(totalLines, 1);
  }

  static double estimateRowHeight(String modul, String project, String activity) {
    final linesC = estimateWrappedLines(modul, modulColumnChars);
    final linesD = estimateWrappedLines(project, projectColumnChars);
    final linesE = estimateWrappedLines(activity, activityColumnChars);
    final maxLines = max(linesC, max(linesD, linesE));
    return max(maxLines * 9.5 + 14.0, minRowHeight);
  }

  static String buildFilename({
    required DateTime cycleMonth,
    required GlobalConfig config,
    required String extension,
  }) {
    final bulanIndo = indonesianMonths[cycleMonth.month - 1];
    final rawName = config.createdByName.trim().isNotEmpty
        ? config.createdByName
        : config.picConsultant;
    final firstName = extractFirstName(rawName, fallback: 'Consultant');
    final cleanExt = extension.startsWith('.') ? extension.substring(1) : extension;
    return 'Timesheet - DATASEA - $bulanIndo - $firstName.$cleanExt';
  }

  static DateTime _parseCalendarDate(String isoDate) {
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(isoDate);
    if (match != null) {
      return DateTime(
        int.parse(match.group(1)!),
        int.parse(match.group(2)!),
        int.parse(match.group(3)!),
      );
    }
    final parsed = DateTime.parse(isoDate);
    return DateTime(parsed.year, parsed.month, parsed.day);
  }
}
