import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../data/worker_model.dart';

// ==========================================
// 1. WORKER STATS PROVIDER
// ==========================================
final workerStatsProvider = FutureProvider.autoDispose((ref) async {
  final api = ref.watch(apiClientProvider);
  try {
    // Expected backend response: { "data": { "PENDING_MODERATION": 5, "ACTIVE": 12, "BLOCKED": 2, "REJECTED": 1 } }
    final response = await api.dio.get('/workers/admin/stats');
    final Map<String, dynamic> data = response.data['data'] ?? {};
    return data.map((key, value) => MapEntry(key, (value as num).toInt()));
  } catch (e) {
    return {'PENDING_MODERATION': 0, 'ACTIVE': 0, 'BLOCKED': 0, 'REJECTED': 0};
  }
});

// ==========================================
// 2. PAGINATED WORKERS LIST PROVIDER
// ==========================================
class WorkerFilter {
  final String? authStatus;
  final String? moderationStatus;
  WorkerFilter({this.authStatus, this.moderationStatus});

  String get queryString {
    List<String> query = [];
    if (authStatus != null) query.add('authStatus=$authStatus');
    if (moderationStatus != null)
      query.add('moderationStatus=$moderationStatus');
    return query.join('&');
  }
}

final workersListProvider = AsyncNotifierProvider.autoDispose
    .family<WorkersListNotifier, List<WorkerModel>, WorkerFilter>(() {
      return WorkersListNotifier();
    });

class WorkersListNotifier
    extends AutoDisposeFamilyAsyncNotifier<List<WorkerModel>, WorkerFilter> {
  int _page = 1;
  final int _limit = 20;
  bool _hasMore = true;
  bool _isFetchingMore = false;

  @override
  Future<List<WorkerModel>> build(WorkerFilter arg) async {
    _page = 1;
    _hasMore = true;
    return _fetchPage(1);
  }

  Future<List<WorkerModel>> _fetchPage(int pageIndex) async {
    final api = ref.read(apiClientProvider);
    final response = await api.dio.get(
      '/workers/admin/list?page=$pageIndex&limit=$_limit&${arg.queryString}',
    );
    final List data = response.data['data'] ?? [];
    final total = response.data['meta']?['total'] ?? 0;

    final workers = data.map((json) => WorkerModel.fromJson(json)).toList();
    if (pageIndex * _limit >= total) _hasMore = false;
    return workers;
  }

  Future<void> loadMore() async {
    if (_isFetchingMore || !_hasMore || state.hasError || state.value == null)
      return;
    _isFetchingMore = true;
    _page++;
    try {
      final newWorkers = await _fetchPage(_page);
      state = AsyncData([...state.value!, ...newWorkers]);
    } catch (e) {
      _page--;
    } finally {
      _isFetchingMore = false;
    }
  }
}

// ==========================================
// 3. SINGLE WORKER DETAIL PROVIDER
// ==========================================
final workerDetailProvider = FutureProvider.autoDispose
    .family<WorkerModel, String>((ref, workerId) async {
      final api = ref.watch(apiClientProvider);
      final response = await api.dio.get('/workers/admin/$workerId');
      return WorkerModel.fromJson(response.data['data']);
    });
