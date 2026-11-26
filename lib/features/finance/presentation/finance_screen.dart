import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/network/api_exceptions.dart';
import '../../../core/router/route_names.dart';
import '../data/finance_models.dart';
import '../data/finance_repository.dart';
import '../providers/finance_provider.dart';

String _formatRub(double value) {
  final isNeg = value < 0;
  final abs = value.abs();
  final fixed = abs.toStringAsFixed(abs.truncateToDouble() == abs ? 0 : 2);
  final parts = fixed.split('.');
  final intPart = parts[0].replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
    (m) => '${m[1]} ',
  );
  final decimal = parts.length > 1 ? ',${parts[1]}' : '';
  return '${isNeg ? '-' : ''}$intPart$decimal ₽';
}

String _formatDateTime(DateTime? dt) {
  if (dt == null) return '—';
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(dt.day)}.${two(dt.month)}.${dt.year} ${two(dt.hour)}:${two(dt.minute)}';
}

class FinanceScreen extends ConsumerStatefulWidget {
  final int initialTab;

  const FinanceScreen({super.key, this.initialTab = 0});

  @override
  ConsumerState<FinanceScreen> createState() => _FinanceScreenState();
}

class _FinanceScreenState extends ConsumerState<FinanceScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _searchController = TextEditingController();
  Timer? _searchDebounce;

  // Local editable copy of settings for the Settings tab
  PlatformFinanceSettings? _draftSettings;
  final _commissionController = TextEditingController();
  final _holdHoursController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTab.clamp(0, 1),
    );
  }

  @override
  void didUpdateWidget(covariant FinanceScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialTab != widget.initialTab) {
      final target = widget.initialTab.clamp(0, 1);
      if (_tabController.index != target) {
        _tabController.animateTo(target);
      }
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _tabController.dispose();
    _searchController.dispose();
    _commissionController.dispose();
    _holdHoursController.dispose();
    super.dispose();
  }

  void _syncDraftSettings(PlatformFinanceSettings? serverSettings) {
    if (serverSettings == null || _draftSettings != null) return;
    _draftSettings = serverSettings;
    _commissionController.text = serverSettings.commissionPercent
        .toStringAsFixed(1);
    _holdHoursController.text = serverSettings.minPayoutHoldHours.toString();
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: isError
              ? const Color(0xFFDC2626)
              : const Color(0xFF10B981),
        ),
      );
  }

  Future<void> _copyToClipboard(String label, String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    _showSnack('$label скопирован');
  }

  // ============================================================================
  // ACTIONS: KILL SWITCH, SAVE SETTINGS, BATCH RUN, REFUND, BLOCK, KUDIR, LEDGER
  // ============================================================================

  Future<bool> _saveSettings({PlatformFinanceSettings? override}) async {
    final base = override ?? _draftSettings;
    if (base == null) return false;

    final pct =
        double.tryParse(
          _commissionController.text.trim().replaceAll(',', '.'),
        ) ??
        base.commissionPercent;
    final holdHours =
        int.tryParse(_holdHoursController.text.trim()) ??
        base.minPayoutHoldHours;

    if (pct < 0 || pct > 50) {
      _showSnack('Комиссия должна быть от 0% до 50%', isError: true);
      return false;
    }
    if (holdHours < 0 || holdHours > 720) {
      _showSnack('Холд должен быть от 0 до 720 часов', isError: true);
      return false;
    }

    final payload = base.copyWith(
      defaultCommissionBps: (pct * 100).round(),
      minPayoutHoldHours: holdHours,
    );

    try {
      await ref.read(adminFinanceProvider.notifier).saveSettings(payload);
      if (mounted) {
        setState(
          () => _draftSettings =
              ref.read(adminFinanceProvider).settings ?? payload,
        );
      }
      _showSnack('Финансовые настройки сохранены');
      return true;
    } on ApiException catch (e) {
      _showSnack(e.message, isError: true);
      return false;
    } catch (_) {
      _showSnack('Не удалось сохранить настройки', isError: true);
      return false;
    }
  }

  Future<void> _confirmKillSwitch(bool enable) async {
    final previous = _draftSettings ?? ref.read(adminFinanceProvider).settings;
    if (previous == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          enable ? 'Включить автовыплаты?' : 'Остановить все автовыплаты?',
        ),
        content: Text(
          enable
              ? 'Запланированные выплаты исполнителям возобновятся по текущему расписанию.'
              : 'Аварийный рубильник немедленно приостановит автоматический перевод средств исполнителям до повторного включения.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: enable
                  ? const Color(0xFF10B981)
                  : const Color(0xFFDC2626),
              foregroundColor: Colors.white,
            ),
            child: Text(enable ? 'Включить' : 'Остановить'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    final updated = previous.copyWith(autoPayoutsEnabled: enable);
    setState(() => _draftSettings = updated);

    final ok = await _saveSettings(override: updated);
    if (!ok && mounted) {
      // Roll back optimistic UI toggle if the backend rejected the update
      setState(() => _draftSettings = previous);
    }
  }

  Future<void> _confirmRunBatchNow() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Запустить выплаты сейчас?'),
        content: const Text(
          'Все незаблокированные платежи со статусом SCHEDULED и прошедшим временем холда будут отправлены в T-Bank E2C.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0F172A),
              foregroundColor: Colors.white,
            ),
            child: const Text('Запустить'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final result = await ref
          .read(adminFinanceProvider.notifier)
          .runBatchNow();
      final processed = result['processed'] ?? 0;
      final succeeded = result['succeeded'] ?? 0;
      _showSnack('Пакет завершен: обработано $processed, успешно $succeeded');
    } on ApiException catch (e) {
      _showSnack(e.message, isError: true);
    } catch (_) {
      _showSnack('Ошибка при запуске пакета выплат', isError: true);
    }
  }

  Future<void> _openRefundSheet(AdminPaymentRecord payment) async {
    final amountCtrl = TextEditingController(
      text: payment.refundableRemaining.toStringAsFixed(2),
    );
    final reasonCtrl = TextEditingController();
    bool isFullRefund = true;
    bool isSubmitting = false;
    String? modalError;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(
                    LucideIcons.rotate_ccw,
                    color: Color(0xFFDC2626),
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Возврат средств (T-Bank)',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(LucideIcons.x, size: 20),
                    onPressed: isSubmitting ? null : () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Доступно к возврату: ${_formatRub(payment.refundableRemaining)} из ${_formatRub(payment.amount)}',
                style: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
              ),
              const SizedBox(height: 16),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: true, label: Text('Полный')),
                  ButtonSegment(value: false, label: Text('Частичный')),
                ],
                selected: {isFullRefund},
                onSelectionChanged: isSubmitting
                    ? null
                    : (selection) {
                        final full = selection.first;
                        setModalState(() {
                          isFullRefund = full;
                          modalError = null;
                          if (full) {
                            amountCtrl.text = payment.refundableRemaining
                                .toStringAsFixed(2);
                          }
                        });
                      },
              ),
              const SizedBox(height: 14),
              TextField(
                controller: amountCtrl,
                enabled: !isFullRefund && !isSubmitting,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: 'Сумма возврата (₽)',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: reasonCtrl,
                enabled: !isSubmitting,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: 'Причина возврата *',
                  hintText: 'Например: отмена заказа клиентом / спор решен',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              if (modalError != null) ...[
                const SizedBox(height: 12),
                _InlineErrorBanner(message: modalError!),
              ],
              const SizedBox(height: 20),
              SizedBox(
                height: 50,
                child: ElevatedButton(
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          final amount = double.tryParse(
                            amountCtrl.text.trim().replaceAll(',', '.'),
                          );
                          final reason = reasonCtrl.text.trim();

                          if (amount == null ||
                              amount <= 0 ||
                              amount > payment.refundableRemaining + 0.01) {
                            setModalState(
                              () => modalError =
                                  'Укажите корректную сумму (до ${_formatRub(payment.refundableRemaining)})',
                            );
                            return;
                          }
                          if (reason.length < 3) {
                            setModalState(
                              () => modalError = 'Укажите причину возврата (минимум 3 символа)',
                            );
                            return;
                          }

                          setModalState(() {
                            isSubmitting = true;
                            modalError = null;
                          });

                          try {
                            await ref
                                .read(adminFinanceProvider.notifier)
                                .refundPayment(
                                  paymentId: payment.id,
                                  amount: amount,
                                  reason: reason,
                                );
                            if (ctx.mounted) Navigator.pop(ctx);
                            _showSnack(
                              'Возврат ${_formatRub(amount)} успешно оформлен',
                            );
                          } on ApiException catch (e) {
                            setModalState(() {
                              isSubmitting = false;
                              modalError = e.message;
                            });
                          } catch (_) {
                            setModalState(() {
                              isSubmitting = false;
                              modalError = 'Ошибка при выполнении возврата';
                            });
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFDC2626),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: isSubmitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Подтвердить возврат',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    amountCtrl.dispose();
    reasonCtrl.dispose();
  }

  Future<void> _openPayoutBlockDialog(AdminPaymentRecord payment) async {
    final shouldBlock = !payment.payoutBlocked;
    final reasonCtrl = TextEditingController(
      text: payment.payoutBlockReason ?? '',
    );

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          shouldBlock ? 'Заблокировать выплату?' : 'Разблокировать выплату?',
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              shouldBlock
                  ? 'Выплата исполнителю (${_formatRub(payment.netAmount)}) будет удержана на номинальном счете.'
                  : 'Выплата снова вернется в график автоматических переводов.',
            ),
            if (shouldBlock) ...[
              const SizedBox(height: 12),
              TextField(
                controller: reasonCtrl,
                decoration: const InputDecoration(
                  labelText: 'Причина блокировки',
                  hintText: 'Открыт спор / проверка качества',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: shouldBlock
                  ? const Color(0xFFD97706)
                  : const Color(0xFF10B981),
              foregroundColor: Colors.white,
            ),
            child: Text(shouldBlock ? 'Заблокировать' : 'Разблокировать'),
          ),
        ],
      ),
    );

    final reason = reasonCtrl.text.trim();
    reasonCtrl.dispose();

    if (confirmed != true) return;

    try {
      await ref
          .read(adminFinanceProvider.notifier)
          .togglePayoutBlock(
            paymentId: payment.id,
            blocked: shouldBlock,
            reason: shouldBlock ? reason : null,
          );
      _showSnack(
        shouldBlock ? 'Выплата заблокирована' : 'Выплата разблокирована',
      );
    } on ApiException catch (e) {
      _showSnack(e.message, isError: true);
    } catch (_) {
      _showSnack('Не удалось изменить статус блокировки', isError: true);
    }
  }

  Future<void> _openKudirExportSheet() async {
    final now = DateTime.now();
    DateTimeRange? selectedRange = DateTimeRange(
      start: DateTime(now.year, now.month, 1),
      end: now,
    );
    bool isExporting = false;
    String? modalError;

    String formatShort(DateTime dt) =>
        '${dt.day.toString().padLeft(2, '0')}.'
        '${dt.month.toString().padLeft(2, '0')}.${dt.year}';

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(
                    LucideIcons.file_spreadsheet,
                    color: Color(0xFF0F766E),
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Экспорт КУДиР (CSV)',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(LucideIcons.x, size: 20),
                    onPressed: isExporting ? null : () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              const Text(
                'Выгрузка доходов платформы (комиссий) в формате CSV с кодировкой UTF-8 BOM для Excel и 1С.',
                style: TextStyle(color: Color(0xFF64748B), fontSize: 13),
              ),
              const SizedBox(height: 16),

              // Quick Period Presets
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ActionChip(
                    label: const Text('Этот месяц'),
                    onPressed: isExporting
                        ? null
                        : () => setModalState(() {
                            modalError = null;
                            selectedRange = DateTimeRange(
                              start: DateTime(now.year, now.month, 1),
                              end: now,
                            );
                          }),
                  ),
                  ActionChip(
                    label: const Text('Прошлый месяц'),
                    onPressed: isExporting
                        ? null
                        : () => setModalState(() {
                            modalError = null;
                            final prevStart = DateTime(
                              now.year,
                              now.month - 1,
                              1,
                            );
                            final prevEnd = DateTime(now.year, now.month, 0);
                            selectedRange = DateTimeRange(
                              start: prevStart,
                              end: prevEnd,
                            );
                          }),
                  ),
                  ActionChip(
                    label: const Text('Квартал'),
                    onPressed: isExporting
                        ? null
                        : () => setModalState(() {
                            modalError = null;
                            final qStartMonth = ((now.month - 1) ~/ 3) * 3 + 1;
                            selectedRange = DateTimeRange(
                              start: DateTime(now.year, qStartMonth, 1),
                              end: now,
                            );
                          }),
                  ),
                  ActionChip(
                    label: const Text('Весь период'),
                    onPressed: isExporting
                        ? null
                        : () => setModalState(() {
                            modalError = null;
                            selectedRange = null;
                          }),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Custom Date Range Picker
              OutlinedButton.icon(
                onPressed: isExporting
                    ? null
                    : () async {
                        final picked = await showDateRangePicker(
                          context: ctx,
                          firstDate: DateTime(2024, 1, 1),
                          lastDate: now,
                          initialDateRange: selectedRange,
                          helpText: 'Выберите период КУДиР',
                          saveText: 'Выбрать',
                        );
                        if (picked != null) {
                          setModalState(() {
                            modalError = null;
                            selectedRange = picked;
                          });
                        }
                      },
                icon: const Icon(LucideIcons.calendar_range, size: 18),
                label: Text(
                  selectedRange == null
                      ? 'Период: за все время'
                      : 'Период: ${formatShort(selectedRange!.start)} — ${formatShort(selectedRange!.end)}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF0F172A),
                  side: const BorderSide(color: Color(0xFFCBD5E1)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              if (modalError != null) ...[
                const SizedBox(height: 12),
                _InlineErrorBanner(message: modalError!),
              ],
              const SizedBox(height: 20),

              // Download & Share CTA (share_plus ^9.0.0 API)
              SizedBox(
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: isExporting
                      ? null
                      : () async {
                          setModalState(() {
                            isExporting = true;
                            modalError = null;
                          });
                          try {
                            final file = await ref
                                .read(adminFinanceRepositoryProvider)
                                .exportKudirCsv(
                                  from: selectedRange?.start,
                                  to: selectedRange?.end,
                                );

                            if (ctx.mounted) Navigator.pop(ctx);

                            await Share.shareXFiles([
                              XFile(file.path, mimeType: 'text/csv'),
                            ], subject: 'КУДиР Klinciti');
                          } on ApiException catch (e) {
                            setModalState(() {
                              isExporting = false;
                              modalError = e.message;
                            });
                          } catch (_) {
                            setModalState(() {
                              isExporting = false;
                              modalError = 'Не удалось выгрузить отчет КУДиР';
                            });
                          }
                        },
                  icon: isExporting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(LucideIcons.download, size: 18),
                  label: const Text(
                    'Скачать и поделиться CSV',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0F766E),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openLedgerSheet(AdminPaymentRecord payment) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        maxChildSize: 0.92,
        minChildSize: 0.45,
        builder: (ctx, scrollController) => _PaymentLedgerSheet(
          paymentId: payment.id,
          scrollController: scrollController,
          onCopy: _copyToClipboard,
        ),
      ),
    );
  }

  // ============================================================================
  // BUILD
  // ============================================================================
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(adminFinanceProvider);
    _syncDraftSettings(state.settings);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF0F172A),
        elevation: 0,
        title: const Text(
          'Финансы и выплаты',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
        ),
        actions: [
          IconButton(
            tooltip: 'Экспорт КУДиР (CSV)',
            icon: const Icon(LucideIcons.download, size: 20),
            onPressed: _openKudirExportSheet,
          ),
          IconButton(
            tooltip: 'Обновить',
            icon: const Icon(LucideIcons.refresh_cw, size: 20),
            onPressed: () {
              setState(() => _draftSettings = null);
              ref.read(adminFinanceProvider.notifier).loadInitial();
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: const Color(0xFF0F172A),
          unselectedLabelColor: const Color(0xFF64748B),
          indicatorColor: const Color(0xFF0F172A),
          tabs: const [
            Tab(text: 'Платежи и реестр'),
            Tab(text: 'Настройки выплат'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [_buildLedgerTab(state), _buildSettingsTab(state)],
      ),
    );
  }

  // ============================================================================
  // TAB 1: PAYMENTS LEDGER
  // ============================================================================
  Widget _buildLedgerTab(AdminFinanceState state) {
    const statuses = [
      ('ALL', 'Все'),
      ('PAID', 'Оплачено'),
      ('PENDING', 'Ожидание'),
      ('PARTIALLY_REFUNDED', 'Част. возврат'),
      ('REFUNDED', 'Возврат'),
      ('FAILED', 'Ошибка'),
    ];

    return RefreshIndicator(
      onRefresh: () =>
          ref.read(adminFinanceProvider.notifier).refreshPayments(),
      child: CustomScrollView(
        slivers: [
          // Global Kill-Switch Warning Banner
          if (state.settings != null && !state.settings!.autoPayoutsEnabled)
            SliverToBoxAdapter(
              child: Container(
                margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFFECACA)),
                ),
                child: const Row(
                  children: [
                    Icon(
                      LucideIcons.shield_alert,
                      color: Color(0xFFDC2626),
                      size: 18,
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Автовыплаты остановлены (Kill Switch активен)',
                        style: TextStyle(
                          color: Color(0xFF991B1B),
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Summary KPI Grid
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 2.1,
                children: [
                  _KpiCard(
                    label: 'Оборот (GMV)',
                    value: _formatRub(state.summary.grossVolume),
                    accent: const Color(0xFF0F172A),
                  ),
                  _KpiCard(
                    label: 'Комиссия (КУДиР)',
                    value: _formatRub(state.summary.platformFees),
                    accent: const Color(0xFF10B981),
                  ),
                  _KpiCard(
                    label: 'К выплате мастерам',
                    value: _formatRub(state.summary.pendingPayouts),
                    accent: const Color(0xFFD97706),
                  ),
                  _KpiCard(
                    label: 'Возвраты',
                    value: _formatRub(state.summary.totalRefunded),
                    accent: const Color(0xFFDC2626),
                  ),
                ],
              ),
            ),
          ),

          // Search + Filter Chips
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  TextField(
                    controller: _searchController,
                    onChanged: (val) {
                      setState(() {}); // Refresh clear icon visibility
                      _searchDebounce?.cancel();
                      _searchDebounce = Timer(
                        const Duration(milliseconds: 400),
                        () => ref
                            .read(adminFinanceProvider.notifier)
                            .refreshPayments(search: val),
                      );
                    },
                    decoration: InputDecoration(
                      hintText: 'Поиск по ID заказа, сделки или счета...',
                      prefixIcon: const Icon(LucideIcons.search, size: 18),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(LucideIcons.x, size: 16),
                              onPressed: () {
                                _searchController.clear();
                                setState(() {});
                                ref
                                    .read(adminFinanceProvider.notifier)
                                    .refreshPayments(search: '');
                              },
                            )
                          : null,
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 36,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: statuses.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (_, idx) {
                        final (code, label) = statuses[idx];
                        final selected = state.selectedStatus == code;
                        return ChoiceChip(
                          label: Text(label),
                          selected: selected,
                          selectedColor: const Color(0xFF0F172A),
                          labelStyle: TextStyle(
                            color: selected
                                ? Colors.white
                                : const Color(0xFF334155),
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                          onSelected: (_) => ref
                              .read(adminFinanceProvider.notifier)
                              .refreshPayments(status: code),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),

          // Payment Cards List
          if (state.isLoading && state.payments.isEmpty)
            const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator()),
            )
          else if (state.error != null && state.payments.isEmpty)
            SliverFillRemaining(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        state.error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Color(0xFFDC2626)),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: () => ref
                            .read(adminFinanceProvider.notifier)
                            .loadInitial(),
                        icon: const Icon(LucideIcons.refresh_cw, size: 16),
                        label: const Text('Повторить'),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else if (state.payments.isEmpty)
            const SliverFillRemaining(
              child: Center(
                child: Text(
                  'Платежей не найдено',
                  style: TextStyle(color: Color(0xFF64748B)),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              sliver: SliverList.separated(
                itemCount: state.payments.length + (state.hasMore ? 1 : 0),
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, index) {
                  if (index >= state.payments.length) {
                    return Center(
                      child: TextButton(
                        onPressed: state.isLoadingMore
                            ? null
                            : () => ref
                                  .read(adminFinanceProvider.notifier)
                                  .loadMorePayments(),
                        child: state.isLoadingMore
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Загрузить еще'),
                      ),
                    );
                  }

                  final payment = state.payments[index];
                  return _PaymentCard(
                    payment: payment,
                    onInspectLedger: () => _openLedgerSheet(payment),
                    onOpenJob: payment.jobId.isNotEmpty
                        ? () => context.push(
                            AppRoutes.jobDetailPath(payment.jobId),
                          )
                        : null,
                    onRefund: payment.canRefund
                        ? () => _openRefundSheet(payment)
                        : null,
                    onToggleBlock: payment.canTogglePayoutBlock
                        ? () => _openPayoutBlockDialog(payment)
                        : null,
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  // ============================================================================
  // TAB 2: PAYOUT CYCLE CONTROLS & KILL SWITCH
  // ============================================================================
  Widget _buildSettingsTab(AdminFinanceState state) {
    final settings = _draftSettings ?? state.settings;
    if (settings == null) {
      if (state.error != null) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  state.error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Color(0xFFDC2626)),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () =>
                      ref.read(adminFinanceProvider.notifier).loadInitial(),
                  icon: const Icon(LucideIcons.refresh_cw, size: 16),
                  label: const Text('Повторить'),
                ),
              ],
            ),
          ),
        );
      }
      return const Center(child: CircularProgressIndicator());
    }

    const cycleOptions = [
      ('INSTANT', 'Мгновенно'),
      ('DAILY', 'Ежедневно'),
      ('WEEKLY', 'Еженедельно'),
      ('BIWEEKLY', 'Раз в 2 недели'),
      ('MONTHLY', 'Ежемесячно'),
    ];

    const weekDays = [
      (1, 'Понедельник'),
      (2, 'Вторник'),
      (3, 'Среда'),
      (4, 'Четверг'),
      (5, 'Пятница'),
      (6, 'Суббота'),
      (7, 'Воскресенье'),
    ];

    final safeCycle = cycleOptions.any((c) => c.$1 == settings.payoutCycle)
        ? settings.payoutCycle
        : 'DAILY';

    return RefreshIndicator(
      onRefresh: () async {
        setState(() => _draftSettings = null);
        await ref.read(adminFinanceProvider.notifier).loadInitial();
      },
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 1. Auto-Payouts Kill Switch Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: settings.autoPayoutsEnabled
                  ? Colors.white
                  : const Color(0xFFFEF2F2),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: settings.autoPayoutsEnabled
                    ? const Color(0xFFE2E8F0)
                    : const Color(0xFFFCA5A5),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  settings.autoPayoutsEnabled
                      ? LucideIcons.circle_check
                      : LucideIcons.shield_alert,
                  color: settings.autoPayoutsEnabled
                      ? const Color(0xFF10B981)
                      : const Color(0xFFDC2626),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Автоматические выплаты (Kill Switch)',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        settings.autoPayoutsEnabled
                            ? 'Активны — планировщик работает каждые 15 мин.'
                            : 'ПРИОСТАНОВЛЕНЫ — средства удерживаются на счете.',
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: settings.autoPayoutsEnabled,
                  activeColor: const Color(0xFF10B981),
                  onChanged: state.isSavingSettings
                      ? null
                      : (val) => _confirmKillSwitch(val),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 2. Payout Cycle & Schedule Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Цикл и расписание выплат',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                    ),
                    if (settings.updatedAt != null)
                      Text(
                        _formatDateTime(settings.updatedAt),
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF94A3B8),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  value: safeCycle,
                  decoration: const InputDecoration(
                    labelText: 'Периодичность выплат',
                    border: OutlineInputBorder(),
                  ),
                  items: cycleOptions
                      .map(
                        (c) => DropdownMenuItem(value: c.$1, child: Text(c.$2)),
                      )
                      .toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setState(
                        () => _draftSettings = settings.copyWith(
                          payoutCycle: val,
                        ),
                      );
                    }
                  },
                ),
                if (safeCycle == 'WEEKLY' || safeCycle == 'BIWEEKLY') ...[
                  const SizedBox(height: 14),
                  DropdownButtonFormField<int>(
                    value: settings.payoutDayOfWeek.clamp(1, 7),
                    decoration: const InputDecoration(
                      labelText: 'День недели',
                      border: OutlineInputBorder(),
                    ),
                    items: weekDays
                        .map(
                          (d) =>
                              DropdownMenuItem(value: d.$1, child: Text(d.$2)),
                        )
                        .toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setState(
                          () => _draftSettings = settings.copyWith(
                            payoutDayOfWeek: val,
                          ),
                        );
                      }
                    },
                  ),
                ],
                if (safeCycle == 'MONTHLY') ...[
                  const SizedBox(height: 14),
                  DropdownButtonFormField<int>(
                    value: settings.payoutDayOfMonth.clamp(1, 28),
                    decoration: const InputDecoration(
                      labelText: 'Число месяца (1–28)',
                      border: OutlineInputBorder(),
                    ),
                    items: List.generate(
                      28,
                      (i) => DropdownMenuItem(
                        value: i + 1,
                        child: Text('${i + 1}-е число'),
                      ),
                    ),
                    onChanged: (val) {
                      if (val != null) {
                        setState(
                          () => _draftSettings = settings.copyWith(
                            payoutDayOfMonth: val,
                          ),
                        );
                      }
                    },
                  ),
                ],
                const SizedBox(height: 14),
                DropdownButtonFormField<int>(
                  value: settings.payoutHourMsk.clamp(0, 23),
                  decoration: const InputDecoration(
                    labelText: 'Час запуска (МСК)',
                    border: OutlineInputBorder(),
                  ),
                  items: List.generate(
                    24,
                    (h) => DropdownMenuItem(
                      value: h,
                      child: Text('${h.toString().padLeft(2, '0')}:00 МСК'),
                    ),
                  ),
                  onChanged: (val) {
                    if (val != null) {
                      setState(
                        () => _draftSettings = settings.copyWith(
                          payoutHourMsk: val,
                        ),
                      );
                    }
                  },
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _holdHoursController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: const InputDecoration(
                          labelText: 'Холд (0–720 ч)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _commissionController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Комиссия (%)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                SizedBox(
                  height: 50,
                  child: ElevatedButton.icon(
                    onPressed: state.isSavingSettings ? null : _saveSettings,
                    icon: state.isSavingSettings
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(LucideIcons.save, size: 18),
                    label: const Text(
                      'Сохранить настройки',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0F172A),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 3. Manual Batch Trigger Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Ручной запуск выплат',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Немедленно обработать все готовые выплаты в очереди T-Bank E2C, не дожидаясь следующего интервала.',
                  style: TextStyle(fontSize: 12.5, color: Color(0xFF64748B)),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: state.isRunningBatch ? null : _confirmRunBatchNow,
                  icon: state.isRunningBatch
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(LucideIcons.play, size: 16),
                  label: const Text('Запустить пакет выплат сейчас'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF0F172A),
                    side: const BorderSide(color: Color(0xFFCBD5E1)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// SUPPORTING WIDGETS
// ============================================================================
class _InlineErrorBanner extends StatelessWidget {
  final String message;

  const _InlineErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Row(
        children: [
          const Icon(
            LucideIcons.circle_alert,
            color: Color(0xFFDC2626),
            size: 16,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Color(0xFF991B1B),
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _KpiCard extends StatelessWidget {
  final String label;
  final String value;
  final Color accent;

  const _KpiCard({
    required this.label,
    required this.value,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: accent,
            ),
          ),
        ],
      ),
    );
  }
}

class _PaymentCard extends StatelessWidget {
  final AdminPaymentRecord payment;
  final VoidCallback onInspectLedger;
  final VoidCallback? onOpenJob;
  final VoidCallback? onRefund;
  final VoidCallback? onToggleBlock;

  const _PaymentCard({
    required this.payment,
    required this.onInspectLedger,
    this.onOpenJob,
    this.onRefund,
    this.onToggleBlock,
  });

  Color _statusColor(String status) {
    switch (status) {
      case 'PAID':
      case 'PAID_OUT':
        return const Color(0xFF10B981);
      case 'PENDING':
      case 'SCHEDULED':
      case 'PROCESSING':
        return const Color(0xFFD97706);
      case 'REFUNDED':
      case 'PARTIALLY_REFUNDED':
      case 'BLOCKED':
      case 'FAILED':
        return const Color(0xFFDC2626);
      default:
        return const Color(0xFF64748B);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _formatRub(payment.amount),
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ),
              _Badge(
                label: payment.status,
                color: _statusColor(payment.status),
              ),
              const SizedBox(width: 6),
              _Badge(
                label: payment.payoutBlocked ? 'BLOCKED' : payment.payoutStatus,
                color: _statusColor(
                  payment.payoutBlocked ? 'BLOCKED' : payment.payoutStatus,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Комиссия: ${_formatRub(payment.platformFee)} • Мастеру: ${_formatRub(payment.netAmount)}',
            style: const TextStyle(fontSize: 12.5, color: Color(0xFF475569)),
          ),
          if (payment.refundedAmount > 0) ...[
            const SizedBox(height: 2),
            Text(
              'Возвращено: ${_formatRub(payment.refundedAmount)}',
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFFDC2626),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if ((payment.customerName != null &&
                  payment.customerName!.isNotEmpty) ||
              (payment.workerName != null &&
                  payment.workerName!.isNotEmpty)) ...[
            const SizedBox(height: 4),
            Text(
              [
                if (payment.customerName != null &&
                    payment.customerName!.isNotEmpty)
                  'Клиент: ${payment.customerName}',
                if (payment.workerName != null &&
                    payment.workerName!.isNotEmpty)
                  'Мастер: ${payment.workerName}',
              ].join(' • '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: Color(0xFF334155)),
            ),
          ],
          if (payment.dealId != null || payment.invoiceNumber != null) ...[
            const SizedBox(height: 4),
            Text(
              [
                payment.provider,
                if (payment.dealId != null) 'Deal: ${payment.dealId}',
                if (payment.invoiceNumber != null)
                  'Счет: ${payment.invoiceNumber}',
              ].join(' • '),
              style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
            ),
          ],
          if (payment.payoutBlocked &&
              payment.payoutBlockReason != null &&
              payment.payoutBlockReason!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Блок: ${payment.payoutBlockReason}',
              style: const TextStyle(
                fontSize: 11.5,
                color: Color(0xFFB45309),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
          const SizedBox(height: 4),
          Row(
            children: [
              Text(
                _formatDateTime(payment.createdAt),
                style: const TextStyle(
                  fontSize: 11.5,
                  color: Color(0xFF94A3B8),
                ),
              ),
              if (payment.payoutScheduledFor != null &&
                  payment.payoutStatus == 'SCHEDULED') ...[
                const Text(
                  ' • ',
                  style: TextStyle(fontSize: 11.5, color: Color(0xFF94A3B8)),
                ),
                Expanded(
                  child: Text(
                    'Выплата: ${_formatDateTime(payment.payoutScheduledFor)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: Color(0xFFD97706),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const Divider(height: 18),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              OutlinedButton.icon(
                onPressed: onInspectLedger,
                icon: const Icon(LucideIcons.file_text, size: 14),
                label: const Text('Реестр', style: TextStyle(fontSize: 12.5)),
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
              ),
              if (onOpenJob != null)
                OutlinedButton.icon(
                  onPressed: onOpenJob,
                  icon: const Icon(LucideIcons.briefcase, size: 14),
                  label: const Text('Заказ', style: TextStyle(fontSize: 12.5)),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              if (onToggleBlock != null)
                OutlinedButton.icon(
                  onPressed: onToggleBlock,
                  icon: Icon(
                    payment.payoutBlocked
                        ? LucideIcons.lock_open
                        : LucideIcons.lock,
                    size: 14,
                  ),
                  label: Text(
                    payment.payoutBlocked ? 'Разблокировать' : 'Блок выплаты',
                    style: const TextStyle(fontSize: 12.5),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFD97706),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              if (onRefund != null)
                OutlinedButton.icon(
                  onPressed: onRefund,
                  icon: const Icon(LucideIcons.rotate_ccw, size: 14),
                  label: const Text(
                    'Возврат',
                    style: TextStyle(fontSize: 12.5),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFDC2626),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;

  const _Badge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _PaymentLedgerSheet extends ConsumerStatefulWidget {
  final String paymentId;
  final ScrollController scrollController;
  final Future<void> Function(String label, String value) onCopy;

  const _PaymentLedgerSheet({
    required this.paymentId,
    required this.scrollController,
    required this.onCopy,
  });

  @override
  ConsumerState<_PaymentLedgerSheet> createState() =>
      _PaymentLedgerSheetState();
}

class _PaymentLedgerSheetState extends ConsumerState<_PaymentLedgerSheet> {
  late Future<PaymentLedgerDetail> _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _future = ref
        .read(adminFinanceRepositoryProvider)
        .getPaymentLedger(widget.paymentId);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PaymentLedgerDetail>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Ошибка загрузки реестра: ${snapshot.error}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Color(0xFFDC2626)),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () => setState(_load),
                    icon: const Icon(LucideIcons.refresh_cw, size: 16),
                    label: const Text('Повторить'),
                  ),
                ],
              ),
            ),
          );
        }

        final detail = snapshot.data!;
        final p = detail.payment;

        return ListView(
          controller: widget.scrollController,
          padding: const EdgeInsets.all(20),
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Журнал операций платежа',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(LucideIcons.x, size: 20),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            InkWell(
              onTap: () => widget.onCopy('ID платежа', p.id),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'ID: ${p.id}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ),
                  const Icon(
                    LucideIcons.copy,
                    size: 14,
                    color: Color(0xFF64748B),
                  ),
                ],
              ),
            ),
            if (p.dealId != null && p.dealId!.isNotEmpty) ...[
              const SizedBox(height: 4),
              InkWell(
                onTap: () => widget.onCopy('Deal ID', p.dealId!),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Deal ID: ${p.dealId}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ),
                    const Icon(
                      LucideIcons.copy,
                      size: 14,
                      color: Color(0xFF64748B),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Сумма: ${_formatRub(p.amount)} • Комиссия: ${_formatRub(p.platformFee)} • Мастеру: ${_formatRub(p.netAmount)}',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Провайдер: ${p.provider} • Статус: ${p.status} • Выплата: ${p.payoutStatus}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Транзакции (payment_transactions)',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 8),
            if (detail.transactions.isEmpty)
              const Text(
                'Записей пока нет',
                style: TextStyle(color: Color(0xFF64748B), fontSize: 13),
              )
            else
              ...detail.transactions.map(
                (tx) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    '${tx.type} • ${_formatRub(tx.amount)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13.5,
                    ),
                  ),
                  subtitle: Text(
                    [
                      tx.status,
                      _formatDateTime(tx.createdAt),
                      if (tx.providerTxId != null) 'TX: ${tx.providerTxId}',
                      if (tx.errorMessage != null) tx.errorMessage!,
                    ].join(' • '),
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ),
            const Divider(height: 24),
            const Text(
              'Возвраты (refunds)',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 8),
            if (detail.refunds.isEmpty)
              const Text(
                'Возвратов не было',
                style: TextStyle(color: Color(0xFF64748B), fontSize: 13),
              )
            else
              ...detail.refunds.map(
                (r) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    '${_formatRub(r.amount)} (${r.status})',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13.5,
                      color: Color(0xFFDC2626),
                    ),
                  ),
                  subtitle: Text(
                    [
                      if (r.reason != null) r.reason!,
                      _formatDateTime(r.createdAt),
                    ].join(' • '),
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
