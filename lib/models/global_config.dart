class GlobalConfig {
  int id; // Always 1
  String picConsultant;
  String role;
  String createdByName;
  String approvedByName;
  String approvedByLeadName;
  double defaultBaseHours;

  GlobalConfig({
    this.id = 1,
    required this.picConsultant,
    required this.role,
    required this.createdByName,
    required this.approvedByName,
    required this.approvedByLeadName,
    required this.defaultBaseHours,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'pic_consultant': picConsultant,
      'role': role,
      'created_by_name': createdByName,
      'approved_by_name': approvedByName,
      'approved_by_lead_name': approvedByLeadName,
      'default_base_hours': defaultBaseHours,
    };
  }

  factory GlobalConfig.fromMap(Map<String, dynamic> map) {
    return GlobalConfig(
      id: map['id'],
      picConsultant: map['pic_consultant'] ?? '',
      role: map['role'] ?? '',
      createdByName: map['created_by_name'] ?? '',
      approvedByName: map['approved_by_name'] ?? '',
      approvedByLeadName: map['approved_by_lead_name'] ?? '',
      defaultBaseHours: map['default_base_hours'] is int ? (map['default_base_hours'] as int).toDouble() : (map['default_base_hours'] ?? 8.0),
    );
  }
}
