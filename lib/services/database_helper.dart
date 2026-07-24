import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/daily_log.dart';
import '../models/global_config.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('intern_noter.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path, 
      version: 2, 
      onCreate: _createDB,
      onUpgrade: _onUpgrade,
    );
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
CREATE TABLE daily_logs (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  date TEXT NOT NULL UNIQUE,
  base_hours REAL NOT NULL,
  overwork_hours REAL NOT NULL
)
''');

    await db.execute('''
CREATE TABLE activity_lines (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  daily_log_id INTEGER NOT NULL,
  modul TEXT NOT NULL,
  project TEXT NOT NULL,
  description TEXT NOT NULL,
  FOREIGN KEY (daily_log_id) REFERENCES daily_logs(id) ON DELETE CASCADE
)
''');

    await db.execute('''
CREATE TABLE global_config (
  id INTEGER PRIMARY KEY,
  pic_consultant TEXT NOT NULL,
  role TEXT NOT NULL,
  created_by_name TEXT NOT NULL,
  approved_by_name TEXT NOT NULL,
  approved_by_lead_name TEXT NOT NULL,
  default_base_hours REAL NOT NULL
)
''');

    // Insert default config
    await db.insert('global_config', {
      'id': 1,
      'pic_consultant': '',
      'role': '',
      'created_by_name': '',
      'approved_by_name': '',
      'approved_by_lead_name': '',
      'default_base_hours': 8.0,
    });
  }

  Future _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Create new tables
      await db.execute('''
CREATE TABLE daily_logs (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  date TEXT NOT NULL UNIQUE,
  base_hours REAL NOT NULL,
  overwork_hours REAL NOT NULL
)
''');

      await db.execute('''
CREATE TABLE activity_lines (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  daily_log_id INTEGER NOT NULL,
  modul TEXT NOT NULL,
  project TEXT NOT NULL,
  description TEXT NOT NULL,
  FOREIGN KEY (daily_log_id) REFERENCES daily_logs(id) ON DELETE CASCADE
)
''');

      // Migrate existing data
      final oldActivities = await db.query('activities');
      Map<String, List<Map<String, dynamic>>> grouped = {};
      for (var a in oldActivities) {
        String dateStr = (a['date'] as String).substring(0, 10);
        if (!grouped.containsKey(dateStr)) {
          grouped[dateStr] = [];
        }
        grouped[dateStr]!.add(a);
      }

      for (var dateStr in grouped.keys) {
        final group = grouped[dateStr]!;
        double totalHours = 0;
        for (var a in group) {
          totalHours += (a['hours'] is int) ? (a['hours'] as int).toDouble() : (a['hours'] as double);
        }
        
        double base = totalHours > 8.0 ? 8.0 : totalHours;
        double over = totalHours > 8.0 ? totalHours - 8.0 : 0.0;
        
        int logId = await db.insert('daily_logs', {
          'date': dateStr,
          'base_hours': base,
          'overwork_hours': over,
        });

        for (var a in group) {
          await db.insert('activity_lines', {
            'daily_log_id': logId,
            'modul': a['modul'],
            'project': a['project'],
            'description': a['activity'],
          });
        }
      }

      // Add new columns to global_config
      await db.execute("ALTER TABLE global_config ADD COLUMN approved_by_lead_name TEXT DEFAULT ''");
      await db.execute("ALTER TABLE global_config ADD COLUMN default_base_hours REAL DEFAULT 8.0");
      
      // Rename old table so we don't lose data in case of issues
      await db.execute("ALTER TABLE activities RENAME TO old_activities");
    }
  }

  Future<DailyLog> createDailyLog(DailyLog log) async {
    final db = await instance.database;
    final logId = await db.insert('daily_logs', log.toMap());
    log.id = logId;
    
    for (var line in log.lines) {
      line.dailyLogId = logId;
      line.id = await db.insert('activity_lines', line.toMap());
    }
    return log;
  }

  Future<List<DailyLog>> readAllDailyLogs() async {
    final db = await instance.database;
    final logMaps = await db.query('daily_logs', orderBy: 'date DESC');
    
    List<DailyLog> logs = [];
    for (var map in logMaps) {
      final log = DailyLog.fromMap(map);
      
      final lineMaps = await db.query(
        'activity_lines',
        where: 'daily_log_id = ?',
        whereArgs: [log.id],
      );
      
      log.lines = lineMaps.map((m) => ActivityLine.fromMap(m)).toList();
      logs.add(log);
    }
    
    return logs;
  }

  Future<int> updateDailyLog(DailyLog log) async {
    final db = await instance.database;
    int count = await db.update(
      'daily_logs',
      log.toMap(),
      where: 'id = ?',
      whereArgs: [log.id],
    );

    // Simplest way to update lines: delete old ones and insert new ones
    await db.delete('activity_lines', where: 'daily_log_id = ?', whereArgs: [log.id]);
    for (var line in log.lines) {
      line.dailyLogId = log.id;
      line.id = await db.insert('activity_lines', line.toMap());
    }
    
    return count;
  }

  Future<int> deleteDailyLog(int id) async {
    final db = await instance.database;
    await db.delete('activity_lines', where: 'daily_log_id = ?', whereArgs: [id]);
    return await db.delete(
      'daily_logs',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<String>> getDistinctModules() async {
    final db = await instance.database;
    final result = await db.rawQuery('SELECT DISTINCT modul FROM activity_lines WHERE modul != "" ORDER BY modul ASC');
    return result.map((row) => row['modul'] as String).toList();
  }

  Future<List<String>> getDistinctProjects() async {
    final db = await instance.database;
    final result = await db.rawQuery('SELECT DISTINCT project FROM activity_lines WHERE project != "" ORDER BY project ASC');
    return result.map((row) => row['project'] as String).toList();
  }

  Future<GlobalConfig> readGlobalConfig() async {
    final db = await instance.database;
    final maps = await db.query('global_config', where: 'id = ?', whereArgs: [1]);
    if (maps.isNotEmpty) {
      return GlobalConfig.fromMap(maps.first);
    } else {
      return GlobalConfig(picConsultant: '', role: '', createdByName: '', approvedByName: '', approvedByLeadName: '', defaultBaseHours: 8.0);
    }
  }

  Future<int> updateGlobalConfig(GlobalConfig config) async {
    final db = await instance.database;
    return db.update(
      'global_config',
      config.toMap(),
      where: 'id = ?',
      whereArgs: [1],
    );
  }

  Future close() async {
    final db = await instance.database;
    db.close();
  }
}
