import 'package:flutter/material.dart';

import '../models/daily_log.dart';
import '../models/global_config.dart';
import '../services/backup_service.dart';
import '../services/database_helper.dart';
import '../services/widget_sync_service.dart';
import '../utils/billing_cycle.dart';
import '../utils/date_formatters.dart';

enum TimelineFilter { all, currentCycle, needsTag }

class AppProvider with ChangeNotifier {
  final DatabaseHelper _db;
  final WidgetSyncService _widgetSync;

  List<DailyLog> _dailyLogs = [];
  GlobalConfig? _globalConfig;
  bool _isLoading;
  String? _errorMessage;
  List<String> _modules = [];
  List<String> _projects = [];
  String _searchQuery = '';
  TimelineFilter _timelineFilter = TimelineFilter.all;
  BillingCycle _activeCycle;
  bool _hasLoadedOnce = false;
  bool _disposed = false;
  Future<void>? _activeDbRefresh;

  AppProvider({
    DatabaseHelper? dbHelper,
    WidgetSyncService? widgetSync,
    bool autoLoad = true,
  })  : _db = dbHelper ?? DatabaseHelper.instance,
        _widgetSync = widgetSync ?? const WidgetSyncService(),
        _isLoading = autoLoad,
        _activeCycle = BillingCycleHelper.cycleFor(
          DateTime.now(),
          cutoffDay: 24,
        ) {
    if (autoLoad) {
      Future.microtask(_initData);
    }
  }

  List<DailyLog> get dailyLogs => _dailyLogs;

  List<DailyLog> get filteredDailyLogs {
    Iterable<DailyLog> items = _dailyLogs;

    switch (_timelineFilter) {
      case TimelineFilter.all:
        break;
      case TimelineFilter.currentCycle:
        final cutoff = _globalConfig?.cutoffDay ?? 24;
        final currentCycle = BillingCycleHelper.cycleFor(
          DateTime.now(),
          cutoffDay: cutoff,
        );
        items = items.where((log) {
          final parsed = DateTime.tryParse(normalizeIsoDate(log.date));
          return parsed != null && currentCycle.contains(parsed);
        });
        break;
      case TimelineFilter.needsTag:
        items = items.where((log) => log.hasUncategorizedLines);
        break;
    }

    final q = _searchQuery.trim().toLowerCase();
    if (q.isNotEmpty) {
      items = items.where((log) {
        return log.lines.any(
          (line) =>
              line.modul.toLowerCase().contains(q) ||
              line.project.toLowerCase().contains(q) ||
              line.description.toLowerCase().contains(q),
        );
      });
    }

    return items.toList();
  }

  GlobalConfig? get globalConfig => _globalConfig;
  GlobalConfig get effectiveConfig => _globalConfig ?? GlobalConfig.defaults();
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  List<String> get modules => _modules;
  List<String> get projects => _projects;
  String get searchQuery => _searchQuery;
  TimelineFilter get timelineFilter => _timelineFilter;
  BillingCycle get activeCycle => _activeCycle;
  ThemeMode get themeMode =>
      _globalConfig?.flutterThemeMode ?? ThemeMode.system;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _safeNotify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  Future<void> _initData() async {
    if (_disposed) return;
    final run = () async {
      if (_disposed) return;
      _errorMessage = null;
      try {
        await _loadFromDb(updateCycle: true);
      } catch (e) {
        _errorMessage = 'Gagal memuat data: $e';
      } finally {
        _isLoading = false;
        _safeNotify();
      }
    }();
    _activeDbRefresh = run;
    run.whenComplete(() {
      if (identical(_activeDbRefresh, run)) {
        _activeDbRefresh = null;
      }
    });
    await run;
  }

  Future<void> _loadFromDb({required bool updateCycle}) async {
    final logs = await _db.readAllDailyLogs();
    final config = await _db.readGlobalConfig();
    final distinctModules = await _db.getDistinctModules();
    final distinctProjects = await _db.getDistinctProjects();

    if (_disposed) return;

    final previousCutoff = _globalConfig?.cutoffDay;
    _dailyLogs = logs;
    _globalConfig = config;
    _modules = distinctModules;
    _projects = distinctProjects;

    if (updateCycle ||
        !_hasLoadedOnce ||
        (previousCutoff != null && previousCutoff != config.cutoffDay)) {
      _activeCycle = BillingCycleHelper.cycleFor(
        DateTime.now(),
        cutoffDay: config.cutoffDay,
      );
    }
    _hasLoadedOnce = true;
    _errorMessage = null;
  }

  Future<void> _reloadLogsAndSuggestions() async {
    final logs = await _db.readAllDailyLogs();
    final distinctModules = await _db.getDistinctModules();
    final distinctProjects = await _db.getDistinctProjects();
    if (_disposed) return;
    _dailyLogs = logs;
    _modules = distinctModules;
    _projects = distinctProjects;
    _errorMessage = null;
    _safeNotify();
  }

  Future<void> refreshFromDisk() {
    if (_disposed) return Future.value();
    final previous = _activeDbRefresh;
    final next = () async {
      if (previous != null) {
        try {
          await previous;
        } catch (_) {}
      }
      if (_disposed) return;
      try {
        await _loadFromDb(updateCycle: !_hasLoadedOnce);
      } catch (e) {
        _errorMessage = 'Gagal menyinkronkan data: $e';
      } finally {
        _isLoading = false;
        _safeNotify();
      }
    }();
    _activeDbRefresh = next;
    next.whenComplete(() {
      if (identical(_activeDbRefresh, next)) {
        _activeDbRefresh = null;
      }
    });
    return next;
  }

  Future<void> retryLoad() async {
    if (_disposed) return;
    _isLoading = true;
    _errorMessage = null;
    _safeNotify();
    await _initData();
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    _safeNotify();
  }

  void setTimelineFilter(TimelineFilter filter) {
    _timelineFilter = filter;
    _safeNotify();
  }

  void previousCycle() {
    _activeCycle = BillingCycleHelper.previousCycle(
      _activeCycle,
      cutoffDay: effectiveConfig.cutoffDay,
    );
    _safeNotify();
  }

  void nextCycle() {
    _activeCycle = BillingCycleHelper.nextCycle(
      _activeCycle,
      cutoffDay: effectiveConfig.cutoffDay,
    );
    _safeNotify();
  }

  void resetCycleToToday() {
    _activeCycle = BillingCycleHelper.cycleFor(
      DateTime.now(),
      cutoffDay: effectiveConfig.cutoffDay,
    );
    _safeNotify();
  }

  Future<void> fetchDailyLogs() async {
    _dailyLogs = await _db.readAllDailyLogs();
    _safeNotify();
  }

  Future<void> fetchSuggestions() async {
    _modules = await _db.getDistinctModules();
    _projects = await _db.getDistinctProjects();
    _safeNotify();
  }

  Future<void> fetchGlobalConfig() async {
    _globalConfig = await _db.readGlobalConfig();
    _safeNotify();
  }

  Future<void> addDailyLog(DailyLog log, {bool mergeIfExists = true}) async {
    await _db.upsertDailyLog(log, mergeIfExists: mergeIfExists);
    await _reloadLogsAndSuggestions();
    await _widgetSync.updateWidget();
  }

  Future<void> updateDailyLog(DailyLog log) async {
    await _db.updateDailyLog(log);
    await _reloadLogsAndSuggestions();
    await _widgetSync.updateWidget();
  }

  Future<DailyLog?> deleteDailyLog(int id) async {
    DailyLog? snapshot;
    for (final log in _dailyLogs) {
      if (log.id == id) {
        snapshot = log.copyWith(
          lines: log.lines.map((line) => line.copyWith()).toList(),
        );
        break;
      }
    }
    final deleted = await _db.deleteDailyLog(id);
    await _reloadLogsAndSuggestions();
    await _widgetSync.updateWidget();
    if (deleted == 0 && snapshot == null) {
      return null;
    }
    return snapshot;
  }

  Future<void> restoreDailyLog(DailyLog log) async {
    await _db.restoreDailyLog(log);
    await _reloadLogsAndSuggestions();
    await _widgetSync.updateWidget();
  }

  Future<DailyLog> quickAddTodayNote({
    required String description,
    String? modul,
    String? project,
  }) async {
    final cfg = _globalConfig ?? await _db.readGlobalConfig();
    final updated = await _db.appendQuickNote(
      isoDate: formatIsoDate(DateTime.now()),
      description: description,
      modul: (modul ?? cfg.defaultModul).trim(),
      project: (project ?? cfg.defaultProject).trim(),
      defaultBaseHours: cfg.defaultBaseHours,
    );
    _globalConfig ??= cfg;
    await _reloadLogsAndSuggestions();
    await _widgetSync.updateWidget();
    return updated;
  }

  Future<void> updateGlobalConfig(GlobalConfig config) async {
    final previousCutoff = _globalConfig?.cutoffDay;
    await _db.updateGlobalConfig(config);
    final loaded = await _db.readGlobalConfig();
    if (_disposed) return;
    _globalConfig = loaded;
    if (previousCutoff != loaded.cutoffDay) {
      _activeCycle = BillingCycleHelper.cycleFor(
        DateTime.now(),
        cutoffDay: loaded.cutoffDay,
      );
    }
    _safeNotify();
    await _widgetSync.updateWidget();
  }

  Future<BackupRestoreResult> restoreBackup(
    BackupPayload payload,
    RestoreMode mode,
  ) async {
    final result = await BackupService.applyRestore(_db, payload, mode);
    await _loadFromDb(updateCycle: true);
    _safeNotify();
    await _widgetSync.updateWidget();
    return result;
  }

  Future<String?> consumePendingRoute() {
    return _widgetSync.consumePendingRoute();
  }

  DailyLog? getDailyLogForDate(DateTime date) {
    final targetIso = formatIsoDate(date);
    for (final log in _dailyLogs) {
      if (normalizeIsoDate(log.date) == targetIso) {
        return log;
      }
    }
    return null;
  }

  List<DailyLog> logsInCycle(BillingCycle cycle) {
    return _dailyLogs.where((log) {
      final parsed = DateTime.tryParse(normalizeIsoDate(log.date));
      return parsed != null && cycle.contains(parsed);
    }).toList();
  }
}
