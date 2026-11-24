import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import '../models/daily_log.dart';
import '../models/global_config.dart';
import '../utils/date_formatters.dart';
import 'timesheet_formatter.dart';

class XlsxExportEngine {
  static const List<String> _columns = ['A', 'B', 'C', 'D', 'E', 'F', 'G'];

  static const String _fallbackA2Style = '32';
  static const List<String?> _fallbackDataStyles = ['30', '28', '24', '17', '17', '9', '9'];
  static const List<String?> _fallbackTotalStyles = ['6', '21', '26', '19', '7', '10', '10'];
  static const List<String?> _fallbackSpacerStyles = ['31', '22', '27', '12', '12', '31', '1'];
  static const List<String?> _fallbackF1Styles = ['37', '33', '34', null, '13', '37', '36'];
  static const List<String?> _fallbackF2Styles = ['37', '33', '34', null, '14', '8', '5'];
  static const List<String?> _fallbackF3Styles = ['39', '33', '34', null, '15', '40', '36'];

  static Uint8List generateBytes({
    required Uint8List templateBytes,
    required List<DailyLog> logs,
    required GlobalConfig config,
    required DateTime exportDate,
    required bool includeSignature,
  }) {
    if (logs.isEmpty) {
      throw ArgumentError.value(logs, 'logs', 'Cannot export an empty log list.');
    }

    final data = TimesheetFormatter.aggregateLogs(logs);
    final archive = ZipDecoder().decodeBytes(templateBytes);

    _removeCalcChain(archive);
    _patchContentTypes(archive);
    _patchWorkbook(archive);
    _patchSheet1(
      archive: archive,
      data: data,
      config: config,
      exportDate: exportDate,
    );
    _patchDrawing1(
      archive: archive,
      rowCount: data.rows.length,
      includeSignature: includeSignature,
    );

    return ZipEncoder().encodeBytes(archive);
  }

  static void _removeCalcChain(Archive archive) {
    final calcChain = archive.find('xl/calcChain.xml');
    if (calcChain != null) {
      archive.removeFile(calcChain);
    }
  }

  static void _patchContentTypes(Archive archive) {
    final doc = _readXml(archive, '[Content_Types].xml');
    if (doc == null) return;

    final toRemove = doc
        .findAllElements('Override')
        .where((el) => el.getAttribute('PartName') == '/xl/calcChain.xml')
        .toList();
    for (final node in toRemove) {
      node.remove();
    }
    _writeXml(archive, '[Content_Types].xml', doc);
  }

  static void _patchWorkbook(Archive archive) {
    final doc = _readXml(archive, 'xl/workbook.xml');
    if (doc == null) return;

    final workbook = doc.rootElement;
    final calcPr = workbook.findElements('calcPr', namespace: '*').firstOrNull;
    if (calcPr != null) {
      calcPr.setAttribute('fullCalcOnLoad', '1');
    } else {
      workbook.children.add(
        XmlElement(
          XmlName('calcPr'),
          [XmlAttribute(XmlName('fullCalcOnLoad'), '1')],
        ),
      );
    }
    _writeXml(archive, 'xl/workbook.xml', doc);
  }

  static void _patchSheet1({
    required Archive archive,
    required FormattedTimesheetData data,
    required GlobalConfig config,
    required DateTime exportDate,
  }) {
    final doc = _readXml(archive, 'xl/worksheets/sheet1.xml');
    if (doc == null) {
      throw StateError('Template archive is missing xl/worksheets/sheet1.xml');
    }

    final worksheet = doc.rootElement;
    final sheetData = worksheet.findElements('sheetData', namespace: '*').first;
    final existingRows = sheetData.findElements('row', namespace: '*').toList();

    final a2Style = _extractCellStyle(existingRows, 'A2') ?? _fallbackA2Style;
    final templateTotalRow = _detectTemplateTotalRowNum(existingRows);
    final dataStyles = _extractRowStyles(existingRows, 4, _fallbackDataStyles);
    final totalStyles = _extractRowStyles(
      existingRows,
      templateTotalRow,
      _fallbackTotalStyles,
    );
    final spacerStyles = _extractRowStyles(
      existingRows,
      templateTotalRow + 1,
      _fallbackSpacerStyles,
    );
    final f1Styles = _extractRowStyles(
      existingRows,
      templateTotalRow + 2,
      _fallbackF1Styles,
    );
    final f2Styles = _extractRowStyles(
      existingRows,
      templateTotalRow + 3,
      _fallbackF2Styles,
    );
    final f3Styles = _extractRowStyles(
      existingRows,
      templateTotalRow + 4,
      _fallbackF3Styles,
    );

    _updateHeaderCellA2(
      rows: existingRows,
      style: a2Style,
      config: config,
    );

    for (final row in existingRows) {
      final rowNum = int.tryParse(row.getAttribute('r') ?? '') ?? 0;
      if (rowNum >= 4) {
        row.remove();
      }
    }

    final n = data.rows.length;
    for (var i = 0; i < n; i++) {
      final rowNum = 4 + i;
      sheetData.children.add(
        _buildDataRow(
          rowNum: rowNum,
          row: data.rows[i],
          styles: dataStyles,
        ),
      );
    }

    final totalRowNum = 4 + n;
    final spacerRowNum = 5 + n;
    final f1RowNum = 6 + n;
    final f2RowNum = 7 + n;
    final f3RowNum = 8 + n;

    sheetData.children.add(
      _buildTotalRow(
        rowNum: totalRowNum,
        lastDataRowNum: 3 + n,
        data: data,
        styles: totalStyles,
      ),
    );
    sheetData.children.add(
      _buildSpacerRow(
        rowNum: spacerRowNum,
        styles: spacerStyles,
      ),
    );

    final dateStr = 'Date: ${formatIndonesianDate(exportDate)}';
    final hasMiddleApprover = config.approvedByName.trim().isNotEmpty;

    sheetData.children.add(
      _buildFooterRow(
        rowNum: f1RowNum,
        height: '65.25',
        styles: f1Styles,
        cellTexts: {
          0: 'Created by\n',
          if (hasMiddleApprover) 4: 'Approved by',
          5: 'Approved by Lead Project',
        },
      ),
    );
    sheetData.children.add(
      _buildFooterRow(
        rowNum: f2RowNum,
        height: '10.05',
        styles: f2Styles,
        cellTexts: {
          0: 'Name: ${config.createdByName}',
          if (hasMiddleApprover) 4: 'Name: ${config.approvedByName}',
          5: 'Name: ${config.approvedByLeadName}',
        },
      ),
    );
    sheetData.children.add(
      _buildFooterRow(
        rowNum: f3RowNum,
        height: '10.05',
        styles: f3Styles,
        cellTexts: {
          0: dateStr,
          if (hasMiddleApprover) 4: dateStr,
          5: dateStr,
        },
      ),
    );

    _updateDimension(worksheet, 'A1:G$f3RowNum');
    _updateMergeCells(
      worksheet: worksheet,
      f1: f1RowNum,
      f2: f2RowNum,
      f3: f3RowNum,
    );

    _writeXml(archive, 'xl/worksheets/sheet1.xml', doc);
  }

  static void _patchDrawing1({
    required Archive archive,
    required int rowCount,
    required bool includeSignature,
  }) {
    final doc = _readXml(archive, 'xl/drawings/drawing1.xml');
    if (doc == null) return;

    final twoCellAnchors = doc
        .findAllElements('twoCellAnchor', namespace: '*')
        .toList();

    for (final anchor in twoCellAnchors) {
      if (!includeSignature) {
        anchor.remove();
        continue;
      }

      final fromRow = anchor
          .findElements('from', namespace: '*')
          .firstOrNull
          ?.findElements('row', namespace: '*')
          .firstOrNull;
      final toRow = anchor
          .findElements('to', namespace: '*')
          .firstOrNull
          ?.findElements('row', namespace: '*')
          .firstOrNull;

      if (fromRow != null) {
        _setElementText(fromRow, '${5 + rowCount}');
      }
      if (toRow != null) {
        _setElementText(toRow, '${6 + rowCount}');
      }
    }

    _writeXml(archive, 'xl/drawings/drawing1.xml', doc);
  }

  static void _updateHeaderCellA2({
    required List<XmlElement> rows,
    required String style,
    required GlobalConfig config,
  }) {
    final row2 = rows
        .where((r) => r.getAttribute('r') == '2')
        .firstOrNull;
    if (row2 == null) return;

    final a2Text =
        'PIC Consultan                         : ${config.picConsultant}\n'
        'Role                                          : ${config.role}';
    final newA2 = _buildInlineStringCell(
      ref: 'A2',
      style: style,
      text: a2Text,
    );

    final cells = row2.children.whereType<XmlElement>().toList();
    final a2Index = cells.indexWhere((c) => c.getAttribute('r') == 'A2');
    if (a2Index >= 0) {
      final oldNode = cells[a2Index];
      final childIdx = row2.children.indexOf(oldNode);
      row2.children[childIdx] = newA2;
    } else {
      row2.children.insert(0, newA2);
    }
  }

  static XmlElement _buildDataRow({
    required int rowNum,
    required FormattedTimesheetRow row,
    required List<String?> styles,
  }) {
    final cells = <XmlElement>[
      _buildNumericCell(
        ref: 'A$rowNum',
        style: styles[0],
        value: '${row.index}',
      ),
      _buildNumericCell(
        ref: 'B$rowNum',
        style: styles[1],
        value: '${row.excelSerial}',
      ),
      _buildInlineStringCell(
        ref: 'C$rowNum',
        style: styles[2],
        text: row.modul,
      ),
      _buildInlineStringCell(
        ref: 'D$rowNum',
        style: styles[3],
        text: row.project,
      ),
      _buildInlineStringCell(
        ref: 'E$rowNum',
        style: styles[4],
        text: row.activity,
      ),
      _buildNumericCell(
        ref: 'F$rowNum',
        style: styles[5],
        value: _formatNumber(row.hours),
      ),
      _buildNumericCell(
        ref: 'G$rowNum',
        style: styles[6],
        value: _formatNumber(row.totalDays),
      ),
    ];

    return XmlElement(
      XmlName('row'),
      [
        XmlAttribute(XmlName('r'), '$rowNum'),
        XmlAttribute(XmlName('spans'), '1:7'),
        XmlAttribute(XmlName('ht'), row.estimatedHeight.toStringAsFixed(1)),
        XmlAttribute(XmlName('customHeight'), '1'),
      ],
      cells,
    );
  }

  static XmlElement _buildTotalRow({
    required int rowNum,
    required int lastDataRowNum,
    required FormattedTimesheetData data,
    required List<String?> styles,
  }) {
    final cells = <XmlElement>[
      for (var col = 0; col < 5; col++)
        _buildEmptyStyledCell(ref: '${_columns[col]}$rowNum', style: styles[col]),
      _buildFormulaCell(
        ref: 'F$rowNum',
        style: styles[5],
        formula: 'SUM(F4:F$lastDataRowNum)',
        cachedValue: _formatNumber(data.grandTotalHours),
      ),
      _buildFormulaCell(
        ref: 'G$rowNum',
        style: styles[6],
        formula: 'SUM(G4:G$lastDataRowNum)',
        cachedValue: _formatNumber(data.grandTotalDays),
      ),
    ];

    return XmlElement(
      XmlName('row'),
      [
        XmlAttribute(XmlName('r'), '$rowNum'),
        XmlAttribute(XmlName('spans'), '1:7'),
        XmlAttribute(XmlName('ht'), '12'),
        XmlAttribute(XmlName('customHeight'), '1'),
      ],
      cells,
    );
  }

  static XmlElement _buildSpacerRow({
    required int rowNum,
    required List<String?> styles,
  }) {
    final cells = <XmlElement>[
      for (var col = 0; col < _columns.length; col++)
        _buildEmptyStyledCell(ref: '${_columns[col]}$rowNum', style: styles[col]),
    ];

    return XmlElement(
      XmlName('row'),
      [
        XmlAttribute(XmlName('r'), '$rowNum'),
        XmlAttribute(XmlName('spans'), '1:7'),
        XmlAttribute(XmlName('ht'), '11.25'),
        XmlAttribute(XmlName('customHeight'), '1'),
      ],
      cells,
    );
  }

  static XmlElement _buildFooterRow({
    required int rowNum,
    required String height,
    required List<String?> styles,
    required Map<int, String> cellTexts,
  }) {
    final cells = <XmlElement>[];
    for (var col = 0; col < _columns.length; col++) {
      final style = styles[col];
      final text = cellTexts[col];
      final ref = '${_columns[col]}$rowNum';
      if (text != null) {
        cells.add(_buildInlineStringCell(ref: ref, style: style, text: text));
      } else if (style != null) {
        cells.add(_buildEmptyStyledCell(ref: ref, style: style));
      }
    }

    return XmlElement(
      XmlName('row'),
      [
        XmlAttribute(XmlName('r'), '$rowNum'),
        XmlAttribute(XmlName('spans'), '1:7'),
        XmlAttribute(XmlName('ht'), height),
        XmlAttribute(XmlName('customHeight'), '1'),
      ],
      cells,
    );
  }

  static XmlElement _buildInlineStringCell({
    required String ref,
    String? style,
    required String text,
  }) {
    return XmlElement(
      XmlName('c'),
      [
        XmlAttribute(XmlName('r'), ref),
        if (style != null) XmlAttribute(XmlName('s'), style),
        XmlAttribute(XmlName('t'), 'inlineStr'),
      ],
      [
        XmlElement(
          XmlName('is'),
          const [],
          [
            XmlElement(
              XmlName('t'),
              [XmlAttribute(XmlName('space', 'xml'), 'preserve')],
              [XmlText(text)],
            ),
          ],
        ),
      ],
    );
  }

  static XmlElement _buildNumericCell({
    required String ref,
    String? style,
    required String value,
  }) {
    return XmlElement(
      XmlName('c'),
      [
        XmlAttribute(XmlName('r'), ref),
        if (style != null) XmlAttribute(XmlName('s'), style),
      ],
      [
        XmlElement(XmlName('v'), const [], [XmlText(value)]),
      ],
    );
  }

  static XmlElement _buildFormulaCell({
    required String ref,
    String? style,
    required String formula,
    required String cachedValue,
  }) {
    return XmlElement(
      XmlName('c'),
      [
        XmlAttribute(XmlName('r'), ref),
        if (style != null) XmlAttribute(XmlName('s'), style),
      ],
      [
        XmlElement(XmlName('f'), const [], [XmlText(formula)]),
        XmlElement(XmlName('v'), const [], [XmlText(cachedValue)]),
      ],
    );
  }

  static XmlElement _buildEmptyStyledCell({
    required String ref,
    String? style,
  }) {
    return XmlElement(
      XmlName('c'),
      [
        XmlAttribute(XmlName('r'), ref),
        if (style != null) XmlAttribute(XmlName('s'), style),
      ],
    );
  }

  static void _updateDimension(XmlElement worksheet, String ref) {
    final dimension = worksheet.findElements('dimension', namespace: '*').firstOrNull;
    if (dimension != null) {
      dimension.setAttribute('ref', ref);
    } else {
      worksheet.children.insert(
        0,
        XmlElement(XmlName('dimension'), [XmlAttribute(XmlName('ref'), ref)]),
      );
    }
  }

  static void _updateMergeCells({
    required XmlElement worksheet,
    required int f1,
    required int f2,
    required int f3,
  }) {
    var mergeCells = worksheet.findElements('mergeCells', namespace: '*').firstOrNull;
    final headerMerges = <String>[];

    if (mergeCells != null) {
      for (final m in mergeCells.findElements('mergeCell', namespace: '*')) {
        final ref = m.getAttribute('ref') ?? '';
        if (_isHeaderMerge(ref)) {
          headerMerges.add(ref);
        }
      }
    }

    if (headerMerges.isEmpty) {
      headerMerges.addAll(['A1:F1', 'A2:F2']);
    }

    final allMerges = <String>[
      ...headerMerges,
      'A$f1:C$f1',
      'A$f2:C$f2',
      'A$f3:C$f3',
      'F$f1:G$f1',
      'F$f3:G$f3',
    ];

    if (mergeCells == null) {
      mergeCells = XmlElement(XmlName('mergeCells'));
      final sheetData = worksheet.findElements('sheetData', namespace: '*').first;
      final idx = worksheet.children.indexOf(sheetData);
      worksheet.children.insert(idx + 1, mergeCells);
    }

    mergeCells.setAttribute('count', '${allMerges.length}');
    mergeCells.children
      ..clear()
      ..addAll(
        allMerges.map(
          (ref) => XmlElement(
            XmlName('mergeCell'),
            [XmlAttribute(XmlName('ref'), ref)],
          ),
        ),
      );
  }

  static bool _isHeaderMerge(String ref) {
    final matches = RegExp(r'[A-Z]+(\d+)').allMatches(ref);
    if (matches.isEmpty) return false;
    return matches.every((m) => (int.tryParse(m.group(1)!) ?? 99) <= 3);
  }

  static String? _extractCellStyle(List<XmlElement> rows, String cellRef) {
    for (final row in rows) {
      for (final cell in row.findElements('c', namespace: '*')) {
        if (cell.getAttribute('r') == cellRef) {
          return cell.getAttribute('s');
        }
      }
    }
    return null;
  }

  static int _detectTemplateTotalRowNum(List<XmlElement> rows) {
    for (final row in rows) {
      final rowNum = int.tryParse(row.getAttribute('r') ?? '') ?? 0;
      if (rowNum < 4) continue;
      final hasSumFormula = row
          .findAllElements('f', namespace: '*')
          .any((f) => f.innerText.toUpperCase().contains('SUM('));
      if (hasSumFormula) {
        return rowNum;
      }
    }
    return 27;
  }

  static List<String?> _extractRowStyles(
    List<XmlElement> rows,
    int rowNum,
    List<String?> fallbacks,
  ) {
    final row = rows
        .where((r) => r.getAttribute('r') == '$rowNum')
        .firstOrNull;
    if (row == null) {
      return List<String?>.from(fallbacks);
    }

    final cellByRef = <String, XmlElement>{};
    for (final cell in row.findElements('c', namespace: '*')) {
      final ref = cell.getAttribute('r');
      if (ref != null) {
        cellByRef[ref] = cell;
      }
    }

    return List<String?>.generate(_columns.length, (col) {
      final ref = '${_columns[col]}$rowNum';
      final cell = cellByRef[ref];
      if (cell == null) {
        return fallbacks[col];
      }
      return cell.getAttribute('s') ?? fallbacks[col];
    });
  }

  static XmlDocument? _readXml(Archive archive, String path) {
    final file = archive.find(path);
    if (file == null) return null;
    final bytes = file.readBytes();
    if (bytes == null) return null;
    return XmlDocument.parse(utf8.decode(bytes));
  }

  static void _writeXml(Archive archive, String path, XmlDocument doc) {
    final encoded = utf8.encode(doc.toXmlString(pretty: false));
    archive.add(ArchiveFile.bytes(path, encoded));
  }

  static void _setElementText(XmlElement element, String text) {
    element.children
      ..clear()
      ..add(XmlText(text));
  }

  static String _formatNumber(double value) {
    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }
    final formatted = value.toStringAsFixed(4);
    return formatted.replaceFirst(RegExp(r'\.?0+$'), '');
  }
}
