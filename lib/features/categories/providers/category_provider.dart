import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exceptions.dart';
import '../data/category_model.dart';

typedef JsonMap = Map<String, dynamic>;
typedef CategoryList = List<CategoryModel>;

final categoryProvider =
    AsyncNotifierProvider.autoDispose<CategoryNotifier, CategoryList>(
      CategoryNotifier.new,
    );

class CategoryNotifier extends AutoDisposeAsyncNotifier<CategoryList> {
  @override
  Future<CategoryList> build() async {
    return _fetchCategories();
  }

  Future<CategoryList> _fetchCategories() async {
    try {
      final api = ref.read(apiClientProvider);

      // Fetch from `/categories/admin/list` so hidden (`is_active: false`)
      // categories and usage counters are returned to the Admin App.
      final response = await api.dio.get('/categories/admin/list');

      final raw = response.data;
      final List<dynamic> data = raw is List
          ? raw
          : (raw is Map && raw['data'] is List
                ? raw['data'] as List<dynamic>
                : const []);

      return data
          .whereType()
          .map((json) => CategoryModel.fromJson(JsonMap.from(json)))
          .toList();
    } catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<void> createCategory({
    required String name,
    required String slug,
    String? parentId,
    String? icon,
    String? image,
    bool isActive = true,
  }) async {
    try {
      final api = ref.read(apiClientProvider);
      await api.dio.post(
        '/categories',
        data: {
          'name': name.trim(),
          'slug': slug.trim().toLowerCase(),
          if (parentId != null && parentId.trim().isNotEmpty)
            'parent_id': parentId.trim(),
          if (icon != null && icon.trim().isNotEmpty) 'icon': icon.trim(),
          if (image != null && image.trim().isNotEmpty) 'image': image.trim(),
          'is_active': isActive,
        },
      );
      ref.invalidateSelf();
      await future;
    } catch (e) {
      throw e is ApiException ? e : ApiException.fromDioException(e);
    }
  }

  Future<void> updateCategory(
    String id, {
    required String name,
    required String slug,
    String? parentId,
    String? icon,
    String? image,
    required bool isActive,
  }) async {
    try {
      final api = ref.read(apiClientProvider);
      await api.dio.patch(
        '/categories/$id',
        data: {
          'name': name.trim(),
          'slug': slug.trim().toLowerCase(),
          'parent_id': (parentId != null && parentId.trim().isNotEmpty)
              ? parentId.trim()
              : null,
          'icon': (icon != null && icon.trim().isNotEmpty) ? icon.trim() : null,
          'image': (image != null && image.trim().isNotEmpty)
              ? image.trim()
              : null,
          'is_active': isActive,
        },
      );
      ref.invalidateSelf();
      await future;
    } catch (e) {
      throw e is ApiException ? e : ApiException.fromDioException(e);
    }
  }

  /// Quick 1-tap toggle for hiding/showing a category or subcategory
  Future<void> toggleCategoryActive(String id, bool newActiveState) async {
    try {
      final api = ref.read(apiClientProvider);
      await api.dio.patch(
        '/categories/$id',
        data: {'is_active': newActiveState},
      );
      ref.invalidateSelf();
      await future;
    } catch (e) {
      throw e is ApiException ? e : ApiException.fromDioException(e);
    }
  }

  Future<void> deleteCategory(String id) async {
    try {
      final api = ref.read(apiClientProvider);
      await api.dio.delete('/categories/$id');
      ref.invalidateSelf();
      await future;
    } catch (e) {
      throw e is ApiException ? e : ApiException.fromDioException(e);
    }
  }
}
