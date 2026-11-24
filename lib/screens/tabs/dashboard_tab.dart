import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/daily_log.dart';
import '../../providers/app_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/billing_cycle.dart';
import '../../utils/date_formatters.dart';
import '../../widgets/daily_log_sheet.dart';

class DashboardTab extends StatefulWidget {
  final void Function([DateTime? targetDate])? onJumpToCalendar;

  const DashboardTab({super.key, this.onJumpToCalendar});

  @override
  State<DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends State<DashboardTab> {
  final _quickNoteController = TextEditingController();
  bool _isSavingQuickNote = false;

  @override
  void dispose() {
    _quickNoteController.dispose();
    super.dispose();
  }

  Future<void> _openLogSheet(
    BuildContext context, {
    DateTime? initialDate,
    DailyLog? log,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => DailyLogSheet(initialDate: initialDate, log: log),
    );
  }

  Future<void> _submitQuickNote({String? presetText}) async {
    final text = (presetText ?? _quickNoteController.text).trim();
    if (text.isEmpty || _isSavingQuickNote) return;

    setState(() => _isSavingQuickNote = true);
    final provider = context.read<AppProvider>();
    try {
      await provider.quickAddTodayNote(description: text);
      if (presetText == null) {
        _quickNoteController.clear();
      }
      if (!mounted) return;
      final colors = AppColors.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Tersimpan ke catatan hari ini: $text'),
          backgroundColor: colors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal menyimpan catatan: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isSavingQuickNote = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.sync),
            tooltip: 'Sinkronkan data',
            onPressed: () => context.read<AppProvider>().refreshFromDisk(),
          ),
        ],
      ),
      body: Consumer<AppProvider>(
        builder: (context, provider, _) {
          if (provider.isLoading) {
            return const JournalSkeletonList(cardCount: 3);
          }

          if (provider.errorMessage != null &&
              provider.dailyLogs.isEmpty &&
              provider.globalConfig == null) {
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                JournalErrorBanner(
                  message: provider.errorMessage!,
                  onRetry: provider.retryLoad,
                ),
              ],
            );
          }

          final config = provider.effectiveConfig;
          final cycle = provider.activeCycle;
          final today = DateTime.now();
          final todayCycle = BillingCycleHelper.cycleFor(
            today,
            cutoffDay: config.cutoffDay,
          );
          final todayLog = provider.getDailyLogForDate(today);
          final cycleLogs = provider.logsInCycle(cycle);

          double totalHours = 0;
          double totalDays = 0;
          final Map<String, double> projectHours = {};
          final List<DailyLog> uncategorizedLogs = [];

          for (final log in cycleLogs) {
            totalHours += log.totalHours;
            totalDays += log.totalDays;
            if (log.hasUncategorizedLines) {
              uncategorizedLogs.add(log);
            }
            if (log.lines.isEmpty) {
              projectHours['Belum Dikategorikan'] =
                  (projectHours['Belum Dikategorikan'] ?? 0) + log.totalHours;
            } else {
              final hrsPerLine = log.totalHours / log.lines.length;
              for (final line in log.lines) {
                final key = line.project.trim().isEmpty
                    ? 'Belum Dikategorikan'
                    : line.project.trim();
                projectHours[key] = (projectHours[key] ?? 0) + hrsPerLine;
              }
            }
          }

          if (uncategorizedLogs.isEmpty &&
              todayLog != null &&
              todayLog.hasUncategorizedLines) {
            uncategorizedLogs.add(todayLog);
          }

          final topProjects = projectHours.entries.toList()
            ..sort((a, b) => b.value.compareTo(a.value));

          final expectedWeekdays =
              BillingCycleHelper.expectedWeekdaysCount(cycle);
          final missingDays = BillingCycleHelper.missingWeekdays(
            cycle,
            cycleLogs.map((l) => l.date),
          );

          return RefreshIndicator(
            onRefresh: provider.refreshFromDisk,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (provider.errorMessage != null) ...[
                  JournalErrorBanner(
                    message: provider.errorMessage!,
                    onRetry: provider.retryLoad,
                  ),
                  const SizedBox(height: 12),
                ],
                _CycleSwitcherCard(
                  cycle: cycle,
                  isCurrentCycle: cycle == todayCycle,
                  onPrevious: provider.previousCycle,
                  onNext: provider.nextCycle,
                  onResetToday: provider.resetCycleToToday,
                ),
                const SizedBox(height: 12),
                _KpiSummaryCard(
                  totalHours: totalHours,
                  totalDays: totalDays,
                  loggedDays: cycleLogs.length,
                  expectedWeekdays: expectedWeekdays,
                  missingDays: missingDays,
                  uncategorizedLogs: uncategorizedLogs,
                  onJumpToMissing: widget.onJumpToCalendar,
                  onFixUncategorized: (log) => _openLogSheet(
                    context,
                    initialDate: DateTime.tryParse(normalizeIsoDate(log.date)),
                    log: log,
                  ),
                ),
                const SizedBox(height: 12),
                _TodayNoteCard(
                  today: today,
                  todayLog: todayLog,
                  presets: config.quickPresets,
                  controller: _quickNoteController,
                  isSaving: _isSavingQuickNote,
                  onSubmitQuickNote: () => _submitQuickNote(),
                  onTapPreset: (preset) => _submitQuickNote(presetText: preset),
                  onOpenSheet: () => _openLogSheet(
                    context,
                    initialDate: today,
                    log: todayLog,
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Top Project Siklus Ini',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (topProjects.isNotEmpty)
                      Text(
                        '${topProjects.length} project',
                        style: AppTheme.tabularStyle(
                          Theme.of(context).textTheme.bodySmall!,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                if (topProjects.isEmpty)
                  JournalEmptyState(
                    icon: Icons.work_outline,
                    title: 'Belum ada aktivitas di siklus ${cycle.monthNameIndo}',
                    subtitle:
                        'Catat pekerjaan harian Anda agar jam dan project terhitung di ringkasan siklus.',
                    actionLabel: 'Tambah Catatan',
                    onAction: () => _openLogSheet(
                      context,
                      initialDate: today,
                      log: todayLog,
                    ),
                  )
                else
                  ...topProjects.map((entry) {
                    final isUncategorized = entry.key == 'Belum Dikategorikan';
                    final ratio = totalHours > 0
                        ? (entry.value / totalHours).clamp(0.0, 1.0)
                        : 0.0;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: JournalCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  isUncategorized
                                      ? Icons.label_off_outlined
                                      : Icons.folder_outlined,
                                  size: 18,
                                  color: isUncategorized
                                      ? colors.warning
                                      : colors.accent,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    entry.key,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: isUncategorized
                                          ? colors.warning
                                          : colors.inkPrimary,
                                    ),
                                  ),
                                ),
                                Text(
                                  '${entry.value.toStringAsFixed(1)} jam',
                                  style: AppTheme.tabularStyle(
                                    TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: colors.inkPrimary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: ratio,
                                minHeight: 6,
                                backgroundColor: colors.surfaceAlt,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  isUncategorized
                                      ? colors.warning
                                      : colors.accent,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _CycleSwitcherCard extends StatelessWidget {
  final BillingCycle cycle;
  final bool isCurrentCycle;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onResetToday;

  const _CycleSwitcherCard({
    required this.cycle,
    required this.isCurrentCycle,
    required this.onPrevious,
    required this.onNext,
    required this.onResetToday,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final rangeLabel = formatCycleRangeLabel(cycle.start, cycle.end);

    return JournalCard(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: Row(
        children: [
          IconButton(
            onPressed: onPrevious,
            tooltip: 'Siklus sebelumnya',
            icon: const Icon(Icons.chevron_left),
          ),
          Expanded(
            child: InkWell(
              onTap: isCurrentCycle ? null : onResetToday,
              borderRadius: BorderRadius.circular(AppTheme.chipRadius),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  children: [
                    Text(
                      'Siklus ${cycle.monthNameIndo} ${cycle.cycleYear}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      rangeLabel,
                      style: AppTheme.tabularStyle(
                        TextStyle(fontSize: 12, color: colors.inkMuted),
                      ),
                    ),
                    if (!isCurrentCycle) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Ketuk untuk kembali ke siklus saat ini',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: colors.accent,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            onPressed: onNext,
            tooltip: 'Siklus berikutnya',
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    );
  }
}

class _KpiSummaryCard extends StatelessWidget {
  final double totalHours;
  final double totalDays;
  final int loggedDays;
  final int expectedWeekdays;
  final List<DateTime> missingDays;
  final List<DailyLog> uncategorizedLogs;
  final void Function([DateTime? targetDate])? onJumpToMissing;
  final void Function(DailyLog log) onFixUncategorized;

  const _KpiSummaryCard({
    required this.totalHours,
    required this.totalDays,
    required this.loggedDays,
    required this.expectedWeekdays,
    required this.missingDays,
    required this.uncategorizedLogs,
    required this.onJumpToMissing,
    required this.onFixUncategorized,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    return JournalCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: _KpiMetric(
                  value: totalHours.toStringAsFixed(1),
                  label: 'Total Jam',
                  valueColor: colors.accent,
                ),
              ),
              Container(width: 1, height: 40, color: colors.border),
              Expanded(
                child: _KpiMetric(
                  value: totalDays.toStringAsFixed(1),
                  label: 'Total Hari',
                  valueColor: colors.inkPrimary,
                ),
              ),
              Container(width: 1, height: 40, color: colors.border),
              Expanded(
                child: _KpiMetric(
                  value: '$loggedDays/$expectedWeekdays',
                  label: 'Hari Kerja',
                  valueColor: colors.inkPrimary,
                ),
              ),
            ],
          ),
          if (missingDays.isNotEmpty || uncategorizedLogs.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Divider(),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (missingDays.isNotEmpty)
                  InkWell(
                    onTap: () => onJumpToMissing?.call(missingDays.first),
                    borderRadius: BorderRadius.circular(AppTheme.chipRadius),
                    child: Container(
                      constraints: const BoxConstraints(
                        minHeight: AppTheme.minTapTarget,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: colors.accentTint,
                        borderRadius: BorderRadius.circular(
                          AppTheme.chipRadius,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.event_note_outlined,
                            size: 16,
                            color: colors.accent,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '${missingDays.length} hari kerja belum dicatat',
                            style: AppTheme.tabularStyle(
                              TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: colors.accent,
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            Icons.arrow_forward,
                            size: 14,
                            color: colors.accent,
                          ),
                        ],
                      ),
                    ),
                  ),
                if (uncategorizedLogs.isNotEmpty)
                  JournalUncategorizedPill(
                    label: uncategorizedLogs.length > 1
                        ? 'Perlu tag modul/project (${uncategorizedLogs.length})'
                        : 'Perlu tag modul/project',
                    onTap: () => onFixUncategorized(uncategorizedLogs.first),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _KpiMetric extends StatelessWidget {
  final String value;
  final String label;
  final Color valueColor;

  const _KpiMetric({
    required this.value,
    required this.label,
    required this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Column(
      children: [
        Text(
          value,
          style: AppTheme.tabularStyle(
            TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: valueColor,
            ),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: colors.inkMuted,
          ),
        ),
      ],
    );
  }
}

class _TodayNoteCard extends StatelessWidget {
  final DateTime today;
  final DailyLog? todayLog;
  final List<String> presets;
  final TextEditingController controller;
  final bool isSaving;
  final VoidCallback onSubmitQuickNote;
  final void Function(String preset) onTapPreset;
  final VoidCallback onOpenSheet;

  const _TodayNoteCard({
    required this.today,
    required this.todayLog,
    required this.presets,
    required this.controller,
    required this.isSaving,
    required this.onSubmitQuickNote,
    required this.onTapPreset,
    required this.onOpenSheet,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final lines = List<ActivityLine>.from(todayLog?.lines ?? const [])
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

    return JournalCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Catatan Hari Ini',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      formatIndonesianShortDate(today),
                      style: AppTheme.tabularStyle(
                        TextStyle(fontSize: 12, color: colors.inkMuted),
                      ),
                    ),
                  ],
                ),
              ),
              JournalHoursBadge(hours: todayLog?.totalHours ?? 0.0),
              const SizedBox(width: 4),
              TextButton(
                onPressed: onOpenSheet,
                child: Text(todayLog == null ? 'Buka Form' : 'Edit'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (lines.isEmpty)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colors.surfaceAlt,
                borderRadius: BorderRadius.circular(AppTheme.controlRadius),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Belum ada catatan hari ini',
                      style: TextStyle(fontSize: 14, color: colors.inkMuted),
                    ),
                  ),
                  OutlinedButton(
                    onPressed: onOpenSheet,
                    child: const Text('Tambah Catatan'),
                  ),
                ],
              ),
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: lines.map((line) {
                final tagParts = [
                  if (line.modul.trim().isNotEmpty) line.modul.trim(),
                  if (line.project.trim().isNotEmpty) line.project.trim(),
                ];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: line.isUncategorized
                                ? colors.warning
                                : colors.accent,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (tagParts.isNotEmpty)
                              Text(
                                tagParts.join(' / '),
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: colors.accent,
                                ),
                              )
                            else
                              const Padding(
                                padding: EdgeInsets.only(bottom: 2),
                                child: JournalUncategorizedPill(),
                              ),
                            Text(
                              line.description,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => onSubmitQuickNote(),
                  decoration: const InputDecoration(
                    hintText: 'Tulis catatan cepat hari ini...',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: isSaving ? null : onSubmitQuickNote,
                child: isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send, size: 18),
              ),
            ],
          ),
          if (presets.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: presets.map((preset) {
                return ActionChip(
                  materialTapTargetSize: MaterialTapTargetSize.padded,
                  avatar: Icon(
                    Icons.add,
                    size: 16,
                    color: colors.accent,
                  ),
                  label: Text(preset),
                  onPressed: isSaving ? null : () => onTapPreset(preset),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }
}
