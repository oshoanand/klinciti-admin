import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exceptions.dart';
import '../../workers/data/worker_model.dart';
import '../data/audit_log_model.dart';
import '../data/job_model.dart';

typedef JsonMap = Map<String, dynamic>;
typedef StringList = List<String>;
typedef AssignableWorkerList = List<AssignableWorkerModel>;
typedef WorkerModelList = List<WorkerModel>;
typedef AuditLogList = List<AuditLogModel>;

// ==========================================
// ASSIGNABLE WORKER MODEL (With Category Metadata)
// ==========================================
class AssignableWorkerModel {
  final String id;
  final String name;
  final String? mobile;
  final String? avatarUrl;
  final String? city;
  final double rating;
  final bool hasVehicle;
  final StringList categoryIds;
  final StringList categoryNames;

  const AssignableWorkerModel({
    required this.id,
    required this.name,
    this.mobile,
    this.avatarUrl,
    this.city,
    this.rating = 5.0,
    this.hasVehicle = false,
    this.categoryIds = const [],
    this.categoryNames = const [],
  });

  factory AssignableWorkerModel.fromJson(JsonMap json) {
    final rawIds = json['categoryIds'] ?? json['category_ids'];
    final StringList parsedIds = rawIds is List
        ? rawIds
              .map((e) => e.toString().trim())
              .where((s) => s.isNotEmpty)
              .toList()
        : const [];

    final rawNames =
        json['categoryNames'] ?? json['category_names'] ?? json['categories'];
    final StringList parsedNames = rawNames is List
        ? rawNames
              .map(
                (e) => e is Map ? (e['name'] ?? '').toString() : e.toString(),
              )
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .toList()
        : const [];

    final fullName = [json['first_name'], json['last_name']]
        .where((e) => e != null && e.toString().trim().isNotEmpty)
        .join(' ')
        .trim();

    final rawName = json['name']?.toString().trim() ?? '';

    return AssignableWorkerModel(
      id: (json['id'] ?? json['user_id'] ?? '').toString(),
      name: rawName.isNotEmpty
          ? rawName
          : (fullName.isNotEmpty ? fullName : 'Исполнитель'),
      mobile: json['mobile']?.toString(),
      avatarUrl: (json['avatarUrl'] ?? json['avatar_url'] ?? json['image'])
          ?.toString(),
      city: json['city']?.toString(),
      rating: double.tryParse((json['rating'] ?? '5.0').toString()) ?? 5.0,
      hasVehicle: json['hasVehicle'] == true || json['has_vehicle'] == true,
      categoryIds: parsedIds,
      categoryNames: parsedNames,
    );
  }
}

// ==========================================
// 1. FETCH SPECIFIC JOB DETAILS
// ==========================================
final jobDetailProvider = FutureProvider.autoDispose.family<JobModel, String>((
  ref,
  jobId,
) async {
  try {
    final api = ref.watch(apiClientProvider);
    final response = await api.dio.get('/jobs/admin/$jobId');

    final raw = response.data;
    final JsonMap jobJson = (raw is Map && raw['data'] is Map)
        ? JsonMap.from(raw['data'] as Map)
        : JsonMap.from(raw as Map);

    return JobModel.fromJson(jobJson);
  } catch (e) {
    throw ApiException.fromDioException(e);
  }
});

// ==========================================
// 2. FETCH ALL AVAILABLE WORKERS (Unfiltered Fallback)
// ==========================================
final availableWorkersProvider = FutureProvider.autoDispose<WorkerModelList>((
  ref,
) async {
  try {
    final api = ref.watch(apiClientProvider);

    final response = await api.dio.get(
      '/workers/admin/list',
      queryParameters: {
        'authStatus': 'ACTIVE',
        'moderationStatus': 'APPROVED',
        'limit': 100,
      },
    );

    final raw = response.data;
    final List<dynamic> data = raw is List
        ? raw
        : (raw is Map && raw['data'] is List ? raw['data'] as List : const []);

    return data
        .map((json) => WorkerModel.fromJson(JsonMap.from(json as Map)))
        .toList();
  } catch (e) {
    throw ApiException.fromDioException(e);
  }
});

// ==========================================
// 3. FETCH WORKERS MATCHING JOB CATEGORY & SUBCATEGORIES
// ==========================================
final availableWorkersForJobProvider = FutureProvider.autoDispose
    .family<AssignableWorkerList, JobModel>((ref, job) async {
      try {
        final api = ref.watch(apiClientProvider);

        // Collect explicit category and subcategory IDs if present on the JobModel
        final Set<String> reqIds = <String>{
          if (job.categoryId != null && job.categoryId!.trim().isNotEmpty)
            job.categoryId!.trim(),
          if (job.subcategoryId != null && job.subcategoryId!.trim().isNotEmpty)
            job.subcategoryId!.trim(),
          ...job.subcategoryIds.map((e) => e.trim()).where((e) => e.isNotEmpty),
        };

        final response = await api.dio.get(
          '/workers/admin/active',
          queryParameters: {
            'jobId': job.id,
            if (reqIds.isNotEmpty) 'categoryIds': reqIds.join(','),
          },
        );

        final raw = response.data;
        final List<dynamic> list = raw is List
            ? raw
            : (raw is Map && raw['data'] is List
                  ? raw['data'] as List
                  : (raw is Map && raw['workers'] is List
                        ? raw['workers'] as List
                        : const []));

        final workers = list
            .map(
              (item) =>
                  AssignableWorkerModel.fromJson(JsonMap.from(item as Map)),
            )
            .toList();

        return _verifyWorkersMatchJob(workers, job, reqIds);
      } catch (e) {
        throw ApiException.fromDioException(e);
      }
    });

/// Verifies on the client side that each returned worker matches all required
/// category/subcategory IDs or names of the job.
AssignableWorkerList _verifyWorkersMatchJob(
  AssignableWorkerList workers,
  JobModel job,
  Set<String> requiredIds,
) {
  final Set<String> requiredNames = <String>{};
  if (job.categoryName != null && job.categoryName!.trim().isNotEmpty) {
    requiredNames.add(job.categoryName!.trim().toLowerCase());
  }
  if (job.subcategoryName != null && job.subcategoryName!.trim().isNotEmpty) {
    for (final part in job.subcategoryName!.split(',')) {
      final clean = part.trim().toLowerCase();
      if (clean.isNotEmpty) requiredNames.add(clean);
    }
  }

  return workers.where((w) {
    // 1. If worker has categoryIds and job has requiredIds, verify all IDs match
    if (requiredIds.isNotEmpty && w.categoryIds.isNotEmpty) {
      final workerIdSet = w.categoryIds.map((id) => id.trim()).toSet();
      return requiredIds.every(workerIdSet.contains);
    }

    // 2. Fallback: If categoryNames are populated, verify all required names match
    if (requiredNames.isNotEmpty && w.categoryNames.isNotEmpty) {
      final workerNameSet = w.categoryNames
          .map((n) => n.trim().toLowerCase())
          .toSet();
      return requiredNames.every(workerNameSet.contains);
    }

    // 3. Otherwise trust the backend SQL HAVING COUNT(DISTINCT category_id) filter
    return true;
  }).toList();
}

// ==========================================
// 4. FETCH JOB AUDIT LOGS
// ==========================================
final jobAuditLogsProvider = FutureProvider.autoDispose
    .family<AuditLogList, String>((ref, jobId) async {
      try {
        final api = ref.watch(apiClientProvider);
        final response = await api.dio.get('/jobs/admin/$jobId/audit-logs');

        final raw = response.data;
        final List<dynamic> data = raw is List
            ? raw
            : (raw is Map && raw['data'] is List
                  ? raw['data'] as List
                  : const []);

        return data
            .map((json) => AuditLogModel.fromJson(JsonMap.from(json as Map)))
            .toList();
      } catch (e) {
        throw ApiException.fromDioException(e);
      }
    });
