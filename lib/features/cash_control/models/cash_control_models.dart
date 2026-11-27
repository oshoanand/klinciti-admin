class CashSummary {
  final int totalDebtKopeks;
  final int totalSettledKopeks;
  final int debtorCount;
  final int blockedWorkersCount;
  final int openDisputesCount;

  const CashSummary({
    this.totalDebtKopeks = 0,
    this.totalSettledKopeks = 0,
    this.debtorCount = 0,
    this.blockedWorkersCount = 0,
    this.openDisputesCount = 0,
  });

  factory CashSummary.fromJson(Map<String, dynamic> json) => CashSummary(
    totalDebtKopeks: (json['totalDebtKopeks'] as num? ?? 0).toInt(),
    totalSettledKopeks: (json['totalSettledKopeks'] as num? ?? 0).toInt(),
    debtorCount: (json['debtorCount'] as num? ?? 0).toInt(),
    blockedWorkersCount: (json['blockedWorkersCount'] as num? ?? 0).toInt(),
    openDisputesCount: (json['openDisputesCount'] as num? ?? 0).toInt(),
  );
}

class WorkerCashItem {
  final String workerId;
  final String name;
  final String? mobile;
  final String? image;
  final String authStatus;
  final int balanceKopeks;
  final int dueKopeks;
  final int debtLimitKopeks;
  final bool canAcceptCash;
  final bool manualCashBan;
  final DateTime? debtBlockedAt;
  final DateTime? debtSince;
  final int daysInDebt;

  const WorkerCashItem({
    required this.workerId,
    required this.name,
    this.mobile,
    this.image,
    required this.authStatus,
    required this.balanceKopeks,
    required this.dueKopeks,
    required this.debtLimitKopeks,
    required this.canAcceptCash,
    required this.manualCashBan,
    this.debtBlockedAt,
    this.debtSince,
    required this.daysInDebt,
  });

  bool get isSuspended => authStatus.toUpperCase() == 'SUSPENDED';

  factory WorkerCashItem.fromJson(Map<String, dynamic> json) => WorkerCashItem(
    workerId: json['worker_id'].toString(),
    name: (json['name']?.toString().trim().isNotEmpty ?? false)
        ? json['name'].toString()
        : 'Без имени',
    mobile: json['mobile']?.toString(),
    image: json['image']?.toString(),
    authStatus: (json['auth_status'] ?? 'ACTIVE').toString(),
    balanceKopeks: (json['balance_kopeks'] as num? ?? 0).toInt(),
    dueKopeks: (json['due_kopeks'] as num? ?? 0).toInt(),
    debtLimitKopeks: (json['debt_limit_kopeks'] as num? ?? -300000).toInt(),
    canAcceptCash: json['can_accept_cash'] == true,
    manualCashBan: json['manual_cash_ban'] == true,
    debtBlockedAt: json['debt_blocked_at'] != null
        ? DateTime.tryParse(json['debt_blocked_at'].toString())
        : null,
    debtSince: json['debt_since'] != null
        ? DateTime.tryParse(json['debt_since'].toString())
        : null,
    daysInDebt: (json['days_in_debt'] as num? ?? 0).toInt(),
  );
}

class OpenCashDispute {
  final String id;
  final String? workerId;
  final String customerId;
  final int totalAmountKopeks;
  final int platformCommissionKopeks;
  final String? reason;
  final DateTime? updatedAt;

  const OpenCashDispute({
    required this.id,
    this.workerId,
    required this.customerId,
    required this.totalAmountKopeks,
    required this.platformCommissionKopeks,
    this.reason,
    this.updatedAt,
  });

  factory OpenCashDispute.fromJson(Map<String, dynamic> json) =>
      OpenCashDispute(
        id: json['id'].toString(),
        workerId: json['worker_id']?.toString(),
        customerId: json['customer_id'].toString(),
        totalAmountKopeks: (json['total_amount_kopeks'] as num? ?? 0).toInt(),
        platformCommissionKopeks:
            (json['platform_commission_kopeks'] as num? ?? 0).toInt(),
        reason: json['cash_dispute_reason']?.toString(),
        updatedAt: json['updated_at'] != null
            ? DateTime.tryParse(json['updated_at'].toString())
            : null,
      );
}

class WorkerLedgerEntry {
  final String id;
  final String? jobId;
  final String entryType;
  final int amountKopeks;
  final int balanceBeforeKopeks;
  final int balanceAfterKopeks;
  final String? createdByName;
  final String? note;
  final DateTime? createdAt;

  const WorkerLedgerEntry({
    required this.id,
    this.jobId,
    required this.entryType,
    required this.amountKopeks,
    required this.balanceBeforeKopeks,
    required this.balanceAfterKopeks,
    this.createdByName,
    this.note,
    this.createdAt,
  });

  factory WorkerLedgerEntry.fromJson(Map<String, dynamic> json) =>
      WorkerLedgerEntry(
        id: json['id'].toString(),
        jobId: json['job_id']?.toString(),
        entryType: (json['entry_type'] ?? '').toString(),
        amountKopeks: (json['amount_kopeks'] as num? ?? 0).toInt(),
        balanceBeforeKopeks: (json['balance_before_kopeks'] as num? ?? 0)
            .toInt(),
        balanceAfterKopeks: (json['balance_after_kopeks'] as num? ?? 0).toInt(),
        createdByName: json['created_by_name']?.toString(),
        note: json['note']?.toString(),
        createdAt: json['created_at'] != null
            ? DateTime.tryParse(json['created_at'].toString())
            : null,
      );
}

class PlatformCashSettings {
  final bool cashEnabled;
  final double maxCashOrderRub;
  final double cashCommissionPercent;
  final double cardCommissionPercent;
  final double minCommissionRub;
  final double defaultDebtLimitRub;
  final int warningThresholdPercent;
  final bool autoUnblockOnSettlement;
  final bool autoBlockOverdueWorkers;
  final double overdueMinDebtRub;
  final int overdueWarningDays;
  final int overdueCashBlockDays;
  final int overdueAccountSuspendDays;
  final bool autoRemindersEnabled;
  final int reminderCooldownHours;

  const PlatformCashSettings({
    this.cashEnabled = true,
    this.maxCashOrderRub = 15000,
    this.cashCommissionPercent = 15,
    this.cardCommissionPercent = 12,
    this.minCommissionRub = 0,
    this.defaultDebtLimitRub = -3000,
    this.warningThresholdPercent = 75,
    this.autoUnblockOnSettlement = true,
    this.autoBlockOverdueWorkers = true,
    this.overdueMinDebtRub = 100,
    this.overdueWarningDays = 2,
    this.overdueCashBlockDays = 3,
    this.overdueAccountSuspendDays = 7,
    this.autoRemindersEnabled = true,
    this.reminderCooldownHours = 24,
  });

  factory PlatformCashSettings.fromJson(
    Map<String, dynamic> json,
  ) => PlatformCashSettings(
    cashEnabled: json['cashEnabled'] != false,
    maxCashOrderRub: (json['maxCashOrderRub'] as num? ?? 15000).toDouble(),
    cashCommissionPercent: (json['cashCommissionPercent'] as num? ?? 15)
        .toDouble(),
    cardCommissionPercent: (json['cardCommissionPercent'] as num? ?? 12)
        .toDouble(),
    minCommissionRub: (json['minCommissionRub'] as num? ?? 0).toDouble(),
    defaultDebtLimitRub: (json['defaultDebtLimitRub'] as num? ?? -3000)
        .toDouble(),
    warningThresholdPercent: (json['warningThresholdPercent'] as num? ?? 75)
        .toInt(),
    autoUnblockOnSettlement: json['autoUnblockOnSettlement'] != false,
    autoBlockOverdueWorkers: json['autoBlockOverdueWorkers'] != false,
    overdueMinDebtRub: (json['overdueMinDebtRub'] as num? ?? 100).toDouble(),
    overdueWarningDays: (json['overdueWarningDays'] as num? ?? 2).toInt(),
    overdueCashBlockDays: (json['overdueCashBlockDays'] as num? ?? 3).toInt(),
    overdueAccountSuspendDays: (json['overdueAccountSuspendDays'] as num? ?? 7)
        .toInt(),
    autoRemindersEnabled: json['autoRemindersEnabled'] != false,
    reminderCooldownHours: (json['reminderCooldownHours'] as num? ?? 24)
        .toInt(),
  );

  Map<String, dynamic> toPatchJson() => {
    'cashEnabled': cashEnabled,
    'maxCashOrderRub': maxCashOrderRub,
    'cashCommissionPercent': cashCommissionPercent,
    'cardCommissionPercent': cardCommissionPercent,
    'minCommissionRub': minCommissionRub,
    'defaultDebtLimitRub': defaultDebtLimitRub,
    'warningThresholdPercent': warningThresholdPercent,
    'autoUnblockOnSettlement': autoUnblockOnSettlement,
    'autoBlockOverdueWorkers': autoBlockOverdueWorkers,
    'overdueMinDebtRub': overdueMinDebtRub,
    'overdueWarningDays': overdueWarningDays,
    'overdueCashBlockDays': overdueCashBlockDays,
    'overdueAccountSuspendDays': overdueAccountSuspendDays,
    'autoRemindersEnabled': autoRemindersEnabled,
    'reminderCooldownHours': reminderCooldownHours,
  };
}

class OverdueReportItem {
  final String workerId;
  final String name;
  final int daysInDebt;
  final int debtKopeks;

  const OverdueReportItem({
    required this.workerId,
    required this.name,
    required this.daysInDebt,
    required this.debtKopeks,
  });

  factory OverdueReportItem.fromJson(Map<String, dynamic> json) =>
      OverdueReportItem(
        workerId: json['workerId'].toString(),
        name: (json['name']?.toString().trim().isNotEmpty ?? false)
            ? json['name'].toString()
            : 'Без имени',
        daysInDebt: (json['daysInDebt'] as num? ?? 0).toInt(),
        debtKopeks: (json['debtKopeks'] as num? ?? 0).toInt(),
      );
}

class OverdueCheckReport {
  final bool dryRun;
  final bool skippedDueToLock;
  final int evaluatedCount;
  final List<OverdueReportItem> warned;
  final List<OverdueReportItem> cashBlocked;
  final List<OverdueReportItem> accountSuspended;

  const OverdueCheckReport({
    required this.dryRun,
    required this.skippedDueToLock,
    required this.evaluatedCount,
    required this.warned,
    required this.cashBlocked,
    required this.accountSuspended,
  });

  factory OverdueCheckReport.fromJson(Map<String, dynamic> json) {
    List<OverdueReportItem> parseList(dynamic raw) => (raw as List? ?? [])
        .map((e) => OverdueReportItem.fromJson(Map<String, dynamic>.from(e)))
        .toList();

    return OverdueCheckReport(
      dryRun: json['dryRun'] == true,
      skippedDueToLock: json['skippedDueToLock'] == true,
      evaluatedCount: (json['evaluatedCount'] as num? ?? 0).toInt(),
      warned: parseList(json['warned']),
      cashBlocked: parseList(json['cashBlocked']),
      accountSuspended: parseList(json['accountSuspended']),
    );
  }
}

String formatKopeksRub(int kopeks, {bool signed = false}) {
  final abs = kopeks.abs();
  final rub = abs / 100;
  final formatted = abs % 100 == 0
      ? rub.toStringAsFixed(0)
      : rub.toStringAsFixed(2);
  if (!signed) return '$formatted ₽';
  if (kopeks > 0) return '+$formatted ₽';
  if (kopeks < 0) return '-$formatted ₽';
  return '0 ₽';
}
