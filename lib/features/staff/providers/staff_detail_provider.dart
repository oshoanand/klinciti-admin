import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../data/staff_model.dart';

final staffDetailProvider = FutureProvider.autoDispose
    .family<StaffModel, String>((ref, staffId) async {
      final api = ref.watch(apiClientProvider);

      final response = await api.dio.get('/users/staff/$staffId');

      return StaffModel.fromJson(response.data['data'] as Map<String, dynamic>);
    });
