import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/daily_log.dart';
import '../models/global_config.dart';
import '../utils/date_formatters.dart';
import 'timesheet_formatter.dart';

class PdfExportEngine {
  static final PdfColor _headerFill = PdfColor.fromHex('#BDD7EE');
  static final PdfColor _totalFill = PdfColor.fromHex('#9BC2E6');

  static const pw.EdgeInsets _pageMargin = pw.EdgeInsets.fromLTRB(
    22,
    24,
    22,
    24,
  );

  static const pw.EdgeInsets _cellPadding = pw.EdgeInsets.symmetric(
    horizontal: 4,
    vertical: 3,
  );

  static const Map<int, pw.TableColumnWidth> _columnWidths = {
    0: pw.FixedColumnWidth(24),
    1: pw.FixedColumnWidth(102),
    2: pw.FixedColumnWidth(60),
    3: pw.FixedColumnWidth(92),
    4: pw.FixedColumnWidth(205),
    5: pw.FixedColumnWidth(34),
    6: pw.FixedColumnWidth(34),
  };

  static const List<String> _headers = [
    'No',
    'Date',
    'Modul',
    'Project',
    'Activity',
    'Hours',
    'Total Days',
  ];

  static Future<Uint8List> generateBytes({
    required List<DailyLog> logs,
    required GlobalConfig config,
    required DateTime exportDate,
    required bool includeSignature,
    required Uint8List logoBytes,
    Uint8List? signatureBytes,
  }) async {
    if (logs.isEmpty) {
      throw ArgumentError.value(
        logs,
        'logs',
        'Cannot export an empty log list.',
      );
    }

    final data = TimesheetFormatter.aggregateLogs(logs);
    final logoImage = pw.MemoryImage(logoBytes);
    final pw.MemoryImage? signatureImage =
        (includeSignature &&
                signatureBytes != null &&
                signatureBytes.isNotEmpty)
            ? pw.MemoryImage(signatureBytes)
            : null;

    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: _pageMargin,
        build: (context) => [
          _buildFirstPageHeader(logoImage: logoImage, config: config),
          pw.SizedBox(height: 6),
          _buildTimesheetTable(data),
          pw.SizedBox(height: 16),
          _buildSignatureFooter(
            config: config,
            exportDate: exportDate,
            signatureImage: signatureImage,
          ),
        ],
      ),
    );

    return pdf.save();
  }

  static pw.Widget _buildFirstPageHeader({
    required pw.MemoryImage logoImage,
    required GlobalConfig config,
  }) {
    final titleStyle = pw.TextStyle(
      fontSize: 11,
      fontWeight: pw.FontWeight.bold,
      color: PdfColors.black,
    );
    final subtitleStyle = pw.TextStyle(
      fontSize: 10,
      fontWeight: pw.FontWeight.bold,
      color: PdfColors.black,
    );
    const metaStyle = pw.TextStyle(
      fontSize: 8,
      color: PdfColors.black,
    );

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Stack(
          alignment: pw.Alignment.center,
          children: [
            pw.Align(
              alignment: pw.Alignment.centerLeft,
              child: pw.Image(logoImage, width: 110),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(horizontal: 116),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                mainAxisSize: pw.MainAxisSize.min,
                children: [
                  pw.Text(
                    'PT ACARYA DATA ESA',
                    textAlign: pw.TextAlign.center,
                    style: titleStyle,
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    'Timesheet - System & Data Analyst',
                    textAlign: pw.TextAlign.center,
                    style: subtitleStyle,
                  ),
                ],
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 10),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(
              width: 82,
              child: pw.Text('PIC Consultan', style: metaStyle),
            ),
            pw.Expanded(
              child: pw.Text(
                ': ${_pdfSafeText(config.picConsultant)}',
                style: metaStyle,
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 2),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(
              width: 82,
              child: pw.Text('Role', style: metaStyle),
            ),
            pw.Expanded(
              child: pw.Text(
                ': ${_pdfSafeText(config.role)}',
                style: metaStyle,
              ),
            ),
          ],
        ),
      ],
    );
  }

  static pw.Widget _buildTimesheetTable(FormattedTimesheetData data) {
    final headerTextStyle = pw.TextStyle(
      fontSize: 7,
      fontWeight: pw.FontWeight.bold,
      color: PdfColors.black,
    );
    const dataTextStyle = pw.TextStyle(
      fontSize: 6.8,
      color: PdfColors.black,
    );
    final totalTextStyle = pw.TextStyle(
      fontSize: 6.8,
      fontWeight: pw.FontWeight.bold,
      color: PdfColors.black,
    );

    final tableRows = <pw.TableRow>[
      pw.TableRow(
        repeat: true,
        decoration: pw.BoxDecoration(color: _headerFill),
        verticalAlignment: pw.TableCellVerticalAlignment.full,
        children: _headers
            .map(
              (title) => _tableCell(
                text: title,
                style: headerTextStyle,
                alignment: pw.Alignment.center,
                textAlign: pw.TextAlign.center,
              ),
            )
            .toList(),
      ),
      for (final row in data.rows)
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.white),
          verticalAlignment: pw.TableCellVerticalAlignment.full,
          children: [
            _tableCell(
              text: '${row.index}',
              style: dataTextStyle,
              alignment: pw.Alignment.topCenter,
              textAlign: pw.TextAlign.center,
            ),
            _tableCell(
              text: formatExcelDisplayDate(row.date),
              style: dataTextStyle,
              alignment: pw.Alignment.topCenter,
              textAlign: pw.TextAlign.center,
            ),
            _tableCell(
              text: _pdfSafeText(row.modul),
              style: dataTextStyle,
              alignment: pw.Alignment.topCenter,
              textAlign: pw.TextAlign.center,
            ),
            _tableCell(
              text: _pdfSafeText(row.project),
              style: dataTextStyle,
              alignment: pw.Alignment.topLeft,
              textAlign: pw.TextAlign.left,
            ),
            _tableCell(
              text: _pdfSafeText(row.activity),
              style: dataTextStyle,
              alignment: pw.Alignment.topLeft,
              textAlign: pw.TextAlign.left,
            ),
            _tableCell(
              text: row.hours.toStringAsFixed(1),
              style: dataTextStyle,
              alignment: pw.Alignment.bottomLeft,
              textAlign: pw.TextAlign.left,
            ),
            _tableCell(
              text: row.totalDays.toStringAsFixed(1),
              style: dataTextStyle,
              alignment: pw.Alignment.bottomLeft,
              textAlign: pw.TextAlign.left,
            ),
          ],
        ),
      pw.TableRow(
        decoration: pw.BoxDecoration(color: _totalFill),
        verticalAlignment: pw.TableCellVerticalAlignment.full,
        children: [
          for (var i = 0; i < 5; i++) pw.SizedBox(),
          _tableCell(
            text: data.grandTotalHours.toStringAsFixed(1),
            style: totalTextStyle,
            alignment: pw.Alignment.centerLeft,
            textAlign: pw.TextAlign.left,
          ),
          _tableCell(
            text: data.grandTotalDays.toStringAsFixed(1),
            style: totalTextStyle,
            alignment: pw.Alignment.centerLeft,
            textAlign: pw.TextAlign.left,
          ),
        ],
      ),
    ];

    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.black, width: 0.7),
      columnWidths: _columnWidths,
      defaultVerticalAlignment: pw.TableCellVerticalAlignment.top,
      children: tableRows,
    );
  }

  static pw.Widget _tableCell({
    required String text,
    required pw.TextStyle style,
    required pw.Alignment alignment,
    required pw.TextAlign textAlign,
  }) {
    return pw.Container(
      alignment: alignment,
      padding: _cellPadding,
      child: pw.Text(
        text,
        textAlign: textAlign,
        style: style,
      ),
    );
  }

  static pw.Widget _buildSignatureFooter({
    required GlobalConfig config,
    required DateTime exportDate,
    required pw.MemoryImage? signatureImage,
  }) {
    const footerStyle = pw.TextStyle(
      fontSize: 7,
      color: PdfColors.black,
    );
    final dateStr = 'Date: ${formatIndonesianDate(exportDate)}';
    final hasApprovedBy = config.approvedByName.trim().isNotEmpty;

    final createdCol = pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('Created by', style: footerStyle),
        if (signatureImage != null)
          pw.Image(
            signatureImage,
            width: 72,
            height: 34,
            fit: pw.BoxFit.contain,
            alignment: pw.Alignment.centerLeft,
          )
        else
          pw.SizedBox(height: 34),
        pw.Text(
          'Name: ${_pdfSafeText(config.createdByName)}',
          style: footerStyle,
        ),
        pw.Text(dateStr, style: footerStyle),
      ],
    );

    final leadCol = pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('Approved by Lead Project', style: footerStyle),
        pw.SizedBox(height: 34),
        pw.Text(
          'Name: ${_pdfSafeText(config.approvedByLeadName)}',
          style: footerStyle,
        ),
        pw.Text(dateStr, style: footerStyle),
      ],
    );

    final rowContent = hasApprovedBy
        ? pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.SizedBox(width: 270, child: createdCol),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('Approved by', style: footerStyle),
                    pw.SizedBox(height: 34),
                    pw.Text(
                      'Name: ${_pdfSafeText(config.approvedByName)}',
                      style: footerStyle,
                    ),
                    pw.Text(dateStr, style: footerStyle),
                  ],
                ),
              ),
              pw.SizedBox(width: 116, child: leadCol),
            ],
          )
        : pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.SizedBox(width: 270, child: createdCol),
              pw.SizedBox(width: 116, child: leadCol),
            ],
          );

    // Keep the entire 3-column signature block atomic across page breaks.
    return pw.Inseparable(
      canSpan: false,
      child: rowContent,
    );
  }

  /// Built-in PDF Type1 Helvetica uses WinAnsi/Latin-1 and throws on runes > 0xFF.
  static String _pdfSafeText(String input) {
    if (input.isEmpty) return input;
    var needsNormalization = false;
    for (final rune in input.runes) {
      if (rune > 0xFF) {
        needsNormalization = true;
        break;
      }
    }
    if (!needsNormalization) return input;

    final buffer = StringBuffer();
    for (final rune in input.runes) {
      if (rune <= 0xFF) {
        buffer.writeCharCode(rune);
        continue;
      }
      switch (rune) {
        case 0x2013:
        case 0x2014:
        case 0x2212:
          buffer.write('-');
          break;
        case 0x2018:
        case 0x2019:
          buffer.write("'");
          break;
        case 0x201C:
        case 0x201D:
          buffer.write('"');
          break;
        case 0x2022:
          buffer.write('*');
          break;
        case 0x2026:
          buffer.write('...');
          break;
        case 0x2192:
          buffer.write('->');
          break;
        case 0x2713:
        case 0x2714:
          buffer.write('OK');
          break;
        default:
          buffer.write('?');
          break;
      }
    }
    return buffer.toString();
  }
}
