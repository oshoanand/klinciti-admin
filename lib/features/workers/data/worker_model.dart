class WorkerModel {
  final String id;
  final String name;
  final String? mobile;
  final String authStatus; // 'PENDING', 'ACTIVE', 'BLOCKED', 'DELETED'
  final String
  moderationStatus; // 'INCOMPLETE', 'PENDING', 'APPROVED', 'REJECTED'

  // Profile specific fields
  final bool hasVehicle;
  final String? vehicleModel;
  final String? vehicleNumber; // Added to match UI usage
  final List<String> experience;
  final String? categoryName;

  // KYC & Documents
  final String? idDocumentFrontUrl;
  final String? idDocumentBackUrl; // ✅ ADDED
  final String? selfieWithIdUrl;
  final String? driversLicenseUrl; // ✅ ADDED

  final double rating;

  // Aggregated stats
  final int totalJobsCompleted;
  final double totalIncome;
  final String? rejectionReason;
  final String? avatarUrl;

  bool get isApproved =>
      moderationStatus == 'APPROVED' && authStatus == 'ACTIVE';

  WorkerModel({
    required this.id,
    required this.name,
    this.mobile,
    required this.authStatus,
    required this.moderationStatus,
    required this.hasVehicle,
    this.vehicleModel,
    this.vehicleNumber,
    this.experience = const [],
    this.categoryName,
    this.idDocumentFrontUrl,
    this.idDocumentBackUrl, // ✅ ADDED
    this.selfieWithIdUrl,
    this.driversLicenseUrl, // ✅ ADDED
    this.rating = 5.0,
    this.totalJobsCompleted = 0,
    this.totalIncome = 0.0,
    this.rejectionReason,
    this.avatarUrl,
  });

  factory WorkerModel.fromJson(Map<String, dynamic> json) {
    return WorkerModel(
      id: json['id']?.toString() ?? '',
      name: json['name'] ?? 'Без имени',
      mobile: json['mobile']?.toString(),
      authStatus: json['auth_status'] ?? 'PENDING',
      moderationStatus: json['moderation_status'] ?? 'INCOMPLETE',
      hasVehicle: json['has_vehicle'] == true || json['has_vehicle'] == 1,
      vehicleModel: json['vehicle_model']?.toString(),
      vehicleNumber: json['vehicle_number']?.toString(),
      experience: json['experience'] != null
          ? List<String>.from(json['experience'])
          : [],
      categoryName: json['category_name']?.toString(),

      // ✅ KYC Documents
      idDocumentFrontUrl: json['id_document_front_url']?.toString(),
      idDocumentBackUrl: json['id_document_back_url']?.toString(), // ✅ ADDED
      selfieWithIdUrl: json['selfie_with_id_url']?.toString(),
      driversLicenseUrl: json['drivers_license_url']?.toString(), // ✅ ADDED

      rating: json['rating'] != null
          ? double.tryParse(json['rating'].toString()) ?? 5.0
          : 5.0,

      // Safely parse aggregated stats
      totalJobsCompleted: json['totalJobsCompleted'] != null
          ? int.tryParse(json['totalJobsCompleted'].toString()) ?? 0
          : 0,

      totalIncome: json['totalIncome'] != null
          ? double.tryParse(json['totalIncome'].toString()) ?? 0.0
          : 0.0,

      rejectionReason: json['rejection_reason']?.toString(),
      avatarUrl: json['image']?.toString(),
    );
  }
}
