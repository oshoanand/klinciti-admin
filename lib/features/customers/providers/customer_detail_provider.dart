import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exceptions.dart';
import '../data/customer_model.dart';

typedef JsonMap = Map<String, dynamic>;

final customerDetailProvider = AsyncNotifierProvider.autoDispose
    .family<CustomerDetailNotifier, CustomerModel, String>(
      CustomerDetailNotifier.new,
    );

class CustomerDetailNotifier
    extends AutoDisposeFamilyAsyncNotifier<CustomerModel, String> {
  @override
  Future<CustomerModel> build(String arg) async {
    try {
      final api = ref.watch(apiClientProvider);
      final response = await api.dio.get('/customers/admin/$arg');

      final raw = response.data;
      final JsonMap customerJson = (raw is Map && raw['data'] is Map)
          ? JsonMap.from(raw['data'] as Map)
          : JsonMap.from(raw as Map);

      return CustomerModel.fromJson(customerJson);
    } catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// Updates real-time presence from Socket.io without a network call
  void updatePresence(bool isOnline, DateTime? lastSeen) {
    final current = state.valueOrNull;
    if (current != null) {
      state = AsyncData(
        current.copyWith(isOnline: isOnline, lastSeen: lastSeen),
      );
    }
  }
}
