class ActivityLine {
  int? id;
  int? dailyLogId;
  String modul;
  String project;
  String description;

  ActivityLine({
    this.id,
    this.dailyLogId,
    required this.modul,
    required this.project,
    required this.description,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'daily_log_id': dailyLogId,
      'modul': modul,
      'project': project,
      'description': description,
    };
  }

  factory ActivityLine.fromMap(Map<String, dynamic> map) {
    return ActivityLine(
      id: map['id'],
      dailyLogId: map['daily_log_id'],
      modul: map['modul'],
      project: map['project'],
      description: map['description'],
    );
  }
}

class DailyLog {
  int? id;
  String date; // ISO8601 YYYY-MM-DD
  double baseHours;
  double overworkHours;
  List<ActivityLine> lines; // The activities

  DailyLog({
    this.id,
    required this.date,
    required this.baseHours,
    required this.overworkHours,
    this.lines = const [],
  });

  double get totalHours => baseHours + overworkHours;
  double get totalDays => totalHours / 8.0;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'date': date,
      'base_hours': baseHours,
      'overwork_hours': overworkHours,
    };
  }

  factory DailyLog.fromMap(Map<String, dynamic> map) {
    return DailyLog(
      id: map['id'],
      date: map['date'],
      baseHours: map['base_hours'] is int ? (map['base_hours'] as int).toDouble() : (map['base_hours'] ?? 8.0),
      overworkHours: map['overwork_hours'] is int ? (map['overwork_hours'] as int).toDouble() : (map['overwork_hours'] ?? 0.0),
      lines: [],
    );
  }
}
