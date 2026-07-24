import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../models/daily_log.dart';
import '../providers/app_provider.dart';

class ActivityLineForm {
  int? id;
  TextEditingController modulCtrl;
  TextEditingController projectCtrl;
  TextEditingController descCtrl;
  
  ActivityLineForm({this.id, String modul = '', String project = '', String desc = ''}) 
    : modulCtrl = TextEditingController(text: modul),
      projectCtrl = TextEditingController(text: project),
      descCtrl = TextEditingController(text: desc);

  void dispose() {
    modulCtrl.dispose();
    projectCtrl.dispose();
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
  
  late DateTime _selectedDate;
  final _baseHoursCtrl = TextEditingController();
  final _overworkHoursCtrl = TextEditingController();
  List<ActivityLineForm> _lines = [];

  @override
  void initState() {
    super.initState();
    final config = Provider.of<AppProvider>(context, listen: false).globalConfig;
    
    _selectedDate = widget.log != null ? DateTime.parse(widget.log!.date) : (widget.initialDate ?? DateTime.now());
    if (widget.log != null) {
      _baseHoursCtrl.text = widget.log!.baseHours.toString();
      _overworkHoursCtrl.text = widget.log!.overworkHours.toString();
      for (var l in widget.log!.lines) {
        _lines.add(ActivityLineForm(id: l.id, modul: l.modul, project: l.project, desc: l.description));
      }
    } else {
      _baseHoursCtrl.text = config?.defaultBaseHours.toString() ?? '8.0';
      _overworkHoursCtrl.text = '0.0';
      _lines.add(ActivityLineForm());
    }
  }

  @override
  void dispose() {
    _baseHoursCtrl.dispose();
    _overworkHoursCtrl.dispose();
    for (var l in _lines) {
      l.dispose();
    }
    super.dispose();
  }

  void _addLine() {
    setState(() {
      _lines.add(ActivityLineForm());
    });
  }

  void _removeLine(int index) {
    setState(() {
      _lines[index].dispose();
      _lines.removeAt(index);
    });
  }

  void _save() {
    if (_formKey.currentState!.validate()) {
      if (_lines.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('At least one activity is required')));
        return;
      }

      final newLog = DailyLog(
        id: widget.log?.id,
        date: _selectedDate.toIso8601String(),
        baseHours: double.tryParse(_baseHoursCtrl.text) ?? 8.0,
        overworkHours: double.tryParse(_overworkHoursCtrl.text) ?? 0.0,
        lines: _lines.map((l) => ActivityLine(
          id: l.id,
          modul: l.modulCtrl.text,
          project: l.projectCtrl.text,
          description: l.descCtrl.text,
        )).toList(),
      );
      
      if (widget.log == null) {
        Provider.of<AppProvider>(context, listen: false).addDailyLog(newLog);
      } else {
        Provider.of<AppProvider>(context, listen: false).updateDailyLog(newLog);
      }
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AppProvider>(context, listen: false);
    
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 16,
        right: 16,
        top: 16,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.log == null ? 'Log Daily Activities' : 'Edit Daily Log', style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ListTile(
                title: Text('Date: ${DateFormat('yyyy-MM-dd').format(_selectedDate)}'),
                trailing: const Icon(Icons.calendar_today),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _selectedDate,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2100),
                  );
                  if (picked != null) {
                    setState(() => _selectedDate = picked);
                  }
                },
              ),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _baseHoursCtrl,
                      decoration: const InputDecoration(labelText: 'Base Hours', border: OutlineInputBorder()),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      validator: (v) => v!.isEmpty ? 'Required' : null,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextFormField(
                      controller: _overworkHoursCtrl,
                      decoration: const InputDecoration(labelText: 'Overwork Hours', border: OutlineInputBorder()),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      validator: (v) => v!.isEmpty ? 'Required' : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Row(
                children: const [
                  Expanded(flex: 2, child: Text('Modul', style: TextStyle(fontWeight: FontWeight.bold))),
                  SizedBox(width: 8),
                  Expanded(flex: 2, child: Text('Project', style: TextStyle(fontWeight: FontWeight.bold))),
                  SizedBox(width: 8),
                  Expanded(flex: 3, child: Text('Activity', style: TextStyle(fontWeight: FontWeight.bold))),
                  SizedBox(width: 48),
                ],
              ),
              const Divider(),
              ...List.generate(_lines.length, (index) {
                final line = _lines[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 2,
                        child: Autocomplete<String>(
                          initialValue: TextEditingValue(text: line.modulCtrl.text),
                          optionsBuilder: (TextEditingValue textEditingValue) {
                            if (textEditingValue.text.isEmpty) return provider.modules;
                            return provider.modules.where((String option) => option.toLowerCase().contains(textEditingValue.text.toLowerCase()));
                          },
                          fieldViewBuilder: (context, controller, focusNode, onEditingComplete) {
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (controller.text != line.modulCtrl.text) {
                                line.modulCtrl.text = controller.text;
                              }
                            });
                            controller.addListener(() {
                              line.modulCtrl.text = controller.text;
                            });
                            return TextFormField(
                              controller: controller,
                              focusNode: focusNode,
                              decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
                              validator: (v) => v!.isEmpty ? 'Req' : null,
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: Autocomplete<String>(
                          initialValue: TextEditingValue(text: line.projectCtrl.text),
                          optionsBuilder: (TextEditingValue textEditingValue) {
                            if (textEditingValue.text.isEmpty) return provider.projects;
                            return provider.projects.where((String option) => option.toLowerCase().contains(textEditingValue.text.toLowerCase()));
                          },
                          fieldViewBuilder: (context, controller, focusNode, onEditingComplete) {
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (controller.text != line.projectCtrl.text) {
                                line.projectCtrl.text = controller.text;
                              }
                            });
                            controller.addListener(() {
                              line.projectCtrl.text = controller.text;
                            });
                            return TextFormField(
                              controller: controller,
                              focusNode: focusNode,
                              decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
                              validator: (v) => v!.isEmpty ? 'Req' : null,
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 3,
                        child: TextFormField(
                          controller: line.descCtrl,
                          decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
                          validator: (v) => v!.isEmpty ? 'Req' : null,
                          maxLines: null,
                        ),
                      ),
                      if (_lines.length > 1)
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () => _removeLine(index),
                        )
                      else
                        const SizedBox(width: 24),
                    ],
                  ),
                );
              }),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _addLine,
                  icon: const Icon(Icons.add),
                  label: const Text('Add Line'),
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _save,
                style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                child: Text(widget.log == null ? 'Save Daily Log' : 'Update Daily Log', style: const TextStyle(fontSize: 16)),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
