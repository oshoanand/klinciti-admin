import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../data/job_model.dart';

// ==========================================
// PAGINATED JOBS BY STATUS PROVIDER
// ==========================================
final jobsByStatusProvider = AsyncNotifierProvider.autoDispose
    .family<JobsByStatusNotifier, List<JobModel>, String>(() {
      return JobsByStatusNotifier();
    });

class JobsByStatusNotifier
    extends AutoDisposeFamilyAsyncNotifier<List<JobModel>, String> {
  // Pagination State
  int _page = 1;
  final int _limit = 20;
  bool _hasMore = true;
  bool _isFetchingMore = false; // Guard to prevent duplicate network requests

  @override
  Future<List<JobModel>> build(String arg) async {
    // 'arg' contains the status (e.g., "PENDING") passed from the UI
    _page = 1;
    _hasMore = true;
    return _fetchPage(1);
  }

  Future<List<JobModel>> _fetchPage(int pageIndex) async {
    final api = ref.read(apiClientProvider);

    final response = await api.dio.get(
      '/jobs/by-status',
      queryParameters: {'status': arg, 'page': pageIndex, 'limit': _limit},
    );

    final List data = response.data['data'] ?? [];
    final meta = response.data['meta'] ?? {};

    final total = meta['total'] ?? 0;

    // Parse the JSON into our JobModel (which now safely handles the photos array)
    final jobs = data
        .map((json) => JobModel.fromJson(json as Map<String, dynamic>))
        .toList();

    // ✅ FIX: Corrected multiplication syntax to check if we fetched everything
    if (pageIndex * _limit >= total) {
      _hasMore = false;
    }

    return jobs;
  }

  Future<void> loadMore() async {
    if (_isFetchingMore || !_hasMore || state.hasError || state.value == null) {
      return;
    }

    _isFetchingMore = true;
    _page++;

    try {
      final newJobs = await _fetchPage(_page);
      state = AsyncData([...state.value!, ...newJobs]);
    } catch (error) {
      _page--; // Revert so user can try again
    } finally {
      _isFetchingMore = false;
    }
  }
}
