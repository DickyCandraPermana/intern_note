import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/daily_log.dart';
import '../models/global_config.dart';
import '../providers/app_provider.dart';
import '../theme/app_theme.dart';
import '../utils/date_formatters.dart';

class ActivityLineForm {
  int? id;
  final TextEditingController modulCtrl;
  final FocusNode modulFocusNode;
  final TextEditingController projectCtrl;
  final FocusNode projectFocusNode;
  final TextEditingController descCtrl;
  final bool isFromExisting;
  final String _initialModul;
  final String _initialProject;
  final String _initialDesc;

  ActivityLineForm({
    this.id,
    String modul = '',
    String project = '',
    String desc = '',
    this.isFromExisting = false,
  })  : modulCtrl = TextEditingController(text: modul),
        modulFocusNode = FocusNode(),
        projectCtrl = TextEditingController(text: project),
        projectFocusNode = FocusNode(),
        descCtrl = TextEditingController(text: desc),
        _initialModul = modul.trim(),
        _initialProject = project.trim(),
        _initialDesc = desc.trim();

  bool get isModifiedFromExisting =>
      !isFromExisting ||
      modulCtrl.text.trim() != _initialModul ||
      projectCtrl.text.trim() != _initialProject ||
      descCtrl.text.trim() != _initialDesc;

  bool hasUserContent(String defaultModul, String defaultProject) {
    return descCtrl.text.trim().isNotEmpty ||
        modulCtrl.text.trim() != defaultModul.trim() ||
        projectCtrl.text.trim() != defaultProject.trim();
  }

  void dispose() {
    modulCtrl.dispose();
    modulFocusNode.dispose();
    projectCtrl.dispose();
    projectFocusNode.dispose();
    descCtrl.dispose();
  }
}

class DailyLogSheet extends StatefulWidget {
  final DateTime? initialDate;
  final DailyLog? log;

  const DailyLogSheet({super.key, this.initialDate, this.log});

  @override
  State<DailyLogSheet> createState() => _DailyLogSheetState();
}

class _DailyLogSheetState extends State<DailyLogSheet> {
  final _formKey = GlobalKey<FormState>();
  final _baseHoursCtrl = TextEditingController();
  final _overworkHoursCtrl = TextEditingController();
  final List<ActivityLineForm> _lines = [];

  late DateTime _selectedDate;
  DailyLog? _existingSameDayLog;
  String? _dateCollisionWarning;
  bool _hoursEditedByUser = false;
  bool _isSaving = false;

  static DateTime _dateOnly(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

  static DateTime _parseDateOnly(String raw) {
    final normalized = normalizeIsoDate(raw);
    final parsed = DateTime.tryParse(normalized);
    if (parsed != null) return _dateOnly(parsed);
    return _dateOnly(DateTime.now());
  }

  static List<ActivityLine> _sortedLines(List<ActivityLine> source) {
    final copy = List<ActivityLine>.from(source);
    copy.sort((a, b) {
      final orderCmp = a.sortOrder.compareTo(b.sortOrder);
      if (orderCmp != 0) return orderCmp;
      return (a.id ?? 0).compareTo(b.id ?? 0);
    });
    return copy;
  }

  static List<ActivityLineForm> _existingForms(DailyLog log) {
    return _sortedLines(log.lines)
        .map(
          (line) => ActivityLineForm(
            id: line.id,
            modul: line.modul,
            project: line.project,
            desc: line.description,
            isFromExisting: true,
          ),
        )
        .toList();
  }

  static ActivityLineForm _blankLine(GlobalConfig config) {
    return ActivityLineForm(
      modul: config.defaultModul,
      project: config.defaultProject,
    );
  }

  @override
  void initState() {
    super.initState();
    final provider = context.read<AppProvider>();
    final config = provider.effectiveConfig;

    _selectedDate = widget.log != null
        ? _parseDateOnly(widget.log!.date)
        : _dateOnly(widget.initialDate ?? DateTime.now());

    final sourceLog = widget.log ?? provider.getDailyLogForDate(_selectedDate);
    if (sourceLog != null) {
      if (widget.log == null) {
        _existingSameDayLog = sourceLog;
      }
      _baseHoursCtrl.text = sourceLog.baseHours.toString();
      _overworkHoursCtrl.text = sourceLog.overworkHours.toString();
      _lines.addAll(_existingForms(sourceLog));
      if (_lines.isEmpty) {
        _lines.add(_blankLine(config));
      }
    } else {
      _baseHoursCtrl.text = config.defaultBaseHours.toString();
      _overworkHoursCtrl.text = '0.0';
      _lines.add(_blankLine(config));
    }
  }

  @override
  void dispose() {
    _baseHoursCtrl.dispose();
    _overworkHoursCtrl.dispose();
    for (final line in _lines) {
      line.dispose();
    }
    super.dispose();
  }

  void _disposeLater(List<ActivityLineForm> removed) {
    if (removed.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final item in removed) {
        item.dispose();
      }
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) return;

    final pickedDate = _dateOnly(picked);
    if (pickedDate == _selectedDate) return;

    final provider = context.read<AppProvider>();
    final config = provider.effectiveConfig;

    if (widget.log != null) {
      final collision = provider.getDailyLogForDate(pickedDate);
      if (collision != null && collision.id != widget.log!.id) {
        setState(() {
          _dateCollisionWarning =
              'Tanggal ${formatIndonesianShortDate(pickedDate)} sudah memiliki catatan terpisah. Pilih tanggal lain.';
        });
        return;
      }
      setState(() {
        _dateCollisionWarning = null;
        _selectedDate = pickedDate;
      });
      return;
    }

    final preservedLines = <ActivityLineForm>[];
    final toDispose = <ActivityLineForm>[];
    for (final line in _lines) {
      if (line.isFromExisting) {
        if (line.isModifiedFromExisting &&
            line.descCtrl.text.trim().isNotEmpty) {
          preservedLines.add(
            ActivityLineForm(
              modul: line.modulCtrl.text,
              project: line.projectCtrl.text,
              desc: line.descCtrl.text,
            ),
          );
        }
        toDispose.add(line);
      } else if (line.hasUserContent(
        config.defaultModul,
        config.defaultProject,
      )) {
        preservedLines.add(line);
      } else {
        toDispose.add(line);
      }
    }

    final nextExisting = provider.getDailyLogForDate(pickedDate);
    final nextLines = <ActivityLineForm>[];

    if (nextExisting != null) {
      nextLines.addAll(_existingForms(nextExisting));
      nextLines.addAll(preservedLines);
      if (nextLines.isEmpty) {
        nextLines.add(_blankLine(config));
      }
      if (!_hoursEditedByUser) {
        _baseHoursCtrl.text = nextExisting.baseHours.toString();
        _overworkHoursCtrl.text = nextExisting.overworkHours.toString();
      }
    } else {
      nextLines.addAll(preservedLines);
      if (nextLines.isEmpty) {
        nextLines.add(_blankLine(config));
      }
      if (!_hoursEditedByUser) {
        _baseHoursCtrl.text = config.defaultBaseHours.toString();
        _overworkHoursCtrl.text = '0.0';
      }
    }

    setState(() {
      _selectedDate = pickedDate;
      _existingSameDayLog = nextExisting;
      _dateCollisionWarning = null;
      _lines
        ..clear()
        ..addAll(nextLines);
    });
    _disposeLater(toDispose);
  }

  void _addLine() {
    final config = context.read<AppProvider>().effectiveConfig;
    setState(() {
      _lines.add(_blankLine(config));
    });
  }

  void _removeLine(int index) {
    if (_lines.length <= 1) return;
    late final ActivityLineForm removed;
    setState(() {
      removed = _lines.removeAt(index);
    });
    _disposeLater([removed]);
  }

  void _moveLineUp(int index) {
    if (index <= 0 || index >= _lines.length) return;
    setState(() {
      final item = _lines.removeAt(index);
      _lines.insert(index - 1, item);
    });
  }

  void _moveLineDown(int index) {
    if (index < 0 || index >= _lines.length - 1) return;
    setState(() {
      final item = _lines.removeAt(index);
      _lines.insert(index + 1, item);
    });
  }

  void _applyPreset(ActivityLineForm line, String preset) {
    final current = line.descCtrl.text.trim();
    final String nextText;
    if (current.isEmpty) {
      nextText = preset;
    } else if (current
        .split(RegExp(r'\r?\n'))
        .any((p) => p.trim() == preset.trim())) {
      nextText = current;
    } else {
      nextText = '$current\n$preset';
    }
    line.descCtrl.value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(offset: nextText.length),
    );
  }

  Future<void> _save() async {
    if (_isSaving) return;
    if (!_formKey.currentState!.validate()) return;

    if (_lines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Minimal satu aktivitas harus diisi')),
      );
      return;
    }

    final provider = context.read<AppProvider>();
    final targetLogId = widget.log?.id ?? _existingSameDayLog?.id;
    final isoDate = formatIsoDate(_selectedDate);
    final baseHours = double.tryParse(_baseHoursCtrl.text.trim()) ??
        provider.effectiveConfig.defaultBaseHours;
    final overworkHours =
        double.tryParse(_overworkHoursCtrl.text.trim()) ?? 0.0;

    final builtLines = List<ActivityLine>.generate(_lines.length, (index) {
      final form = _lines[index];
      return ActivityLine(
        id: form.id,
        dailyLogId: targetLogId,
        modul: form.modulCtrl.text.trim(),
        project: form.projectCtrl.text.trim(),
        description: form.descCtrl.text.trim(),
        sortOrder: index,
      );
    });

    final logToSave = DailyLog(
      id: targetLogId,
      date: isoDate,
      baseHours: baseHours,
      overworkHours: overworkHours,
      lines: builtLines,
    );

    setState(() => _isSaving = true);
    try {
      if (targetLogId != null) {
        await provider.updateDailyLog(logToSave);
      } else {
        await provider.addDailyLog(
          logToSave,
          mergeIfExists: _existingSameDayLog == null,
        );
      }
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal menyimpan catatan: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final theme = Theme.of(context);
    final provider = context.read<AppProvider>();
    final presets = provider.effectiveConfig.quickPresets;
    final maxSheetHeight = MediaQuery.of(context).size.height * 0.92;

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxSheetHeight),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: colors.border,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.log == null
                              ? 'Log Daily Activities'
                              : 'Edit Daily Log',
                          style: theme.textTheme.titleLarge,
                        ),
                      ),
                      IconButton(
                        onPressed: _isSaving ? null : () => Navigator.pop(context),
                        tooltip: 'Tutup',
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  InkWell(
                    onTap: _isSaving ? null : _pickDate,
                    borderRadius: BorderRadius.circular(AppTheme.controlRadius),
                    child: Container(
                      constraints: const BoxConstraints(
                        minHeight: AppTheme.minTapTarget,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: colors.surfaceAlt,
                        borderRadius: BorderRadius.circular(
                          AppTheme.controlRadius,
                        ),
                        border: Border.all(color: colors.border),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.calendar_today_outlined,
                            size: 18,
                            color: colors.accent,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  formatIndonesianLongDayDate(_selectedDate),
                                  style: AppTheme.tabularStyle(
                                    theme.textTheme.bodyMedium!.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                Text(
                                  formatIsoDate(_selectedDate),
                                  style: AppTheme.tabularStyle(
                                    TextStyle(
                                      fontSize: 12,
                                      color: colors.inkMuted,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.edit_calendar_outlined,
                            size: 18,
                            color: colors.inkMuted,
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (widget.log == null && _existingSameDayLog != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: colors.accentTint,
                        borderRadius: BorderRadius.circular(
                          AppTheme.controlRadius,
                        ),
                        border: Border.all(
                          color: colors.accent.withValues(alpha: 0.45),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            size: 18,
                            color: colors.accent,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Menambahkan ke catatan tanggal ini yang sudah ada',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: colors.accent,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (_dateCollisionWarning != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: colors.warning.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(
                          AppTheme.controlRadius,
                        ),
                        border: Border.all(
                          color: colors.warning.withValues(alpha: 0.5),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.warning_amber_outlined,
                            size: 18,
                            color: colors.warning,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _dateCollisionWarning!,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: colors.warning,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _baseHoursCtrl,
                          style: AppTheme.tabularStyle(
                            theme.textTheme.bodyMedium!,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Base Hours',
                          ),
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          onChanged: (_) => _hoursEditedByUser = true,
                          validator: (v) {
                            final parsed = double.tryParse((v ?? '').trim());
                            if (parsed == null || !parsed.isFinite || parsed < 0) {
                              return 'Jam tidak valid';
                            }
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _overworkHoursCtrl,
                          style: AppTheme.tabularStyle(
                            theme.textTheme.bodyMedium!,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Overwork Hours',
                          ),
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          onChanged: (_) => _hoursEditedByUser = true,
                          validator: (v) {
                            final parsed = double.tryParse((v ?? '').trim());
                            if (parsed == null || !parsed.isFinite || parsed < 0) {
                              return 'Jam tidak valid';
                            }
                            return null;
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Daftar Aktivitas',
                        style: theme.textTheme.titleMedium,
                      ),
                      Text(
                        '${_lines.length} baris',
                        style: AppTheme.tabularStyle(
                          theme.textTheme.bodySmall!,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ...List.generate(_lines.length, (index) {
                    final line = _lines[index];
                    return Padding(
                      key: ObjectKey(line),
                      padding: const EdgeInsets.only(bottom: 12),
                      child: JournalCard(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'Aktivitas #${index + 1}',
                                    style: AppTheme.tabularStyle(
                                      theme.textTheme.titleMedium!,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.arrow_upward, size: 20),
                                  tooltip: 'Pindah ke atas',
                                  onPressed: (!_isSaving && index > 0)
                                      ? () => _moveLineUp(index)
                                      : null,
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.arrow_downward,
                                    size: 20,
                                  ),
                                  tooltip: 'Pindah ke bawah',
                                  onPressed:
                                      (!_isSaving && index < _lines.length - 1)
                                          ? () => _moveLineDown(index)
                                          : null,
                                ),
                                IconButton(
                                  icon: Icon(
                                    Icons.delete_outline,
                                    size: 20,
                                    color: _lines.length > 1
                                        ? colors.destructive
                                        : colors.inkMuted.withValues(
                                            alpha: 0.4,
                                          ),
                                  ),
                                  tooltip: 'Hapus aktivitas',
                                  onPressed: (!_isSaving && _lines.length > 1)
                                      ? () => _removeLine(index)
                                      : null,
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: _AutocompleteTagField(
                                    controller: line.modulCtrl,
                                    focusNode: line.modulFocusNode,
                                    options: provider.modules,
                                    labelText: 'Modul',
                                    hintText: 'Opsional',
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _AutocompleteTagField(
                                    controller: line.projectCtrl,
                                    focusNode: line.projectFocusNode,
                                    options: provider.projects,
                                    labelText: 'Project',
                                    hintText: 'Opsional',
                                  ),
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
                                    materialTapTargetSize:
                                        MaterialTapTargetSize.padded,
                                    avatar: Icon(
                                      Icons.add,
                                      size: 16,
                                      color: colors.accent,
                                    ),
                                    label: Text(preset),
                                    onPressed: _isSaving
                                        ? null
                                        : () => _applyPreset(line, preset),
                                  );
                                }).toList(),
                              ),
                            ],
                            const SizedBox(height: 10),
                            TextFormField(
                              controller: line.descCtrl,
                              minLines: 2,
                              maxLines: 6,
                              keyboardType: TextInputType.multiline,
                              decoration: const InputDecoration(
                                labelText: 'Aktivitas',
                                hintText: 'Tulis pekerjaan atau catatan...',
                                alignLabelWithHint: true,
                              ),
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) {
                                  return 'Aktivitas wajib diisi';
                                }
                                return null;
                              },
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: _isSaving ? null : _addLine,
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Tambah Aktivitas'),
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _isSaving ? null : _save,
                    child: _isSaving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            widget.log == null
                                ? 'Simpan Catatan'
                                : 'Simpan Perubahan',
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AutocompleteTagField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final List<String> options;
  final String labelText;
  final String hintText;

  const _AutocompleteTagField({
    required this.controller,
    required this.focusNode,
    required this.options,
    required this.labelText,
    required this.hintText,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        return RawAutocomplete<String>(
          textEditingController: controller,
          focusNode: focusNode,
          optionsBuilder: (TextEditingValue textEditingValue) {
            final query = textEditingValue.text.trim().toLowerCase();
            if (query.isEmpty) return options;
            return options.where(
              (option) => option.toLowerCase().contains(query),
            );
          },
          fieldViewBuilder:
              (context, textController, fieldFocusNode, onFieldSubmitted) {
            return TextFormField(
              controller: textController,
              focusNode: fieldFocusNode,
              textInputAction: TextInputAction.next,
              onFieldSubmitted: (_) => onFieldSubmitted(),
              decoration: InputDecoration(
                labelText: labelText,
                hintText: hintText,
              ),
            );
          },
          optionsViewBuilder: (context, onSelected, iterableOptions) {
            final items = iterableOptions.toList();
            if (items.isEmpty) return const SizedBox.shrink();
            return Align(
              alignment: Alignment.topLeft,
              child: Material(
                elevation: 4,
                color: colors.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppTheme.controlRadius),
                  side: BorderSide(color: colors.border),
                ),
                clipBehavior: Clip.antiAlias,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: 192,
                    maxWidth: constraints.maxWidth,
                  ),
                  child: ListView.builder(
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final option = items[index];
                      return InkWell(
                        onTap: () => onSelected(option),
                        child: Container(
                          constraints: const BoxConstraints(
                            minHeight: AppTheme.minTapTarget,
                          ),
                          alignment: Alignment.centerLeft,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          child: Text(
                            option,
                            style: Theme.of(context).textTheme.bodyMedium,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
