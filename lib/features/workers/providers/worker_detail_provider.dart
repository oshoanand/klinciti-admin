import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../data/worker_model.dart';

final workerDetailProvider = FutureProvider.autoDispose
    .family<WorkerModel, String>((ref, id) async {
      final api = ref.watch(apiClientProvider);
      final response = await api.dio.get('/admin/workers/$id');
      return WorkerModel.fromJson(
        response.data['data'] as Map<String, dynamic>,
      );
    });
