import 'package:flutter/material.dart';
import '../models/daily_log.dart';
import '../models/global_config.dart';
import '../services/database_helper.dart';

class AppProvider with ChangeNotifier {
  List<DailyLog> _dailyLogs = [];
  GlobalConfig? _globalConfig;
  bool _isLoading = true;
  List<String> _modules = [];
  List<String> _projects = [];
  String _searchQuery = '';

  List<DailyLog> get dailyLogs => _dailyLogs;
  
  List<DailyLog> get filteredDailyLogs {
    if (_searchQuery.isEmpty) return _dailyLogs;
    return _dailyLogs.where((log) {
      final q = _searchQuery.toLowerCase();
      // Search in lines (modul or project)
      return log.lines.any((line) => 
        line.modul.toLowerCase().contains(q) || 
        line.project.toLowerCase().contains(q) ||
        line.description.toLowerCase().contains(q)
      );
    }).toList();
  }

  GlobalConfig? get globalConfig => _globalConfig;
  bool get isLoading => _isLoading;
  List<String> get modules => _modules;
  List<String> get projects => _projects;
  String get searchQuery => _searchQuery;

  AppProvider() {
    _initData();
  }

  Future<void> _initData() async {
    _isLoading = true;
    notifyListeners();
    
    await fetchDailyLogs();
    await fetchGlobalConfig();
    await fetchSuggestions();
    
    _isLoading = false;
    notifyListeners();
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  Future<void> fetchDailyLogs() async {
    _dailyLogs = await DatabaseHelper.instance.readAllDailyLogs();
    notifyListeners();
  }

  Future<void> fetchSuggestions() async {
    _modules = await DatabaseHelper.instance.getDistinctModules();
    _projects = await DatabaseHelper.instance.getDistinctProjects();
    notifyListeners();
  }

  Future<void> addDailyLog(DailyLog log) async {
    await DatabaseHelper.instance.createDailyLog(log);
    await fetchDailyLogs();
    await fetchSuggestions();
  }

  Future<void> updateDailyLog(DailyLog log) async {
    await DatabaseHelper.instance.updateDailyLog(log);
    await fetchDailyLogs();
    await fetchSuggestions();
  }

  Future<void> deleteDailyLog(int id) async {
    await DatabaseHelper.instance.deleteDailyLog(id);
    await fetchDailyLogs();
  }

  Future<void> fetchGlobalConfig() async {
    _globalConfig = await DatabaseHelper.instance.readGlobalConfig();
    notifyListeners();
  }

  Future<void> updateGlobalConfig(GlobalConfig config) async {
    await DatabaseHelper.instance.updateGlobalConfig(config);
    await fetchGlobalConfig();
  }

  DailyLog? getDailyLogForDate(DateTime date) {
    try {
      return _dailyLogs.firstWhere((log) {
        final logDate = DateTime.parse(log.date);
        return logDate.year == date.year &&
               logDate.month == date.month &&
               logDate.day == date.day;
      });
    } catch (_) {
      return null;
    }
  }
}
