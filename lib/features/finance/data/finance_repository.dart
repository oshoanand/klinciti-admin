import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exceptions.dart';
import './finance_models.dart';

typedef JsonMap = Map<String, dynamic>;

final adminFinanceRepositoryProvider = Provider<AdminFinanceRepository>((ref) {
  return AdminFinanceRepository(ref.watch(apiClientProvider));
});

class AdminFinanceRepository {
  final ApiClient _api;

  AdminFinanceRepository(this._api);

  Future<PlatformFinanceSettings> getSettings() async {
    try {
      final res = await _api.dio.get('/finance/settings');
      final map = _extractMap(res.data);
      final settingsMap = map['settings'] is Map
          ? Map<String, dynamic>.from(map['settings'] as Map)
          : map;
      return PlatformFinanceSettings.fromJson(settingsMap);
    } catch (e) {
      throw e is ApiException ? e : ApiException.fromDioException(e);
    }
  }

  Future<PlatformFinanceSettings> updateSettings(
    PlatformFinanceSettings settings,
  ) async {
    try {
      final res = await _api.dio.patch(
        '/finance/settings',
        data: settings.toUpdatePayload(),
      );
      final map = _extractMap(res.data);
      final settingsMap = map['settings'] is Map
          ? Map<String, dynamic>.from(map['settings'] as Map)
          : map;
      return PlatformFinanceSettings.fromJson(settingsMap);
    } catch (e) {
      throw e is ApiException ? e : ApiException.fromDioException(e);
    }
  }

  Future<JsonMap> runPayoutsBatchNow() async {
    try {
      final res = await _api.dio.post(
        '/finance/payouts/run-batch',
        data: const <String, dynamic>{},
      );
      return _extractMap(res.data);
    } catch (e) {
      throw e is ApiException ? e : ApiException.fromDioException(e);
    }
  }

  Future<PaginatedPaymentsResponse> getPayments({
    int page = 1,
    int limit = 20,
    String? status,
    String? search,
  }) async {
    try {
      final res = await _api.dio.get(
        '/finance/payments',
        queryParameters: {
          'page': page,
          'limit': limit,
          if (status != null && status.isNotEmpty && status != 'ALL')
            'status': status,
          if (search != null && search.trim().isNotEmpty)
            'search': search.trim(),
        },
      );

      final map = _extractMap(res.data);
      final rawList =
          (map['payments'] ?? map['items'] ?? map['data'] ?? const []) as List;

      final items = rawList
          .whereType()
          .map((e) => AdminPaymentRecord.fromJson(Map<String, dynamic>.from(e)))
          .toList();

      final summaryMap = map['summary'] is Map
          ? Map<String, dynamic>.from(map['summary'] as Map)
          : <String, dynamic>{};

      final pagination = map['pagination'] is Map
          ? Map<String, dynamic>.from(map['pagination'] as Map)
          : map;

      final total =
          int.tryParse((pagination['total'] ?? items.length).toString()) ??
          items.length;
      final totalPages =
          int.tryParse(
            (pagination['totalPages'] ??
                    pagination['total_pages'] ??
                    ((total / limit).ceil().clamp(1, 9999)))
                .toString(),
          ) ??
          1;

      return PaginatedPaymentsResponse(
        items: items,
        summary: FinanceSummary.fromJson(summaryMap),
        page: page,
        totalPages: totalPages,
        total: total,
      );
    } catch (e) {
      throw e is ApiException ? e : ApiException.fromDioException(e);
    }
  }

  Future<PaymentLedgerDetail> getPaymentLedger(String paymentId) async {
    try {
      final res = await _api.dio.get('/finance/payments/$paymentId/ledger');
      return PaymentLedgerDetail.fromJson(_extractMap(res.data));
    } catch (e) {
      throw e is ApiException ? e : ApiException.fromDioException(e);
    }
  }

  Future<void> issueRefund({
    required String paymentId,
    required double amount,
    required String reason,
  }) async {
    try {
      await _api.dio.post(
        '/finance/payments/$paymentId/refund',
        data: {'amount': amount, 'reason': reason.trim()},
      );
    } catch (e) {
      throw e is ApiException ? e : ApiException.fromDioException(e);
    }
  }

  Future<void> setPaymentPayoutBlock({
    required String paymentId,
    required bool blocked,
    String? reason,
  }) async {
    try {
      await _api.dio.patch(
        '/finance/payments/$paymentId/payout-block',
        data: {
          'blocked': blocked,
          if (reason != null && reason.trim().isNotEmpty)
            'reason': reason.trim(),
        },
      );
    } catch (e) {
      throw e is ApiException ? e : ApiException.fromDioException(e);
    }
  }

  Map<String, dynamic> _extractMap(dynamic raw) {
    if (raw is Map) {
      final map = Map<String, dynamic>.from(raw);
      if (map['data'] is Map) {
        return Map<String, dynamic>.from(map['data'] as Map);
      }
      return map;
    }
    return <String, dynamic>{};
  }

  /// GET /api/admin/finance/kudir-export?from=YYYY-MM-DD&to=YYYY-MM-DD
  Future<File> exportKudirCsv({DateTime? from, DateTime? to}) async {
    try {
      String formatIsoDate(DateTime dt) =>
          '${dt.year.toString().padLeft(4, '0')}-'
          '${dt.month.toString().padLeft(2, '0')}-'
          '${dt.day.toString().padLeft(2, '0')}';

      final res = await _api.dio.get<List<int>>(
        '/finance/kudir-export',
        queryParameters: {
          if (from != null) 'from': formatIsoDate(from),
          if (to != null) 'to': formatIsoDate(to),
        },
        options: Options(
          responseType: ResponseType.bytes,
          headers: const {'Accept': 'text/csv'},
        ),
      );

      final bytes = res.data;
      if (bytes == null || bytes.isEmpty) {
        throw ApiException('Сервер вернул пустой файл КУДиР');
      }

      final fromLabel = from != null ? formatIsoDate(from) : 'all';
      final toLabel = to != null
          ? formatIsoDate(to)
          : formatIsoDate(DateTime.now());
      final fileName = 'kudir_${fromLabel}_$toLabel.csv';

      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/$fileName');
      await file.writeAsBytes(bytes, flush: true);

      return file;
    } catch (e) {
      throw e is ApiException ? e : ApiException.fromDioException(e);
    }
  }
}
