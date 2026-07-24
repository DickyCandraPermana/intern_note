import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:excel/excel.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import '../models/daily_log.dart';
import '../models/global_config.dart';

class ExportService {
  static Future<void> exportToXlsx(List<DailyLog> logs, GlobalConfig config, DateTime month, DateTime exportDate) async {
    final ByteData data = await rootBundle.load('assets/template.xlsx');
    var bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    var excel = Excel.decodeBytes(bytes);
    
    String sheetName = excel.tables.keys.first;
    Sheet sheetObject = excel.tables[sheetName]!;

    sheetObject.cell(CellIndex.indexByString("A2")).value = TextCellValue(
      "PIC Consultan                         : ${config.picConsultant}\n"
      "Role                                          : ${config.role}"
    );

    List<Map<String, dynamic>> finalData = [];
    double grandTotalHours = 0;
    double grandTotalDays = 0;

    for (var log in logs) {
      List<String> modules = [];
      List<String> projects = [];
      List<String> activityTexts = [];
      
      for (var line in log.lines) {
        if (!modules.contains(line.modul)) modules.add(line.modul);
        if (!projects.contains(line.project)) projects.add(line.project);
        
        final descLines = line.description.split('\n').where((l) => l.trim().isNotEmpty).toList();
        for (var desc in descLines) {
          activityTexts.add('${activityTexts.length + 1}. $desc');
        }
      }
      
      finalData.add({
        'date': log.date,
        'modul': modules.join('; '),
        'project': projects.join('; '),
        'activity': activityTexts.join('\n'),
        'hours': log.totalHours,
        'totalDays': log.totalDays,
      });

      grandTotalHours += log.totalHours;
      grandTotalDays += log.totalDays;
    }

    // Clear old data rows from the template (row 6 down to 100)
    for (int r = 5; r <= 100; r++) {
      for (int c = 0; c <= 6; c++) {
        sheetObject.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r)).value = null;
      }
    }

    int currentRow = 5;
    
    for (int i = 0; i < finalData.length; i++) {
      final rowData = finalData[i];
      sheetObject.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: currentRow)).value = IntCellValue(i + 1);
      sheetObject.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: currentRow)).value = TextCellValue(DateFormat('dd MMMM yyyy').format(DateTime.parse(rowData['date'])));
      sheetObject.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: currentRow)).value = TextCellValue(rowData['modul']);
      sheetObject.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: currentRow)).value = TextCellValue(rowData['project']);
      sheetObject.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: currentRow)).value = TextCellValue(rowData['activity']);
      sheetObject.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: currentRow)).value = DoubleCellValue(rowData['hours']);
      sheetObject.cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: currentRow)).value = DoubleCellValue(rowData['totalDays']);
      currentRow++;
    }

    // Add Sum Row
    sheetObject.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: currentRow)).value = DoubleCellValue(grandTotalHours);
    sheetObject.cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: currentRow)).value = DoubleCellValue(grandTotalDays);
    
    currentRow += 2; // empty lines
    
    int signatureRowIndex = currentRow;

    sheetObject.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: signatureRowIndex)).value = TextCellValue("Created by");
    if (config.approvedByName.isNotEmpty) {
      sheetObject.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: signatureRowIndex)).value = TextCellValue("Approved by");
      sheetObject.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: signatureRowIndex + 2)).value = TextCellValue("Name: ${config.approvedByName}");
      sheetObject.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: signatureRowIndex + 3)).value = TextCellValue("Date: ${DateFormat('dd MMMM yyyy').format(exportDate)}");
    }
    
    sheetObject.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: signatureRowIndex)).value = TextCellValue("Approved by Lead Project");
    
    sheetObject.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: signatureRowIndex + 2)).value = TextCellValue("Name: ${config.createdByName}");
    sheetObject.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: signatureRowIndex + 2)).value = TextCellValue("Name: ${config.approvedByLeadName}");
    
    String exportDateStr = "Date: ${DateFormat('dd MMMM yyyy').format(exportDate)}";
    sheetObject.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: signatureRowIndex + 3)).value = TextCellValue(exportDateStr);
    sheetObject.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: signatureRowIndex + 3)).value = TextCellValue(exportDateStr);

    var fileBytes = excel.save();
    
    final directory = await getTemporaryDirectory();
    final fileName = 'Timesheet_${DateFormat('MMM_yyyy').format(month)}.xlsx';
    final path = '${directory.path}/$fileName';
    final file = File(path);
    
    await file.writeAsBytes(fileBytes!);
    
    await Share.shareXFiles([XFile(path)], text: 'Timesheet for ${DateFormat('MMMM yyyy').format(month)}');
  }

  static Future<void> exportToPdf(List<DailyLog> logs, GlobalConfig config, DateTime month, DateTime exportDate) async {
    List<Map<String, dynamic>> finalData = [];
    
    double grandTotalHours = 0;
    double grandTotalDays = 0;
    
    for (var log in logs) {
      List<String> modules = [];
      List<String> projects = [];
      List<String> activityTexts = [];
      
      for (var line in log.lines) {
        if (!modules.contains(line.modul)) modules.add(line.modul);
        if (!projects.contains(line.project)) projects.add(line.project);
        
        final descLines = line.description.split('\n').where((l) => l.trim().isNotEmpty).toList();
        for (var desc in descLines) {
          activityTexts.add('${activityTexts.length + 1}. $desc');
        }
      }
      
      finalData.add({
        'date': log.date,
        'modul': modules.join('; '),
        'project': projects.join('; '),
        'activity': activityTexts.join('\n'),
        'hours': log.totalHours,
        'totalDays': log.totalDays,
      });

      grandTotalHours += log.totalHours;
      grandTotalDays += log.totalDays;
    }

    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        build: (context) => [
          pw.Center(child: pw.Text("PT ACARYA DATA ESA", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 16))),
          pw.Center(child: pw.Text("Timesheet - System & Data Analyst", style: const pw.TextStyle(fontSize: 14))),
          pw.SizedBox(height: 20),
          pw.Row(children: [pw.Text("PIC Consultan: "), pw.Text(config.picConsultant)]),
          pw.Row(children: [pw.Text("Role: "), pw.Text(config.role)]),
          pw.SizedBox(height: 10),
          pw.TableHelper.fromTextArray(
            headers: ['No', 'Date', 'Modul', 'Project', 'Activity', 'Hours', 'Total Days'],
            data: [
              ...List<List<dynamic>>.generate(finalData.length, (index) {
                final a = finalData[index];
                return [
                  index + 1,
                  DateFormat('dd MMMM yyyy').format(DateTime.parse(a['date'])),
                  a['modul'],
                  a['project'],
                  a['activity'],
                  a['hours'],
                  a['totalDays'],
                ];
              }),
              ['', '', '', '', 'Total', grandTotalHours, grandTotalDays]
            ],
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.blue100),
          ),
          pw.SizedBox(height: 30),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text("Created by"),
                  pw.SizedBox(height: 40),
                  pw.Text("Name: ${config.createdByName}"),
                  pw.Text("Date: ${DateFormat('dd MMMM yyyy').format(exportDate)}"),
                ],
              ),
              if (config.approvedByName.isNotEmpty)
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text("Approved by"),
                    pw.SizedBox(height: 40),
                    pw.Text("Name: ${config.approvedByName}"),
                    pw.Text("Date: ${DateFormat('dd MMMM yyyy').format(exportDate)}"),
                  ],
                ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text("Approved by Lead Project"),
                  pw.SizedBox(height: 40),
                  pw.Text("Name: ${config.approvedByLeadName}"),
                  pw.Text("Date: ${DateFormat('dd MMMM yyyy').format(exportDate)}"),
                ],
              ),
            ]
          )
        ],
      ),
    );

    final directory = await getTemporaryDirectory();
    final fileName = 'Timesheet_${DateFormat('MMM_yyyy').format(month)}.pdf';
    final path = '${directory.path}/$fileName';
    final file = File(path);
    
    await file.writeAsBytes(await pdf.save());
    
    await Share.shareXFiles([XFile(path)], text: 'Timesheet PDF for ${DateFormat('MMMM yyyy').format(month)}');
  }
}
