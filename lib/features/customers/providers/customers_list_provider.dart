import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exceptions.dart';
import '../data/customer_model.dart';

typedef JsonMap = Map<String, dynamic>;
typedef CustomerList = List<CustomerModel>;

final customersListProvider =
    AsyncNotifierProvider.autoDispose<CustomersListNotifier, CustomerList>(
      CustomersListNotifier.new,
    );

class CustomersListNotifier extends AutoDisposeAsyncNotifier<CustomerList> {
  int _page = 1;
  final int _limit = 20;
  bool _hasMore = true;
  bool _isFetchingMore = false;

  bool get hasMore => _hasMore;
  bool get isFetchingMore => _isFetchingMore;

  @override
  Future<CustomerList> build() async {
    _page = 1;
    _hasMore = true;
    _isFetchingMore = false;
    return _fetchPage(1);
  }

  Future<CustomerList> _fetchPage(int pageIndex) async {
    try {
      final api = ref.read(apiClientProvider);
      final response = await api.dio.get(
        '/customers/admin/list',
        queryParameters: {'page': pageIndex, 'limit': _limit},
      );

      final raw = response.data;
      final List<dynamic> data = (raw is Map && raw['data'] is List)
          ? raw['data'] as List<dynamic>
          : (raw is List ? raw : const []);

      final JsonMap meta = (raw is Map && raw['meta'] is Map)
          ? JsonMap.from(raw['meta'] as Map)
          : JsonMap();
      final int total = int.tryParse((meta['total'] ?? 0).toString()) ?? 0;

      final CustomerList list = data
          .whereType()
          .map((json) => CustomerModel.fromJson(JsonMap.from(json)))
          .toList();

      if (pageIndex * _limit >= total || list.length < _limit) {
        _hasMore = false;
      }

      return list;
    } catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<void> loadMore() async {
    final currentList = state.valueOrNull;
    if (_isFetchingMore || !_hasMore || state.hasError || currentList == null) {
      return;
    }

    _isFetchingMore = true;
    final int nextPage = _page + 1;

    try {
      final newItems = await _fetchPage(nextPage);
      _page = nextPage;
      state = AsyncData([...currentList, ...newItems]);
    } catch (_) {
      // Keep current `_page` so user can retry on next scroll
    } finally {
      _isFetchingMore = false;
    }
  }

  /// Instantly updates a customer's online status when a Socket event fires
  void updateCustomerStatus(String id, bool isOnline, DateTime? lastSeen) {
    final currentList = state.valueOrNull;
    if (currentList == null) return;

    final index = currentList.indexWhere((c) => c.id == id);
    if (index != -1) {
      final updatedCustomer = currentList[index].copyWith(
        isOnline: isOnline,
        lastSeen: lastSeen,
      );

      final newList = CustomerList.from(currentList);
      newList[index] = updatedCustomer;
      state = AsyncData(newList);
    }
  }
}
