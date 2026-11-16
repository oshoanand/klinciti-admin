import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exceptions.dart';
import '../data/worker_model.dart';

typedef JsonMap = Map<String, dynamic>;
typedef StatsMap = Map<String, int>;
typedef WorkerModelList = List<WorkerModel>;

// ==========================================
// 1. WORKER STATS PROVIDER
// ==========================================
final workerStatsProvider = FutureProvider.autoDispose<StatsMap>((ref) async {
  final api = ref.watch(apiClientProvider);
  try {
    // Expected backend response: { "data": { "PENDING_MODERATION": 5, "ACTIVE": 12, "BLOCKED": 2, "REJECTED": 1 } }
    final response = await api.dio.get('/workers/admin/stats');
    final raw = response.data;
    final JsonMap data = (raw is Map && raw['data'] is Map)
        ? JsonMap.from(raw['data'] as Map)
        : (raw is Map ? JsonMap.from(raw) : JsonMap());

    return {
      'PENDING_MODERATION':
          int.tryParse((data['PENDING_MODERATION'] ?? 0).toString()) ?? 0,
      'ACTIVE': int.tryParse((data['ACTIVE'] ?? 0).toString()) ?? 0,
      'BLOCKED': int.tryParse((data['BLOCKED'] ?? 0).toString()) ?? 0,
      'REJECTED': int.tryParse((data['REJECTED'] ?? 0).toString()) ?? 0,
    };
  } catch (_) {
    return const {
      'PENDING_MODERATION': 0,
      'ACTIVE': 0,
      'BLOCKED': 0,
      'REJECTED': 0,
    };
  }
});

// ==========================================
// 2. PAGINATED WORKERS LIST PROVIDER
// ==========================================
class WorkerFilter {
  final String? authStatus;
  final String? moderationStatus;

  const WorkerFilter({this.authStatus, this.moderationStatus});

  JsonMap toQueryParameters({required int page, required int limit}) {
    return {
      'page': page,
      'limit': limit,
      if (authStatus != null && authStatus!.trim().isNotEmpty)
        'authStatus': authStatus!.trim(),
      if (moderationStatus != null && moderationStatus!.trim().isNotEmpty)
        'moderationStatus': moderationStatus!.trim(),
    };
  }

  // Prevents infinite Riverpod `.family` rebuild loops!
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WorkerFilter &&
          runtimeType == other.runtimeType &&
          authStatus == other.authStatus &&
          moderationStatus == other.moderationStatus;

  @override
  int get hashCode => Object.hash(authStatus, moderationStatus);
}

final workersListProvider = AsyncNotifierProvider.autoDispose
    .family<WorkersListNotifier, WorkerModelList, WorkerFilter>(
      WorkersListNotifier.new,
    );

class WorkersListNotifier
    extends AutoDisposeFamilyAsyncNotifier<WorkerModelList, WorkerFilter> {
  int _page = 1;
  final int _limit = 20;
  bool _hasMore = true;
  bool _isFetchingMore = false;

  bool get hasMore => _hasMore;
  bool get isFetchingMore => _isFetchingMore;

  @override
  Future<WorkerModelList> build(WorkerFilter arg) async {
    _page = 1;
    _hasMore = true;
    _isFetchingMore = false;
    return _fetchPage(1);
  }

  Future<WorkerModelList> _fetchPage(int pageIndex) async {
    try {
      final api = ref.read(apiClientProvider);
      final response = await api.dio.get(
        '/workers/admin/list',
        queryParameters: arg.toQueryParameters(page: pageIndex, limit: _limit),
      );

      final raw = response.data;
      final List<dynamic> data = (raw is Map && raw['data'] is List)
          ? raw['data'] as List<dynamic>
          : (raw is List ? raw : const []);

      final meta = (raw is Map && raw['meta'] is Map)
          ? JsonMap.from(raw['meta'] as Map)
          : JsonMap();
      final int total = int.tryParse((meta['total'] ?? 0).toString()) ?? 0;

      final workers = data
          .whereType()
          .map((json) => WorkerModel.fromJson(JsonMap.from(json)))
          .toList();

      if (pageIndex * _limit >= total || workers.length < _limit) {
        _hasMore = false;
      }

      return workers;
    } catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<void> loadMore() async {
    final currentList = state.valueOrNull;
    if (_isFetchingMore || !_hasMore || state.hasError || currentList == null) {
      return;
    }

    _isFetchingMore = true;
    final nextPage = _page + 1;

    try {
      final newWorkers = await _fetchPage(nextPage);
      _page = nextPage;
      state = AsyncData([...currentList, ...newWorkers]);
    } catch (_) {
      // Keep current `_page` so user can retry scrolling
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
      try {
        final api = ref.watch(apiClientProvider);
        final response = await api.dio.get('/workers/admin/$workerId');

        final raw = response.data;
        final JsonMap workerMap = (raw is Map && raw['data'] is Map)
            ? JsonMap.from(raw['data'] as Map)
            : JsonMap.from(raw as Map);

        return WorkerModel.fromJson(workerMap);
      } catch (e) {
        throw ApiException.fromDioException(e);
      }
    });
