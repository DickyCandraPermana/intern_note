import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intern_noter/models/daily_log.dart';
import 'package:intern_noter/models/global_config.dart';
import 'package:intern_noter/services/timesheet_formatter.dart';
import 'package:intern_noter/services/xlsx_export_engine.dart';
import 'package:xml/xml.dart';

GlobalConfig _sampleConfig({
  String picConsultant = 'Dicky Candra Permana',
  String role = 'Front-end and Odoo Developer',
  String createdByName = 'Dicky Candra Permana',
  String approvedByName = 'Ardya Pusaka',
  String approvedByLeadName = 'Joko Setiyo Lelono',
  bool includeSignature = true,
}) {
  return GlobalConfig.defaults().copyWith(
    picConsultant: picConsultant,
    role: role,
    createdByName: createdByName,
    approvedByName: approvedByName,
    approvedByLeadName: approvedByLeadName,
    includeSignature: includeSignature,
  );
}

List<DailyLog> _buildSampleLogs(int count, {DateTime? startDate}) {
  final start = startDate ?? DateTime(2026, 10, 23);
  return List<DailyLog>.generate(count, (i) {
    final d = start.add(Duration(days: i));
    final iso =
        '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    return DailyLog(
      id: i + 1,
      date: iso,
      baseHours: 8.0,
      overworkHours: 0.0,
      lines: [
        ActivityLine(
          id: i * 2 + 1,
          dailyLogId: i + 1,
          modul: 'OMS',
          project: 'Kraft Heinz (OMS)',
          description: 'Daily Scrum 7E\nSync deployment progress',
          sortOrder: 0,
        ),
        ActivityLine(
          id: i * 2 + 2,
          dailyLogId: i + 1,
          modul: 'Payment',
          project: 'EVOQ 7E',
          description: 'Refactor date formatter',
          sortOrder: 1,
        ),
      ],
    );
  });
}

XmlDocument _readXmlFromZip(Archive archive, String path) {
  final file = archive.find(path);
  expect(file, isNotNull, reason: 'Expected $path in zip archive');
  final bytes = file!.readBytes();
  expect(bytes, isNotNull);
  return XmlDocument.parse(utf8.decode(bytes!));
}

XmlElement? _findCell(XmlDocument sheetDoc, String cellRef) {
  for (final cell in sheetDoc.findAllElements('c')) {
    if (cell.getAttribute('r') == cellRef) {
      return cell;
    }
  }
  return null;
}

String _readCellText(XmlDocument sheetDoc, String cellRef) {
  final cell = _findCell(sheetDoc, cellRef);
  if (cell == null) return '';
  final inlineT = cell.findAllElements('t').firstOrNull;
  if (inlineT != null) return inlineT.innerText;
  final v = cell.findElements('v').firstOrNull;
  return v?.innerText ?? '';
}

void main() {
  late Uint8List templateBytes;

  setUpAll(() {
    templateBytes = File('assets/template.xlsx').readAsBytesSync();
  });

  group('TimesheetFormatter', () {
    test('sorts logs by normalized date and lines by sortOrder', () {
      final logs = [
        DailyLog(
          date: '2026-11-02T14:00:00.000',
          baseHours: 8.0,
          overworkHours: 1.0,
          lines: [
            ActivityLine(
              modul: 'Payment',
              project: 'EVOQ 7E',
              description: 'Second task\r\nThird task',
              sortOrder: 2,
            ),
            ActivityLine(
              modul: ' OMS ',
              project: 'Kraft Heinz (OMS)',
              description: 'First task',
              sortOrder: 0,
            ),
            ActivityLine(
              modul: 'OMS',
              project: 'Kraft Heinz (OMS)',
              description: '  \n  ',
              sortOrder: 1,
            ),
          ],
        ),
        DailyLog(
          date: '2026-10-23',
          baseHours: 8.0,
          overworkHours: 0.0,
          lines: [
            ActivityLine(
              modul: '',
              project: '',
              description: 'Quick note only',
              sortOrder: 0,
            ),
          ],
        ),
      ];

      final formatted = TimesheetFormatter.aggregateLogs(logs);
      expect(formatted.rows.length, 2);

      final first = formatted.rows[0];
      expect(first.index, 1);
      expect(first.isoDate, '2026-10-23');
      expect(first.excelSerial, 46318);
      expect(first.modul, '-');
      expect(first.project, '-');
      expect(first.activity, '1. Quick note only');

      final second = formatted.rows[1];
      expect(second.index, 2);
      expect(second.isoDate, '2026-11-02');
      expect(second.modul, 'OMS / Payment');
      expect(second.project, 'Kraft Heinz (OMS) / EVOQ 7E');
      expect(
        second.activity,
        '1. First task\n2. Second task\n3. Third task',
      );
      expect(formatted.grandTotalHours, 17.0);
      expect(formatted.grandTotalDays, 2.125);
    });

    test('estimates wrapped lines and enforces minimum row height 48.0', () {
      expect(TimesheetFormatter.estimateWrappedLines('Short', 47), 1);
      expect(TimesheetFormatter.estimateWrappedLines('A\nB\nC', 47), 3);
      expect(TimesheetFormatter.estimateWrappedLines('x' * 95, 47), 3);
      expect(TimesheetFormatter.estimateRowHeight('OMS', 'EVOQ', 'Short'), 48.0);

      final tallHeight = TimesheetFormatter.estimateRowHeight(
        'OMS',
        'EVOQ 7E',
        List.generate(6, (i) => '${i + 1}. Line item ${i + 1}').join('\n'),
      );
      expect(tallHeight, greaterThan(48.0));
      expect(tallHeight, 6 * 9.5 + 14.0);
    });

    test('builds DataSea filename with Indonesian month and first name fallback', () {
      expect(
        TimesheetFormatter.buildFilename(
          cycleMonth: DateTime(2026, 11, 1),
          config: _sampleConfig(),
          extension: 'xlsx',
        ),
        'Timesheet - DATASEA - November - Dicky.xlsx',
      );
      expect(
        TimesheetFormatter.buildFilename(
          cycleMonth: DateTime(2026, 12, 1),
          config: _sampleConfig(
            createdByName: '',
            picConsultant: 'Ardya Pusaka',
          ),
          extension: '.pdf',
        ),
        'Timesheet - DATASEA - Desember - Ardya.pdf',
      );
      expect(
        TimesheetFormatter.buildFilename(
          cycleMonth: DateTime(2026, 1, 1),
          config: _sampleConfig(createdByName: '  ', picConsultant: ''),
          extension: 'xlsx',
        ),
        'Timesheet - DATASEA - Januari - Consultant.xlsx',
      );
    });
  });

  group('XlsxExportEngine', () {
    test('throws ArgumentError when logs list is empty', () {
      expect(
        () => XlsxExportEngine.generateBytes(
          templateBytes: templateBytes,
          logs: const [],
          config: _sampleConfig(),
          exportDate: DateTime(2026, 11, 24),
          includeSignature: true,
        ),
        throwsArgumentError,
      );
    });

    test(
      'exports 23 days matching November template anchors, SUM formulas, merges, and drops calcChain',
      () {
        final logs = _buildSampleLogs(23, startDate: DateTime(2026, 10, 23));
        final outBytes = XlsxExportEngine.generateBytes(
          templateBytes: templateBytes,
          logs: logs,
          config: _sampleConfig(),
          exportDate: DateTime(2026, 11, 24),
          includeSignature: true,
        );

        final archive = ZipDecoder().decodeBytes(outBytes);
        expect(archive.find('xl/calcChain.xml'), isNull);

        final contentTypes = _readXmlFromZip(archive, '[Content_Types].xml');
        final hasCalcChainOverride = contentTypes
            .findAllElements('Override')
            .any((el) => el.getAttribute('PartName') == '/xl/calcChain.xml');
        expect(hasCalcChainOverride, isFalse);

        final workbookDoc = _readXmlFromZip(archive, 'xl/workbook.xml');
        final calcPr = workbookDoc.findAllElements('calcPr').firstOrNull;
        expect(calcPr, isNotNull);
        expect(calcPr!.getAttribute('fullCalcOnLoad'), '1');

        final sheetDoc = _readXmlFromZip(archive, 'xl/worksheets/sheet1.xml');
        final a2Text = _readCellText(sheetDoc, 'A2');
        expect(a2Text, contains('PIC Consultan'));
        expect(a2Text, contains('Role'));
        expect(a2Text, contains('Dicky Candra Permana'));
        expect(a2Text, contains('Front-end and Odoo Developer'));

        final b4 = _findCell(sheetDoc, 'B4');
        expect(b4, isNotNull);
        expect(b4!.findElements('v').first.innerText, '46318');

        final f27 = _findCell(sheetDoc, 'F27');
        final g27 = _findCell(sheetDoc, 'G27');
        expect(f27?.findElements('f').firstOrNull?.innerText, 'SUM(F4:F26)');
        expect(g27?.findElements('f').firstOrNull?.innerText, 'SUM(G4:G26)');
        expect(f27?.findElements('v').firstOrNull?.innerText, '184');
        expect(g27?.findElements('v').firstOrNull?.innerText, '23');

        final dimension = sheetDoc.findAllElements('dimension').firstOrNull;
        expect(dimension?.getAttribute('ref'), 'A1:G31');

        final mergeCellsEl = sheetDoc.findAllElements('mergeCells').firstOrNull;
        expect(mergeCellsEl?.getAttribute('count'), '7');
        final mergeRefs = mergeCellsEl!
            .findElements('mergeCell')
            .map((e) => e.getAttribute('ref'))
            .toSet();
        expect(
          mergeRefs,
          containsAll([
            'A1:F1',
            'A2:F2',
            'A29:C29',
            'A30:C30',
            'A31:C31',
            'F29:G29',
            'F31:G31',
          ]),
        );

        expect(_readCellText(sheetDoc, 'A29'), 'Created by\n');
        expect(_readCellText(sheetDoc, 'A30'), 'Name: Dicky Candra Permana');
        expect(_readCellText(sheetDoc, 'A31'), 'Date: 24 November 2026');
        expect(_readCellText(sheetDoc, 'E29'), 'Approved by');
        expect(_readCellText(sheetDoc, 'E30'), 'Name: Ardya Pusaka');
        expect(_readCellText(sheetDoc, 'E31'), 'Date: 24 November 2026');
        expect(_readCellText(sheetDoc, 'F29'), 'Approved by Lead Project');
        expect(_readCellText(sheetDoc, 'F30'), 'Name: Joko Setiyo Lelono');
        expect(_readCellText(sheetDoc, 'F31'), 'Date: 24 November 2026');

        final drawingDoc = _readXmlFromZip(archive, 'xl/drawings/drawing1.xml');
        final oneCellAnchors = drawingDoc
            .findAllElements('oneCellAnchor', namespace: '*')
            .toList();
        expect(oneCellAnchors.length, 1);
        final blip = oneCellAnchors.first
            .findAllElements('blip', namespace: '*')
            .first;
        expect(blip.getAttribute('r:embed'), 'rId2');

        final twoCellAnchors = drawingDoc
            .findAllElements('twoCellAnchor', namespace: '*')
            .toList();
        expect(twoCellAnchors.length, 1);
        final fromRow = twoCellAnchors.first
            .findElements('from', namespace: '*')
            .first
            .findElements('row', namespace: '*')
            .first
            .innerText;
        final toRow = twoCellAnchors.first
            .findElements('to', namespace: '*')
            .first
            .findElements('row', namespace: '*')
            .first
            .innerText;
        expect(fromRow, '28');
        expect(toRow, '29');
      },
    );

    test(
      'exports 5 days without leaving stale rows > 13 and shifts signature anchor to 10..11',
      () {
        final logs = _buildSampleLogs(5, startDate: DateTime(2026, 11, 2));
        final outBytes = XlsxExportEngine.generateBytes(
          templateBytes: templateBytes,
          logs: logs,
          config: _sampleConfig(),
          exportDate: DateTime(2026, 11, 24),
          includeSignature: true,
        );

        final archive = ZipDecoder().decodeBytes(outBytes);
        final sheetDoc = _readXmlFromZip(archive, 'xl/worksheets/sheet1.xml');

        final rowNums = sheetDoc
            .findAllElements('row')
            .map((r) => int.parse(r.getAttribute('r')!))
            .toList();
        expect(rowNums.reduce((a, b) => a > b ? a : b), 13);
        expect(rowNums.where((r) => r > 13), isEmpty);

        final f9 = _findCell(sheetDoc, 'F9');
        final g9 = _findCell(sheetDoc, 'G9');
        expect(f9?.findElements('f').firstOrNull?.innerText, 'SUM(F4:F8)');
        expect(g9?.findElements('f').firstOrNull?.innerText, 'SUM(G4:G8)');

        final dimension = sheetDoc.findAllElements('dimension').firstOrNull;
        expect(dimension?.getAttribute('ref'), 'A1:G13');

        final mergeRefs = sheetDoc
            .findAllElements('mergeCell')
            .map((e) => e.getAttribute('ref'))
            .toSet();
        expect(
          mergeRefs,
          containsAll([
            'A11:C11',
            'A12:C12',
            'A13:C13',
            'F11:G11',
            'F13:G13',
          ]),
        );

        final drawingDoc = _readXmlFromZip(archive, 'xl/drawings/drawing1.xml');
        final twoCell = drawingDoc
            .findAllElements('twoCellAnchor', namespace: '*')
            .single;
        expect(
          twoCell
              .findElements('from', namespace: '*')
              .single
              .findElements('row', namespace: '*')
              .single
              .innerText,
          '10',
        );
        expect(
          twoCell
              .findElements('to', namespace: '*')
              .single
              .findElements('row', namespace: '*')
              .single
              .innerText,
          '11',
        );
      },
    );

    test('omits signature anchor when includeSignature is false while keeping logo', () {
      final logs = _buildSampleLogs(5, startDate: DateTime(2026, 11, 2));
      final outBytes = XlsxExportEngine.generateBytes(
        templateBytes: templateBytes,
        logs: logs,
        config: _sampleConfig(includeSignature: false),
        exportDate: DateTime(2026, 11, 24),
        includeSignature: false,
      );

      final archive = ZipDecoder().decodeBytes(outBytes);
      final drawingDoc = _readXmlFromZip(archive, 'xl/drawings/drawing1.xml');
      expect(
        drawingDoc.findAllElements('twoCellAnchor', namespace: '*').length,
        0,
      );
      expect(
        drawingDoc.findAllElements('oneCellAnchor', namespace: '*').length,
        1,
      );
    });

    test(
      'escapes XML special characters and joins uncategorized/mixed tags cleanly',
      () {
        final logs = [
          DailyLog(
            date: '2026-11-02',
            baseHours: 8.0,
            overworkHours: 0.0,
            lines: [
              ActivityLine(
                modul: '',
                project: '',
                description: 'R&D <tag> "quote" \'single\'',
                sortOrder: 0,
              ),
              ActivityLine(
                modul: 'Payment',
                project: 'EVOQ 7E',
                description: 'Fix API',
                sortOrder: 1,
              ),
            ],
          ),
          DailyLog(
            date: '2026-11-03',
            baseHours: 8.0,
            overworkHours: 0.0,
            lines: [
              ActivityLine(
                modul: '',
                project: '',
                description: 'Quick note',
                sortOrder: 0,
              ),
            ],
          ),
        ];

        final outBytes = XlsxExportEngine.generateBytes(
          templateBytes: templateBytes,
          logs: logs,
          config: _sampleConfig(),
          exportDate: DateTime(2026, 11, 24),
          includeSignature: true,
        );

        final archive = ZipDecoder().decodeBytes(outBytes);
        final sheetDoc = _readXmlFromZip(archive, 'xl/worksheets/sheet1.xml');

        expect(_readCellText(sheetDoc, 'C4'), 'Payment');
        expect(_readCellText(sheetDoc, 'D4'), 'EVOQ 7E');
        expect(
          _readCellText(sheetDoc, 'E4'),
          '1. R&D <tag> "quote" \'single\'\n2. Fix API',
        );

        expect(_readCellText(sheetDoc, 'C5'), '-');
        expect(_readCellText(sheetDoc, 'D5'), '-');
        expect(_readCellText(sheetDoc, 'E5'), '1. Quick note');
      },
    );

    test('preserves UTF-8 characters cleanly in inline strings', () {
      final logs = [
        DailyLog(
          date: '2026-11-04',
          baseHours: 8.0,
          overworkHours: 0.0,
          lines: [
            ActivityLine(
              modul: 'OMS',
              project: 'Kraft Heinz (OMS)',
              description: 'Sinkronisasi modul café & metrik >= 95% ✓',
              sortOrder: 0,
            ),
          ],
        ),
      ];

      final outBytes = XlsxExportEngine.generateBytes(
        templateBytes: templateBytes,
        logs: logs,
        config: _sampleConfig(picConsultant: 'Dicky Candra ✓'),
        exportDate: DateTime(2026, 11, 24),
        includeSignature: true,
      );

      final archive = ZipDecoder().decodeBytes(outBytes);
      final sheetDoc = _readXmlFromZip(archive, 'xl/worksheets/sheet1.xml');
      expect(_readCellText(sheetDoc, 'A2'), contains('Dicky Candra ✓'));
      expect(
        _readCellText(sheetDoc, 'E4'),
        '1. Sinkronisasi modul café & metrik >= 95% ✓',
      );
    });

    test('omits middle Approved by block when approvedByName is blank', () {
      final logs = _buildSampleLogs(3, startDate: DateTime(2026, 11, 2));
      final outBytes = XlsxExportEngine.generateBytes(
        templateBytes: templateBytes,
        logs: logs,
        config: _sampleConfig(approvedByName: '   '),
        exportDate: DateTime(2026, 11, 24),
        includeSignature: true,
      );

      final archive = ZipDecoder().decodeBytes(outBytes);
      final sheetDoc = _readXmlFromZip(archive, 'xl/worksheets/sheet1.xml');

      // f1 = 6 + 3 = 9, f2 = 10, f3 = 11
      expect(_readCellText(sheetDoc, 'A9'), 'Created by\n');
      expect(_readCellText(sheetDoc, 'F9'), 'Approved by Lead Project');
      expect(_readCellText(sheetDoc, 'E9'), '');
      expect(_readCellText(sheetDoc, 'E10'), '');
      expect(_readCellText(sheetDoc, 'E11'), '');
    });
  });
}
