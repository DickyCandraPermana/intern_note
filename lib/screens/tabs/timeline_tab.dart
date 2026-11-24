import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/daily_log.dart';
import '../../providers/app_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/date_formatters.dart';
import '../../widgets/daily_log_sheet.dart';

class TimelineTab extends StatefulWidget {
  const TimelineTab({super.key});

  @override
  State<TimelineTab> createState() => _TimelineTabState();
}

class _TimelineTabState extends State<TimelineTab> {
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _openLogSheet(BuildContext context, {DailyLog? log}) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => DailyLogSheet(log: log),
    );
  }

  Future<void> _confirmAndDelete(
    BuildContext context,
    AppProvider provider,
    DailyLog log,
    DateTime parsedDate,
  ) async {
    final logId = log.id;
    if (logId == null) return;
    final colors = AppColors.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Hapus Catatan?'),
        content: Text(
          'Hapus catatan aktivitas pada ${formatIndonesianLongDayDate(parsedDate)}?',
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
        content: Text(
          'Catatan ${formatIndonesianShortDate(parsedDate)} dihapus',
        ),
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

    return Scaffold(
      appBar: AppBar(title: const Text('Timeline')),
      body: Consumer<AppProvider>(
        builder: (context, provider, _) {
          if (provider.isLoading) {
            return const JournalSkeletonList(cardCount: 4);
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

          final logs = provider.filteredDailyLogs;
          final filter = provider.timelineFilter;

          return Column(
            children: [
              if (provider.errorMessage != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: JournalErrorBanner(
                    message: provider.errorMessage!,
                    onRetry: provider.retryLoad,
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _searchCtrl,
                      onChanged: provider.setSearchQuery,
                      decoration: InputDecoration(
                        hintText: 'Cari modul, project, atau aktivitas...',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _searchCtrl.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear),
                                tooltip: 'Bersihkan pencarian',
                                onPressed: () {
                                  _searchCtrl.clear();
                                  provider.setSearchQuery('');
                                },
                              )
                            : null,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        _FilterChipItem(
                          label: 'Semua',
                          selected: filter == TimelineFilter.all,
                          onSelected: () =>
                              provider.setTimelineFilter(TimelineFilter.all),
                        ),
                        _FilterChipItem(
                          label: 'Siklus Ini',
                          selected: filter == TimelineFilter.currentCycle,
                          onSelected: () => provider.setTimelineFilter(
                            TimelineFilter.currentCycle,
                          ),
                        ),
                        _FilterChipItem(
                          label: 'Perlu Tag',
                          selected: filter == TimelineFilter.needsTag,
                          onSelected: () => provider.setTimelineFilter(
                            TimelineFilter.needsTag,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Expanded(
                child: logs.isEmpty
                    ? ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          _buildEmptyState(context, provider),
                        ],
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                        itemCount: logs.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final log = logs[index];
                          final parsedDate =
                              DateTime.tryParse(normalizeIsoDate(log.date)) ??
                                  DateTime.now();
                          final sortedLines =
                              List<ActivityLine>.from(log.lines)
                                ..sort(
                                  (a, b) =>
                                      a.sortOrder.compareTo(b.sortOrder),
                                );
                          final visibleLines = sortedLines.take(4).toList();
                          final remaining =
                              sortedLines.length - visibleLines.length;

                          return JournalCard(
                            onTap: () => _openLogSheet(context, log: log),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            formatIndonesianLongDayDate(
                                              parsedDate,
                                            ),
                                            style: AppTheme.tabularStyle(
                                              Theme.of(
                                                context,
                                              ).textTheme.titleMedium!,
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          Wrap(
                                            spacing: 8,
                                            runSpacing: 6,
                                            crossAxisAlignment:
                                                WrapCrossAlignment.center,
                                            children: [
                                              JournalHoursBadge(
                                                hours: log.totalHours,
                                              ),
                                              if (log.hasUncategorizedLines)
                                                const JournalUncategorizedPill(),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    IconButton(
                                      icon: Icon(
                                        Icons.delete_outline,
                                        color: colors.destructive,
                                      ),
                                      tooltip: 'Hapus catatan',
                                      onPressed: () => _confirmAndDelete(
                                        context,
                                        provider,
                                        log,
                                        parsedDate,
                                      ),
                                    ),
                                  ],
                                ),
                                if (visibleLines.isNotEmpty) ...[
                                  const SizedBox(height: 10),
                                  const Divider(),
                                  const SizedBox(height: 8),
                                  ...visibleLines.map((line) {
                                    final tags = [
                                      if (line.modul.trim().isNotEmpty)
                                        line.modul.trim(),
                                      if (line.project.trim().isNotEmpty)
                                        line.project.trim(),
                                    ];
                                    final prefix = tags.isNotEmpty
                                        ? '[${tags.join(' - ')}] '
                                        : '';
                                    return Padding(
                                      padding: const EdgeInsets.only(bottom: 4),
                                      child: Text(
                                        '• $prefix${line.description}',
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(
                                          context,
                                        ).textTheme.bodyMedium,
                                      ),
                                    );
                                  }),
                                  if (remaining > 0)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 2),
                                      child: Text(
                                        '+$remaining aktivitas lainnya',
                                        style: AppTheme.tabularStyle(
                                          TextStyle(
                                            fontSize: 12,
                                            color: colors.inkMuted,
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openLogSheet(context),
        tooltip: 'Tambah catatan',
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, AppProvider provider) {
    if (provider.dailyLogs.isEmpty) {
      return JournalEmptyState(
        icon: Icons.edit_note_outlined,
        title: 'Belum ada catatan harian',
        subtitle:
            'Mulai catat aktivitas harian Anda untuk melacak jam kerja dan menyiapkan timesheet.',
        actionLabel: 'Tambah Catatan',
        onAction: () => _openLogSheet(context),
      );
    }

    if (provider.timelineFilter == TimelineFilter.needsTag &&
        provider.searchQuery.trim().isEmpty) {
      return JournalEmptyState(
        icon: Icons.verified_outlined,
        title: 'Semua catatan sudah memiliki tag',
        subtitle:
            'Tidak ada catatan cepat yang belum memiliki modul atau project.',
        actionLabel: 'Lihat Semua',
        onAction: () => provider.setTimelineFilter(TimelineFilter.all),
      );
    }

    if (provider.searchQuery.trim().isNotEmpty) {
      return JournalEmptyState(
        icon: Icons.search_off_outlined,
        title: 'Tidak ada hasil untuk "${provider.searchQuery.trim()}"',
        subtitle: 'Coba kata kunci lain atau bersihkan filter yang aktif.',
        actionLabel: 'Reset Pencarian',
        onAction: () {
          _searchCtrl.clear();
          provider.setSearchQuery('');
          provider.setTimelineFilter(TimelineFilter.all);
        },
      );
    }

    return JournalEmptyState(
      icon: Icons.date_range_outlined,
      title: 'Belum ada catatan di siklus ini',
      subtitle:
          'Tambahkan catatan baru atau tampilkan seluruh riwayat log Anda.',
      actionLabel: 'Tambah Catatan',
      onAction: () => _openLogSheet(context),
      secondaryLabel: 'Lihat Semua',
      onSecondary: () => provider.setTimelineFilter(TimelineFilter.all),
    );
  }
}

class _FilterChipItem extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onSelected;

  const _FilterChipItem({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return ChoiceChip(
      label: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          color: selected ? colors.accent : colors.inkPrimary,
        ),
      ),
      selected: selected,
      showCheckmark: false,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      selectedColor: colors.accentTint,
      backgroundColor: colors.surfaceAlt,
      side: BorderSide(
        color: selected ? colors.accent : colors.border,
      ),
      onSelected: (_) => onSelected(),
    );
  }
}
