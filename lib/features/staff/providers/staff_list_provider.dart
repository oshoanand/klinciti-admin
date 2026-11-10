import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../data/staff_model.dart';

// Family string represents the role filter ('ALL', 'ADMINISTRATOR', 'SUPPORT')
final staffListProvider = AsyncNotifierProvider.autoDispose
    .family<StaffListNotifier, List<StaffModel>, String>(() {
      return StaffListNotifier();
    });

class StaffListNotifier
    extends AutoDisposeFamilyAsyncNotifier<List<StaffModel>, String> {
  @override
  Future<List<StaffModel>> build(String arg) async {
    final api = ref.read(apiClientProvider);

    // Ensure this path matches exactly where you mounted the admin users router
    final response = await api.dio.get('/users/staff');

    final List data = response.data['data'] ?? [];

    final staffList = data
        .map((json) => StaffModel.fromJson(json as Map<String, dynamic>))
        .toList();

    // Apply role filtering locally
    if (arg != 'ALL') {
      return staffList.where((staff) => staff.role == arg).toList();
    }

    return staffList;
  }
}
