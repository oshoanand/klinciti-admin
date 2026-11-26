typedef JsonMap = Map<String, dynamic>;

class WorkerCategoryItem {
  final String id;
  final String name;
  final String? slug;
  final String? icon;
  final String? image;
  final String? parentId;

  const WorkerCategoryItem({
    required this.id,
    required this.name,
    this.slug,
    this.icon,
    this.image,
    this.parentId,
  });

  factory WorkerCategoryItem.fromJson(JsonMap json) {
    return WorkerCategoryItem(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      slug: json['slug']?.toString(),
      icon: json['icon']?.toString(),
      image: json['image']?.toString(),
      parentId: (json['parent_id'] ?? json['parentId'])?.toString(),
    );
  }
}

class WorkerModel {
  final String id;
  final String name;
  final String? firstName;
  final String? middleName;
  final String? lastName;
  final String? email;
  final String? mobile;
  final String? avatarUrl;
  final String authStatus;
  final String moderationStatus;
  final String? rejectionReason;

  // Step 2: Legal & Professional Profile
  final String? legalType; // 'SELF_EMPLOYED', 'IP', 'OOO'
  final String? inn;
  final String? companyName;
  final String? city;
  final String? address;
  final String? experience;
  final String? description;
  final bool hasVehicle;
  final String? vehicleModel;
  final String? vehicleNumber;
  final List<WorkerCategoryItem> categories;

  // Step 3: KYC & Identity
  final DateTime? dateOfBirth;
  final String? gender;
  final String? passportNumber;
  final String? idDocumentFrontUrl;
  final String? idDocumentBackUrl;
  final String? selfieWithIdUrl;
  final String? driversLicenseUrl;

  // Step 4: Banking & Financial Details
  final String? bankName;
  final String? bankBik;
  final String? checkingAccount;
  final String? correspondentAccount;
  final String? taxId; // Legacy fallback
  final String? payoutDetails; // Legacy fallback

  // Stats & Timestamps
  final double rating;
  final int totalJobsCompleted;
  final double totalIncome;
  final DateTime? createdAt;

  const WorkerModel({
    required this.id,
    required this.name,
    this.firstName,
    this.middleName,
    this.lastName,
    this.email,
    this.mobile,
    this.avatarUrl,
    required this.authStatus,
    required this.moderationStatus,
    this.rejectionReason,
    this.legalType,
    this.inn,
    this.companyName,
    this.city,
    this.address,
    this.experience,
    this.description,
    this.hasVehicle = false,
    this.vehicleModel,
    this.vehicleNumber,
    this.categories = const [],
    this.dateOfBirth,
    this.gender,
    this.passportNumber,
    this.idDocumentFrontUrl,
    this.idDocumentBackUrl,
    this.selfieWithIdUrl,
    this.driversLicenseUrl,
    this.bankName,
    this.bankBik,
    this.checkingAccount,
    this.correspondentAccount,
    this.taxId,
    this.payoutDetails,
    this.rating = 5.0,
    this.totalJobsCompleted = 0,
    this.totalIncome = 0.0,
    this.createdAt,
  });

  /// Returns full Russian FIO (Фамилия Имя Отчество) if available, otherwise `name`
  String get fullName {
    final parts = [lastName, firstName, middleName]
        .where((p) => p != null && p.trim().isNotEmpty)
        .map((p) => p!.trim())
        .toList();
    if (parts.isNotEmpty) {
      return parts.join(' ');
    }
    return name;
  }

  factory WorkerModel.fromJson(JsonMap rawJson) {
    // Unwrap `{ data: { ... } }` if passed directly from response.data
    final JsonMap json = (rawJson['data'] is Map)
        ? JsonMap.from(rawJson['data'] as Map)
        : rawJson;

    // Parse experience whether String, num, or legacy List
    String? parsedExperience;
    final rawExp = json['experience'];
    if (rawExp is List) {
      parsedExperience = rawExp
          .map((e) => e.toString().trim())
          .where((s) => s.isNotEmpty)
          .join(', ');
    } else if (rawExp != null && rawExp.toString().trim().isNotEmpty) {
      parsedExperience = rawExp.toString().trim();
    }

    // Parse categories list
    final rawCats = json['categories'];
    final List<WorkerCategoryItem> parsedCategories = rawCats is List
        ? rawCats
              .whereType()
              .map((c) => WorkerCategoryItem.fromJson(JsonMap.from(c)))
              .toList()
        : const [];

    final firstName = (json['first_name'] ?? json['firstName'])
        ?.toString()
        .trim();
    final middleName = (json['middle_name'] ?? json['middleName'])
        ?.toString()
        .trim();
    final lastName = (json['last_name'] ?? json['lastName'])?.toString().trim();

    final fallbackName = [
      firstName,
      lastName,
    ].where((e) => e != null && e.isNotEmpty).join(' ').trim();

    final rawName = json['name']?.toString().trim() ?? '';

    return WorkerModel(
      id: (json['id'] ?? json['user_id'] ?? '').toString(),
      name: rawName.isNotEmpty
          ? rawName
          : (fallbackName.isNotEmpty ? fallbackName : 'No name'),
      firstName: firstName,
      middleName: middleName,
      lastName: lastName,
      email: json['email']?.toString(),
      mobile: json['mobile']?.toString(),
      avatarUrl: (json['image'] ?? json['avatarUrl'] ?? json['avatar_url'])
          ?.toString(),
      authStatus: (json['auth_status'] ?? json['authStatus'] ?? 'ACTIVE')
          .toString(),
      moderationStatus:
          (json['moderation_status'] ?? json['moderationStatus'] ?? 'PENDING')
              .toString(),
      rejectionReason: (json['rejection_reason'] ?? json['rejectionReason'])
          ?.toString(),

      // Legal & Professional Fields
      legalType: (json['legal_type'] ?? json['legalType'])?.toString(),
      inn: json['inn']?.toString(),
      companyName: (json['company_name'] ?? json['companyName'])?.toString(),
      city: json['city']?.toString(),
      address: json['address']?.toString(),
      experience: parsedExperience,
      description: json['description']?.toString(),
      hasVehicle: json['has_vehicle'] == true || json['hasVehicle'] == true,
      vehicleModel: (json['vehicle_model'] ?? json['vehicleModel'])?.toString(),
      vehicleNumber: (json['vehicle_number'] ?? json['vehicleNumber'])
          ?.toString(),
      categories: parsedCategories,

      // KYC & Identity
      dateOfBirth: (json['date_of_birth'] ?? json['dateOfBirth']) != null
          ? DateTime.tryParse(
              (json['date_of_birth'] ?? json['dateOfBirth']).toString(),
            )
          : null,
      gender: json['gender']?.toString(),
      passportNumber: (json['passport_number'] ?? json['passportNumber'])
          ?.toString(),
      idDocumentFrontUrl:
          (json['id_document_front_url'] ?? json['idDocumentFrontUrl'])
              ?.toString(),
      idDocumentBackUrl:
          (json['id_document_back_url'] ?? json['idDocumentBackUrl'])
              ?.toString(),
      selfieWithIdUrl: (json['selfie_with_id_url'] ?? json['selfieWithIdUrl'])
          ?.toString(),
      driversLicenseUrl:
          (json['drivers_license_url'] ?? json['driversLicenseUrl'])
              ?.toString(),

      // Banking & Financial
      bankName: (json['bank_name'] ?? json['bankName'])?.toString(),
      bankBik: (json['bank_bik'] ?? json['bankBik'])?.toString(),
      checkingAccount: (json['checking_account'] ?? json['checkingAccount'])
          ?.toString(),
      correspondentAccount:
          (json['correspondent_account'] ?? json['correspondentAccount'])
              ?.toString(),
      taxId: (json['tax_id'] ?? json['taxId'])?.toString(), // Legacy
      payoutDetails: (json['payout_details'] ?? json['payoutDetails'])
          ?.toString(), // Legacy
      // Stats
      rating: double.tryParse((json['rating'] ?? '5.0').toString()) ?? 5.0,
      totalJobsCompleted:
          int.tryParse(
            (json['totalJobsCompleted'] ?? json['total_jobs_completed'] ?? '0')
                .toString(),
          ) ??
          0,
      totalIncome:
          double.tryParse(
            (json['totalIncome'] ?? json['total_income'] ?? '0').toString(),
          ) ??
          0.0,
      createdAt: (json['created_at'] ?? json['createdAt']) != null
          ? DateTime.tryParse(
              (json['created_at'] ?? json['createdAt']).toString(),
            )
          : null,
    );
  }
}
