class ActivityLine {
  int? id;
  int? dailyLogId;
  String modul;
  String project;
  String description;
  int sortOrder;

  ActivityLine({
    this.id,
    this.dailyLogId,
    required this.modul,
    required this.project,
    required this.description,
    this.sortOrder = 0,
  });

  bool get isUncategorized => modul.trim().isEmpty || project.trim().isEmpty;

  ActivityLine copyWith({
    int? id,
    int? dailyLogId,
    String? modul,
    String? project,
    String? description,
    int? sortOrder,
  }) {
    return ActivityLine(
      id: id ?? this.id,
      dailyLogId: dailyLogId ?? this.dailyLogId,
      modul: modul ?? this.modul,
      project: project ?? this.project,
      description: description ?? this.description,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'daily_log_id': dailyLogId,
      'modul': modul,
      'project': project,
      'description': description,
      'sort_order': sortOrder,
    };
  }

  factory ActivityLine.fromMap(Map<String, dynamic> map) {
    return ActivityLine(
      id: (map['id'] as num?)?.toInt(),
      dailyLogId: (map['daily_log_id'] as num?)?.toInt(),
      modul: (map['modul'] ?? '').toString(),
      project: (map['project'] ?? '').toString(),
      description: (map['description'] ?? '').toString(),
      sortOrder: (map['sort_order'] as num?)?.toInt() ?? 0,
    );
  }
}

class DailyLog {
  int? id;
  String date; // ISO8601 YYYY-MM-DD
  double baseHours;
  double overworkHours;
  List<ActivityLine> lines;

  DailyLog({
    this.id,
    required this.date,
    required this.baseHours,
    required this.overworkHours,
    this.lines = const [],
  });

  double get totalHours => baseHours + overworkHours;
  double get totalDays => totalHours / 8.0;
  bool get hasUncategorizedLines => lines.any((line) => line.isUncategorized);

  DailyLog copyWith({
    int? id,
    String? date,
    double? baseHours,
    double? overworkHours,
    List<ActivityLine>? lines,
  }) {
    return DailyLog(
      id: id ?? this.id,
      date: date ?? this.date,
      baseHours: baseHours ?? this.baseHours,
      overworkHours: overworkHours ?? this.overworkHours,
      lines: lines ?? this.lines,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'date': date,
      'base_hours': baseHours,
      'overwork_hours': overworkHours,
    };
  }

  factory DailyLog.fromMap(Map<String, dynamic> map) {
    final rawLines = map['lines'];
    final parsedLines = rawLines is List
        ? rawLines
            .whereType<Map>()
            .map((m) => ActivityLine.fromMap(Map<String, dynamic>.from(m)))
            .toList()
        : <ActivityLine>[];

    return DailyLog(
      id: (map['id'] as num?)?.toInt(),
      date: (map['date'] ?? '').toString(),
      baseHours: (map['base_hours'] as num?)?.toDouble() ?? 8.0,
      overworkHours: (map['overwork_hours'] as num?)?.toDouble() ?? 0.0,
      lines: parsedLines,
    );
  }
}
