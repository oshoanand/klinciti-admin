import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exceptions.dart';
import '../data/job_model.dart';

typedef JsonMap = Map<String, dynamic>;
typedef JobStatsMap = Map<String, int>;
typedef JobModelList = List<JobModel>;

// ==========================================
// 1. JOB STATS PROVIDER (Dashboard Counters)
// ==========================================
final jobStatsProvider = FutureProvider.autoDispose<JobStatsMap>((ref) async {
  final api = ref.watch(apiClientProvider);
  try {
    final response = await api.dio.get('/jobs/stats');
    final raw = response.data;
    final JsonMap data = (raw is Map && raw['data'] is Map)
        ? JsonMap.from(raw['data'] as Map)
        : (raw is Map ? JsonMap.from(raw) : JsonMap());

    int parseCount(String key) =>
        int.tryParse((data[key] ?? 0).toString()) ?? 0;

    return {
      'SLA_BREACHED': parseCount('SLA_BREACHED'),
      'PENDING': parseCount('PENDING'),
      'ACCEPTED': parseCount('ACCEPTED'),
      'ONGOING': parseCount('ONGOING'),
      'DISPUTED': parseCount('DISPUTED'),
      'COMPLETED': parseCount('COMPLETED'),
      'PAYMENT_PENDING': parseCount('PAYMENT_PENDING'),
      'PAID': parseCount('PAID'),
      'CANCELLED': parseCount('CANCELLED'),
      'REFUSED': parseCount('REFUSED'),
    };
  } catch (_) {
    return const {
      'SLA_BREACHED': 0,
      'PENDING': 0,
      'ACCEPTED': 0,
      'ONGOING': 0,
      'DISPUTED': 0,
      'COMPLETED': 0,
      'PAYMENT_PENDING': 0,
      'PAID': 0,
      'CANCELLED': 0,
      'REFUSED': 0,
    };
  }
});

// ==========================================
// 2. PAGINATED JOBS LIST PROVIDER (By Status or All)
// ==========================================
final jobsListProvider = AsyncNotifierProvider.autoDispose
    .family<JobsListNotifier, JobModelList, String?>(JobsListNotifier.new);

class JobsListNotifier
    extends AutoDisposeFamilyAsyncNotifier<JobModelList, String?> {
  int _page = 1;
  final int _limit = 20;
  bool _hasMore = true;
  bool _isFetchingMore = false;

  bool get hasMore => _hasMore;
  bool get isFetchingMore => _isFetchingMore;

  @override
  Future<JobModelList> build(String? arg) async {
    _page = 1;
    _hasMore = true;
    _isFetchingMore = false;
    return _fetchPage(1);
  }

  Future<JobModelList> _fetchPage(int pageIndex) async {
    try {
      final api = ref.read(apiClientProvider);
      final cleanStatus = arg?.trim();
      final hasStatus =
          cleanStatus != null &&
          cleanStatus.isNotEmpty &&
          cleanStatus.toUpperCase() != 'ALL';

      final String endpoint = hasStatus ? '/jobs/by-status' : '/jobs/all';
      final JsonMap queryParams = {
        'page': pageIndex.toString(),
        'limit': _limit.toString(),
        if (hasStatus) 'status': cleanStatus.toUpperCase(),
      };

      final response = await api.dio.get(
        endpoint,
        queryParameters: queryParams,
      );

      final raw = response.data;
      final List<dynamic> data = (raw is Map && raw['data'] is List)
          ? raw['data'] as List<dynamic>
          : (raw is List ? raw : const []);

      final meta = (raw is Map && raw['meta'] is Map)
          ? JsonMap.from(raw['meta'] as Map)
          : JsonMap();
      final int total = int.tryParse((meta['total'] ?? 0).toString()) ?? 0;

      final jobs = data
          .whereType()
          .map((json) => JobModel.fromJson(JsonMap.from(json)))
          .toList();

      if (pageIndex * _limit >= total || jobs.length < _limit) {
        _hasMore = false;
      }

      return jobs;
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
      final newJobs = await _fetchPage(nextPage);
      _page = nextPage;
      state = AsyncData([...currentList, ...newJobs]);
    } catch (_) {
      // Keep current `_page` so scrolling again can retry
    } finally {
      _isFetchingMore = false;
    }
  }
}
