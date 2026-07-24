import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/app_provider.dart';

class DashboardTab extends StatelessWidget {
  const DashboardTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Dashboard')),
      body: Consumer<AppProvider>(
        builder: (context, provider, child) {
          if (provider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          final now = DateTime.now();
          final currentMonthLogs = provider.dailyLogs.where((log) {
            final date = DateTime.parse(log.date);
            return date.year == now.year && date.month == now.month;
          }).toList();

          double totalHours = 0;
          double totalDays = 0;
          Map<String, double> projectHours = {};

          for (var log in currentMonthLogs) {
            totalHours += log.totalHours;
            totalDays += log.totalDays;
            
            if (log.lines.isNotEmpty) {
              double hrsPerLine = log.totalHours / log.lines.length;
              for (var line in log.lines) {
                projectHours[line.project] = (projectHours[line.project] ?? 0) + hrsPerLine;
              }
            }
          }

          final topProjects = projectHours.entries.toList()
            ..sort((a, b) => b.value.compareTo(a.value));

          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Card(
                  color: Colors.blue.shade100,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      children: [
                        const Text('This Month', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            Column(
                              children: [
                                Text(totalHours.toStringAsFixed(1), style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.blue)),
                                const Text('Hours'),
                              ],
                            ),
                            Column(
                              children: [
                                Text(totalDays.toStringAsFixed(1), style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.blue)),
                                const Text('Days'),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                const Text('Top Projects This Month', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Expanded(
                  child: topProjects.isEmpty
                      ? const Center(child: Text('No activities logged this month.'))
                      : ListView.builder(
                          itemCount: topProjects.length,
                          itemBuilder: (context, index) {
                            final p = topProjects[index];
                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: Colors.blue.shade50,
                                  child: const Icon(Icons.work, color: Colors.blue),
                                ),
                                title: Text(p.key, style: const TextStyle(fontWeight: FontWeight.w500)),
                                trailing: Text('${p.value.toStringAsFixed(1)} hrs', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                              ),
                            );
                          },
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
