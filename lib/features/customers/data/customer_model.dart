typedef JsonMap = Map<String, dynamic>;

class CustomerModel {
  final String id;
  final String name;
  final String? email;
  final String? mobile;
  final String? image;
  final String authStatus;
  final DateTime createdAt;

  // Profile specific fields
  final String? city;
  final String? address;
  final String? description;
  final String? gender;
  final DateTime? dateOfBirth;

  // Real-time Presence fields
  final bool isOnline;
  final DateTime? lastSeen;

  bool get isActive => authStatus == 'ACTIVE';

  const CustomerModel({
    required this.id,
    required this.name,
    this.email,
    this.mobile,
    this.image,
    required this.authStatus,
    required this.createdAt,
    this.city,
    this.address,
    this.description,
    this.gender,
    this.dateOfBirth,
    this.isOnline = false,
    this.lastSeen,
  });

  CustomerModel copyWith({
    String? authStatus,
    bool? isOnline,
    DateTime? lastSeen,
  }) {
    return CustomerModel(
      id: id,
      name: name,
      email: email,
      mobile: mobile,
      image: image,
      authStatus: authStatus ?? this.authStatus,
      createdAt: createdAt,
      city: city,
      address: address,
      description: description,
      gender: gender,
      dateOfBirth: dateOfBirth,
      isOnline: isOnline ?? this.isOnline,
      lastSeen: lastSeen ?? this.lastSeen,
    );
  }

  factory CustomerModel.fromJson(JsonMap rawJson) {
    final JsonMap json = (rawJson['data'] is Map)
        ? JsonMap.from(rawJson['data'] as Map)
        : rawJson;

    String finalName = (json['name'] ?? '').toString().trim();
    if (finalName.isEmpty) {
      final fName = (json['first_name'] ?? json['firstName'] ?? '')
          .toString()
          .trim();
      final lName = (json['last_name'] ?? json['lastName'] ?? '')
          .toString()
          .trim();
      finalName = '$lName$fName'.trim();
    }
    if (finalName.isEmpty) {
      finalName = 'Без имени';
    }

    final rawCreatedAt = json['created_at'] ?? json['createdAt'];
    final rawDob = json['date_of_birth'] ?? json['dateOfBirth'];
    final rawLastSeen = json['lastSeen'] ?? json['last_seen'];

    return CustomerModel(
      id: (json['id'] ?? json['user_id'] ?? '').toString(),
      name: finalName,
      email: json['email']?.toString(),
      mobile: json['mobile']?.toString(),
      image: (json['image'] ?? json['avatar_url'] ?? json['avatarUrl'])
          ?.toString(),
      authStatus: (json['auth_status'] ?? json['authStatus'] ?? 'ACTIVE')
          .toString(),
      createdAt: rawCreatedAt != null
          ? DateTime.tryParse(rawCreatedAt.toString()) ?? DateTime.now()
          : DateTime.now(),
      city: json['city']?.toString(),
      address: json['address']?.toString(),
      description: json['description']?.toString(),
      gender: json['gender']?.toString(),
      dateOfBirth: rawDob != null ? DateTime.tryParse(rawDob.toString()) : null,
      isOnline: json['isOnline'] == true || json['is_online'] == true,
      lastSeen: rawLastSeen != null
          ? DateTime.tryParse(rawLastSeen.toString())
          : null,
    );
  }
}
