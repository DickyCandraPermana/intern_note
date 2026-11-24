import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

class PdfPreviewScreen extends StatelessWidget {
  final Future<Uint8List> Function() buildPdf;
  final String fileName;
  final String title;

  const PdfPreviewScreen({
    super.key,
    required this.buildPdf,
    required this.fileName,
    this.title = 'Preview Timesheet PDF',
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
      ),
      body: PdfPreview(
        build: (_) => buildPdf(),
        initialPageFormat: PdfPageFormat.a4,
        canChangeOrientation: false,
        canChangePageFormat: false,
        canDebug: false,
        allowSharing: true,
        allowPrinting: true,
        pdfFileName: fileName,
      ),
    );
  }
}
