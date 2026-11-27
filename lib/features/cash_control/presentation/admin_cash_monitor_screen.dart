import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exceptions.dart';
import '../models/cash_control_models.dart';
import '../providers/admin_cash_control_provider.dart';
import 'admin_cash_settings_screen.dart';

class AdminCashMonitorScreen extends ConsumerStatefulWidget {
  const AdminCashMonitorScreen({super.key});

  @override
  ConsumerState<AdminCashMonitorScreen> createState() =>
      _AdminCashMonitorScreenState();
}

class _AdminCashMonitorScreenState extends ConsumerState<AdminCashMonitorScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;
  final _searchCtrl = TextEditingController();
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    _tabCtrl.dispose();
    super.dispose();
  }

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? const Color(0xFFDC2626) : null,
      ),
    );
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      ref.read(adminCashMonitorProvider.notifier).loadOverview(search: value);
    });
  }

  // ==========================================================================
  // BOTTOM SHEETS & DIALOGS
  // ==========================================================================

  Future<void> _showSettleSheet(WorkerCashItem worker) async {
    final amountCtrl = TextEditingController(
      text: worker.dueKopeks > 0
          ? (worker.dueKopeks / 100).toStringAsFixed(2)
          : '',
    );
    final refCtrl = TextEditingController(
      text: 'CASH-${DateTime.now().millisecondsSinceEpoch % 1000000}',
    );
    final noteCtrl = TextEditingController();
    String channel = 'CASH_HANDOVER';
    bool submitting = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            20,
            20,
            MediaQuery.viewInsetsOf(ctx).bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Принять оплату • ${worker.name}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Текущий долг: ${formatKopeksRub(worker.dueKopeks)}',
                style: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: amountCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Сумма (₽)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'CASH_HANDOVER', label: Text('Нал')),
                  ButtonSegment(value: 'SBP', label: Text('СБП')),
                  ButtonSegment(value: 'BANK_TRANSFER', label: Text('Банк')),
                ],
                selected: {channel},
                onSelectionChanged: (sel) =>
                    setModalState(() => channel = sel.first),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: refCtrl,
                decoration: const InputDecoration(
                  labelText: 'Номер платежа / квитанции (идемпотентность)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: noteCtrl,
                decoration: const InputDecoration(
                  labelText: 'Комментарий (опционально)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 18),
              FilledButton(
                onPressed: submitting
                    ? null
                    : () async {
                        final amount = double.tryParse(
                          amountCtrl.text.replaceAll(',', '.').trim(),
                        );
                        if (amount == null || amount <= 0) {
                          _showSnack('Введите корректную сумму', isError: true);
                          return;
                        }
                        if (refCtrl.text.trim().length < 3) {
                          _showSnack(
                            'Укажите номер платежа (минимум 3 символа)',
                            isError: true,
                          );
                          return;
                        }

                        setModalState(() => submitting = true);
                        try {
                          final msg = await ref
                              .read(adminCashMonitorProvider.notifier)
                              .settleDebt(
                                workerId: worker.workerId,
                                amountRub: amount,
                                reference: refCtrl.text,
                                paymentChannel: channel,
                                note: noteCtrl.text,
                              );
                          if (ctx.mounted) Navigator.pop(ctx);
                          _showSnack(msg);
                        } catch (e) {
                          setModalState(() => submitting = false);
                          _showSnack(
                            ApiException.fromDioException(e).message,
                            isError: true,
                          );
                        }
                      },
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF0F172A),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: submitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Text('Подтвердить зачисление'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showAdjustSheet(WorkerCashItem worker) async {
    final amountCtrl = TextEditingController();
    final refCtrl = TextEditingController(
      text: 'ADJ-${DateTime.now().millisecondsSinceEpoch % 1000000}',
    );
    final noteCtrl = TextEditingController();
    bool isCredit = true; // true = reduce debt, false = add debit
    bool submitting = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            20,
            20,
            MediaQuery.viewInsetsOf(ctx).bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Корректировка • ${worker.name}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 14),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: true, label: Text('Списать долг (+)')),
                  ButtonSegment(value: false, label: Text('Начислить (-)')),
                ],
                selected: {isCredit},
                onSelectionChanged: (s) =>
                    setModalState(() => isCredit = s.first),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: amountCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Сумма (₽)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: refCtrl,
                decoration: const InputDecoration(
                  labelText: 'Референс операции',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: noteCtrl,
                decoration: const InputDecoration(
                  labelText: 'Причина корректировки (обязательно)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 18),
              FilledButton(
                onPressed: submitting
                    ? null
                    : () async {
                        final raw = double.tryParse(
                          amountCtrl.text.replaceAll(',', '.').trim(),
                        );
                        if (raw == null || raw <= 0) {
                          _showSnack('Введите сумму больше 0', isError: true);
                          return;
                        }
                        if (noteCtrl.text.trim().length < 3) {
                          _showSnack(
                            'Укажите причину (минимум 3 символа)',
                            isError: true,
                          );
                          return;
                        }
                        setModalState(() => submitting = true);
                        try {
                          final msg = await ref
                              .read(adminCashMonitorProvider.notifier)
                              .adjustWallet(
                                workerId: worker.workerId,
                                amountRub: isCredit ? raw : -raw,
                                reference: refCtrl.text,
                                note: noteCtrl.text,
                              );
                          if (ctx.mounted) Navigator.pop(ctx);
                          _showSnack(msg);
                        } catch (e) {
                          setModalState(() => submitting = false);
                          _showSnack(
                            ApiException.fromDioException(e).message,
                            isError: true,
                          );
                        }
                      },
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF0F172A),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: submitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Text('Применить корректировку'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showCashPolicySheet(WorkerCashItem worker) async {
    final limitCtrl = TextEditingController(
      text: (worker.debtLimitKopeks.abs() / 100).toStringAsFixed(0),
    );
    final reasonCtrl = TextEditingController();
    bool manualBan = worker.manualCashBan;
    bool resetClock = false;
    bool submitting = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            20,
            20,
            MediaQuery.viewInsetsOf(ctx).bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Политика наличных • ${worker.name}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: limitCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Лимит долга (₽, положительное число)',
                  helperText: 'Например 5000 сохранится как лимит -5000 ₽',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Ручной запрет наличных'),
                subtitle: const Text(
                  'Блокирует прием наличных независимо от баланса',
                ),
                value: manualBan,
                onChanged: (v) => setModalState(() => manualBan = v),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Сбросить счетчик дней просрочки'),
                subtitle: Text('В долге: ${worker.daysInDebt} дн.'),
                value: resetClock,
                onChanged: (v) => setModalState(() => resetClock = v ?? false),
              ),
              TextField(
                controller: reasonCtrl,
                decoration: const InputDecoration(
                  labelText: 'Комментарий для исполнителя (опционально)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: submitting
                    ? null
                    : () async {
                        final parsed = double.tryParse(limitCtrl.text.trim());
                        if (parsed == null || parsed < 0 || parsed > 100000) {
                          _showSnack(
                            'Лимит должен быть от 0 до 100 000 ₽',
                            isError: true,
                          );
                          return;
                        }
                        setModalState(() => submitting = true);
                        try {
                          final msg = await ref
                              .read(adminCashMonitorProvider.notifier)
                              .updateCashPolicy(
                                workerId: worker.workerId,
                                debtLimitRub: -parsed,
                                manualCashBan: manualBan,
                                resetOverdueClock: resetClock,
                                reason: reasonCtrl.text,
                              );
                          if (ctx.mounted) Navigator.pop(ctx);
                          _showSnack(msg);
                        } catch (e) {
                          setModalState(() => submitting = false);
                          _showSnack(
                            ApiException.fromDioException(e).message,
                            isError: true,
                          );
                        }
                      },
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF0F172A),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: submitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Text('Сохранить политику'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showLedgerSheet(WorkerCashItem worker) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.72,
        maxChildSize: 0.92,
        builder: (ctx, scrollCtrl) =>
            _WorkerLedgerSheet(worker: worker, scrollController: scrollCtrl),
      ),
    );
  }

  Future<void> _showResolveDisputeDialog(OpenCashDispute dispute) async {
    final noteCtrl = TextEditingController();
    String resolution = 'CONFIRM_PAID';
    bool submitting = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text('Спор #${dispute.id.substring(0, 8)}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Сумма: ${formatKopeksRub(dispute.totalAmountKopeks)} • Комиссия: ${formatKopeksRub(dispute.platformCommissionKopeks)}',
                style: const TextStyle(fontSize: 13, color: Color(0xFF475569)),
              ),
              if (dispute.reason != null && dispute.reason!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  'Причина: ${dispute.reason}',
                  style: const TextStyle(fontSize: 13),
                ),
              ],
              const SizedBox(height: 14),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'CONFIRM_PAID',
                    label: Text('Подтвердить'),
                  ),
                  ButtonSegment(
                    value: 'REVERSE_COMMISSION',
                    label: Text('Вернуть ком.'),
                  ),
                ],
                selected: {resolution},
                onSelectionChanged: (s) =>
                    setDialogState(() => resolution = s.first),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: noteCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Решение администратора',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: submitting ? null : () => Navigator.pop(ctx),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: submitting
                  ? null
                  : () async {
                      if (noteCtrl.text.trim().length < 3) {
                        _showSnack('Укажите комментарий', isError: true);
                        return;
                      }
                      setDialogState(() => submitting = true);
                      try {
                        final msg = await ref
                            .read(adminCashMonitorProvider.notifier)
                            .resolveCashDispute(
                              jobId: dispute.id,
                              resolution: resolution,
                              note: noteCtrl.text,
                            );
                        if (ctx.mounted) Navigator.pop(ctx);
                        _showSnack(msg);
                      } catch (e) {
                        setDialogState(() => submitting = false);
                        _showSnack(
                          ApiException.fromDioException(e).message,
                          isError: true,
                        );
                      }
                    },
              child: const Text('Закрыть спор'),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================================================
  // BUILD
  // ==========================================================================

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(adminCashMonitorProvider);
    final notifier = ref.read(adminCashMonitorProvider.notifier);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        title: const Text(
          'Наличные и комиссии',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        actions: [
          IconButton(
            tooltip: 'Напомнить всем должникам',
            icon: const Icon(LucideIcons.bell_ring),
            onPressed: () async {
              try {
                final msg = await notifier.remindAllOverdue();
                _showSnack(msg);
              } catch (e) {
                _showSnack(
                  ApiException.fromDioException(e).message,
                  isError: true,
                );
              }
            },
          ),
          IconButton(
            tooltip: 'Настройки комиссий и блокировок',
            icon: const Icon(LucideIcons.settings_2),
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const AdminCashSettingsScreen(),
                ),
              );
              if (mounted) notifier.loadOverview();
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabCtrl,
          labelColor: const Color(0xFF0F172A),
          indicatorColor: const Color(0xFF0F172A),
          tabs: [
            Tab(text: 'Исполнители (${state.summary.debtorCount})'),
            Tab(text: 'Споры (${state.summary.openDisputesCount})'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          // TAB 1: WORKERS & KPIs
          RefreshIndicator(
            onRefresh: () => notifier.loadOverview(),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (state.settings != null && !state.settings!.cashEnabled)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFFCA5A5)),
                    ),
                    child: const Row(
                      children: [
                        Icon(
                          LucideIcons.ban,
                          color: Color(0xFFDC2626),
                          size: 18,
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Прием наличной оплаты глобально отключен в настройках.',
                            style: TextStyle(
                              color: Color(0xFF991B1B),
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                // KPI Grid
                Row(
                  children: [
                    Expanded(
                      child: _KpiTile(
                        label: 'Общий долг',
                        value: formatKopeksRub(state.summary.totalDebtKopeks),
                        accent: const Color(0xFFE0780F),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _KpiTile(
                        label: 'Собрано комиссий',
                        value: formatKopeksRub(
                          state.summary.totalSettledKopeks,
                        ),
                        accent: const Color(0xFF0D9488),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _KpiTile(
                        label: 'Должников',
                        value: '${state.summary.debtorCount}',
                        accent: const Color(0xFF2563EB),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _KpiTile(
                        label: 'Заблокированы',
                        value: '${state.summary.blockedWorkersCount}',
                        accent: const Color(0xFFDC2626),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 14),

                // Search bar
                TextField(
                  controller: _searchCtrl,
                  onChanged: _onSearchChanged,
                  decoration: InputDecoration(
                    hintText: 'Поиск по имени или телефону...',
                    prefixIcon: const Icon(LucideIcons.search, size: 18),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                // Filter chips
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: CashMonitorFilter.values.map((f) {
                      final selected = state.filter == f;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(f.label),
                          selected: selected,
                          selectedColor: const Color(0xFF0F172A),
                          labelStyle: TextStyle(
                            color: selected
                                ? Colors.white
                                : const Color(0xFF0F172A),
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                          onSelected: (_) => notifier.loadOverview(filter: f),
                        ),
                      );
                    }).toList(),
                  ),
                ),

                const SizedBox(height: 14),

                if (state.isLoading && state.debtors.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (state.error != null)
                  Center(child: Text(state.error!))
                else if (state.debtors.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(
                      child: Text(
                        'Нет исполнителей по выбранному фильтру',
                        style: TextStyle(color: Color(0xFF64748B)),
                      ),
                    ),
                  )
                else
                  ...state.debtors.map((w) => _buildWorkerCard(w, notifier)),
              ],
            ),
          ),

          // TAB 2: OPEN CASH DISPUTES
          RefreshIndicator(
            onRefresh: () => notifier.loadOverview(),
            child: state.openDisputes.isEmpty
                ? ListView(
                    children: const [
                      SizedBox(height: 80),
                      Center(
                        child: Text(
                          'Открытых споров по наличным нет',
                          style: TextStyle(color: Color(0xFF64748B)),
                        ),
                      ),
                    ],
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: state.openDisputes.length,
                    itemBuilder: (_, i) {
                      final d = state.openDisputes[i];
                      return Card(
                        color: Colors.white,
                        elevation: 0,
                        margin: const EdgeInsets.only(bottom: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: const BorderSide(color: Color(0xFFFED7AA)),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.all(14),
                          title: Text(
                            'Заказ #${d.id.substring(0, 8)} • ${formatKopeksRub(d.totalAmountKopeks)}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              'Комиссия: ${formatKopeksRub(d.platformCommissionKopeks)}\n${d.reason ?? 'Без комментария'}',
                              style: const TextStyle(fontSize: 12.5),
                            ),
                          ),
                          trailing: FilledButton(
                            onPressed: () => _showResolveDisputeDialog(d),
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFFE0780F),
                            ),
                            child: const Text('Решить'),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildWorkerCard(WorkerCashItem w, AdminCashMonitorNotifier notifier) {
    final isBlocked = !w.canAcceptCash || w.isSuspended;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isBlocked ? const Color(0xFFFCA5A5) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        w.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${w.mobile ?? '—'} • Лимит: ${formatKopeksRub(w.debtLimitKopeks.abs())}',
                        style: const TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          if (w.daysInDebt > 0)
                            _StatusPill(
                              label: 'Долг ${w.daysInDebt} дн.',
                              bg: const Color(0xFFFFF7ED),
                              fg: const Color(0xFFC2410C),
                            ),
                          if (w.manualCashBan)
                            const _StatusPill(
                              label: 'Ручной бан',
                              bg: Color(0xFFFEF2F2),
                              fg: Color(0xFFB91C1C),
                            )
                          else if (!w.canAcceptCash)
                            const _StatusPill(
                              label: 'Нал. отключен',
                              bg: Color(0xFFFEF2F2),
                              fg: Color(0xFFB91C1C),
                            ),
                          if (w.isSuspended)
                            const _StatusPill(
                              label: 'Аккаунт заблокирован',
                              bg: Color(0xFF7F1D1D),
                              fg: Colors.white,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  formatKopeksRub(w.balanceKopeks, signed: true),
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: w.balanceKopeks < 0
                        ? const Color(0xFFDC2626)
                        : const Color(0xFF0D9488),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _showSettleSheet(w),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF0F172A),
                    ),
                    icon: const Icon(LucideIcons.banknote, size: 16),
                    label: const Text('Принять'),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.outlined(
                  tooltip: 'Отправить напоминание (FCM)',
                  icon: const Icon(LucideIcons.bell, size: 18),
                  onPressed: w.dueKopeks <= 0
                      ? null
                      : () async {
                          try {
                            final msg = await notifier.remindWorker(w.workerId);
                            _showSnack(msg);
                          } catch (e) {
                            _showSnack(
                              ApiException.fromDioException(e).message,
                              isError: true,
                            );
                          }
                        },
                ),
                const SizedBox(width: 4),
                PopupMenuButton<String>(
                  icon: const Icon(LucideIcons.ellipsis_vertical),
                  onSelected: (action) async {
                    if (action == 'ledger') {
                      await _showLedgerSheet(w);
                    } else if (action == 'policy') {
                      await _showCashPolicySheet(w);
                    } else if (action == 'adjust') {
                      await _showAdjustSheet(w);
                    } else if (action == 'unsuspend') {
                      try {
                        final msg = await notifier.unsuspendWorker(
                          workerId: w.workerId,
                          grantGracePeriod: true,
                        );
                        _showSnack(msg);
                      } catch (e) {
                        _showSnack(
                          ApiException.fromDioException(e).message,
                          isError: true,
                        );
                      }
                    }
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: 'ledger',
                      child: Text('История операций (Ledger)'),
                    ),
                    const PopupMenuItem(
                      value: 'policy',
                      child: Text('Лимит и запрет наличных'),
                    ),
                    const PopupMenuItem(
                      value: 'adjust',
                      child: Text('Корректировка баланса'),
                    ),
                    if (w.isSuspended)
                      const PopupMenuItem(
                        value: 'unsuspend',
                        child: Text(
                          'Разблокировать аккаунт',
                          style: TextStyle(
                            color: Color(0xFF0D9488),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _WorkerLedgerSheet extends ConsumerWidget {
  final WorkerCashItem worker;
  final ScrollController scrollController;

  const _WorkerLedgerSheet({
    required this.worker,
    required this.scrollController,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ledgerAsync = ref.watch(workerLedgerProvider(worker.workerId));

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFE2E8F0),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Журнал операций • ${worker.name}',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ledgerAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => Center(
                child: Text(ApiException.fromDioException(err).message),
              ),
              data: (entries) {
                if (entries.isEmpty) {
                  return const Center(child: Text('Операций пока нет'));
                }
                return ListView.separated(
                  controller: scrollController,
                  itemCount: entries.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final e = entries[i];
                    final isPositive = e.amountKopeks > 0;
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        e.note?.isNotEmpty == true ? e.note! : e.entryType,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        '${e.entryType}${e.createdByName != null ? ' • ${e.createdByName}' : ''}\nБаланс после: ${formatKopeksRub(e.balanceAfterKopeks, signed: true)}',
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: Color(0xFF64748B),
                        ),
                      ),
                      trailing: Text(
                        formatKopeksRub(e.amountKopeks, signed: true),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: isPositive
                              ? const Color(0xFF0D9488)
                              : const Color(0xFFDC2626),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _KpiTile extends StatelessWidget {
  final String label;
  final String value;
  final Color accent;

  const _KpiTile({
    required this.label,
    required this.value,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w800,
              color: accent,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String label;
  final Color bg;
  final Color fg;

  const _StatusPill({required this.label, required this.bg, required this.fg});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fg),
      ),
    );
  }
}
