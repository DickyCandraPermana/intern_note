import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/daily_log.dart';
import '../models/global_config.dart';
import '../utils/date_formatters.dart';
import 'pdf_export_engine.dart';
import 'timesheet_formatter.dart';
import 'xlsx_export_engine.dart';

class ExportService {
  static const String _templateAssetPath = 'assets/template.xlsx';
  static const String _logoAssetPath = 'assets/datasea_logo.jpg';
  static const String _signatureAssetPath = 'assets/signature_dicky.png';

  static Future<Uint8List> buildXlsxBytes({
    required List<DailyLog> logs,
    required GlobalConfig config,
    required DateTime exportDate,
    bool? includeSignature,
  }) async {
    final templateBytes = await _loadAssetBytes(_templateAssetPath);
    return XlsxExportEngine.generateBytes(
      templateBytes: templateBytes,
      logs: logs,
      config: config,
      exportDate: exportDate,
      includeSignature: includeSignature ?? config.includeSignature,
    );
  }

  static Future<Uint8List> buildPdfBytes({
    required List<DailyLog> logs,
    required GlobalConfig config,
    required DateTime exportDate,
    bool? includeSignature,
  }) async {
    final effectiveIncludeSignature =
        includeSignature ?? config.includeSignature;
    final logoBytes = await _loadAssetBytes(_logoAssetPath);
    final Uint8List? signatureBytes = effectiveIncludeSignature
        ? await _loadAssetBytes(_signatureAssetPath)
        : null;

    return PdfExportEngine.generateBytes(
      logs: logs,
      config: config,
      exportDate: exportDate,
      includeSignature: effectiveIncludeSignature,
      logoBytes: logoBytes,
      signatureBytes: signatureBytes,
    );
  }

  static Future<File> exportAndShareXlsx({
    required List<DailyLog> logs,
    required GlobalConfig config,
    required DateTime cycleMonth,
    required DateTime exportDate,
    bool? includeSignature,
  }) async {
    final bytes = await buildXlsxBytes(
      logs: logs,
      config: config,
      exportDate: exportDate,
      includeSignature: includeSignature,
    );
    final fileName = TimesheetFormatter.buildFilename(
      cycleMonth: cycleMonth,
      config: config,
      extension: 'xlsx',
    );
    return _writeAndShareFile(
      bytes: bytes,
      fileName: fileName,
      shareText:
          'Timesheet ${indonesianMonths[cycleMonth.month - 1]} ${cycleMonth.year}',
    );
  }

  static Future<File> exportAndSharePdf({
    required List<DailyLog> logs,
    required GlobalConfig config,
    required DateTime cycleMonth,
    required DateTime exportDate,
    bool? includeSignature,
  }) async {
    final bytes = await buildPdfBytes(
      logs: logs,
      config: config,
      exportDate: exportDate,
      includeSignature: includeSignature,
    );
    final fileName = TimesheetFormatter.buildFilename(
      cycleMonth: cycleMonth,
      config: config,
      extension: 'pdf',
    );
    return _writeAndShareFile(
      bytes: bytes,
      fileName: fileName,
      shareText:
          'Timesheet PDF ${indonesianMonths[cycleMonth.month - 1]} ${cycleMonth.year}',
    );
  }

  static Future<Uint8List> _loadAssetBytes(String assetPath) async {
    final data = await rootBundle.load(assetPath);
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }

  static Future<File> _writeAndShareFile({
    required Uint8List bytes,
    required String fileName,
    required String shareText,
  }) async {
    final directory = await getTemporaryDirectory();
    final file = File(p.join(directory.path, fileName));
    await file.writeAsBytes(bytes, flush: true);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        text: shareText,
      ),
    );
    return file;
  }
}
