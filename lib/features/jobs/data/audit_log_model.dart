class AuditLogModel {
  final String id;
  final String eventType;
  final Map<String, dynamic> payload;
  final DateTime createdAt;

  AuditLogModel({
    required this.id,
    required this.eventType,
    required this.payload,
    required this.createdAt,
  });

  factory AuditLogModel.fromJson(Map<String, dynamic> json) {
    return AuditLogModel(
      id: json['id'],
      eventType: json['event_type'],
      payload: json['payload'] as Map<String, dynamic>? ?? {},
      createdAt: DateTime.parse(json['created_at']),
    );
  }
}
