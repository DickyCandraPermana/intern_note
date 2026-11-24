import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intern_noter/models/daily_log.dart';
import 'package:intern_noter/models/global_config.dart';
import 'package:intern_noter/screens/pdf_preview_screen.dart';
import 'package:intern_noter/services/export_service.dart';
import 'package:intern_noter/services/pdf_export_engine.dart';
import 'package:printing/printing.dart';

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
          description: 'Daily Scrum 7E\nSync deployment progress & verification',
          sortOrder: 0,
        ),
        ActivityLine(
          id: i * 2 + 2,
          dailyLogId: i + 1,
          modul: 'Payment',
          project: 'EVOQ 7E',
          description: 'Refactor date formatter & submit PR',
          sortOrder: 1,
        ),
      ],
    );
  });
}

void main() {
  late Uint8List logoBytes;
  late Uint8List signatureBytes;

  setUpAll(() {
    logoBytes = File('assets/datasea_logo.jpg').readAsBytesSync();
    signatureBytes = File('assets/signature_dicky.png').readAsBytesSync();
  });

  group('PdfExportEngine', () {
    test('throws ArgumentError when logs list is empty', () async {
      await expectLater(
        () => PdfExportEngine.generateBytes(
          logs: const [],
          config: _sampleConfig(),
          exportDate: DateTime(2026, 11, 24),
          includeSignature: true,
          logoBytes: logoBytes,
          signatureBytes: signatureBytes,
        ),
        throwsArgumentError,
      );
    });

    test('generates valid A4 portrait PDF bytes with logo and signature', () async {
      final logs = _buildSampleLogs(23, startDate: DateTime(2026, 10, 23));
      final bytes = await PdfExportEngine.generateBytes(
        logs: logs,
        config: _sampleConfig(),
        exportDate: DateTime(2026, 11, 24),
        includeSignature: true,
        logoBytes: logoBytes,
        signatureBytes: signatureBytes,
      );

      expect(bytes.length, greaterThan(5000));
      expect(bytes.sublist(0, 5), [0x25, 0x50, 0x44, 0x46, 0x2D]);
    });

    test(
      'generates valid PDF with includeSignature false and optional Approved by omitted',
      () async {
        final logs = _buildSampleLogs(5, startDate: DateTime(2026, 11, 2));

        final signedBytes = await PdfExportEngine.generateBytes(
          logs: logs,
          config: _sampleConfig(approvedByName: 'Ardya Pusaka'),
          exportDate: DateTime(2026, 11, 24),
          includeSignature: true,
          logoBytes: logoBytes,
          signatureBytes: signatureBytes,
        );

        final unsignedBytesWithSigProvided = await PdfExportEngine.generateBytes(
          logs: logs,
          config: _sampleConfig(
            approvedByName: '   ',
            includeSignature: false,
          ),
          exportDate: DateTime(2026, 11, 24),
          includeSignature: false,
          logoBytes: logoBytes,
          signatureBytes: signatureBytes,
        );

        final unsignedBytesNoSig = await PdfExportEngine.generateBytes(
          logs: logs,
          config: _sampleConfig(
            approvedByName: '',
            includeSignature: false,
          ),
          exportDate: DateTime(2026, 11, 24),
          includeSignature: false,
          logoBytes: logoBytes,
          signatureBytes: null,
        );

        expect(unsignedBytesWithSigProvided.sublist(0, 5), [0x25, 0x50, 0x44, 0x46, 0x2D]);
        expect(unsignedBytesNoSig.sublist(0, 5), [0x25, 0x50, 0x44, 0x46, 0x2D]);
        expect(unsignedBytesWithSigProvided.length, lessThan(signedBytes.length));
        expect(unsignedBytesNoSig.length, lessThan(signedBytes.length));
      },
    );

    test('handles uncategorized quick notes and unsorted timestamped logs', () async {
      final logs = [
        DailyLog(
          date: '2026-11-04T09:30:00.000',
          baseHours: 8.0,
          overworkHours: 1.5,
          lines: [
            ActivityLine(
              modul: '',
              project: '',
              description: 'Quick note without tags',
              sortOrder: 0,
            ),
          ],
        ),
        DailyLog(
          date: '2026-11-02',
          baseHours: 8.0,
          overworkHours: 0.0,
          lines: [
            ActivityLine(
              modul: 'OMS',
              project: 'Kraft Heinz (OMS)',
              description: 'Daily Scrum 7E\nBuild verification',
              sortOrder: 0,
            ),
          ],
        ),
      ];

      final bytes = await PdfExportEngine.generateBytes(
        logs: logs,
        config: _sampleConfig(approvedByName: ''),
        exportDate: DateTime(2026, 11, 24),
        includeSignature: false,
        logoBytes: logoBytes,
      );

      expect(bytes.sublist(0, 5), [0x25, 0x50, 0x44, 0x46, 0x2D]);
      expect(bytes.length, greaterThan(3000));
    });

    test('normalizes non-Latin-1 punctuation and symbols without throwing', () async {
      final logs = [
        DailyLog(
          date: '2026-11-05',
          baseHours: 8.0,
          overworkHours: 0.0,
          lines: [
            ActivityLine(
              modul: 'Payment',
              project: 'EVOQ 7E',
              description:
                  'PR\u2013Payment \u201Cstaging\u201D \u2022 verified \u2713 \u2192 ready',
              sortOrder: 0,
            ),
          ],
        ),
      ];

      final bytes = await PdfExportEngine.generateBytes(
        logs: logs,
        config: _sampleConfig(picConsultant: 'Dicky \u2013 Consultant'),
        exportDate: DateTime(2026, 11, 24),
        includeSignature: false,
        logoBytes: logoBytes,
      );

      expect(bytes.sublist(0, 5), [0x25, 0x50, 0x44, 0x46, 0x2D]);
    });
  });

  group('ExportService builders', () {
    setUpAll(() {
      TestWidgetsFlutterBinding.ensureInitialized();
    });

    test('buildXlsxBytes and buildPdfBytes load bundled assets and respect includeSignature', () async {
      final logs = _buildSampleLogs(3, startDate: DateTime(2026, 11, 2));
      final config = _sampleConfig();

      final xlsxSigned = await ExportService.buildXlsxBytes(
        logs: logs,
        config: config,
        exportDate: DateTime(2026, 11, 24),
        includeSignature: true,
      );
      final xlsxUnsigned = await ExportService.buildXlsxBytes(
        logs: logs,
        config: config,
        exportDate: DateTime(2026, 11, 24),
        includeSignature: false,
      );

      expect(xlsxSigned.sublist(0, 2), [0x50, 0x4B]);
      final signedArchive = ZipDecoder().decodeBytes(xlsxSigned);
      final unsignedArchive = ZipDecoder().decodeBytes(xlsxUnsigned);
      final signedDrawing = utf8.decode(
        signedArchive.find('xl/drawings/drawing1.xml')!.readBytes()!,
      );
      final unsignedDrawing = utf8.decode(
        unsignedArchive.find('xl/drawings/drawing1.xml')!.readBytes()!,
      );
      expect(signedDrawing, contains('twoCellAnchor'));
      expect(unsignedDrawing, isNot(contains('twoCellAnchor')));

      final pdfSigned = await ExportService.buildPdfBytes(
        logs: logs,
        config: config,
        exportDate: DateTime(2026, 11, 24),
        includeSignature: true,
      );
      final pdfUnsigned = await ExportService.buildPdfBytes(
        logs: logs,
        config: config,
        exportDate: DateTime(2026, 11, 24),
        includeSignature: false,
      );

      expect(pdfSigned.sublist(0, 5), [0x25, 0x50, 0x44, 0x46, 0x2D]);
      expect(pdfUnsigned.sublist(0, 5), [0x25, 0x50, 0x44, 0x46, 0x2D]);
      expect(pdfUnsigned.length, lessThan(pdfSigned.length));
    });
  });

  group('PdfPreviewScreen', () {
    testWidgets('configures A4 Portrait PdfPreview with fixed format and sharing', (
      WidgetTester tester,
    ) async {
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

      final logs = _buildSampleLogs(2, startDate: DateTime(2026, 11, 2));
      final pdfBytes = await PdfExportEngine.generateBytes(
        logs: logs,
        config: _sampleConfig(),
        exportDate: DateTime(2026, 11, 24),
        includeSignature: false,
        logoBytes: logoBytes,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: PdfPreviewScreen(
            buildPdf: () async => pdfBytes,
            fileName: 'Timesheet - DATASEA - November - Dicky.pdf',
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Preview Timesheet PDF'), findsOneWidget);
      final preview = tester.widget<PdfPreview>(find.byType(PdfPreview));
      expect(preview.canChangeOrientation, isFalse);
      expect(preview.canChangePageFormat, isFalse);
      expect(preview.allowSharing, isTrue);
      expect(preview.allowPrinting, isTrue);
      expect(
        preview.pdfFileName,
        'Timesheet - DATASEA - November - Dicky.pdf',
      );
    });
  });
}
