class ProfileModel {
  final String id;
  final String? email;
  final String? mobile;
  final String? emailVerified;
  final String? mobileVerified;
  final String? image;
  final String? firstName;
  final String? lastName;
  final String? middleName;

  ProfileModel({
    required this.id,
    this.email,
    this.mobile,
    this.emailVerified,
    this.mobileVerified,
    this.image,
    this.firstName,
    this.lastName,
    this.middleName,
  });

  factory ProfileModel.fromJson(Map<String, dynamic> json) {
    return ProfileModel(
      id: json['id'],
      email: json['email'],
      mobile: json['mobile'],
      emailVerified: json['email_verified'],
      mobileVerified: json['mobile_verified'],
      image: json['image'],
      firstName: json['first_name'],
      lastName: json['last_name'],
      middleName: json['middle_name'],
    );
  }
}
