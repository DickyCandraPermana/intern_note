import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../models/global_config.dart';
import '../../providers/app_provider.dart';
import '../../services/backup_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/date_formatters.dart';

class SettingsTab extends StatefulWidget {
  const SettingsTab({super.key});

  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> {
  final _formKey = GlobalKey<FormState>();
  final _picController = TextEditingController();
  final _roleController = TextEditingController();
  final _createdByController = TextEditingController();
  final _approvedByController = TextEditingController();
  final _approvedByLeadController = TextEditingController();
  final _baseHoursController = TextEditingController();
  final _defaultModulController = TextEditingController();
  final _defaultProjectController = TextEditingController();
  final _newPresetController = TextEditingController();

  AppProvider? _provider;
  GlobalConfig? _lastSyncedConfig;
  int _selectedCutoffDay = 24;
  bool _isBackingUp = false;
  bool _isRestoring = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nextProvider = context.read<AppProvider>();
    if (!identical(_provider, nextProvider)) {
      _provider?.removeListener(_onProviderChanged);
      _provider = nextProvider;
      _provider!.addListener(_onProviderChanged);
      if (!_provider!.isLoading) {
        _applyConfigToFields(
          _provider!.effectiveConfig,
          forceAll: _lastSyncedConfig == null,
        );
      }
    }
  }

  @override
  void dispose() {
    _provider?.removeListener(_onProviderChanged);
    _picController.dispose();
    _roleController.dispose();
    _createdByController.dispose();
    _approvedByController.dispose();
    _approvedByLeadController.dispose();
    _baseHoursController.dispose();
    _defaultModulController.dispose();
    _defaultProjectController.dispose();
    _newPresetController.dispose();
    super.dispose();
  }

  void _onProviderChanged() {
    if (!mounted || _provider == null || _provider!.isLoading) return;
    _scheduleSync(_provider!.effectiveConfig);
  }

  void _scheduleSync(GlobalConfig config, {bool forceAll = false}) {
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _applyConfigToFields(config, forceAll: forceAll, allowSetState: true);
      });
      return;
    }
    _applyConfigToFields(config, forceAll: forceAll, allowSetState: true);
  }

  void _applyConfigToFields(
    GlobalConfig config, {
    bool forceAll = false,
    bool allowSetState = false,
  }) {
    final prev = _lastSyncedConfig;

    void syncController(
      TextEditingController controller,
      String nextValue,
      String? prevValue,
    ) {
      if (forceAll || prev == null || prevValue != nextValue) {
        if (controller.text != nextValue) {
          controller.text = nextValue;
        }
      }
    }

    syncController(_picController, config.picConsultant, prev?.picConsultant);
    syncController(_roleController, config.role, prev?.role);
    syncController(
      _createdByController,
      config.createdByName,
      prev?.createdByName,
    );
    syncController(
      _approvedByController,
      config.approvedByName,
      prev?.approvedByName,
    );
    syncController(
      _approvedByLeadController,
      config.approvedByLeadName,
      prev?.approvedByLeadName,
    );
    syncController(
      _baseHoursController,
      config.defaultBaseHours.toString(),
      prev?.defaultBaseHours.toString(),
    );
    syncController(
      _defaultModulController,
      config.defaultModul,
      prev?.defaultModul,
    );
    syncController(
      _defaultProjectController,
      config.defaultProject,
      prev?.defaultProject,
    );

    final nextCutoff = config.cutoffDay.clamp(1, 28);
    if (forceAll || prev == null || prev.cutoffDay != config.cutoffDay) {
      if (_selectedCutoffDay != nextCutoff) {
        if (allowSetState && mounted) {
          setState(() => _selectedCutoffDay = nextCutoff);
        } else {
          _selectedCutoffDay = nextCutoff;
        }
      }
    }

    _lastSyncedConfig = config.copyWith();
  }

  GlobalConfig _buildFormConfig(GlobalConfig base) {
    final parsedHours = double.tryParse(_baseHoursController.text.trim());
    return base.copyWith(
      picConsultant: _picController.text.trim(),
      role: _roleController.text.trim(),
      createdByName: _createdByController.text.trim(),
      approvedByName: _approvedByController.text.trim(),
      approvedByLeadName: _approvedByLeadController.text.trim(),
      defaultBaseHours: (parsedHours != null && parsedHours > 0)
          ? parsedHours
          : base.defaultBaseHours,
      cutoffDay: _selectedCutoffDay,
      defaultModul: _defaultModulController.text.trim(),
      defaultProject: _defaultProjectController.text.trim(),
    );
  }

  Future<void> _updateSingleSetting(
    AppProvider provider,
    GlobalConfig updated,
    String errorPrefix, {
    VoidCallback? onError,
  }) async {
    try {
      await provider.updateGlobalConfig(updated);
    } catch (e) {
      onError?.call();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$errorPrefix: $e')),
      );
    }
  }

  Future<void> _saveConfig(AppProvider provider) async {
    if (!_formKey.currentState!.validate()) return;
    final base = provider.effectiveConfig;
    final updated = _buildFormConfig(base);
    try {
      await provider.updateGlobalConfig(updated);
      if (!mounted) return;
      final colors = AppColors.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Pengaturan berhasil disimpan'),
          backgroundColor: colors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal menyimpan pengaturan: $e')),
      );
    }
  }

  Future<void> _addPreset(AppProvider provider) async {
    final raw = _newPresetController.text.trim();
    if (raw.isEmpty) return;

    final config = provider.effectiveConfig;
    final updatedPresets = List<String>.from(config.quickPresets);
    final alreadyExists = updatedPresets.any(
      (item) => item.toLowerCase() == raw.toLowerCase(),
    );
    if (!alreadyExists) {
      updatedPresets.add(raw);
    }

    try {
      await provider.updateGlobalConfig(
        config.copyWith(quickPresets: updatedPresets),
      );
      if (!mounted) return;
      _newPresetController.clear();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal menambah preset: $e')),
      );
    }
  }

  Future<void> _removePreset(AppProvider provider, String preset) async {
    final config = provider.effectiveConfig;
    final updatedPresets =
        config.quickPresets.where((item) => item != preset).toList();
    await _updateSingleSetting(
      provider,
      config.copyWith(quickPresets: updatedPresets),
      'Gagal menghapus preset',
    );
  }

  Future<void> _exportJsonBackup(AppProvider provider) async {
    if (_isBackingUp) return;
    setState(() => _isBackingUp = true);
    try {
      final file = await BackupService.writeBackupFile(
        provider.effectiveConfig,
        provider.dailyLogs,
      );
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          text: 'Intern Noter Backup JSON',
        ),
      );
      if (!mounted) return;
      final colors = AppColors.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Backup siap dibagikan (${provider.dailyLogs.length} hari)',
          ),
          backgroundColor: colors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal membuat backup JSON: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isBackingUp = false);
      }
    }
  }

  Future<void> _restoreJsonBackup(AppProvider provider) async {
    if (_isRestoring) return;
    setState(() => _isRestoring = true);
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) {
        return;
      }

      final picked = result.files.single;
      final String jsonText;
      if (picked.path != null && picked.path!.isNotEmpty) {
        jsonText = await File(picked.path!).readAsString();
      } else if (picked.bytes != null) {
        jsonText = utf8.decode(picked.bytes!);
      } else {
        throw const FormatException('File backup tidak dapat dibaca.');
      }

      final payload = BackupService.parseAndValidateBackupJson(jsonText);
      if (!mounted) return;

      final colors = AppColors.of(context);
      final mode = await showDialog<RestoreMode>(
        context: context,
        builder: (dialogCtx) => AlertDialog(
          title: const Text('Restore Backup JSON'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Backup valid (schema v${payload.schemaVersion}, diekspor ${formatIndonesianDate(payload.exportedAt)}).',
              ),
              const SizedBox(height: 8),
              Text(
                'Jumlah catatan harian: ${payload.dailyLogs.length} hari.',
                style: AppTheme.tabularStyle(
                  const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Merge hanya menambah tanggal baru. Replace akan mengganti seluruh data saat ini.',
                style: TextStyle(fontSize: 13, color: colors.inkMuted),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('Batal'),
            ),
            OutlinedButton(
              onPressed: () => Navigator.pop(dialogCtx, RestoreMode.merge),
              child: const Text('Merge'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogCtx, RestoreMode.replace),
              style: FilledButton.styleFrom(
                backgroundColor: colors.destructive,
                foregroundColor: Theme.of(dialogCtx).colorScheme.onError,
              ),
              child: const Text('Replace'),
            ),
          ],
        ),
      );

      if (mode == null || !mounted) return;
      final restoreResult = await provider.restoreBackup(payload, mode);
      if (!mounted) return;

      _scheduleSync(provider.effectiveConfig, forceAll: true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Restore selesai: ${restoreResult.addedLogs} ditambahkan, '
            '${restoreResult.skippedLogs} dilewati (total ${restoreResult.totalLogsAfter} hari)',
          ),
          backgroundColor: colors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Restore backup gagal: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isRestoring = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Pengaturan')),
      body: Consumer<AppProvider>(
        builder: (context, provider, _) {
          if (provider.isLoading) {
            return const JournalSkeletonList(cardCount: 4);
          }

          if (provider.errorMessage != null && provider.globalConfig == null) {
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

          return Form(
            key: _formKey,
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
                JournalCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('Tampilan Aplikasi', style: theme.textTheme.titleMedium),
                      const SizedBox(height: 4),
                      Text(
                        'Pilih tema Light, Dark, atau ikuti pengaturan perangkat.',
                        style: TextStyle(fontSize: 13, color: colors.inkMuted),
                      ),
                      const SizedBox(height: 12),
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment<String>(
                            value: 'system',
                            label: Text('System'),
                            icon: Icon(Icons.brightness_auto_outlined, size: 18),
                          ),
                          ButtonSegment<String>(
                            value: 'light',
                            label: Text('Light'),
                            icon: Icon(Icons.light_mode_outlined, size: 18),
                          ),
                          ButtonSegment<String>(
                            value: 'dark',
                            label: Text('Dark'),
                            icon: Icon(Icons.dark_mode_outlined, size: 18),
                          ),
                        ],
                        selected: {config.themeMode},
                        onSelectionChanged: (selection) {
                          _updateSingleSetting(
                            provider,
                            config.copyWith(themeMode: selection.first),
                            'Gagal mengubah tema',
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                JournalCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Siklus Cutoff & Catatan Cepat',
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<int>(
                        key: ValueKey<int>(_selectedCutoffDay),
                        initialValue: _selectedCutoffDay,
                        decoration: const InputDecoration(
                          labelText: 'Cutoff Day (Tanggal Tutup Buku)',
                          helperText:
                              'Cutoff 24 berarti siklus 25 bulan lalu s/d 24 bulan ini',
                        ),
                        items: List.generate(28, (index) {
                          final day = index + 1;
                          return DropdownMenuItem<int>(
                            value: day,
                            child: Text(
                              'Tanggal $day',
                              style: AppTheme.tabularStyle(
                                theme.textTheme.bodyMedium!,
                              ),
                            ),
                          );
                        }),
                        onChanged: (val) {
                          if (val == null) return;
                          final prevDay = _selectedCutoffDay;
                          setState(() => _selectedCutoffDay = val);
                          _updateSingleSetting(
                            provider,
                            config.copyWith(cutoffDay: val),
                            'Gagal menyimpan cutoff day',
                            onError: () {
                              if (mounted) {
                                setState(() => _selectedCutoffDay = prevDay);
                              }
                            },
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _defaultModulController,
                        decoration: const InputDecoration(
                          labelText: 'Default Modul (Widget / Quick Note)',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _defaultProjectController,
                        decoration: const InputDecoration(
                          labelText: 'Default Project (Widget / Quick Note)',
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Quick Presets',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: colors.inkPrimary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (config.quickPresets.isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            'Belum ada preset cepat. Tambahkan preset di bawah.',
                            style: TextStyle(fontSize: 13, color: colors.inkMuted),
                          ),
                        )
                      else
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: config.quickPresets.map((preset) {
                            return InputChip(
                              label: Text(preset),
                              materialTapTargetSize:
                                  MaterialTapTargetSize.padded,
                              onDeleted: () => _removePreset(provider, preset),
                            );
                          }).toList(),
                        ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _newPresetController,
                              textInputAction: TextInputAction.done,
                              onSubmitted: (_) => _addPreset(provider),
                              decoration: const InputDecoration(
                                hintText: 'Tambah preset cepat...',
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton(
                            onPressed: () => _addPreset(provider),
                            child: const Text('Tambah'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                JournalCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Metadata Ekspor Timesheet',
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Include Signature (XLSX & PDF)'),
                        subtitle: const Text(
                          'Sematkan tanda tangan pada hasil ekspor XLSX dan PDF',
                        ),
                        value: config.includeSignature,
                        onChanged: (val) {
                          _updateSingleSetting(
                            provider,
                            config.copyWith(includeSignature: val),
                            'Gagal mengubah pengaturan tanda tangan',
                          );
                        },
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _picController,
                        decoration: const InputDecoration(
                          labelText: 'PIC Consultant',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _roleController,
                        decoration: const InputDecoration(labelText: 'Role'),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _createdByController,
                        decoration: const InputDecoration(
                          labelText: 'Created By Name',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _approvedByController,
                        decoration: const InputDecoration(
                          labelText: 'Approved By Name (Opsional)',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _approvedByLeadController,
                        decoration: const InputDecoration(
                          labelText: 'Approved By Lead Project',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _baseHoursController,
                        style: AppTheme.tabularStyle(
                          theme.textTheme.bodyMedium!,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Default Base Hours',
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        validator: (value) {
                          final trimmed = (value ?? '').trim();
                          final parsed = double.tryParse(trimmed);
                          if (trimmed.isEmpty ||
                              parsed == null ||
                              parsed <= 0) {
                            return 'Masukkan jam dasar yang valid (> 0)';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: () => _saveConfig(provider),
                        icon: const Icon(Icons.save_outlined),
                        label: const Text('Simpan Pengaturan'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                JournalCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Backup & Restore JSON',
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Cadangkan seluruh log aktivitas dan pengaturan dalam format JSON, atau pulihkan ke perangkat ini.',
                        style: TextStyle(fontSize: 13, color: colors.inkMuted),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: _isBackingUp
                            ? null
                            : () => _exportJsonBackup(provider),
                        icon: _isBackingUp
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.upload_file_outlined),
                        label: const Text('Export JSON Backup'),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: _isRestoring
                            ? null
                            : () => _restoreJsonBackup(provider),
                        icon: _isRestoring
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.restore_page_outlined),
                        label: const Text('Restore JSON Backup'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
