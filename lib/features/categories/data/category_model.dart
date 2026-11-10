class CategoryModel {
  final String id;
  final String name;
  final String slug;
  final String? icon;
  final String? parentId;
  final bool isActive;
  final List<CategoryModel> subcategories;

  CategoryModel({
    required this.id,
    required this.name,
    required this.slug,
    this.icon,
    this.parentId,
    required this.isActive,
    this.subcategories = const [],
  });

  factory CategoryModel.fromJson(Map<String, dynamic> json) {
    return CategoryModel(
      id: json['id'],
      name: json['name'],
      slug: json['slug'],
      icon: json['icon'],
      parentId: json['parent_id'],
      isActive: json['is_active'] ?? true,
      subcategories: json['subcategories'] != null
          ? (json['subcategories'] as List)
                .map((e) => CategoryModel.fromJson(e as Map<String, dynamic>))
                .toList()
          : [],
    );
  }
}
