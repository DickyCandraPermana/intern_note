import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/global_config.dart';
import '../../providers/app_provider.dart';

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final config = Provider.of<AppProvider>(context, listen: false).globalConfig;
      if (config != null) {
        _picController.text = config.picConsultant;
        _roleController.text = config.role;
        _createdByController.text = config.createdByName;
        _approvedByController.text = config.approvedByName;
        _approvedByLeadController.text = config.approvedByLeadName;
        _baseHoursController.text = config.defaultBaseHours.toString();
      }
    });
  }

  void _saveConfig() {
    if (!_formKey.currentState!.validate()) return;
    final newConfig = GlobalConfig(
      picConsultant: _picController.text,
      role: _roleController.text,
      createdByName: _createdByController.text,
      approvedByName: _approvedByController.text,
      approvedByLeadName: _approvedByLeadController.text,
      defaultBaseHours: double.tryParse(_baseHoursController.text) ?? 8.0,
    );
    Provider.of<AppProvider>(context, listen: false).updateGlobalConfig(newConfig);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Settings saved')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              const Text('Default Export Configuration', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              TextFormField(
                controller: _picController,
                decoration: const InputDecoration(labelText: 'PIC Consultant', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _roleController,
                decoration: const InputDecoration(labelText: 'Role', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _createdByController,
                decoration: const InputDecoration(labelText: 'Created By Name', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _approvedByController,
                decoration: const InputDecoration(labelText: 'Approved By Name', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _approvedByLeadController,
                decoration: const InputDecoration(labelText: 'Approved By Lead Project', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 24),
              const Text('Timesheet Defaults', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              TextFormField(
                controller: _baseHoursController,
                decoration: const InputDecoration(labelText: 'Default Base Hours', border: OutlineInputBorder()),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: (v) => v!.isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _saveConfig,
                icon: const Icon(Icons.save),
                label: const Text('Save Settings'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
