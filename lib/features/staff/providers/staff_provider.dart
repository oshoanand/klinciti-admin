import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exceptions.dart';
import '../data/staff_model.dart';

typedef JsonMap = Map<String, dynamic>;
typedef StaffModelList = List<StaffModel>;

// Family string represents the role filter ('ALL', 'ADMINISTRATOR', 'SUPPORT')
final staffListProvider = AsyncNotifierProvider.autoDispose
    .family<StaffListNotifier, StaffModelList, String>(StaffListNotifier.new);

class StaffListNotifier
    extends AutoDisposeFamilyAsyncNotifier<StaffModelList, String> {
  @override
  Future<StaffModelList> build(String arg) async {
    try {
      final api = ref.read(apiClientProvider);
      final response = await api.dio.get('/users/staff');

      final raw = response.data;
      final List<dynamic> data = (raw is Map && raw['data'] is List)
          ? raw['data'] as List<dynamic>
          : (raw is List ? raw : const []);

      final StaffModelList staffList = data
          .whereType()
          .map((json) => StaffModel.fromJson(JsonMap.from(json)))
          .toList();

      if (arg != 'ALL' && arg.trim().isNotEmpty) {
        return staffList.where((staff) => staff.role == arg).toList();
      }

      return staffList;
    } catch (e) {
      throw ApiException.fromDioException(e);
    }
  }
}

final staffDetailProvider = FutureProvider.autoDispose
    .family<StaffModel, String>((ref, staffId) async {
      try {
        final api = ref.watch(apiClientProvider);
        final response = await api.dio.get('/users/staff/$staffId');

        final raw = response.data;
        final JsonMap staffMap = (raw is Map && raw['data'] is Map)
            ? JsonMap.from(raw['data'] as Map)
            : JsonMap.from(raw as Map);

        return StaffModel.fromJson(staffMap);
      } catch (e) {
        throw ApiException.fromDioException(e);
      }
    });
