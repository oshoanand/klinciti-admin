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

  // ✅ Real-time Presence fields
  final bool isOnline;
  final DateTime? lastSeen;

  bool get isActive => authStatus == 'ACTIVE';

  CustomerModel({
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

  // ✅ copyWith is required for real-time Riverpod state updates
  CustomerModel copyWith({bool? isOnline, DateTime? lastSeen}) {
    return CustomerModel(
      id: id,
      name: name,
      email: email,
      mobile: mobile,
      image: image,
      authStatus: authStatus,
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

  factory CustomerModel.fromJson(Map<String, dynamic> json) {
    String finalName = json['name'] ?? '';
    if (finalName.isEmpty) {
      final fName = json['first_name'] ?? '';
      final lName = json['last_name'] ?? '';
      finalName = '$lName $fName'.trim();
    }
    if (finalName.isEmpty) finalName = 'Без имени';

    return CustomerModel(
      id: json['id'],
      name: finalName,
      email: json['email'],
      mobile: json['mobile'],
      image: json['image'],
      authStatus: json['auth_status'] ?? 'ACTIVE',
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : DateTime.now(),
      city: json['city'],
      address: json['address'],
      description: json['description'],
      gender: json['gender'],
      dateOfBirth: json['date_of_birth'] != null
          ? DateTime.parse(json['date_of_birth'])
          : null,
      isOnline: json['isOnline'] ?? false,
      lastSeen: json['lastSeen'] != null
          ? DateTime.parse(json['lastSeen'])
          : null,
    );
  }
}
