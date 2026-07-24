import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/global_config.dart';
import '../../providers/app_provider.dart';
import '../../services/export_service.dart';
import 'package:intl/intl.dart';

class ExportDialog extends StatefulWidget {
  final DateTime? targetMonth;

  const ExportDialog({super.key, this.targetMonth});

  @override
  State<ExportDialog> createState() => _ExportDialogState();
}

class _ExportDialogState extends State<ExportDialog> {
  final _picController = TextEditingController();
  final _roleController = TextEditingController();
  final _createdByController = TextEditingController();
  final _approvedByController = TextEditingController();
  final _approvedByLeadController = TextEditingController();

  late DateTime _startDate;
  late DateTime _endDate;
  bool _isExporting = false;
  bool _needsExtraApprover = false;

  @override
  void initState() {
    super.initState();
    final target = widget.targetMonth ?? DateTime.now();
    _endDate = target;
    _startDate = DateTime(target.year, target.month, 1);
    
    final config = Provider.of<AppProvider>(context, listen: false).globalConfig;
    if (config != null) {
      _picController.text = config.picConsultant;
      _roleController.text = config.role;
      _createdByController.text = config.createdByName;
      _approvedByController.text = config.approvedByName;
      _approvedByLeadController.text = config.approvedByLeadName;
    }
  }

  @override
  void dispose() {
    _picController.dispose();
    _roleController.dispose();
    _createdByController.dispose();
    _approvedByController.dispose();
    _approvedByLeadController.dispose();
    super.dispose();
  }

  void _export(String format) async {
    setState(() => _isExporting = true);
    final provider = Provider.of<AppProvider>(context, listen: false);
    
    // Filter daily logs by selected date range
    final logs = provider.dailyLogs.where((log) {
      final d = DateTime.parse(log.date);
      final dateOnly = DateTime(d.year, d.month, d.day);
      final startOnly = DateTime(_startDate.year, _startDate.month, _startDate.day);
      final endOnly = DateTime(_endDate.year, _endDate.month, _endDate.day);
      
      return (dateOnly.isAtSameMomentAs(startOnly) || dateOnly.isAfter(startOnly)) &&
             (dateOnly.isAtSameMomentAs(endOnly) || dateOnly.isBefore(endOnly));
    }).toList();

    // Reverse list so older date is first (optional, but good for timesheet)
    logs.sort((a, b) => DateTime.parse(a.date).compareTo(DateTime.parse(b.date)));

    final configOverride = GlobalConfig(
      picConsultant: _picController.text,
      role: _roleController.text,
      createdByName: _createdByController.text,
      approvedByName: _needsExtraApprover ? _approvedByController.text : '',
      approvedByLeadName: _approvedByLeadController.text,
      defaultBaseHours: provider.globalConfig?.defaultBaseHours ?? 8.0,
    );

    try {
      if (format == 'xlsx') {
        await ExportService.exportToXlsx(logs, configOverride, _endDate, DateTime.now());
      } else if (format == 'pdf') {
        await ExportService.exportToPdf(logs, configOverride, _endDate, DateTime.now());
      }
      
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Exported to $format successfully!')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Export Data'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text('Period: ${DateFormat('dd MMM').format(_startDate)} - ${DateFormat('dd MMM yyyy').format(_endDate)}'),
              trailing: const Icon(Icons.date_range),
              onTap: () async {
                final picked = await showDateRangePicker(
                  context: context,
                  initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2100),
                );
                if (picked != null) {
                  setState(() {
                    _startDate = picked.start;
                    _endDate = picked.end;
                  });
                }
              },
            ),
            const Divider(),
            const Text('Review/Override Details for this Export:'),
            TextField(controller: _picController, decoration: const InputDecoration(labelText: 'PIC Consultant')),
            TextField(controller: _roleController, decoration: const InputDecoration(labelText: 'Role')),
            TextField(controller: _createdByController, decoration: const InputDecoration(labelText: 'Created By')),
            TextField(controller: _approvedByLeadController, decoration: const InputDecoration(labelText: 'Approved By Lead Project')),
            CheckboxListTile(
              title: const Text('Add Approved By (2nd Approver)'),
              value: _needsExtraApprover,
              onChanged: (val) {
                setState(() {
                  _needsExtraApprover = val ?? false;
                });
              },
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
            ),
            if (_needsExtraApprover)
              TextField(
                controller: _approvedByController, 
                decoration: const InputDecoration(labelText: 'Approved By Name')
              ),
          ],
        ),
      ),
      actions: [
        if (_isExporting) const CircularProgressIndicator(),
        if (!_isExporting)
          TextButton(
            onPressed: () => _export('xlsx'),
            child: const Text('Export XLSX'),
          ),
        if (!_isExporting)
          TextButton(
            onPressed: () => _export('pdf'),
            child: const Text('Export PDF'),
          ),
        if (!_isExporting)
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
      ],
    );
  }
}
