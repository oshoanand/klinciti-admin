import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exceptions.dart';
import '../models/cash_control_models.dart';
import '../providers/admin_cash_control_provider.dart';

class AdminCashSettingsScreen extends ConsumerStatefulWidget {
  const AdminCashSettingsScreen({super.key});

  @override
  ConsumerState<AdminCashSettingsScreen> createState() =>
      _AdminCashSettingsScreenState();
}

class _AdminCashSettingsScreenState
    extends ConsumerState<AdminCashSettingsScreen> {
  final _formKey = GlobalKey<FormState>();

  final _maxCashOrderCtrl = TextEditingController();
  final _cashCommCtrl = TextEditingController();
  final _cardCommCtrl = TextEditingController();
  final _minCommCtrl = TextEditingController();
  final _debtLimitCtrl = TextEditingController();
  final _warningPctCtrl = TextEditingController();
  final _overdueMinDebtCtrl = TextEditingController();
  final _warnDaysCtrl = TextEditingController();
  final _blockDaysCtrl = TextEditingController();
  final _suspendDaysCtrl = TextEditingController();
  final _cooldownHoursCtrl = TextEditingController();

  bool _cashEnabled = true;
  bool _autoUnblock = true;
  bool _autoBlockOverdue = true;
  bool _autoReminders = true;
  bool _initializedFromServer = false;
  double _initialDefaultLimitRub = -3000;

  @override
  void dispose() {
    _maxCashOrderCtrl.dispose();
    _cashCommCtrl.dispose();
    _cardCommCtrl.dispose();
    _minCommCtrl.dispose();
    _debtLimitCtrl.dispose();
    _warningPctCtrl.dispose();
    _overdueMinDebtCtrl.dispose();
    _warnDaysCtrl.dispose();
    _blockDaysCtrl.dispose();
    _suspendDaysCtrl.dispose();
    _cooldownHoursCtrl.dispose();
    super.dispose();
  }

  void _hydrateForm(PlatformCashSettings s) {
    _cashEnabled = s.cashEnabled;
    _autoUnblock = s.autoUnblockOnSettlement;
    _autoBlockOverdue = s.autoBlockOverdueWorkers;
    _autoReminders = s.autoRemindersEnabled;
    _initialDefaultLimitRub = s.defaultDebtLimitRub;

    _maxCashOrderCtrl.text = s.maxCashOrderRub.toStringAsFixed(0);
    _cashCommCtrl.text = s.cashCommissionPercent.toString();
    _cardCommCtrl.text = s.cardCommissionPercent.toString();
    _minCommCtrl.text = s.minCommissionRub.toStringAsFixed(0);
    _debtLimitCtrl.text = s.defaultDebtLimitRub.abs().toStringAsFixed(0);
    _warningPctCtrl.text = s.warningThresholdPercent.toString();
    _overdueMinDebtCtrl.text = s.overdueMinDebtRub.toStringAsFixed(0);
    _warnDaysCtrl.text = s.overdueWarningDays.toString();
    _blockDaysCtrl.text = s.overdueCashBlockDays.toString();
    _suspendDaysCtrl.text = s.overdueAccountSuspendDays.toString();
    _cooldownHoursCtrl.text = s.reminderCooldownHours.toString();
    _initializedFromServer = true;
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? const Color(0xFFDC2626) : null,
      ),
    );
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final warnDays = int.parse(_warnDaysCtrl.text.trim());
    final blockDays = int.parse(_blockDaysCtrl.text.trim());
    final suspendDays = int.parse(_suspendDaysCtrl.text.trim());

    if (blockDays < warnDays) {
      _showSnack(
        'Дни до блокировки наличных не могут быть меньше дней предупреждения',
        isError: true,
      );
      return;
    }
    if (suspendDays > 0 && suspendDays < blockDays) {
      _showSnack(
        'Дни до блокировки аккаунта не могут быть меньше дней блокировки наличных',
        isError: true,
      );
      return;
    }

    final next = PlatformCashSettings(
      cashEnabled: _cashEnabled,
      maxCashOrderRub: double.parse(_maxCashOrderCtrl.text.trim()),
      cashCommissionPercent: double.parse(
        _cashCommCtrl.text.replaceAll(',', '.').trim(),
      ),
      cardCommissionPercent: double.parse(
        _cardCommCtrl.text.replaceAll(',', '.').trim(),
      ),
      minCommissionRub: double.parse(_minCommCtrl.text.trim()),
      defaultDebtLimitRub: -double.parse(_debtLimitCtrl.text.trim()).abs(),
      warningThresholdPercent: int.parse(_warningPctCtrl.text.trim()),
      autoUnblockOnSettlement: _autoUnblock,
      autoBlockOverdueWorkers: _autoBlockOverdue,
      overdueMinDebtRub: double.parse(_overdueMinDebtCtrl.text.trim()),
      overdueWarningDays: warnDays,
      overdueCashBlockDays: blockDays,
      overdueAccountSuspendDays: suspendDays,
      autoRemindersEnabled: _autoReminders,
      reminderCooldownHours: int.parse(_cooldownHoursCtrl.text.trim()),
    );

    try {
      final msg = await ref
          .read(adminCashSettingsProvider.notifier)
          .saveSettings(next);
      _showSnack(msg);
    } catch (e) {
      _showSnack(ApiException.fromDioException(e).message, isError: true);
    }
  }

  Future<void> _runOverduePreview({required bool dryRun}) async {
    try {
      final report = await ref
          .read(adminCashSettingsProvider.notifier)
          .runOverdueCheck(dryRun: dryRun);

      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(
            report.dryRun
                ? 'Предпросмотр просрочек (Dry Run)'
                : 'Проверка просрочек выполнена',
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Проверено должников: ${report.evaluatedCount}'),
              const SizedBox(height: 8),
              Text('• Предупреждения: ${report.warned.length}'),
              Text('• Блок наличных: ${report.cashBlocked.length}'),
              Text('• Блок аккаунта: ${report.accountSuspended.length}'),
              if (report.skippedDueToLock)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'Проверка уже выполняется другим процессом.',
                    style: TextStyle(color: Color(0xFFDC2626)),
                  ),
                ),
            ],
          ),
          actions: [
            if (report.dryRun)
              FilledButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _runOverduePreview(dryRun: false);
                },
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFDC2626),
                ),
                child: const Text('Применить сейчас'),
              ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Закрыть'),
            ),
          ],
        ),
      );
    } catch (e) {
      _showSnack(ApiException.fromDioException(e).message, isError: true);
    }
  }

  Future<void> _applyLimitToExisting() async {
    bool overwriteCustom = false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Применить новый лимит к кошелькам?'),
          content: CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Перезаписать индивидуальные лимиты'),
            subtitle: const Text(
              'Если выключено — обновятся только кошельки со старым лимитом по умолчанию.',
            ),
            value: overwriteCustom,
            onChanged: (v) =>
                setDialogState(() => overwriteCustom = v ?? false),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Применить'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) return;

    try {
      final msg = await ref
          .read(adminCashSettingsProvider.notifier)
          .applyDefaultLimit(
            overwriteCustomLimits: overwriteCustom,
            previousDefaultLimitRub: overwriteCustom
                ? null
                : _initialDefaultLimitRub,
          );
      _showSnack(msg);
    } catch (e) {
      _showSnack(ApiException.fromDioException(e).message, isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(adminCashSettingsProvider);

    if (!state.isLoading && !_initializedFromServer && state.error == null) {
      _hydrateForm(state.settings);
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        title: const Text(
          'Настройки наличных и комиссий',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
        ),
      ),
      body: state.isLoading && !_initializedFromServer
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (state.updatedByName != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        'Последнее изменение: ${state.updatedByName}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ),

                  _SectionCard(
                    title: 'Глобальный контроль наличных',
                    children: [
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Оплата наличными включена'),
                        subtitle: const Text(
                          'Глобальный переключатель для всех исполнителей',
                        ),
                        value: _cashEnabled,
                        onChanged: (v) => setState(() => _cashEnabled = v),
                      ),
                      const SizedBox(height: 8),
                      _numField(
                        _maxCashOrderCtrl,
                        'Макс. сумма одного наличного заказа (₽)',
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  _SectionCard(
                    title: 'Ставки комиссий',
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _numField(
                              _cashCommCtrl,
                              'Наличные (%)',
                              decimal: true,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _numField(
                              _cardCommCtrl,
                              'Карта (%)',
                              decimal: true,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _numField(
                        _minCommCtrl,
                        'Минимальная комиссия с заказа (₽)',
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  _SectionCard(
                    title: 'Лимиты задолженности',
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _numField(_debtLimitCtrl, 'Лимит долга (₽)'),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _numField(
                              _warningPctCtrl,
                              'Порог предупр. (%)',
                            ),
                          ),
                        ],
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Авто-разблокировка при оплате'),
                        value: _autoUnblock,
                        onChanged: (v) => setState(() => _autoUnblock = v),
                      ),
                      OutlinedButton.icon(
                        onPressed: _applyLimitToExisting,
                        icon: const Icon(LucideIcons.users, size: 16),
                        label: const Text('Применить лимит к существующим'),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  _SectionCard(
                    title: 'Автоблокировка по дням просрочки',
                    children: [
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Автоблокировка должников'),
                        value: _autoBlockOverdue,
                        onChanged: (v) => setState(() => _autoBlockOverdue = v),
                      ),
                      _numField(
                        _overdueMinDebtCtrl,
                        'Мин. долг для срабатывания (₽)',
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _numField(_warnDaysCtrl, 'Предупр. (дн.)'),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _numField(_blockDaysCtrl, 'Блок нал. (дн.)'),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _numField(
                              _suspendDaysCtrl,
                              'Бан акк. (дн.)',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Автоматические FCM-напоминания'),
                        value: _autoReminders,
                        onChanged: (v) => setState(() => _autoReminders = v),
                      ),
                      _numField(
                        _cooldownHoursCtrl,
                        'Пауза между напоминаниями (часов)',
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _runOverduePreview(dryRun: true),
                              icon: const Icon(LucideIcons.eye, size: 16),
                              label: const Text('Dry Run'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: FilledButton.tonalIcon(
                              onPressed: () =>
                                  _runOverduePreview(dryRun: false),
                              icon: const Icon(LucideIcons.play, size: 16),
                              label: const Text('Проверить сейчас'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  SizedBox(
                    height: 50,
                    child: FilledButton(
                      onPressed: state.isSaving ? null : _save,
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF0F172A),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: state.isSaving
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Text(
                              'Сохранить настройки',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }

  Widget _numField(
    TextEditingController ctrl,
    String label, {
    bool decimal = false,
  }) {
    return TextFormField(
      controller: ctrl,
      keyboardType: TextInputType.numberWithOptions(decimal: decimal),
      validator: (v) {
        if (v == null || v.trim().isEmpty) return 'Обязательно';
        final parsed = decimal
            ? double.tryParse(v.replaceAll(',', '.').trim())
            : int.tryParse(v.trim())?.toDouble();
        if (parsed == null || parsed < 0) return 'Некорректно';
        return null;
      },
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _SectionCard({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }
}
