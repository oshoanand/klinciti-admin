import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../data/customer_model.dart';

final customersListProvider =
    AsyncNotifierProvider.autoDispose<
      CustomersListNotifier,
      List<CustomerModel>
    >(() {
      return CustomersListNotifier();
    });

class CustomersListNotifier
    extends AutoDisposeAsyncNotifier<List<CustomerModel>> {
  int _page = 1;
  final int _limit = 20;
  bool _hasMore = true;
  bool _isFetchingMore = false;

  @override
  Future<List<CustomerModel>> build() async {
    _page = 1;
    _hasMore = true;
    return _fetchPage(1);
  }

  Future<List<CustomerModel>> _fetchPage(int pageIndex) async {
    final api = ref.read(apiClientProvider);
    final response = await api.dio.get(
      '/customers/admin/list',
      queryParameters: {'page': pageIndex, 'limit': _limit},
    );

    final List data = response.data['data'] ?? [];
    final meta = response.data['meta'] ?? {};
    final total = meta['total'] ?? 0;

    final list = data
        .map((json) => CustomerModel.fromJson(json as Map<String, dynamic>))
        .toList();

    // ✅ FIX: Added multiplication operator
    if (pageIndex * _limit >= total) {
      _hasMore = false;
    }

    return list;
  }

  Future<void> loadMore() async {
    if (_isFetchingMore || !_hasMore || state.hasError || state.value == null)
      return;

    _isFetchingMore = true;
    _page++;

    try {
      final newItems = await _fetchPage(_page);
      state = AsyncData([...state.value!, ...newItems]);
    } catch (error, stackTrace) {
      _page--;
    } finally {
      _isFetchingMore = false;
    }
  }

  // ✅ NEW METHOD: Updates a single customer when the Socket event fires
  void updateCustomerStatus(String id, bool isOnline, DateTime? lastSeen) {
    if (state.value == null) return;

    final currentList = state.value!;
    final index = currentList.indexWhere((c) => c.id == id);

    if (index != -1) {
      final updatedCustomer = currentList[index].copyWith(
        isOnline: isOnline,
        lastSeen: lastSeen,
      );

      // Create a new list to trigger UI rebuild
      final newList = List<CustomerModel>.from(currentList);
      newList[index] = updatedCustomer;
      state = AsyncData(newList);
    }
  }
}
