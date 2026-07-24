import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';
import '../../providers/app_provider.dart';
import '../../widgets/daily_log_sheet.dart';
import '../../widgets/export_dialog.dart';

class CalendarTab extends StatefulWidget {
  const CalendarTab({super.key});

  @override
  State<CalendarTab> createState() => _CalendarTabState();
}

class _CalendarTabState extends State<CalendarTab> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;

  @override
  void initState() {
    super.initState();
    _selectedDay = _focusedDay;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Calendar'),
        actions: [
          IconButton(
            icon: const Icon(Icons.download),
            tooltip: 'Export Timesheet',
            onPressed: () {
              showDialog(
                context: context,
                builder: (_) => ExportDialog(targetMonth: _focusedDay),
              );
            },
          ),
        ],
      ),
      body: Consumer<AppProvider>(
        builder: (context, provider, child) {
          if (provider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          final log = provider.getDailyLogForDate(_selectedDay!);

          return Column(
            children: [
              TableCalendar(
                firstDay: DateTime.utc(2020, 1, 1),
                lastDay: DateTime.utc(2100, 12, 31),
                focusedDay: _focusedDay,
                selectedDayPredicate: (day) {
                  return isSameDay(_selectedDay, day);
                },
                onDaySelected: (selectedDay, focusedDay) {
                  setState(() {
                    _selectedDay = selectedDay;
                    _focusedDay = focusedDay;
                  });
                },
                eventLoader: (day) {
                  final dayLog = provider.getDailyLogForDate(day);
                  return dayLog != null ? [dayLog] : [];
                },
                calendarStyle: const CalendarStyle(
                  markerDecoration: BoxDecoration(color: Colors.blue, shape: BoxShape.circle),
                ),
              ),
              const SizedBox(height: 8.0),
              Expanded(
                child: log == null
                    ? const Center(child: Text('No activities for this day.'))
                    : ListView(
                        children: [
                          Card(
                            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                            child: ListTile(
                              title: Text('${log.totalHours} Hours Total', style: const TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Text(log.lines.map((l) => '• ${l.modul} - ${l.project}').join('\n')),
                              isThreeLine: log.lines.isNotEmpty,
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
                          )
                        ],
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
            builder: (_) => DailyLogSheet(initialDate: _selectedDay),
          );
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}
