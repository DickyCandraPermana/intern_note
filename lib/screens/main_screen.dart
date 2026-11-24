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
  bool _recheckRequested = false;
  Future<void>? _latestRefreshFuture;

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
      final refresh = context.read<AppProvider>().refreshFromDisk();
      _latestRefreshFuture = refresh;
      _checkPendingRoute(refreshFuture: refresh);
    }
  }

  Future<void> _checkPendingRoute({Future<void>? refreshFuture}) async {
    if (!mounted) return;
    if (_isCheckingPendingRoute) {
      _recheckRequested = true;
      if (refreshFuture != null) {
        _latestRefreshFuture = refreshFuture;
      }
      return;
    }
    if (_isOpeningTodaySheet) return;

    _isCheckingPendingRoute = true;
    try {
      var activeRefresh = refreshFuture ?? _latestRefreshFuture;
      do {
        _recheckRequested = false;
        final provider = context.read<AppProvider>();
        final route = await provider.consumePendingRoute();
        if (!mounted) return;

        if (route == 'open_today') {
          if (activeRefresh != null) {
            await activeRefresh;
          } else {
            await provider.refreshFromDisk();
          }
          if (!mounted) return;

          _isOpeningTodaySheet = true;
          final today = DateTime.now();
          final existing = provider.getDailyLogForDate(today);
          try {
            await showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              builder: (_) => DailyLogSheet(
                initialDate: today,
                log: existing,
              ),
            );
          } finally {
            _isOpeningTodaySheet = false;
          }
          return;
        }
        activeRefresh = _latestRefreshFuture;
      } while (_recheckRequested && mounted);
    } finally {
      _isCheckingPendingRoute = false;
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
