typedef JsonMap = Map<String, dynamic>;
typedef StringList = List<String>;

enum SlaAlertLevel {
  normal, // Less than 15 minutes waiting
  warning, // 15 to 30 minutes waiting
  critical, // Over 30 minutes waiting without worker
}

class JobModel {
  final String id;
  final String? customerId;
  final String? description;
  final num? budget;
  final String? city;
  final String? timing;
  final String? pickupAddress;
  final String status;
  final String paymentStatus;

  // Customer Details
  final String? customerName;
  final String? customerMobile;
  final String? customerImage;

  // Worker Details
  final String? workerId;
  final String? workerName;
  final String? workerMobile;
  final String? workerImage;

  // Category & Subcategory Details
  final String? categoryId;
  final String? categoryName;
  final String? subcategoryId;
  final StringList subcategoryIds;
  final String? subcategoryName;

  // Timestamps & Photos (Before / After)
  final DateTime createdAt;
  final DateTime? completedAt;
  final DateTime? lastBroadcastAt;
  final StringList photos; // Customer "Before" photos
  final StringList completionPhotos; // Worker "After" completion photos

  JobModel({
    required this.id,
    this.customerId,
    this.description,
    this.budget,
    this.city,
    this.timing,
    this.pickupAddress,
    required this.status,
    this.paymentStatus = 'PENDING',
    this.customerName,
    this.customerMobile,
    this.customerImage,
    this.workerId,
    this.workerName,
    this.workerMobile,
    this.workerImage,
    this.categoryId,
    this.categoryName,
    this.subcategoryId,
    this.subcategoryIds = const [],
    this.subcategoryName,
    required this.createdAt,
    this.completedAt,
    this.lastBroadcastAt,
    this.photos = const [],
    this.completionPhotos = const [],
  });

  /// True if the job is still unassigned and waiting in PENDING status
  bool get isWaitingForWorker =>
      status == 'PENDING' && (workerId == null || workerId!.trim().isEmpty);

  /// Elapsed time since the customer created the order
  Duration get waitingDuration =>
      DateTime.now().difference(createdAt.toLocal());

  /// Industry-standard SLA thresholds for unassigned service jobs
  SlaAlertLevel get slaLevel {
    if (!isWaitingForWorker) return SlaAlertLevel.normal;
    final mins = waitingDuration.inMinutes;
    if (mins >= 30) return SlaAlertLevel.critical;
    if (mins >= 15) return SlaAlertLevel.warning;
    return SlaAlertLevel.normal;
  }

  bool get isSlaBreached =>
      slaLevel == SlaAlertLevel.warning || slaLevel == SlaAlertLevel.critical;

  factory JobModel.fromJson(JsonMap json) {
    final rawSubIds = json['subcategory_ids'] ?? json['subcategoryIds'];
    final StringList parsedSubIds = rawSubIds is List
        ? rawSubIds.map((e) => e.toString()).where((s) => s.isNotEmpty).toList()
        : const [];

    final rawPhotos = json['photos'] ?? json['jobs_photos'];
    final StringList parsedPhotos = rawPhotos is List
        ? rawPhotos
              .map((e) => e.toString().trim())
              .where((s) => s.isNotEmpty)
              .toList()
        : const [];

    final rawCompletionPhotos =
        json['completion_photos'] ?? json['completionPhotos'];
    final StringList parsedCompletionPhotos = rawCompletionPhotos is List
        ? rawCompletionPhotos
              .map((e) => e.toString().trim())
              .where((s) => s.isNotEmpty)
              .toList()
        : const [];

    final rawSubName = json['subcategory_name'] ?? json['subcategoryName'];
    String? normalizedSubName;
    if (rawSubName is List) {
      normalizedSubName = rawSubName.map((e) => e.toString()).join(', ');
    } else if (rawSubName != null) {
      normalizedSubName = rawSubName.toString();
    }

    return JobModel(
      id: json['id']?.toString() ?? '',
      customerId: (json['customer_id'] ?? json['customerId'])?.toString(),
      description: json['description']?.toString(),
      budget: json['budget'] != null
          ? num.tryParse(json['budget'].toString())
          : null,
      city: json['city']?.toString(),
      timing: json['timing']?.toString(),
      pickupAddress: (json['pickup_address'] ?? json['pickupAddress'])
          ?.toString(),
      status: json['status']?.toString() ?? 'PENDING',
      paymentStatus:
          (json['payment_status'] ?? json['paymentStatus'] ?? 'PENDING')
              .toString(),

      customerName: (json['customer_name'] ?? json['customerName'])?.toString(),
      customerMobile: (json['customer_mobile'] ?? json['customerMobile'])
          ?.toString(),
      customerImage: (json['customer_image'] ?? json['customerImage'])
          ?.toString(),

      workerId: (json['worker_id'] ?? json['workerId'])?.toString(),
      workerName: (json['worker_name'] ?? json['workerName'])?.toString(),
      workerMobile: (json['worker_mobile'] ?? json['workerMobile'])?.toString(),
      workerImage: (json['worker_image'] ?? json['workerImage'])?.toString(),

      categoryId: (json['category_id'] ?? json['categoryId'])?.toString(),
      categoryName: (json['category_name'] ?? json['categoryName'])?.toString(),
      subcategoryId: (json['subcategory_id'] ?? json['subcategoryId'])
          ?.toString(),
      subcategoryIds: parsedSubIds,
      subcategoryName: normalizedSubName,

      createdAt: (json['created_at'] ?? json['createdAt']) != null
          ? DateTime.tryParse(
                  (json['created_at'] ?? json['createdAt']).toString(),
                ) ??
                DateTime.now()
          : DateTime.now(),
      completedAt: (json['completed_at'] ?? json['completedAt']) != null
          ? DateTime.tryParse(
              (json['completed_at'] ?? json['completedAt']).toString(),
            )
          : null,
      lastBroadcastAt:
          (json['last_broadcast_at'] ?? json['lastBroadcastAt']) != null
          ? DateTime.tryParse(
              (json['last_broadcast_at'] ?? json['lastBroadcastAt']).toString(),
            )
          : null,

      photos: parsedPhotos,
      completionPhotos: parsedCompletionPhotos,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is JobModel && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
