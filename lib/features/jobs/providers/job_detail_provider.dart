import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../data/job_model.dart';
import '../data/audit_log_model.dart';
import '../../workers/data/worker_model.dart';

// ==========================================
// 1. FETCH SPECIFIC JOB
// ==========================================
final jobDetailProvider = FutureProvider.autoDispose.family<JobModel, String>((
  ref,
  jobId,
) async {
  final api = ref.watch(apiClientProvider);
  final response = await api.dio.get('/jobs/admin/$jobId');
  return JobModel.fromJson(response.data);
});

// ==========================================
// 2. FETCH AVAILABLE WORKERS (For Assignment Modal)
// ==========================================
final availableWorkersProvider = FutureProvider.autoDispose<List<WorkerModel>>((
  ref,
) async {
  final api = ref.watch(apiClientProvider);

  // Use the filtered paginated route we created in the backend
  final response = await api.dio.get(
    '/workers/admin/list',
    queryParameters: {
      'authStatus': 'ACTIVE',
      'moderationStatus': 'APPROVED',
      'limit': 100, // Fetch a large enough list for the assignment modal
    },
  );

  final List data = response.data['data'] ?? [];
  return data.map((json) => WorkerModel.fromJson(json)).toList();
});

// ==========================================
// 3. FETCH JOB AUDIT LOGS
// ==========================================
final jobAuditLogsProvider = FutureProvider.autoDispose
    .family<List<AuditLogModel>, String>((ref, jobId) async {
      final api = ref.watch(apiClientProvider);
      final response = await api.dio.get('/jobs/admin/$jobId/audit-logs');

      final List data = response.data['data'] ?? [];
      return data.map((json) => AuditLogModel.fromJson(json)).toList();
    });
