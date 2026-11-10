class StaffModel {
  final String id;
  final String name; // Computed from first, last, middle
  final String? email;
  final String? mobile;
  final String role; // 'ADMINISTRATOR', 'SUPPORT', 'WORKER'
  final String authStatus; // 'ACTIVE', 'SUSPENDED', 'DELETED'
  final DateTime createdAt;
  final String? accessLevel;

  bool get isActive => authStatus == 'ACTIVE';

  StaffModel({
    required this.id,
    required this.name,
    this.email,
    this.mobile,
    required this.role,
    required this.authStatus,
    required this.createdAt,
    this.accessLevel,
  });

  factory StaffModel.fromJson(Map<String, dynamic> json) {
    final fName = json['first_name'] ?? '';
    final lName = json['last_name'] ?? '';
    final mName = json['middle_name'] ?? '';
    final computedName = '$lName $fName $mName'.trim();

    return StaffModel(
      id: json['id'],
      name: computedName.isNotEmpty
          ? computedName
          : (json['name'] ?? 'Без имени'),
      email: json['email'],
      mobile: json['mobile'],
      role: json['role'] ?? 'SUPPORT',
      authStatus: json['auth_status'] ?? 'ACTIVE',
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : DateTime.now(),
      accessLevel: json['access_level'],
    );
  }
}
