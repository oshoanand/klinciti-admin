class JobModel {
  final String id;
  final String? customerId;
  final String? description;
  final num? budget;
  final String? city;
  final String? timing;
  final String? pickupAddress;
  final String status;

  // Customer Details
  final String? customerName;
  final String? customerMobile;
  final String? customerImage;

  // Worker Details
  final String? workerId;
  final String? workerName;
  final String? workerMobile;
  final String? workerImage;

  final String? categoryName;
  final String? subcategoryName;
  final DateTime createdAt;
  final List<String> photos;

  JobModel({
    required this.id,
    this.customerId,
    this.description,
    this.budget,
    this.city,
    this.timing,
    this.pickupAddress,
    required this.status,
    this.customerName,
    this.customerMobile,
    this.customerImage,
    this.workerId,
    this.workerName,
    this.workerMobile,
    this.workerImage,
    this.categoryName,
    this.subcategoryName,
    required this.createdAt,
    this.photos = const [],
  });

  factory JobModel.fromJson(Map<String, dynamic> json) {
    return JobModel(
      id: json['id']?.toString() ?? '',
      customerId: json['customer_id']?.toString(),
      description: json['description']?.toString(),
      // Safely parse budget whether backend sends an int, double, or String
      budget: json['budget'] != null
          ? num.tryParse(json['budget'].toString())
          : null,
      city: json['city']?.toString(),
      timing: json['timing']?.toString(),
      pickupAddress: json['pickup_address']?.toString(),
      status: json['status']?.toString() ?? 'PENDING',

      customerName: json['customer_name']?.toString(),
      customerMobile: json['customer_mobile']?.toString(),
      customerImage: json['customer_image']?.toString(),

      workerId: json['worker_id']?.toString(),
      workerName: json['worker_name']?.toString(),
      workerMobile: json['worker_mobile']?.toString(),
      workerImage: json['worker_image']?.toString(),

      categoryName: json['category_name']?.toString(),
      subcategoryName: json['subcategory_name']?.toString(),

      // Safe date parsing fallback
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),

      // Clean list extraction
      photos: json['photos'] != null ? List<String>.from(json['photos']) : [],
    );
  }
}
