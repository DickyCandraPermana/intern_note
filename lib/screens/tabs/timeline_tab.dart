import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../providers/app_provider.dart';
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Timeline')),
      body: Consumer<AppProvider>(
        builder: (context, provider, child) {
          if (provider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          final logs = provider.filteredDailyLogs;

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    labelText: 'Search Project or Modul...',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    suffixIcon: _searchCtrl.text.isNotEmpty ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchCtrl.clear();
                        provider.setSearchQuery('');
                      },
                    ) : null,
                  ),
                  onChanged: (val) => provider.setSearchQuery(val),
                ),
              ),
              Expanded(
                child: logs.isEmpty
                    ? const Center(child: Text('No daily logs found.'))
                    : ListView.builder(
                        itemCount: logs.length,
                        itemBuilder: (context, index) {
                          final log = logs[index];
                          final date = DateTime.parse(log.date);
                          
                          String activitiesSummary = log.lines.map((l) => '• ${l.modul} - ${l.project}').join('\n');

                          return Card(
                            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            child: ListTile(
                              title: Text(DateFormat('EEEE, dd MMM yyyy').format(date), style: const TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Text('Total: ${log.totalHours} Hours\n\n$activitiesSummary'),
                              isThreeLine: true,
                              onTap: () {
                                showModalBottomSheet(
                                  context: context,
                                  isScrollControlled: true,
                                  builder: (_) => DailyLogSheet(log: log),
                                );
                              },
                              trailing: IconButton(
                                icon: const Icon(Icons.delete, color: Colors.red),
                                onPressed: () {
                                  provider.deleteDailyLog(log.id!);
                                },
                              ),
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
        onPressed: () {
          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            builder: (_) => const DailyLogSheet(),
          );
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}
