import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exceptions.dart';
import '../data/category_model.dart';

final categoryProvider =
    AsyncNotifierProvider.autoDispose<CategoryNotifier, List<CategoryModel>>(
      () {
        return CategoryNotifier();
      },
    );

class CategoryNotifier extends AutoDisposeAsyncNotifier<List<CategoryModel>> {
  @override
  Future<List<CategoryModel>> build() async {
    return _fetchCategories();
  }

  Future<List<CategoryModel>> _fetchCategories() async {
    final api = ref.read(apiClientProvider);
    final response = await api.dio.get('/categories/list');

    final List data = response.data ?? [];
    return data
        .map((json) => CategoryModel.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  Future<void> createCategory({
    required String name,
    required String slug,
    String? parentId,
    bool isActive = true,
  }) async {
    final api = ref.read(apiClientProvider);
    await api.dio.post(
      '/categories',
      data: {
        'name': name,
        'slug': slug,
        if (parentId != null) 'parent_id': parentId,
        'is_active': isActive,
      },
    );
    ref.invalidateSelf();
  }

  Future<void> updateCategory(
    String id, {
    required String name,
    required String slug,
    String? parentId,
    required bool isActive,
  }) async {
    final api = ref.read(apiClientProvider);
    await api.dio.patch(
      '/categories/$id',
      data: {
        'name': name,
        'slug': slug,
        if (parentId != null) 'parent_id': parentId,
        'is_active': isActive,
      },
    );
    ref.invalidateSelf();
  }

  // ✅ New delete method returning a Future so the UI can catch errors
  Future<void> deleteCategory(String id) async {
    try {
      final api = ref.read(apiClientProvider);
      await api.dio.delete('/categories/$id');
      ref.invalidateSelf();
    } catch (e) {
      throw e is ApiException ? e : ApiException.fromDioException(e as dynamic);
    }
  }
}
