import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/daily_log_sheet.dart';
import 'tabs/calendar_tab.dart';
import 'tabs/dashboard_tab.dart';
import 'tabs/settings_tab.dart';
import 'tabs/timeline_tab.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with WidgetsBindingObserver {
  int _currentIndex = 0;
  DateTime? _calendarJumpDate;
  int _calendarJumpNonce = 0;
  bool _isCheckingPendingRoute = false;
  bool _isOpeningTodaySheet = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkPendingRoute();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      context.read<AppProvider>().refreshFromDisk();
      _checkPendingRoute();
    }
  }

  Future<void> _checkPendingRoute() async {
    if (!mounted || _isCheckingPendingRoute || _isOpeningTodaySheet) return;
    _isCheckingPendingRoute = true;
    try {
      final provider = context.read<AppProvider>();
      final route = await provider.consumePendingRoute();
      if (!mounted || route != 'open_today') return;

      if (provider.isLoading) {
        await provider.refreshFromDisk();
      }
      if (!mounted) return;

      _isOpeningTodaySheet = true;
      final today = DateTime.now();
      final existing = provider.getDailyLogForDate(today);
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => DailyLogSheet(
          initialDate: today,
          log: existing,
        ),
      );
    } finally {
      _isCheckingPendingRoute = false;
      _isOpeningTodaySheet = false;
    }
  }

  void _jumpToCalendar([DateTime? targetDate]) {
    setState(() {
      _currentIndex = 2;
      _calendarJumpDate = targetDate ?? DateTime.now();
      _calendarJumpNonce++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [
          DashboardTab(onJumpToCalendar: _jumpToCalendar),
          const TimelineTab(),
          CalendarTab(
            jumpToDate: _calendarJumpDate,
            jumpNonce: _calendarJumpNonce,
          ),
          const SettingsTab(),
        ],
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: colors.border, width: 1),
          ),
        ),
        child: NavigationBar(
          selectedIndex: _currentIndex,
          onDestinationSelected: (index) {
            setState(() {
              _currentIndex = index;
            });
          },
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.dashboard_outlined),
              selectedIcon: Icon(Icons.dashboard),
              label: 'Dashboard',
            ),
            NavigationDestination(
              icon: Icon(Icons.view_agenda_outlined),
              selectedIcon: Icon(Icons.view_agenda),
              label: 'Timeline',
            ),
            NavigationDestination(
              icon: Icon(Icons.calendar_month_outlined),
              selectedIcon: Icon(Icons.calendar_month),
              label: 'Kalender',
            ),
            NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings),
              label: 'Pengaturan',
            ),
          ],
        ),
      ),
    );
  }
}
