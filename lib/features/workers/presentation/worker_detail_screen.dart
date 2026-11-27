import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exceptions.dart';
import '../../chat/data/chat_repository.dart';
import '../data/worker_model.dart';
import '../providers/workers_provider.dart';

class _KycDocItem {
  final String title;
  final String subtitle;
  final String? url;
  final bool isRequired;

  const _KycDocItem({
    required this.title,
    required this.subtitle,
    required this.url,
    this.isRequired = false,
  });

  bool get isUploaded => url != null && url!.trim().isNotEmpty;
}

class WorkerDetailScreen extends ConsumerStatefulWidget {
  final String workerId;
  const WorkerDetailScreen({super.key, required this.workerId});

  @override
  ConsumerState<WorkerDetailScreen> createState() => _WorkerDetailScreenState();
}

class _WorkerDetailScreenState extends ConsumerState<WorkerDetailScreen> {
  bool _isProcessing = false;

  // ==========================================
  // HARDWARE INTEGRATIONS & CLIPBOARD
  // ==========================================
  Future<void> _makeCall(String? mobile) async {
    if (mobile == null || mobile.trim().isEmpty) return;

    final cleanNumber = mobile.replaceAll(RegExp(r'[^\d+]'), '');
    final Uri launchUri = Uri(scheme: 'tel', path: cleanNumber);

    try {
      await launchUrl(launchUri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to open dialer on this device')),
        );
      }
    }
  }

  Future<void> _startChat() async {
    try {
      final session = await ref
          .read(chatRepositoryProvider)
          .initiateChat(widget.workerId);
      if (mounted) {
        context.push('/chat/${session.id}/${widget.workerId}');
      }
    } catch (e) {
      if (mounted) {
        final msg = ApiException.fromDioException(e).message;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error creating chat: $msg'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label скопирован в буфер обмена'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // ==========================================
  // API MUTATIONS
  // ==========================================
  Future<void> _updateModeration(String status, {String? reason}) async {
    setState(() => _isProcessing = true);
    try {
      final api = ref.read(apiClientProvider);

      await api.dio.patch(
        '/workers/admin/${widget.workerId}/moderation-status',
        data: {
          'moderationStatus': status,
          if (reason != null) 'rejectionReason': reason,
        },
      );

      // If approving, also ensure AUTH status is ACTIVE
      if (status == 'APPROVED') {
        await api.dio.patch(
          '/workers/admin/${widget.workerId}/auth-status',
          data: {'authStatus': 'ACTIVE'},
        );
      }

      ref.invalidate(workerDetailProvider(widget.workerId));
      ref.invalidate(workerStatsProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              status == 'APPROVED'
                  ? 'Анкета мастера успешно одобрена'
                  : 'Анкета мастера отклонена',
            ),
            backgroundColor: status == 'APPROVED' ? Colors.green : Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        final msg = ApiException.fromDioException(e).message;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка при обновлении статуса модерации: $msg'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  Future<void> _updateAuthStatus(String status) async {
    setState(() => _isProcessing = true);
    try {
      await ref
          .read(apiClientProvider)
          .dio
          .patch(
            '/workers/admin/${widget.workerId}/auth-status',
            data: {'authStatus': status},
          );

      ref.invalidate(workerDetailProvider(widget.workerId));
      ref.invalidate(workerStatsProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              status == 'BLOCKED'
                  ? 'Мастер заблокирован'
                  : 'Мастер разблокирован',
            ),
            backgroundColor: status == 'BLOCKED' ? Colors.red : Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        final msg = ApiException.fromDioException(e).message;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка обновления статуса доступа: $msg'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  // ==========================================
  // REJECTION DIALOG & DOCUMENT VIEWER
  // ==========================================
  void _showRejectDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Причина отказа'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Опишите, какие данные или фото документов необходимо исправить:',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: InputDecoration(
                hintText:
                    'Например: Размытое фото главной страницы паспорта...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              final reason = controller.text.trim();
              if (reason.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Укажите причину отказа'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }
              Navigator.pop(dialogContext);
              _updateModeration('REJECTED', reason: reason);
            },
            child: const Text(
              'Отклонить',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  void _openDocumentViewer(String title, String imageUrl) {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (ctx) =>
            _FullScreenDocumentViewer(title: title, imageUrl: imageUrl),
      ),
    );
  }

  // ==========================================
  // BUILD METHOD
  // ==========================================
  @override
  Widget build(BuildContext context) {
    final workerAsync = ref.watch(workerDetailProvider(widget.workerId));

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Анкета мастера'),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.refresh_cw, size: 18),
            tooltip: 'Обновить',
            onPressed: () =>
                ref.invalidate(workerDetailProvider(widget.workerId)),
          ),
          if (workerAsync.valueOrNull != null &&
              workerAsync.valueOrNull!.authStatus == 'ACTIVE')
            IconButton(
              icon: const Icon(LucideIcons.ban, color: Colors.red),
              tooltip: 'Заблокировать доступ',
              onPressed: _isProcessing
                  ? null
                  : () => _updateAuthStatus('BLOCKED'),
            ),
          if (workerAsync.valueOrNull != null &&
              workerAsync.valueOrNull!.authStatus == 'BLOCKED')
            IconButton(
              icon: const Icon(LucideIcons.lock_open, color: Colors.green),
              tooltip: 'Разблокировать доступ',
              onPressed: _isProcessing
                  ? null
                  : () => _updateAuthStatus('ACTIVE'),
            ),
        ],
      ),
      body: workerAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  LucideIcons.circle_exclamation_point,
                  color: Colors.red,
                  size: 42,
                ),
                const SizedBox(height: 12),
                Text(
                  'Ошибка загрузки профиля: $err',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () =>
                      ref.invalidate(workerDetailProvider(widget.workerId)),
                  icon: const Icon(LucideIcons.refresh_cw, size: 16),
                  label: const Text('Повторить'),
                ),
              ],
            ),
          ),
        ),
        data: (worker) => RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(workerDetailProvider(widget.workerId));
          },
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. HEADER CARD (Avatar, Name, Status Badges, Contact & Stats)
                _buildHeaderCard(worker),

                // 2. REJECTION REASON BANNER (if REJECTED)
                if (worker.moderationStatus == 'REJECTED' &&
                    worker.rejectionReason != null &&
                    worker.rejectionReason!.trim().isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _buildRejectionBanner(worker.rejectionReason!),
                ],

                // 3. MODERATION ACTION PANEL
                const SizedBox(height: 20),
                _buildModerationActionCard(worker),

                // 4. STEP 1 & PERSONAL DETAILS
                const SizedBox(height: 24),
                _buildSectionHeader(
                  icon: LucideIcons.user_check,
                  title: 'Личные данные (Шаг 1)',
                ),
                const SizedBox(height: 8),
                _buildPersonalDetailsCard(worker),

                // 5. STEP 2: LEGAL & PROFESSIONAL INFO
                const SizedBox(height: 24),
                _buildSectionHeader(
                  icon: LucideIcons.briefcase,
                  title: 'Профиль, опыт и категории (Шаг 2)',
                ),
                const SizedBox(height: 8),
                _buildProfessionalCard(worker),

                // 6. STEP 2: VEHICLE / TRANSPORT INFO
                const SizedBox(height: 24),
                _buildSectionHeader(
                  icon: LucideIcons.car,
                  title: 'Транспорт (Шаг 2)',
                ),
                const SizedBox(height: 8),
                _buildTransportCard(worker),

                // 7. STEP 3: KYC & UPLOADED DOCUMENTS
                const SizedBox(height: 24),
                _buildSectionHeader(
                  icon: LucideIcons.shield_check,
                  title: 'Документы и верификация KYC (Шаг 3)',
                ),
                const SizedBox(height: 8),
                _buildKycDocumentsSection(worker),

                // 8. STEP 4: FINANCIAL & PAYOUT DETAILS
                const SizedBox(height: 24),
                _buildSectionHeader(
                  icon: LucideIcons.landmark,
                  title: 'Банковские реквизиты (Шаг 4)',
                ),
                const SizedBox(height: 8),
                _buildFinancialCard(worker),

                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ==========================================
  // SECTION BUILDERS
  // ==========================================
  Widget _buildHeaderCard(WorkerModel worker) {
    final hasAvatar =
        worker.avatarUrl != null && worker.avatarUrl!.trim().isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          GestureDetector(
            onTap: hasAvatar
                ? () => _openDocumentViewer('Фото профиля', worker.avatarUrl!)
                : null,
            child: CircleAvatar(
              radius: 44,
              backgroundColor: Colors.grey.shade100,
              backgroundImage: hasAvatar
                  ? NetworkImage(worker.avatarUrl!)
                  : null,
              child: !hasAvatar
                  ? const Icon(LucideIcons.user, size: 42, color: Colors.grey)
                  : null,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            worker.fullName,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            worker.mobile ?? 'Телефон не указан',
            style: const TextStyle(color: Colors.grey, fontSize: 14),
          ),
          if (worker.email != null && worker.email!.trim().isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              worker.email!,
              style: const TextStyle(color: Colors.grey, fontSize: 13),
            ),
          ],
          const SizedBox(height: 12),

          // Status Badges Row
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              _buildStatusChip(
                label: _getModerationLabel(worker.moderationStatus),
                color: _getModerationColor(worker.moderationStatus),
              ),
              _buildStatusChip(
                label: worker.authStatus == 'ACTIVE'
                    ? 'Доступ активен'
                    : 'Заблокирован',
                color: worker.authStatus == 'ACTIVE'
                    ? Colors.green
                    : Colors.red,
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Communication Buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton.icon(
                onPressed: () => _makeCall(worker.mobile),
                icon: const Icon(LucideIcons.phone, size: 18),
                label: const Text('Позвонить'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green.shade50,
                  foregroundColor: Colors.green.shade800,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: _startChat,
                icon: const Icon(LucideIcons.message_circle, size: 18),
                label: const Text('Написать'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue.shade50,
                  foregroundColor: Colors.blue.shade800,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
          const Divider(height: 32),

          // Aggregated Stats Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStat(
                'Рейтинг',
                worker.rating.toStringAsFixed(1),
                LucideIcons.star,
                Colors.amber,
              ),
              _buildStat(
                'Выполнено',
                worker.totalJobsCompleted.toString(),
                LucideIcons.circle_check,
                Colors.green,
              ),
              _buildStat(
                'Заработано',
                '${worker.totalIncome.toStringAsFixed(0)} ₽',
                LucideIcons.wallet,
                Colors.blue,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRejectionBanner(String reason) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            LucideIcons.circle_exclamation_point,
            color: Colors.red,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Причина отклонения анкеты:',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.red.shade900,
                    fontSize: 13.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  reason,
                  style: TextStyle(
                    color: Colors.red.shade800,
                    fontSize: 14,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModerationActionCard(WorkerModel worker) {
    final isApproved = worker.moderationStatus == 'APPROVED';
    final isRejected = worker.moderationStatus == 'REJECTED';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                LucideIcons.user_cog,
                size: 18,
                color: Colors.blueGrey,
              ),
              const SizedBox(width: 8),
              Text(
                worker.moderationStatus == 'PENDING'
                    ? 'Решение по анкете (ожидает проверки)'
                    : 'Управление статусом модерации',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              if (!isApproved)
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: _isProcessing
                        ? null
                        : () => _updateModeration('APPROVED'),
                    icon: _isProcessing
                        ? const SizedBox.shrink()
                        : const Icon(LucideIcons.check, size: 18),
                    label: _isProcessing
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text(
                            'Одобрить анкету',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                  ),
                ),
              if (!isApproved && !isRejected) const SizedBox(width: 12),
              if (!isRejected)
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: _isProcessing ? null : _showRejectDialog,
                    icon: const Icon(LucideIcons.x, size: 18),
                    label: const Text(
                      'Отклонить',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPersonalDetailsCard(WorkerModel worker) {
    String dobText = 'Не указана';
    if (worker.dateOfBirth != null) {
      final dob = worker.dateOfBirth!.toLocal();
      final age = DateTime.now().difference(dob).inDays ~/ 365;
      dobText = '${DateFormat('dd.MM.yyyy').format(dob)} ($age лет)';
    }

    String genderText = 'Не указан';
    if (worker.gender == 'MALE') genderText = 'Мужской';
    if (worker.gender == 'FEMALE') genderText = 'Женский';

    final createdStr = worker.createdAt != null
        ? DateFormat('dd.MM.yyyy HH:mm').format(worker.createdAt!.toLocal())
        : 'Неизвестно';

    return _buildInfoContainer(
      children: [
        _buildInfoRow('Фамилия', worker.lastName ?? '—'),
        const Divider(height: 20),
        _buildInfoRow('Имя', worker.firstName ?? '—'),
        const Divider(height: 20),
        _buildInfoRow('Отчество', worker.middleName ?? '—'),
        const Divider(height: 20),
        _buildInfoRow('Дата рождения', dobText),
        const Divider(height: 20),
        _buildInfoRow('Пол', genderText),
        const Divider(height: 20),
        _buildInfoRow('Дата регистрации', createdStr),
      ],
    );
  }

  String _getLegalTypeText(String? type) {
    switch (type?.toUpperCase()) {
      case 'IP':
        return 'ИП (Индивидуальный предприниматель)';
      case 'OOO':
        return 'ООО (Юр. лицо)';
      case 'SELF_EMPLOYED':
        return 'Самозанятый (НПД)';
      default:
        return 'Не указан';
    }
  }

  Widget _buildProfessionalCard(WorkerModel worker) {
    final hasExperience =
        worker.experience != null && worker.experience!.trim().isNotEmpty;
    final hasDescription =
        worker.description != null && worker.description!.trim().isNotEmpty;

    return _buildInfoContainer(
      children: [
        // 1. Legal Type and Details
        _buildInfoRow('Форма занятости', _getLegalTypeText(worker.legalType)),
        const Divider(height: 20),
        _buildInfoRow(
          'ИНН',
          worker.inn ?? 'Не указан',
          onCopy: worker.inn != null
              ? () => _copyToClipboard(worker.inn!, 'ИНН')
              : null,
        ),
        if (worker.companyName != null && worker.companyName!.isNotEmpty) ...[
          const Divider(height: 20),
          _buildInfoRow('Наименование', worker.companyName!),
        ],
        const Divider(height: 20),

        // 2. Geography & Bio
        _buildInfoRow('Город', worker.city ?? 'Не указан'),
        const Divider(height: 20),
        _buildInfoRow('Адрес проживания', worker.address ?? 'Не указан'),
        const Divider(height: 20),
        _buildInfoRow(
          'Опыт работы',
          hasExperience ? '${worker.experience} лет' : 'Не указан',
        ),
        const Divider(height: 20),
        const Text(
          'О себе и своем опыте:',
          style: TextStyle(
            fontSize: 13,
            color: Colors.grey,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Text(
            hasDescription
                ? worker.description!
                : 'Мастер не добавил описание о себе',
            style: TextStyle(
              fontSize: 14,
              color: hasDescription ? const Color(0xFF0F172A) : Colors.grey,
              fontStyle: hasDescription ? FontStyle.normal : FontStyle.italic,
              height: 1.4,
            ),
          ),
        ),
        const Divider(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Выбранные категории и специализации:',
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey,
                fontWeight: FontWeight.w500,
              ),
            ),
            Text(
              '${worker.categories.length}',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: Colors.blue,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (worker.categories.isEmpty)
          const Text(
            'Категории не выбраны',
            style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: worker.categories.map((cat) {
              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Text(
                  cat.name,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: Colors.blue.shade900,
                  ),
                ),
              );
            }).toList(),
          ),
      ],
    );
  }

  Widget _buildTransportCard(WorkerModel worker) {
    if (!worker.hasVehicle) {
      return _buildInfoContainer(
        children: const [
          Row(
            children: [
              Icon(LucideIcons.car, color: Colors.grey, size: 20),
              SizedBox(width: 10),
              Text(
                'Нет личного автомобиля',
                style: TextStyle(color: Colors.grey, fontSize: 14),
              ),
            ],
          ),
        ],
      );
    }

    return _buildInfoContainer(
      children: [
        _buildInfoRow('Наличие авто', 'Есть личный автомобиль'),
        const Divider(height: 20),
        _buildInfoRow('Марка и модель', worker.vehicleModel ?? 'Не указана'),
        const Divider(height: 20),
        _buildInfoRow(
          'Госномер',
          worker.vehicleNumber ?? 'Не указан',
          onCopy: worker.vehicleNumber != null
              ? () => _copyToClipboard(worker.vehicleNumber!, 'Госномер')
              : null,
        ),
      ],
    );
  }

  Widget _buildKycDocumentsSection(WorkerModel worker) {
    final List<_KycDocItem> docs = [
      _KycDocItem(
        title: 'Паспорт (Главная)',
        subtitle: 'Разворот с фото и ФИО',
        url: worker.idDocumentFrontUrl,
        isRequired: true,
      ),
      _KycDocItem(
        title: 'Селфи с паспортом',
        subtitle: 'Фото лица вместе с документом',
        url: worker.selfieWithIdUrl,
        isRequired: true,
      ),
      _KycDocItem(
        title: 'Паспорт (Прописка)',
        subtitle: 'Страница с регистрацией',
        url: worker.idDocumentBackUrl,
        isRequired: false,
      ),
      _KycDocItem(
        title: 'Водительское удостоверение',
        subtitle: 'Для заказов с авто',
        url: worker.driversLicenseUrl,
        isRequired: worker.hasVehicle,
      ),
    ];

    final uploadedCount = docs.where((d) => d.isUploaded).length;

    return _buildInfoContainer(
      children: [
        _buildInfoRow(
          'Серия и номер паспорта',
          worker.passportNumber ?? 'Не указаны',
          onCopy:
              (worker.passportNumber != null &&
                  worker.passportNumber!.isNotEmpty)
              ? () => _copyToClipboard(worker.passportNumber!, 'Номер паспорта')
              : null,
        ),
        const Divider(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'документов:',
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: Color(0xFF0F172A),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: uploadedCount >= 2
                    ? Colors.green.shade50
                    : Colors.orange.shade50,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'Загружено: $uploadedCount из ${docs.length}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: uploadedCount >= 2
                      ? Colors.green.shade800
                      : Colors.orange.shade800,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // 2x2 Grid of KYC Document Cards
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: docs.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 0.88,
          ),
          itemBuilder: (context, index) {
            return _buildKycDocCard(docs[index]);
          },
        ),
      ],
    );
  }

  Widget _buildKycDocCard(_KycDocItem doc) {
    final isUploaded = doc.isUploaded;

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: isUploaded ? () => _openDocumentViewer(doc.title, doc.url!) : null,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isUploaded
                ? Colors.blue.shade200
                : (doc.isRequired
                      ? Colors.orange.shade200
                      : Colors.grey.shade200),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: isUploaded
                  ? Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.network(
                          doc.url!,
                          fit: BoxFit.cover,
                          loadingBuilder: (ctx, child, progress) {
                            if (progress == null) return child;
                            return const Center(
                              child: CircularProgressIndicator(strokeWidth: 2),
                            );
                          },
                          errorBuilder: (_, __, ___) => Container(
                            color: Colors.grey.shade200,
                            child: const Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(LucideIcons.image_off, color: Colors.grey),
                                SizedBox(height: 4),
                                Text(
                                  'Ошибка фото',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Positioned(
                          right: 6,
                          top: 6,
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.6),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              LucideIcons.maximize_2,
                              color: Colors.white,
                              size: 14,
                            ),
                          ),
                        ),
                      ],
                    )
                  : Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            LucideIcons.file_x,
                            size: 28,
                            color: doc.isRequired
                                ? Colors.orange.shade400
                                : Colors.grey.shade400,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            doc.isRequired
                                ? 'Не загружено (обяз.)'
                                : 'Не загружено',
                            style: TextStyle(
                              fontSize: 11,
                              color: doc.isRequired
                                  ? Colors.orange.shade700
                                  : Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
            Container(
              padding: const EdgeInsets.all(8),
              color: Colors.white,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    doc.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    doc.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFinancialCard(WorkerModel worker) {
    // If the worker has the new banking fields populated
    final hasNewBanking =
        worker.checkingAccount != null && worker.checkingAccount!.isNotEmpty;

    if (hasNewBanking) {
      return _buildInfoContainer(
        children: [
          _buildInfoRow('Название банка', worker.bankName ?? 'Не указано'),
          const Divider(height: 20),
          _buildInfoRow(
            'БИК банка',
            worker.bankBik ?? 'Не указан',
            onCopy: worker.bankBik != null
                ? () => _copyToClipboard(worker.bankBik!, 'БИК')
                : null,
          ),
          const Divider(height: 20),
          _buildInfoRow(
            'Расчетный счет',
            worker.checkingAccount ?? 'Не указан',
            onCopy: worker.checkingAccount != null
                ? () => _copyToClipboard(
                    worker.checkingAccount!,
                    'Расчетный счет',
                  )
                : null,
          ),
          const Divider(height: 20),
          _buildInfoRow(
            'Корр. счет',
            worker.correspondentAccount ?? 'Не указан',
            onCopy: worker.correspondentAccount != null
                ? () => _copyToClipboard(
                    worker.correspondentAccount!,
                    'Корр. счет',
                  )
                : null,
          ),
        ],
      );
    }

    // Legacy fallback rendering
    final hasTaxId = worker.taxId != null && worker.taxId!.trim().isNotEmpty;
    final hasPayout =
        worker.payoutDetails != null && worker.payoutDetails!.trim().isNotEmpty;

    return _buildInfoContainer(
      children: [
        _buildInfoRow(
          'ИНН налогоплательщика',
          hasTaxId ? worker.taxId! : 'Не указан',
          onCopy: hasTaxId
              ? () => _copyToClipboard(worker.taxId!, 'ИНН')
              : null,
        ),
        const Divider(height: 20),
        _buildInfoRow(
          'Реквизиты для выплат',
          hasPayout ? worker.payoutDetails! : 'Не указаны',
          onCopy: hasPayout
              ? () => _copyToClipboard(
                  worker.payoutDetails!,
                  'Платежные реквизиты',
                )
              : null,
        ),
      ],
    );
  }

  // ==========================================
  // COMMON UI HELPERS
  // ==========================================
  Widget _buildSectionHeader({required IconData icon, required String title}) {
    return Row(
      children: [
        Icon(icon, size: 18, color: const Color(0xFF0F172A)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Color(0xFF0F172A),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoContainer({required List<Widget> children}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, {VoidCallback? onCopy}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 2,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 13.5,
              color: Colors.grey,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 3,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Flexible(
                child: Text(
                  value,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ),
              if (onCopy != null) ...[
                const SizedBox(width: 6),
                InkWell(
                  onTap: onCopy,
                  child: const Icon(
                    LucideIcons.copy,
                    size: 16,
                    color: Colors.blue,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatusChip({required String label, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }

  Color _getModerationColor(String status) {
    switch (status) {
      case 'APPROVED':
        return Colors.green;
      case 'PENDING':
        return Colors.orange;
      case 'REJECTED':
        return Colors.red;
      default:
        return Colors.blueGrey;
    }
  }

  String _getModerationLabel(String status) {
    switch (status) {
      case 'APPROVED':
        return 'Анкета одобрена';
      case 'PENDING':
        return 'На проверке';
      case 'REJECTED':
        return 'Анкета отклонена';
      case 'INCOMPLETE':
        return 'Заполняется';
      default:
        return status;
    }
  }

  Widget _buildStat(String label, String value, IconData icon, Color color) {
    return Column(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
      ],
    );
  }
}

// ==========================================
// FULL-SCREEN ZOOMABLE DOCUMENT VIEWER
// ==========================================
class _FullScreenDocumentViewer extends StatelessWidget {
  final String title;
  final String imageUrl;

  const _FullScreenDocumentViewer({
    required this.title,
    required this.imageUrl,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.external_link),
            tooltip: 'Открыть в браузере',
            onPressed: () async {
              final uri = Uri.tryParse(imageUrl);
              if (uri != null) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                minScale: 0.8,
                maxScale: 5.0,
                child: Image.network(
                  imageUrl,
                  fit: BoxFit.contain,
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    );
                  },
                  errorBuilder: (_, __, ___) => const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          LucideIcons.image_off,
                          color: Colors.white54,
                          size: 48,
                        ),
                        SizedBox(height: 12),
                        Text(
                          'Не удалось загрузить изображение',
                          style: TextStyle(color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 16,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'Используйте два пальца для увеличения',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
