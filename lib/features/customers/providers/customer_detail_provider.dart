import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../data/customer_model.dart';

final customerDetailProvider = AsyncNotifierProvider.autoDispose
    .family<CustomerDetailNotifier, CustomerModel, String>(
      () => CustomerDetailNotifier(),
    );

class CustomerDetailNotifier
    extends AutoDisposeFamilyAsyncNotifier<CustomerModel, String> {
  @override
  Future<CustomerModel> build(String arg) async {
    final api = ref.watch(apiClientProvider);
    final response = await api.dio.get('/customers/admin/$arg');

    // The backend returns the object directly, not wrapped in a 'data' key
    return CustomerModel.fromJson(response.data as Map<String, dynamic>);
  }

  // Method to instantly update real-time presence from the Socket event
  // without triggering a new network request to the backend.
  void updatePresence(bool isOnline, DateTime? lastSeen) {
    if (state.value != null) {
      state = AsyncData(
        state.value!.copyWith(isOnline: isOnline, lastSeen: lastSeen),
      );
    }
  }
}
