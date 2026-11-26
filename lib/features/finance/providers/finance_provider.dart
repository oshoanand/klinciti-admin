import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exceptions.dart';
import '../data/finance_models.dart';
import '../data/finance_repository.dart';

typedef JsonMap = Map<String, dynamic>;

class AdminFinanceState {
  final PlatformFinanceSettings? settings;
  final FinanceSummary summary;
  final List<AdminPaymentRecord> payments;
  final String selectedStatus;
  final String searchQuery;
  final int page;
  final int totalPages;
  final bool isLoading;
  final bool isLoadingMore;
  final bool isSavingSettings;
  final bool isRunningBatch;
  final String? error;

  const AdminFinanceState({
    this.settings,
    this.summary = const FinanceSummary(),
    this.payments = const [],
    this.selectedStatus = 'ALL',
    this.searchQuery = '',
    this.page = 1,
    this.totalPages = 1,
    this.isLoading = false,
    this.isLoadingMore = false,
    this.isSavingSettings = false,
    this.isRunningBatch = false,
    this.error,
  });

  bool get hasMore => page < totalPages;

  AdminFinanceState copyWith({
    PlatformFinanceSettings? settings,
    FinanceSummary? summary,
    List<AdminPaymentRecord>? payments,
    String? selectedStatus,
    String? searchQuery,
    int? page,
    int? totalPages,
    bool? isLoading,
    bool? isLoadingMore,
    bool? isSavingSettings,
    bool? isRunningBatch,
    String? error,
    bool clearError = false,
  }) {
    return AdminFinanceState(
      settings: settings ?? this.settings,
      summary: summary ?? this.summary,
      payments: payments ?? this.payments,
      selectedStatus: selectedStatus ?? this.selectedStatus,
      searchQuery: searchQuery ?? this.searchQuery,
      page: page ?? this.page,
      totalPages: totalPages ?? this.totalPages,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      isSavingSettings: isSavingSettings ?? this.isSavingSettings,
      isRunningBatch: isRunningBatch ?? this.isRunningBatch,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

final adminFinanceProvider =
    StateNotifierProvider<AdminFinanceNotifier, AdminFinanceState>((ref) {
      return AdminFinanceNotifier(ref.watch(adminFinanceRepositoryProvider));
    });

class AdminFinanceNotifier extends StateNotifier<AdminFinanceState> {
  final AdminFinanceRepository _repo;
  bool _isFetchingInitial = false;

  AdminFinanceNotifier(this._repo) : super(const AdminFinanceState()) {
    loadInitial();
  }

  String _formatError(Object e) {
    if (e is ApiException) return e.message;
    return e.toString();
  }

  Future<void> loadInitial() async {
    if (_isFetchingInitial) return;
    _isFetchingInitial = true;

    if (mounted) {
      state = state.copyWith(isLoading: true, clearError: true);
    }

    PlatformFinanceSettings? loadedSettings = state.settings;
    PaginatedPaymentsResponse? paymentsRes;
    String? firstError;

    try {
      // Run both requests concurrently, but catch independently so one failure
      // never blocks the other tab from rendering.
      await Future.wait([
        () async {
          try {
            debugPrint('➡️ [Finance] GET /admin/finance/settings');
            loadedSettings = await _repo.getSettings();
          } catch (e, st) {
            debugPrint('❌ [Finance] getSettings failed: $e\n$st');
            firstError ??= _formatError(e);
          }
        }(),
        () async {
          try {
            debugPrint('➡️ [Finance] GET /admin/finance/payments');
            paymentsRes = await _repo.getPayments(
              page: 1,
              status: state.selectedStatus,
              search: state.searchQuery,
            );
          } catch (e, st) {
            debugPrint('❌ [Finance] getPayments failed: $e\n$st');
            firstError ??= _formatError(e);
          }
        }(),
      ]);

      if (!mounted) return;
      state = state.copyWith(
        settings: loadedSettings,
        summary: paymentsRes?.summary ?? state.summary,
        payments: paymentsRes?.items ?? state.payments,
        page: paymentsRes?.page ?? state.page,
        totalPages: paymentsRes?.totalPages ?? state.totalPages,
        isLoading: false,
        error: firstError,
        clearError: firstError == null,
      );
    } finally {
      _isFetchingInitial = false;
    }
  }

  Future<void> refreshPayments({String? status, String? search}) async {
    final nextStatus = status ?? state.selectedStatus;
    final nextSearch = search ?? state.searchQuery;

    if (mounted) {
      state = state.copyWith(
        selectedStatus: nextStatus,
        searchQuery: nextSearch,
        isLoading: true,
        clearError: true,
      );
    }

    try {
      final res = await _repo.getPayments(
        page: 1,
        status: nextStatus,
        search: nextSearch,
      );
      if (!mounted) return;
      state = state.copyWith(
        summary: res.summary,
        payments: res.items,
        page: res.page,
        totalPages: res.totalPages,
        isLoading: false,
        clearError: true,
      );
    } catch (e, st) {
      debugPrint('❌ [Finance] refreshPayments failed: $e\n$st');
      if (!mounted) return;
      state = state.copyWith(isLoading: false, error: _formatError(e));
    }
  }

  Future<void> loadMorePayments() async {
    if (state.isLoading || state.isLoadingMore || !state.hasMore) return;
    state = state.copyWith(isLoadingMore: true);

    try {
      final nextPage = state.page + 1;
      final res = await _repo.getPayments(
        page: nextPage,
        status: state.selectedStatus,
        search: state.searchQuery,
      );
      if (!mounted) return;
      state = state.copyWith(
        payments: [...state.payments, ...res.items],
        page: res.page,
        totalPages: res.totalPages,
        isLoadingMore: false,
      );
    } catch (e, st) {
      debugPrint('❌ [Finance] loadMorePayments failed: $e\n$st');
      if (!mounted) return;
      state = state.copyWith(isLoadingMore: false);
    }
  }

  Future<void> saveSettings(PlatformFinanceSettings updated) async {
    state = state.copyWith(isSavingSettings: true, clearError: true);
    try {
      final saved = await _repo.updateSettings(updated);
      if (!mounted) return;
      state = state.copyWith(settings: saved, isSavingSettings: false);
    } catch (e) {
      if (mounted) {
        state = state.copyWith(isSavingSettings: false);
      }
      rethrow;
    }
  }

  Future<JsonMap> runBatchNow() async {
    state = state.copyWith(isRunningBatch: true);
    try {
      final result = await _repo.runPayoutsBatchNow();
      await refreshPayments();
      return result;
    } finally {
      if (mounted) {
        state = state.copyWith(isRunningBatch: false);
      }
    }
  }

  Future<void> refundPayment({
    required String paymentId,
    required double amount,
    required String reason,
  }) async {
    await _repo.issueRefund(
      paymentId: paymentId,
      amount: amount,
      reason: reason,
    );
    await refreshPayments();
  }

  Future<void> togglePayoutBlock({
    required String paymentId,
    required bool blocked,
    String? reason,
  }) async {
    await _repo.setPaymentPayoutBlock(
      paymentId: paymentId,
      blocked: blocked,
      reason: reason,
    );
    await refreshPayments();
  }
}
