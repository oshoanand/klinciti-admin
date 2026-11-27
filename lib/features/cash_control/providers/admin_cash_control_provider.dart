import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exceptions.dart';
import '../models/cash_control_models.dart';

enum CashMonitorFilter { debtors, overLimit, blocked, suspended, all }

extension CashMonitorFilterX on CashMonitorFilter {
  String get apiValue {
    switch (this) {
      case CashMonitorFilter.debtors:
        return 'DEBTORS';
      case CashMonitorFilter.overLimit:
        return 'OVER_LIMIT';
      case CashMonitorFilter.blocked:
        return 'BLOCKED';
      case CashMonitorFilter.suspended:
        return 'SUSPENDED';
      case CashMonitorFilter.all:
        return 'ALL';
    }
  }

  String get label {
    switch (this) {
      case CashMonitorFilter.debtors:
        return 'Должники';
      case CashMonitorFilter.overLimit:
        return 'Выше лимита';
      case CashMonitorFilter.blocked:
        return 'Без наличных';
      case CashMonitorFilter.suspended:
        return 'Заблокированы';
      case CashMonitorFilter.all:
        return 'Все';
    }
  }
}

// ============================================================================
// 1. CASH MONITOR PROVIDER
// ============================================================================

class CashMonitorState {
  final bool isLoading;
  final String? error;
  final CashMonitorFilter filter;
  final String search;
  final CashSummary summary;
  final PlatformCashSettings? settings;
  final List<WorkerCashItem> debtors;
  final List<OpenCashDispute> openDisputes;

  const CashMonitorState({
    this.isLoading = false,
    this.error,
    this.filter = CashMonitorFilter.debtors,
    this.search = '',
    this.summary = const CashSummary(),
    this.settings,
    this.debtors = const [],
    this.openDisputes = const [],
  });

  CashMonitorState copyWith({
    bool? isLoading,
    String? error,
    bool clearError = false,
    CashMonitorFilter? filter,
    String? search,
    CashSummary? summary,
    PlatformCashSettings? settings,
    List<WorkerCashItem>? debtors,
    List<OpenCashDispute>? openDisputes,
  }) {
    return CashMonitorState(
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
      filter: filter ?? this.filter,
      search: search ?? this.search,
      summary: summary ?? this.summary,
      settings: settings ?? this.settings,
      debtors: debtors ?? this.debtors,
      openDisputes: openDisputes ?? this.openDisputes,
    );
  }
}

final adminCashMonitorProvider =
    StateNotifierProvider.autoDispose<
      AdminCashMonitorNotifier,
      CashMonitorState
    >((ref) => AdminCashMonitorNotifier(ref.watch(apiClientProvider)));

class AdminCashMonitorNotifier extends StateNotifier<CashMonitorState> {
  final ApiClient _api;

  AdminCashMonitorNotifier(this._api) : super(const CashMonitorState()) {
    loadOverview();
  }

  Future<void> loadOverview({CashMonitorFilter? filter, String? search}) async {
    final nextFilter = filter ?? state.filter;
    final nextSearch = search ?? state.search;

    state = state.copyWith(
      isLoading: true,
      filter: nextFilter,
      search: nextSearch,
      clearError: true,
    );

    try {
      final res = await _api.dio.get(
        '/admin/cash/overview',
        queryParameters: {
          'filter': nextFilter.apiValue,
          if (nextSearch.trim().isNotEmpty) 'search': nextSearch.trim(),
          'page': 1,
          'limit': 50,
        },
      );

      final data = Map<String, dynamic>.from(res.data as Map);
      state = state.copyWith(
        isLoading: false,
        summary: CashSummary.fromJson(
          Map<String, dynamic>.from(data['summary'] as Map? ?? {}),
        ),
        settings: data['settings'] is Map
            ? PlatformCashSettings.fromJson(
                Map<String, dynamic>.from(data['settings'] as Map),
              )
            : state.settings,
        debtors: (data['debtors'] as List? ?? [])
            .map(
              (e) =>
                  WorkerCashItem.fromJson(Map<String, dynamic>.from(e as Map)),
            )
            .toList(),
        openDisputes: (data['openDisputes'] as List? ?? [])
            .map(
              (e) =>
                  OpenCashDispute.fromJson(Map<String, dynamic>.from(e as Map)),
            )
            .toList(),
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: ApiException.fromDioException(e).message,
      );
    }
  }

  Future<String> settleDebt({
    required String workerId,
    required double amountRub,
    required String reference,
    required String paymentChannel,
    String? note,
  }) async {
    final res = await _api.dio.post(
      '/admin/workers/$workerId/settle-debt',
      data: {
        'amountRub': amountRub,
        'reference': reference.trim(),
        'paymentChannel': paymentChannel,
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      },
    );
    await loadOverview();
    return (res.data['message'] ?? 'Баланс исполнителя обновлен').toString();
  }

  Future<String> adjustWallet({
    required String workerId,
    required double amountRub,
    required String reference,
    required String note,
    String entryType = 'MANUAL_ADJUSTMENT',
  }) async {
    final res = await _api.dio.post(
      '/admin/workers/$workerId/adjust',
      data: {
        'amountRub': amountRub,
        'reference': reference.trim(),
        'note': note.trim(),
        'entryType': entryType,
      },
    );
    await loadOverview();
    return (res.data['message'] ?? 'Корректировка выполнена').toString();
  }

  Future<String> updateCashPolicy({
    required String workerId,
    double? debtLimitRub,
    bool? manualCashBan,
    bool? resetOverdueClock,
    String? reason,
  }) async {
    final res = await _api.dio.patch(
      '/admin/workers/$workerId/cash-policy',
      data: {
        if (debtLimitRub != null) 'debtLimitRub': debtLimitRub,
        if (manualCashBan != null) 'manualCashBan': manualCashBan,
        if (resetOverdueClock == true) 'resetOverdueClock': true,
        if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
      },
    );
    await loadOverview();
    return (res.data['message'] ?? 'Политика наличных обновлена').toString();
  }

  Future<String> remindWorker(String workerId, {String? customMessage}) async {
    final res = await _api.dio.post(
      '/admin/workers/$workerId/remind-due',
      data: {
        if (customMessage != null && customMessage.trim().isNotEmpty)
          'customMessage': customMessage.trim(),
      },
    );
    return (res.data['message'] ?? 'Напоминание отправлено').toString();
  }

  Future<String> remindAllOverdue() async {
    final res = await _api.dio.post('/admin/cash/remind-overdue');
    return (res.data['message'] ?? 'Напоминания отправлены').toString();
  }

  Future<String> unsuspendWorker({
    required String workerId,
    required bool grantGracePeriod,
    String? note,
  }) async {
    final res = await _api.dio.post(
      '/admin/workers/$workerId/unsuspend',
      data: {
        'grantGracePeriod': grantGracePeriod,
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      },
    );
    await loadOverview();
    return (res.data['message'] ?? 'Аккаунт разблокирован').toString();
  }

  Future<String> resolveCashDispute({
    required String jobId,
    required String resolution,
    required String note,
  }) async {
    final res = await _api.dio.post(
      '/admin/jobs/$jobId/resolve-cash-dispute',
      data: {'resolution': resolution, 'note': note.trim()},
    );
    await loadOverview();
    return (res.data['message'] ?? 'Спор закрыт').toString();
  }
}

// ============================================================================
// 2. WORKER LEDGER PROVIDER
// ============================================================================

final workerLedgerProvider = FutureProvider.autoDispose
    .family<List<WorkerLedgerEntry>, String>((ref, workerId) async {
      final api = ref.watch(apiClientProvider);
      final res = await api.dio.get(
        '/admin/workers/$workerId/ledger',
        queryParameters: {'limit': 50, 'offset': 0},
      );
      final data = Map<String, dynamic>.from(res.data as Map);
      return (data['entries'] as List? ?? [])
          .map(
            (e) =>
                WorkerLedgerEntry.fromJson(Map<String, dynamic>.from(e as Map)),
          )
          .toList();
    });

// ============================================================================
// 3. ADMIN CASH SETTINGS PROVIDER
// ============================================================================

class AdminCashSettingsState {
  final bool isLoading;
  final bool isSaving;
  final String? error;
  final PlatformCashSettings settings;
  final String? updatedByName;
  final DateTime? updatedAt;

  const AdminCashSettingsState({
    this.isLoading = false,
    this.isSaving = false,
    this.error,
    this.settings = const PlatformCashSettings(),
    this.updatedByName,
    this.updatedAt,
  });

  AdminCashSettingsState copyWith({
    bool? isLoading,
    bool? isSaving,
    String? error,
    bool clearError = false,
    PlatformCashSettings? settings,
    String? updatedByName,
    DateTime? updatedAt,
  }) {
    return AdminCashSettingsState(
      isLoading: isLoading ?? this.isLoading,
      isSaving: isSaving ?? this.isSaving,
      error: clearError ? null : (error ?? this.error),
      settings: settings ?? this.settings,
      updatedByName: updatedByName ?? this.updatedByName,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

final adminCashSettingsProvider =
    StateNotifierProvider.autoDispose<
      AdminCashSettingsNotifier,
      AdminCashSettingsState
    >((ref) => AdminCashSettingsNotifier(ref.watch(apiClientProvider)));

class AdminCashSettingsNotifier extends StateNotifier<AdminCashSettingsState> {
  final ApiClient _api;

  AdminCashSettingsNotifier(this._api) : super(const AdminCashSettingsState()) {
    loadSettings();
  }

  Future<void> loadSettings() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final res = await _api.dio.get('/admin/cash/settings');
      final data = Map<String, dynamic>.from(res.data as Map);
      final meta = Map<String, dynamic>.from(data['meta'] as Map? ?? {});

      state = state.copyWith(
        isLoading: false,
        settings: PlatformCashSettings.fromJson(
          Map<String, dynamic>.from(data['settings'] as Map),
        ),
        updatedByName: meta['updatedByName']?.toString(),
        updatedAt: meta['updatedAt'] != null
            ? DateTime.tryParse(meta['updatedAt'].toString())
            : null,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: ApiException.fromDioException(e).message,
      );
    }
  }

  Future<String> saveSettings(PlatformCashSettings next) async {
    state = state.copyWith(isSaving: true, clearError: true);
    try {
      final res = await _api.dio.patch(
        '/admin/cash/settings',
        data: next.toPatchJson(),
      );
      final data = Map<String, dynamic>.from(res.data as Map);
      final meta = Map<String, dynamic>.from(data['meta'] as Map? ?? {});

      state = state.copyWith(
        isSaving: false,
        settings: PlatformCashSettings.fromJson(
          Map<String, dynamic>.from(data['settings'] as Map),
        ),
        updatedByName: meta['updatedByName']?.toString(),
        updatedAt: meta['updatedAt'] != null
            ? DateTime.tryParse(meta['updatedAt'].toString())
            : null,
      );
      return (data['message'] ?? 'Настройки сохранены').toString();
    } catch (e) {
      state = state.copyWith(isSaving: false);
      throw ApiException.fromDioException(e);
    }
  }

  Future<String> applyDefaultLimit({
    required bool overwriteCustomLimits,
    double? previousDefaultLimitRub,
  }) async {
    final res = await _api.dio.post(
      '/admin/cash/settings/apply-default-limit',
      data: {
        'overwriteCustomLimits': overwriteCustomLimits,
        if (previousDefaultLimitRub != null)
          'previousDefaultLimitRub': previousDefaultLimitRub,
      },
    );
    return (res.data['message'] ?? 'Лимит применен').toString();
  }

  Future<OverdueCheckReport> runOverdueCheck({required bool dryRun}) async {
    final res = await _api.dio.post(
      '/admin/cash/settings/run-overdue-check',
      data: {'dryRun': dryRun},
    );
    final data = Map<String, dynamic>.from(res.data as Map);
    return OverdueCheckReport.fromJson(
      Map<String, dynamic>.from(data['report'] as Map),
    );
  }
}
