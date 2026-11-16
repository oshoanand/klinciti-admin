typedef JsonMap = Map<String, dynamic>;
typedef CategoryModelList = List<CategoryModel>;

class CategoryModel {
  final String id;
  final String name;
  final String slug;
  final String? icon;
  final String? image;
  final String? parentId;
  final bool isActive;
  final int workersCount;
  final int jobsCount;
  final CategoryModelList subcategories;

  const CategoryModel({
    required this.id,
    required this.name,
    required this.slug,
    this.icon,
    this.image,
    this.parentId,
    this.isActive = true,
    this.workersCount = 0,
    this.jobsCount = 0,
    this.subcategories = const [],
  });

  factory CategoryModel.fromJson(JsonMap json) {
    final rawSubs = json['subcategories'];
    final CategoryModelList parsedSubs = rawSubs is List
        ? rawSubs
              .whereType()
              .map((e) => CategoryModel.fromJson(JsonMap.from(e)))
              .toList()
        : const [];

    return CategoryModel(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      slug: (json['slug'] ?? '').toString(),
      icon: json['icon']?.toString(),
      image: json['image']?.toString(),
      parentId: (json['parent_id'] ?? json['parentId'])?.toString(),
      isActive: (json['is_active'] ?? json['isActive'] ?? true) == true,
      workersCount:
          int.tryParse(
            (json['workers_count'] ?? json['workersCount'] ?? 0).toString(),
          ) ??
          0,
      jobsCount:
          int.tryParse(
            (json['jobs_count'] ?? json['jobsCount'] ?? 0).toString(),
          ) ??
          0,
      subcategories: parsedSubs,
    );
  }
}
