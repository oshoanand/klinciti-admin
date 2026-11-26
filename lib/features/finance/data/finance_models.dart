double _parseDouble(dynamic value, [double fallback = 0.0]) {
  if (value == null) return fallback;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString().replaceAll(',', '.')) ?? fallback;
}

int _parseInt(dynamic value, [int fallback = 0]) {
  if (value == null) return fallback;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString()) ?? fallback;
}

DateTime? _parseDate(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  return DateTime.tryParse(value.toString())?.toLocal();
}

class PlatformFinanceSettings {
  final String payoutCycle; // INSTANT, DAILY, WEEKLY, BIWEEKLY, MONTHLY
  final int payoutDayOfWeek; // 1 (Mon) .. 7 (Sun)
  final int payoutDayOfMonth; // 1 .. 28
  final int payoutHourMsk; // 0 .. 23
  final int minPayoutHoldHours;
  final int defaultCommissionBps; // e.g., 1000 = 10.0%
  final bool autoPayoutsEnabled;
  final DateTime? updatedAt;

  const PlatformFinanceSettings({
    required this.payoutCycle,
    required this.payoutDayOfWeek,
    required this.payoutDayOfMonth,
    required this.payoutHourMsk,
    required this.minPayoutHoldHours,
    required this.defaultCommissionBps,
    required this.autoPayoutsEnabled,
    this.updatedAt,
  });

  double get commissionPercent => defaultCommissionBps / 100.0;

  factory PlatformFinanceSettings.fromJson(Map<String, dynamic> json) {
    return PlatformFinanceSettings(
      payoutCycle: (json['payout_cycle'] ?? json['payoutCycle'] ?? 'DAILY')
          .toString(),
      payoutDayOfWeek: _parseInt(
        json['payout_day_of_week'] ?? json['payoutDayOfWeek'],
        5,
      ),
      payoutDayOfMonth: _parseInt(
        json['payout_day_of_month'] ?? json['payoutDayOfMonth'],
        1,
      ),
      payoutHourMsk: _parseInt(
        json['payout_hour_msk'] ?? json['payoutHourMsk'],
        12,
      ),
      minPayoutHoldHours: _parseInt(
        json['min_payout_hold_hours'] ?? json['minPayoutHoldHours'],
        24,
      ),
      defaultCommissionBps: _parseInt(
        json['default_commission_bps'] ?? json['defaultCommissionBps'],
        1000,
      ),
      autoPayoutsEnabled:
          (json['auto_payouts_enabled'] ?? json['autoPayoutsEnabled']) != false,
      updatedAt: _parseDate(json['updated_at'] ?? json['updatedAt']),
    );
  }

  Map<String, dynamic> toUpdatePayload() {
    return {
      'payoutCycle': payoutCycle,
      'payoutDayOfWeek': payoutDayOfWeek,
      'payoutDayOfMonth': payoutDayOfMonth,
      'payoutHourMsk': payoutHourMsk,
      'minPayoutHoldHours': minPayoutHoldHours,
      'defaultCommissionBps': defaultCommissionBps,
      'autoPayoutsEnabled': autoPayoutsEnabled,
    };
  }

  PlatformFinanceSettings copyWith({
    String? payoutCycle,
    int? payoutDayOfWeek,
    int? payoutDayOfMonth,
    int? payoutHourMsk,
    int? minPayoutHoldHours,
    int? defaultCommissionBps,
    bool? autoPayoutsEnabled,
  }) {
    return PlatformFinanceSettings(
      payoutCycle: payoutCycle ?? this.payoutCycle,
      payoutDayOfWeek: payoutDayOfWeek ?? this.payoutDayOfWeek,
      payoutDayOfMonth: payoutDayOfMonth ?? this.payoutDayOfMonth,
      payoutHourMsk: payoutHourMsk ?? this.payoutHourMsk,
      minPayoutHoldHours: minPayoutHoldHours ?? this.minPayoutHoldHours,
      defaultCommissionBps: defaultCommissionBps ?? this.defaultCommissionBps,
      autoPayoutsEnabled: autoPayoutsEnabled ?? this.autoPayoutsEnabled,
      updatedAt: updatedAt,
    );
  }
}

class FinanceSummary {
  final double grossVolume;
  final double platformFees;
  final double pendingPayouts;
  final double totalRefunded;

  const FinanceSummary({
    this.grossVolume = 0,
    this.platformFees = 0,
    this.pendingPayouts = 0,
    this.totalRefunded = 0,
  });

  factory FinanceSummary.fromJson(Map<String, dynamic> json) {
    return FinanceSummary(
      grossVolume: _parseDouble(json['grossVolume'] ?? json['gross_volume']),
      platformFees: _parseDouble(json['platformFees'] ?? json['platform_fees']),
      pendingPayouts: _parseDouble(
        json['pendingPayouts'] ?? json['pending_payouts'],
      ),
      totalRefunded: _parseDouble(
        json['totalRefunded'] ?? json['total_refunded'],
      ),
    );
  }
}

class AdminPaymentRecord {
  final String id;
  final String jobId;
  final String? customerName;
  final String? workerName;
  final String provider;
  final String status; // PENDING, PAID, FAILED, REFUNDED, PARTIALLY_REFUNDED
  final String payoutStatus; // NOT_INITIATED, SCHEDULED, BLOCKED, PROCESSING, PAID_OUT, FAILED
  final bool payoutBlocked;
  final String? payoutBlockReason;
  final double amount;
  final double platformFee;
  final double netAmount;
  final double refundedAmount;
  final String? dealId;
  final String? invoiceNumber;
  final DateTime? payoutScheduledFor;
  final DateTime? createdAt;

  const AdminPaymentRecord({
    required this.id,
    required this.jobId,
    required this.provider,
    required this.status,
    required this.payoutStatus,
    required this.payoutBlocked,
    required this.amount,
    required this.platformFee,
    required this.netAmount,
    this.refundedAmount = 0,
    this.customerName,
    this.workerName,
    this.payoutBlockReason,
    this.dealId,
    this.invoiceNumber,
    this.payoutScheduledFor,
    this.createdAt,
  });

  double get refundableRemaining =>
      (amount - refundedAmount).clamp(0.0, amount);

  bool get canRefund =>
      (status == 'PAID' || status == 'PARTIALLY_REFUNDED') &&
      refundableRemaining > 0.01;

  bool get canTogglePayoutBlock =>
      status == 'PAID' &&
      payoutStatus != 'PAID_OUT' &&
      payoutStatus != 'PROCESSING';

  factory AdminPaymentRecord.fromJson(Map<String, dynamic> json) {
    return AdminPaymentRecord(
      id: (json['id'] ?? '').toString(),
      jobId: (json['job_id'] ?? json['jobId'] ?? '').toString(),
      customerName: (json['customer_name'] ?? json['customerName'])?.toString(),
      workerName: (json['worker_name'] ?? json['workerName'])?.toString(),
      provider: (json['provider'] ?? 'TINKOFF_EACQ').toString(),
      status: (json['status'] ?? 'PENDING').toString().toUpperCase(),
      payoutStatus:
          (json['payout_status'] ?? json['payoutStatus'] ?? 'NOT_INITIATED')
              .toString()
              .toUpperCase(),
      payoutBlocked: (json['payout_blocked'] ?? json['payoutBlocked']) == true,
      payoutBlockReason:
          (json['payout_block_reason'] ?? json['payoutBlockReason'])
              ?.toString(),
      amount: _parseDouble(json['amount']),
      platformFee: _parseDouble(json['platform_fee'] ?? json['platformFee']),
      netAmount: _parseDouble(json['net_amount'] ?? json['netAmount']),
      refundedAmount: _parseDouble(
        json['refunded_amount'] ?? json['refundedAmount'],
      ),
      dealId: (json['deal_id'] ?? json['dealId'])?.toString(),
      invoiceNumber: (json['invoice_number'] ?? json['invoiceNumber'])
          ?.toString(),
      payoutScheduledFor: _parseDate(
        json['payout_scheduled_for'] ?? json['payoutScheduledFor'],
      ),
      createdAt: _parseDate(json['created_at'] ?? json['createdAt']),
    );
  }
}

class PaymentLedgerEntry {
  final String id;
  final String type;
  final String status;
  final double amount;
  final String? providerTxId;
  final String? errorCode;
  final String? errorMessage;
  final DateTime? createdAt;

  const PaymentLedgerEntry({
    required this.id,
    required this.type,
    required this.status,
    required this.amount,
    this.providerTxId,
    this.errorCode,
    this.errorMessage,
    this.createdAt,
  });

  factory PaymentLedgerEntry.fromJson(Map<String, dynamic> json) {
    return PaymentLedgerEntry(
      id: (json['id'] ?? '').toString(),
      type: (json['type'] ?? json['event_type'] ?? 'TX').toString(),
      status: (json['status'] ?? 'UNKNOWN').toString(),
      amount: _parseDouble(json['amount']),
      providerTxId: (json['provider_tx_id'] ?? json['providerTxId'])
          ?.toString(),
      errorCode: (json['error_code'] ?? json['errorCode'])?.toString(),
      errorMessage: (json['error_message'] ?? json['errorMessage'])?.toString(),
      createdAt: _parseDate(json['created_at'] ?? json['createdAt']),
    );
  }
}

class PaymentRefundRecord {
  final String id;
  final double amount;
  final String status;
  final String? reason;
  final String? providerRefundId;
  final DateTime? createdAt;

  const PaymentRefundRecord({
    required this.id,
    required this.amount,
    required this.status,
    this.reason,
    this.providerRefundId,
    this.createdAt,
  });

  factory PaymentRefundRecord.fromJson(Map<String, dynamic> json) {
    return PaymentRefundRecord(
      id: (json['id'] ?? '').toString(),
      amount: _parseDouble(json['amount']),
      status: (json['status'] ?? 'PENDING').toString(),
      reason: json['reason']?.toString(),
      providerRefundId: (json['provider_refund_id'] ?? json['providerRefundId'])
          ?.toString(),
      createdAt: _parseDate(json['created_at'] ?? json['createdAt']),
    );
  }
}

class PaymentLedgerDetail {
  final AdminPaymentRecord payment;
  final List<PaymentLedgerEntry> transactions;
  final List<PaymentRefundRecord> refunds;

  const PaymentLedgerDetail({
    required this.payment,
    required this.transactions,
    required this.refunds,
  });

  factory PaymentLedgerDetail.fromJson(Map<String, dynamic> json) {
    final paymentMap = json['payment'] is Map
        ? Map<String, dynamic>.from(json['payment'] as Map)
        : json;
    final rawTxs = (json['transactions'] as List?) ?? const [];
    final rawRefunds = (json['refunds'] as List?) ?? const [];

    return PaymentLedgerDetail(
      payment: AdminPaymentRecord.fromJson(paymentMap),
      transactions: rawTxs
          .whereType()
          .map((e) => PaymentLedgerEntry.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      refunds: rawRefunds
          .whereType()
          .map(
            (e) => PaymentRefundRecord.fromJson(Map<String, dynamic>.from(e)),
          )
          .toList(),
    );
  }
}

class PaginatedPaymentsResponse {
  final List<AdminPaymentRecord> items;
  final FinanceSummary summary;
  final int page;
  final int totalPages;
  final int total;

  const PaginatedPaymentsResponse({
    required this.items,
    required this.summary,
    required this.page,
    required this.totalPages,
    required this.total,
  });
}
