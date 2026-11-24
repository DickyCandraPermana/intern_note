import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/daily_log.dart';
import '../models/global_config.dart';
import '../providers/app_provider.dart';
import '../screens/pdf_preview_screen.dart';
import '../services/export_service.dart';
import '../services/timesheet_formatter.dart';
import '../theme/app_theme.dart';
import '../utils/billing_cycle.dart';
import '../utils/date_formatters.dart';

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
  late bool _needsExtraApprover;
  late bool _includeSignature;

  @override
  void initState() {
    super.initState();
    final provider = context.read<AppProvider>();
    final config = provider.effectiveConfig;
    final cycle = BillingCycleHelper.cycleFor(
      widget.targetMonth ?? DateTime.now(),
      cutoffDay: config.cutoffDay,
    );
    _startDate = cycle.start;
    _endDate = cycle.end;

    _picController.text = config.picConsultant;
    _roleController.text = config.role;
    _createdByController.text = config.createdByName;
    _approvedByController.text = config.approvedByName;
    _approvedByLeadController.text = config.approvedByLeadName;
    _needsExtraApprover = config.approvedByName.trim().isNotEmpty;
    _includeSignature = config.includeSignature;
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

  List<DailyLog> _matchingLogsForRange(List<DailyLog> allLogs) {
    final startOnly = DateTime(
      _startDate.year,
      _startDate.month,
      _startDate.day,
    );
    final endOnly = DateTime(_endDate.year, _endDate.month, _endDate.day);

    final filtered = allLogs.where((log) {
      final parsed = DateTime.tryParse(normalizeIsoDate(log.date));
      if (parsed == null) return false;
      final dateOnly = DateTime(parsed.year, parsed.month, parsed.day);
      return !dateOnly.isBefore(startOnly) && !dateOnly.isAfter(endOnly);
    }).toList();

    filtered.sort(
      (a, b) => normalizeIsoDate(a.date).compareTo(normalizeIsoDate(b.date)),
    );
    return filtered;
  }

  GlobalConfig _buildConfigOverride(GlobalConfig base) {
    return base.copyWith(
      picConsultant: _picController.text.trim(),
      role: _roleController.text.trim(),
      createdByName: _createdByController.text.trim(),
      approvedByName:
          _needsExtraApprover ? _approvedByController.text.trim() : '',
      approvedByLeadName: _approvedByLeadController.text.trim(),
      includeSignature: _includeSignature,
    );
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) return;

    setState(() {
      _startDate = DateTime(
        picked.start.year,
        picked.start.month,
        picked.start.day,
      );
      _endDate = DateTime(
        picked.end.year,
        picked.end.month,
        picked.end.day,
      );
    });
  }

  Future<void> _exportAndShare({
    required List<DailyLog> logs,
    required GlobalConfig baseConfig,
    required String formatLabel,
    required Future<void> Function(
      GlobalConfig configOverride,
      DateTime exportDate,
    ) runner,
  }) async {
    if (logs.isEmpty || _isExporting) return;

    setState(() => _isExporting = true);
    final configOverride = _buildConfigOverride(baseConfig);
    final colors = AppColors.of(context);
    final messenger = ScaffoldMessenger.of(context);

    try {
      await runner(configOverride, DateTime.now());
      if (!mounted) return;
      Navigator.pop(context);
      messenger.showSnackBar(
        SnackBar(
          content: Text('Timesheet $formatLabel siap dibagikan'),
          backgroundColor: colors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Export $formatLabel gagal: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
      }
    }
  }

  Future<void> _previewPdf(List<DailyLog> logs, GlobalConfig baseConfig) async {
    if (logs.isEmpty || _isExporting) return;
    final configOverride = _buildConfigOverride(baseConfig);
    final fileName = TimesheetFormatter.buildFilename(
      cycleMonth: _endDate,
      config: configOverride,
      extension: 'pdf',
    );
    final exportDate = DateTime.now();

    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => PdfPreviewScreen(
            buildPdf: () => ExportService.buildPdfBytes(
              logs: logs,
              config: configOverride,
              exportDate: exportDate,
              includeSignature: _includeSignature,
            ),
            fileName: fileName,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal membuka preview PDF: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final theme = Theme.of(context);
    final provider = context.watch<AppProvider>();
    final baseConfig = provider.effectiveConfig;
    final matchingLogs = _matchingLogsForRange(provider.dailyLogs);
    final totalHours = matchingLogs.fold<double>(
      0.0,
      (sum, log) => sum + log.totalHours,
    );
    final canExport = matchingLogs.isNotEmpty && !_isExporting;

    return AlertDialog(
      title: const Text('Export Timesheet'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              InkWell(
                onTap: _isExporting ? null : _pickDateRange,
                borderRadius: BorderRadius.circular(AppTheme.controlRadius),
                child: Container(
                  constraints: const BoxConstraints(
                    minHeight: AppTheme.minTapTarget,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: colors.surfaceAlt,
                    borderRadius: BorderRadius.circular(AppTheme.controlRadius),
                    border: Border.all(color: colors.border),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.date_range_outlined,
                        size: 18,
                        color: colors.accent,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Periode Ekspor',
                              style: TextStyle(
                                fontSize: 12,
                                color: colors.inkMuted,
                              ),
                            ),
                            Text(
                              formatCycleRangeLabel(_startDate, _endDate),
                              style: AppTheme.tabularStyle(
                                theme.textTheme.bodyMedium!.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.chevron_right,
                        size: 18,
                        color: colors.inkMuted,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              if (matchingLogs.isEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: colors.warning.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppTheme.controlRadius),
                    border: Border.all(
                      color: colors.warning.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 18,
                        color: colors.warning,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Tidak ada catatan pada periode ini. Pilih rentang tanggal lain untuk mengekspor.',
                          style: TextStyle(
                            fontSize: 13,
                            color: colors.warning,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: colors.accentTint,
                    borderRadius: BorderRadius.circular(AppTheme.chipRadius),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.check_circle_outline,
                        size: 16,
                        color: colors.accent,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${matchingLogs.length} hari tercatat (${totalHours.toStringAsFixed(1)} jam)',
                          style: AppTheme.tabularStyle(
                            TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: colors.accent,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              if (_isExporting) ...[
                const SizedBox(height: 10),
                const LinearProgressIndicator(),
              ],
              const SizedBox(height: 14),
              Text(
                'Detail Dokumen (Opsional Override)',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _picController,
                enabled: !_isExporting,
                decoration: const InputDecoration(labelText: 'PIC Consultant'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _roleController,
                enabled: !_isExporting,
                decoration: const InputDecoration(labelText: 'Role'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _createdByController,
                enabled: !_isExporting,
                decoration: const InputDecoration(labelText: 'Created By'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _approvedByLeadController,
                enabled: !_isExporting,
                decoration: const InputDecoration(
                  labelText: 'Approved By Lead Project',
                ),
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                title: const Text('Add Approved By (2nd Approver)'),
                value: _needsExtraApprover,
                onChanged: _isExporting
                    ? null
                    : (val) {
                        setState(() => _needsExtraApprover = val ?? false);
                      },
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
              ),
              if (_needsExtraApprover) ...[
                const SizedBox(height: 6),
                TextField(
                  controller: _approvedByController,
                  enabled: !_isExporting,
                  decoration: const InputDecoration(
                    labelText: 'Approved By Name',
                  ),
                ),
              ],
              CheckboxListTile(
                title: const Text('Include Signature'),
                subtitle: const Text('Sematkan tanda tangan pada XLSX & PDF'),
                value: _includeSignature,
                onChanged: _isExporting
                    ? null
                    : (val) {
                        setState(() => _includeSignature = val ?? false);
                      },
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
              ),
            ],
          ),
        ),
      ),
      actionsOverflowButtonSpacing: 8,
      actions: [
        TextButton(
          onPressed: _isExporting ? null : () => Navigator.pop(context),
          child: const Text('Batal'),
        ),
        OutlinedButton.icon(
          onPressed: canExport
              ? () => _exportAndShare(
                    logs: matchingLogs,
                    baseConfig: baseConfig,
                    formatLabel: 'XLSX',
                    runner: (cfg, exportDate) =>
                        ExportService.exportAndShareXlsx(
                      logs: matchingLogs,
                      config: cfg,
                      cycleMonth: _endDate,
                      exportDate: exportDate,
                      includeSignature: _includeSignature,
                    ),
                  )
              : null,
          icon: const Icon(Icons.table_chart_outlined, size: 18),
          label: const Text('Export XLSX'),
        ),
        OutlinedButton.icon(
          onPressed:
              canExport ? () => _previewPdf(matchingLogs, baseConfig) : null,
          icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
          label: const Text('Preview PDF'),
        ),
        FilledButton.icon(
          onPressed: canExport
              ? () => _exportAndShare(
                    logs: matchingLogs,
                    baseConfig: baseConfig,
                    formatLabel: 'PDF',
                    runner: (cfg, exportDate) =>
                        ExportService.exportAndSharePdf(
                      logs: matchingLogs,
                      config: cfg,
                      cycleMonth: _endDate,
                      exportDate: exportDate,
                      includeSignature: _includeSignature,
                    ),
                  )
              : null,
          icon: const Icon(Icons.share_outlined, size: 18),
          label: const Text('Share PDF'),
        ),
      ],
    );
  }
}
