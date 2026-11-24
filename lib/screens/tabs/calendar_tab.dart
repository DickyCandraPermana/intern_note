import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../models/daily_log.dart';
import '../../providers/app_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/date_formatters.dart';
import '../../widgets/daily_log_sheet.dart';
import '../../widgets/export_dialog.dart';

class CalendarTab extends StatefulWidget {
  final DateTime? jumpToDate;
  final int jumpNonce;

  const CalendarTab({
    super.key,
    this.jumpToDate,
    this.jumpNonce = 0,
  });

  @override
  State<CalendarTab> createState() => _CalendarTabState();
}

class _CalendarTabState extends State<CalendarTab> {
  late DateTime _focusedDay;
  late DateTime _selectedDay;

  @override
  void initState() {
    super.initState();
    final initial = widget.jumpToDate ?? DateTime.now();
    _focusedDay = initial;
    _selectedDay = initial;
  }

  @override
  void didUpdateWidget(covariant CalendarTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.jumpNonce != oldWidget.jumpNonce && widget.jumpToDate != null) {
      setState(() {
        _focusedDay = widget.jumpToDate!;
        _selectedDay = widget.jumpToDate!;
      });
    }
  }

  void _jumpToToday() {
    final now = DateTime.now();
    setState(() {
      _focusedDay = now;
      _selectedDay = now;
    });
  }

  void _openExportDialog() {
    showDialog<void>(
      context: context,
      builder: (_) => ExportDialog(targetMonth: _focusedDay),
    );
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

  Future<void> _confirmAndDelete(
    BuildContext context,
    AppProvider provider,
    DailyLog log,
    DateTime day,
  ) async {
    final logId = log.id;
    if (logId == null) return;
    final colors = AppColors.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Hapus Catatan?'),
        content: Text(
          'Hapus catatan aktivitas pada ${formatIndonesianLongDayDate(day)}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            style: TextButton.styleFrom(foregroundColor: colors.destructive),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    final snapshot = await provider.deleteDailyLog(logId);
    if (!context.mounted || snapshot == null) return;

    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Text('Catatan ${formatIndonesianShortDate(day)} dihapus'),
        action: SnackBarAction(
          label: 'Urungkan',
          onPressed: () => provider.restoreDailyLog(snapshot),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Kalender'),
        actions: [
          TextButton(
            onPressed: _jumpToToday,
            child: const Text('Hari Ini'),
          ),
          TextButton.icon(
            onPressed: _openExportDialog,
            icon: const Icon(Icons.download_outlined, size: 18),
            label: const Text('Export'),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Consumer<AppProvider>(
        builder: (context, provider, _) {
          if (provider.isLoading) {
            return const JournalSkeletonList(cardCount: 3);
          }

          if (provider.errorMessage != null && provider.dailyLogs.isEmpty) {
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

          final selectedLog = provider.getDailyLogForDate(_selectedDay);
          final sortedLines = List<ActivityLine>.from(
            selectedLog?.lines ?? const [],
          )..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              if (provider.errorMessage != null) ...[
                JournalErrorBanner(
                  message: provider.errorMessage!,
                  onRetry: provider.retryLoad,
                ),
                const SizedBox(height: 12),
              ],
              JournalCard(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                child: TableCalendar<DailyLog>(
                  firstDay: DateTime.utc(2020, 1, 1),
                  lastDay: DateTime.utc(2100, 12, 31),
                  focusedDay: _focusedDay,
                  selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
                  onDaySelected: (selectedDay, focusedDay) {
                    setState(() {
                      _selectedDay = selectedDay;
                      _focusedDay = focusedDay;
                    });
                  },
                  onPageChanged: (focusedDay) {
                    setState(() {
                      _focusedDay = focusedDay;
                    });
                  },
                  eventLoader: (day) {
                    final dayLog = provider.getDailyLogForDate(day);
                    return dayLog != null ? [dayLog] : const [];
                  },
                  headerStyle: HeaderStyle(
                    formatButtonVisible: false,
                    titleCentered: true,
                    titleTextStyle: theme.textTheme.titleMedium!,
                    leftChevronIcon: Icon(
                      Icons.chevron_left,
                      color: colors.inkPrimary,
                    ),
                    rightChevronIcon: Icon(
                      Icons.chevron_right,
                      color: colors.inkPrimary,
                    ),
                  ),
                  daysOfWeekStyle: DaysOfWeekStyle(
                    weekdayStyle: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: colors.inkMuted,
                    ),
                    weekendStyle: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: colors.inkMuted,
                    ),
                  ),
                  calendarStyle: CalendarStyle(
                    markersMaxCount: 1,
                    markerDecoration: BoxDecoration(
                      color: colors.accent,
                      shape: BoxShape.circle,
                    ),
                    selectedDecoration: BoxDecoration(
                      color: colors.accent,
                      shape: BoxShape.circle,
                    ),
                    selectedTextStyle: AppTheme.tabularStyle(
                      TextStyle(
                        color: theme.colorScheme.onPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    todayDecoration: BoxDecoration(
                      color: colors.accentTint,
                      shape: BoxShape.circle,
                      border: Border.all(color: colors.accent, width: 1),
                    ),
                    todayTextStyle: AppTheme.tabularStyle(
                      TextStyle(
                        color: colors.accent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    defaultTextStyle: AppTheme.tabularStyle(
                      TextStyle(color: colors.inkPrimary),
                    ),
                    weekendTextStyle: AppTheme.tabularStyle(
                      TextStyle(color: colors.inkMuted),
                    ),
                    outsideTextStyle: AppTheme.tabularStyle(
                      TextStyle(color: colors.inkMuted.withValues(alpha: 0.45)),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (selectedLog == null)
                JournalEmptyState(
                  icon: Icons.event_available_outlined,
                  title: formatIndonesianLongDayDate(_selectedDay),
                  subtitle: 'Belum ada catatan aktivitas pada tanggal ini.',
                  actionLabel: 'Tambah Catatan',
                  onAction: () => _openLogSheet(
                    context,
                    initialDate: _selectedDay,
                  ),
                )
              else
                JournalCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              formatIndonesianLongDayDate(_selectedDay),
                              style: AppTheme.tabularStyle(
                                theme.textTheme.titleMedium!,
                              ),
                            ),
                          ),
                          JournalHoursBadge(hours: selectedLog.totalHours),
                        ],
                      ),
                      if (selectedLog.hasUncategorizedLines) ...[
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: JournalUncategorizedPill(
                            onTap: () => _openLogSheet(
                              context,
                              initialDate: _selectedDay,
                              log: selectedLog,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      const Divider(),
                      const SizedBox(height: 10),
                      if (sortedLines.isEmpty)
                        Text(
                          'Tidak ada rincian aktivitas pada tanggal ini.',
                          style: TextStyle(color: colors.inkMuted),
                        )
                      else
                        ...sortedLines.map((line) {
                          final tags = [
                            if (line.modul.trim().isNotEmpty) line.modul.trim(),
                            if (line.project.trim().isNotEmpty)
                              line.project.trim(),
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
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      if (tags.isNotEmpty)
                                        Text(
                                          tags.join(' / '),
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: colors.accent,
                                          ),
                                        ),
                                      Text(
                                        line.description,
                                        style: theme.textTheme.bodyMedium,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _openLogSheet(
                                context,
                                initialDate: _selectedDay,
                                log: selectedLog,
                              ),
                              icon: const Icon(Icons.edit_outlined, size: 18),
                              label: const Text('Edit Catatan'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          TextButton.icon(
                            onPressed: () => _confirmAndDelete(
                              context,
                              provider,
                              selectedLog,
                              _selectedDay,
                            ),
                            style: TextButton.styleFrom(
                              foregroundColor: colors.destructive,
                            ),
                            icon: const Icon(Icons.delete_outline, size: 18),
                            label: const Text('Hapus'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
      floatingActionButton: Consumer<AppProvider>(
        builder: (fabContext, provider, _) {
          final currentLog = provider.getDailyLogForDate(_selectedDay);
          return FloatingActionButton(
            onPressed: () => _openLogSheet(
              fabContext,
              initialDate: _selectedDay,
              log: currentLog,
            ),
            tooltip: currentLog == null ? 'Tambah catatan' : 'Edit catatan',
            child: Icon(currentLog == null ? Icons.add : Icons.edit_outlined),
          );
        },
      ),
    );
  }
}
