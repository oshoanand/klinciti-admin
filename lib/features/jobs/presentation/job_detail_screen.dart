import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exceptions.dart';
import '../../chat/data/chat_repository.dart';
import '../data/job_model.dart';
import '../providers/job_detail_provider.dart';

typedef JsonMap = Map<String, dynamic>;
typedef StringList = List<String>;
typedef WorkerSelectCallback = void Function(String workerId);
typedef StatusTranslator = String Function(String status);

class JobDetailScreen extends ConsumerStatefulWidget {
  final String jobId;
  const JobDetailScreen({super.key, required this.jobId});

  @override
  ConsumerState<JobDetailScreen> createState() => _JobDetailScreenState();
}

class _JobDetailScreenState extends ConsumerState<JobDetailScreen> {
  bool _isProcessing = false;

  // ==========================================
  // HARDWARE INTEGRATIONS
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
          const SnackBar(
            content: Text('Невозможно открыть набор номера на этом устройстве'),
          ),
        );
      }
    }
  }

  Future<void> _startChat(String participantId) async {
    try {
      final session = await ref
          .read(chatRepositoryProvider)
          .initiateChat(participantId);
      if (mounted) {
        context.push('/chat/${session.id}/$participantId');
      }
    } catch (e) {
      if (mounted) {
        final msg = ApiException.fromDioException(e).message;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка создания чата: $msg'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ==========================================
  // API MUTATIONS
  // ==========================================
  Future<void> _unassignWorker() async {
    setState(() => _isProcessing = true);
    try {
      await ref
          .read(apiClientProvider)
          .dio
          .patch('/jobs/admin/${widget.jobId}/unassign');

      ref.invalidate(jobDetailProvider(widget.jobId));
      ref.invalidate(jobAuditLogsProvider(widget.jobId));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Исполнитель успешно снят с заказа'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        final msg = ApiException.fromDioException(e).message;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  Future<void> _updateJobStatus(String status, {String? workerId}) async {
    setState(() => _isProcessing = true);
    try {
      await ref
          .read(apiClientProvider)
          .dio
          .patch(
            '/jobs/admin/${widget.jobId}/status',
            data: {
              'status': status,
              if (workerId != null) 'workerId': workerId,
            },
          );

      ref.invalidate(jobDetailProvider(widget.jobId));
      ref.invalidate(jobAuditLogsProvider(widget.jobId));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              workerId != null
                  ? 'Исполнитель успешно назначен'
                  : 'Статус заказа обновлен',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        final msg = ApiException.fromDioException(e).message;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  Future<void> _updatePaymentStatus(String paymentStatus) async {
    setState(() => _isProcessing = true);
    try {
      final response = await ref
          .read(apiClientProvider)
          .dio
          .patch(
            '/jobs/admin/${widget.jobId}/payment-status',
            data: {'paymentStatus': paymentStatus},
          );

      ref.invalidate(jobDetailProvider(widget.jobId));
      ref.invalidate(jobAuditLogsProvider(widget.jobId));

      final msg = (response.data is Map && response.data['message'] != null)
          ? response.data['message'].toString()
          : 'Статус оплаты обновлен';

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            backgroundColor: paymentStatus == 'PAID'
                ? Colors.green
                : Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        final msg = ApiException.fromDioException(e).message;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  Future<void> _broadcastToEligibleWorkers({
    String? customMessage,
    required bool onlySameCity,
  }) async {
    setState(() => _isProcessing = true);
    try {
      final response = await ref
          .read(apiClientProvider)
          .dio
          .post(
            '/jobs/admin/${widget.jobId}/broadcast',
            data: {
              if (customMessage != null && customMessage.trim().isNotEmpty)
                'customMessage': customMessage.trim(),
              'onlySameCity': onlySameCity,
            },
          );

      ref.invalidate(jobDetailProvider(widget.jobId));
      ref.invalidate(jobAuditLogsProvider(widget.jobId));

      final msg = (response.data is Map && response.data['message'] != null)
          ? response.data['message'].toString()
          : 'Рассылка выполнена';
      final sentCount =
          (response.data is Map && response.data['sentCount'] != null)
          ? int.tryParse(response.data['sentCount'].toString()) ?? 0
          : 0;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            backgroundColor: sentCount > 0 ? Colors.green : Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        final msg = ApiException.fromDioException(e).message;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  // ==========================================
  // MODALS & DIALOGS
  // ==========================================
  void _showAssignWorkerModal(JobModel job) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => _AssignWorkerBottomSheet(
        job: job,
        onWorkerSelected: (workerId) {
          Navigator.pop(sheetContext);
          _updateJobStatus('ACCEPTED', workerId: workerId);
        },
      ),
    );
  }

  void _showBroadcastDialog(JobModel job) {
    final msgController = TextEditingController();
    bool onlySameCity = job.city != null && job.city!.trim().isNotEmpty;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            title: const Row(
              children: [
                Icon(LucideIcons.megaphone, color: Colors.indigo, size: 22),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Push-рассылка мастерам',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Уведомление получат только активные и одобренные мастера, зарегистрированные в категории «${job.categoryName ?? "Услуга"}»${job.subcategoryName != null ? " (${job.subcategoryName})" : ""}.',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade700,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: msgController,
                    maxLines: 3,
                    maxLength: 250,
                    decoration: InputDecoration(
                      labelText: 'Текст сообщения (необязательно)',
                      hintText: 'Оставьте пустым для стандартного текста с ценой и адресом...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  if (job.city != null && job.city!.trim().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      value: onlySameCity,
                      activeColor: Colors.indigo,
                      title: Text(
                        'Только мастерам из г. ${job.city}',
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      onChanged: (val) =>
                          setDialogState(() => onlySameCity = val ?? false),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Отмена'),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo,
                  foregroundColor: Colors.white,
                ),
                onPressed: () {
                  Navigator.pop(dialogContext);
                  _broadcastToEligibleWorkers(
                    customMessage: msgController.text,
                    onlySameCity: onlySameCity,
                  );
                },
                icon: const Icon(LucideIcons.send, size: 16),
                label: const Text('Отправить Push'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showAuditLogsModal(JobModel job) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) =>
          _AuditLogsBottomSheet(job: job, statusTranslator: _getStatusText),
    );
  }

  void _showCancelDialog() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Отменить заказ?'),
        content: const Text(
          'Вы уверены, что хотите отменить этот заказ? Это действие нельзя отменить.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Нет'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.pop(dialogContext);
              _updateJobStatus('CANCELLED');
            },
            child: const Text(
              'Да, отменить',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  void _showUnassignDialog() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Снять исполнителя?'),
        content: const Text(
          'Вы уверены, что хотите снять текущего исполнителя? Заказ снова перейдет в статус поиска, и вам нужно будет назначить нового мастера.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            onPressed: () {
              Navigator.pop(dialogContext);
              _unassignWorker();
            },
            child: const Text(
              'Да, снять',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  void _openPhotoGalleryViewer({
    required String title,
    required StringList photos,
    required int initialIndex,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _FullScreenGalleryViewer(
          title: title,
          photos: photos,
          initialIndex: initialIndex,
        ),
      ),
    );
  }

  // ==========================================
  // BUILD METHOD
  // ==========================================
  @override
  Widget build(BuildContext context) {
    final jobAsync = ref.watch(jobDetailProvider(widget.jobId));

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Детали заказа'),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        actions: [
          jobAsync.when(
            data: (job) => IconButton(
              icon: const Icon(LucideIcons.timeline, color: Colors.blueGrey),
              tooltip: 'История изменений',
              onPressed: () => _showAuditLogsModal(job),
            ),
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),
        ],
      ),
      body: jobAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  LucideIcons.circle_alert,
                  color: Colors.red,
                  size: 40,
                ),
                const SizedBox(height: 12),
                Text(
                  'Ошибка загрузки заказа: $err',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () =>
                      ref.invalidate(jobDetailProvider(widget.jobId)),
                  icon: const Icon(LucideIcons.refresh_cw, size: 16),
                  label: const Text('Повторить'),
                ),
              ],
            ),
          ),
        ),
        data: (job) => RefreshIndicator(
          onRefresh: () async =>
              ref.invalidate(jobDetailProvider(widget.jobId)),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. LIVE SLA TIMER & STALE-JOB ALERT BANNER (when PENDING & unassigned)
                if (job.isWaitingForWorker) ...[
                  _SlaAlertBanner(
                    job: job,
                    onBroadcastTap: _isProcessing
                        ? null
                        : () => _showBroadcastDialog(job),
                    onAssignTap: _isProcessing
                        ? null
                        : () => _showAssignWorkerModal(job),
                  ),
                  const SizedBox(height: 16),
                ],

                // 2. HEADER CARD
                _buildHeaderCard(job),
                const SizedBox(height: 16),

                // 3. CUSTOMER & WORKER TILES
                if (job.customerId != null && job.customerId!.isNotEmpty)
                  _buildProfileTile(
                    title: 'Заказчик',
                    name: job.customerName ?? 'Неизвестно',
                    mobile: job.customerMobile,
                    imageUrl: job.customerImage,
                    participantId: job.customerId!,
                  ),
                const SizedBox(height: 16),

                if (job.workerId != null && job.workerId!.isNotEmpty)
                  _buildProfileTile(
                    title: 'Исполнитель',
                    name: job.workerName ?? 'Неизвестно',
                    mobile: job.workerMobile,
                    imageUrl: job.workerImage,
                    participantId: job.workerId!,
                  )
                else
                  _buildEmptyWorkerTile(),

                const SizedBox(height: 24),

                // 4. DESCRIPTION
                const Text(
                  'Описание задачи',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Text(
                    (job.description != null &&
                            job.description!.trim().isNotEmpty)
                        ? job.description!
                        : 'Описание отсутствует',
                    style: const TextStyle(fontSize: 15, height: 1.4),
                  ),
                ),

                // 5. BEFORE / AFTER COMPLETION PHOTO VERIFICATION
                const SizedBox(height: 24),
                _buildBeforeAfterPhotoSection(job),

                // 6. ADMIN ACTION PANEL
                const SizedBox(height: 24),
                if (job.status != 'CANCELLED') _buildAdminActionPanel(job),

                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ==========================================
  // BEFORE / AFTER PHOTO VERIFICATION SECTION
  // ==========================================
  Widget _buildBeforeAfterPhotoSection(JobModel job) {
    final hasBefore = job.photos.isNotEmpty;
    final hasAfter = job.completionPhotos.isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                LucideIcons.camera,
                size: 18,
                color: Color(0xFF0F172A),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Фотоконтроль (ДО и ПОСЛЕ)',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ),
              if (hasAfter)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Отчет загружен (${job.completionPhotos.length})',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.bold,
                      color: Colors.green.shade800,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),

          // Customer "BEFORE" Photos
          Text(
            'Фото ДО начала работ (от заказчика: ${job.photos.length})',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 8),
          if (!hasBefore)
            _buildEmptyPhotosPlaceholder('Заказчик не прикрепил исходные фото')
          else
            _buildHorizontalPhotoStrip(
              title: 'Фото ДО (Заказчик)',
              photos: job.photos,
              badgeColor: Colors.blue,
              badgeText: 'ДО',
            ),

          const Divider(height: 28),

          // Worker "AFTER" Completion Photos
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Фото ПОСЛЕ выполнения (от мастера: ${job.completionPhotos.length})',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade700,
                ),
              ),
              if (job.completedAt != null)
                Text(
                  DateFormat('dd.MM HH:mm').format(job.completedAt!.toLocal()),
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (!hasAfter)
            _buildEmptyPhotosPlaceholder(
              job.status == 'COMPLETED'
                  ? 'Заказ завершен без загрузки фотоотчета'
                  : 'Фотоотчет появится после завершения работы мастером',
            )
          else
            _buildHorizontalPhotoStrip(
              title: 'Фото ПОСЛЕ (Мастер)',
              photos: job.completionPhotos,
              badgeColor: Colors.green,
              badgeText: 'ПОСЛЕ',
            ),

          // Payment & Quality Verification Action inside the card when COMPLETED
          if (job.status == 'COMPLETED') ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: job.paymentStatus == 'PAID'
                    ? Colors.green.shade50
                    : Colors.amber.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: job.paymentStatus == 'PAID'
                      ? Colors.green.shade200
                      : Colors.amber.shade300,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    job.paymentStatus == 'PAID'
                        ? LucideIcons.circle_check
                        : LucideIcons.clock,
                    color: job.paymentStatus == 'PAID'
                        ? Colors.green.shade700
                        : Colors.amber.shade900,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      job.paymentStatus == 'PAID'
                          ? 'Фотоотчет проверен • Оплата подтверждена (PAID)'
                          : 'Ожидает подтверждения оплаты (PAYMENT_PENDING)',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: job.paymentStatus == 'PAID'
                            ? Colors.green.shade900
                            : Colors.amber.shade900,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (job.paymentStatus != 'PAID')
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: _isProcessing
                          ? null
                          : () => _updatePaymentStatus('PAID'),
                      child: const Text(
                        'Подтвердить',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    )
                  else
                    TextButton(
                      onPressed: _isProcessing
                          ? null
                          : () => _updatePaymentStatus('PENDING'),
                      child: const Text(
                        'Отменить',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyPhotosPlaceholder(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(LucideIcons.image, size: 18, color: Colors.grey.shade400),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12.5,
                color: Colors.grey.shade500,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHorizontalPhotoStrip({
    required String title,
    required StringList photos,
    required Color badgeColor,
    required String badgeText,
  }) {
    return SizedBox(
      height: 110,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: photos.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final photoUrl = photos[index];
          return GestureDetector(
            onTap: () => _openPhotoGalleryViewer(
              title: title,
              photos: photos,
              initialIndex: index,
            ),
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    photoUrl,
                    width: 110,
                    height: 110,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      width: 110,
                      height: 110,
                      color: Colors.grey.shade200,
                      child: const Icon(
                        LucideIcons.image_off,
                        color: Colors.grey,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 6,
                  top: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: badgeColor.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      badgeText,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: 6,
                  bottom: 6,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Colors.black54,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      LucideIcons.maximize_2,
                      size: 12,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ==========================================
  // UI HELPERS
  // ==========================================
  Widget _buildHeaderCard(JobModel job) {
    final shortId = job.id.length >= 8
        ? job.id.substring(0, 8).toUpperCase()
        : job.id.toUpperCase();

    return Container(
      padding: const EdgeInsets.all(16),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Wrap(
                spacing: 8,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: _getStatusColor(job.status).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      _getStatusText(job.status),
                      style: TextStyle(
                        color: _getStatusColor(job.status),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  if (job.status == 'COMPLETED')
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: job.paymentStatus == 'PAID'
                            ? Colors.green.shade50
                            : Colors.amber.shade50,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        job.paymentStatus == 'PAID' ? 'Оплачен' : 'Ждет оплаты',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: job.paymentStatus == 'PAID'
                              ? Colors.green.shade800
                              : Colors.amber.shade900,
                        ),
                      ),
                    ),
                ],
              ),
              Text(
                '№ $shortId',
                style: const TextStyle(
                  color: Colors.grey,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            job.categoryName ?? 'Без категории',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          if (job.subcategoryName != null &&
              job.subcategoryName!.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                job.subcategoryName!,
                style: const TextStyle(color: Colors.grey, fontSize: 14),
              ),
            ),
          const Divider(height: 32),
          Row(
            children: [
              const Icon(LucideIcons.wallet, size: 20, color: Colors.blue),
              const SizedBox(width: 8),
              Text(
                job.budget != null
                    ? '${job.budget!.toStringAsFixed(0)} ₽'
                    : 'Не указан',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(LucideIcons.map_pin, size: 20, color: Colors.red),
              const SizedBox(width: 8),
              Expanded(child: Text(job.pickupAddress ?? 'Адрес не указан')),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(LucideIcons.calendar, size: 20, color: Colors.orange),
              const SizedBox(width: 8),
              Text(
                DateFormat('dd.MM.yyyy HH:mm').format(job.createdAt.toLocal()),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildProfileTile({
    required String title,
    required String name,
    required String? mobile,
    required String? imageUrl,
    required String participantId,
  }) {
    final hasImage = imageUrl != null && imageUrl.trim().isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 14,
            color: Colors.grey,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: Colors.grey.shade100,
                backgroundImage: hasImage ? NetworkImage(imageUrl) : null,
                child: !hasImage
                    ? const Icon(LucideIcons.user, color: Colors.grey)
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      (mobile != null && mobile.trim().isNotEmpty)
                          ? mobile
                          : 'Нет телефона',
                      style: const TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(LucideIcons.phone, color: Colors.green),
                onPressed: () => _makeCall(mobile),
              ),
              IconButton(
                icon: const Icon(
                  LucideIcons.message_circle,
                  color: Colors.blue,
                ),
                onPressed: () => _startChat(participantId),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyWorkerTile() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Исполнитель',
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.orange.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.orange.shade200),
          ),
          child: const Row(
            children: [
              Icon(LucideIcons.circle_alert, color: Colors.orange),
              SizedBox(width: 12),
              Text(
                'Исполнитель еще не назначен',
                style: TextStyle(
                  color: Colors.orange,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAdminActionPanel(JobModel job) {
    final hasNoWorker = job.workerId == null || job.workerId!.trim().isEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Действия администратора',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),

        // Broadcast Push Button (Available whenever job is PENDING)
        if (job.status == 'PENDING' && hasNoWorker) ...[
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.indigo,
                side: BorderSide(color: Colors.indigo.shade300, width: 1.5),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: _isProcessing ? null : () => _showBroadcastDialog(job),
              icon: const Icon(LucideIcons.megaphone, size: 18),
              label: Text(
                job.lastBroadcastAt != null
                    ? 'Повторить Push-рассылку подходящим мастерам'
                    : 'Разослать Push-уведомление подходящим мастерам',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],

        if (job.status != 'COMPLETED')
          Row(
            children: [
              // 1. If NO worker is assigned, show Assign Button
              if (job.status == 'PENDING' && hasNoWorker) ...[
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: _isProcessing
                        ? null
                        : () => _showAssignWorkerModal(job),
                    icon: _isProcessing
                        ? const SizedBox.shrink()
                        : const Icon(
                            LucideIcons.user_check,
                            color: Colors.white,
                          ),
                    label: _isProcessing
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text(
                            'Назначить',
                            style: TextStyle(color: Colors.white),
                          ),
                  ),
                ),
                const SizedBox(width: 12),
              ],

              // 2. If a worker IS assigned (and job is active), show Unassign Button
              if (!hasNoWorker &&
                  (job.status == 'ACCEPTED' || job.status == 'ONGOING')) ...[
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange.shade50,
                      foregroundColor: Colors.orange,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: _isProcessing ? null : _showUnassignDialog,
                    icon: const Icon(LucideIcons.user_minus),
                    label: const Text('Снять исполнителя'),
                  ),
                ),
                const SizedBox(width: 12),
              ],

              // 3. Cancel Job Button
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade50,
                    foregroundColor: Colors.red,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: _isProcessing ? null : _showCancelDialog,
                  icon: const Icon(LucideIcons.circle_x),
                  label: const Text('Отменить заказ'),
                ),
              ),
            ],
          ),
      ],
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'PENDING':
        return Colors.orange;
      case 'ACCEPTED':
        return Colors.blue;
      case 'ONGOING':
        return Colors.purple;
      case 'COMPLETED':
        return Colors.green;
      case 'CANCELLED':
        return Colors.red;
      case 'DISPUTED':
        return Colors.redAccent;
      default:
        return Colors.grey;
    }
  }

  String _getStatusText(String status) {
    switch (status) {
      case 'PENDING':
        return 'Поиск исполнителя';
      case 'ACCEPTED':
        return 'Принят';
      case 'ONGOING':
        return 'В процессе';
      case 'COMPLETED':
        return 'Завершен';
      case 'CANCELLED':
        return 'Отменен';
      case 'DISPUTED':
        return 'Спор';
      default:
        return status;
    }
  }
}

// ==========================================
// LIVE SLA TIMER & STALE-JOB ALERT BANNER
// ==========================================
class _SlaAlertBanner extends StatefulWidget {
  final JobModel job;
  final VoidCallback? onBroadcastTap;
  final VoidCallback? onAssignTap;

  const _SlaAlertBanner({
    required this.job,
    this.onBroadcastTap,
    this.onAssignTap,
  });

  @override
  State<_SlaAlertBanner> createState() => _SlaAlertBannerState();
}

class _SlaAlertBannerState extends State<_SlaAlertBanner> {
  Timer? _timer;
  late Duration _elapsed;

  @override
  void initState() {
    super.initState();
    _elapsed = DateTime.now().difference(widget.job.createdAt.toLocal());
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {
          _elapsed = DateTime.now().difference(widget.job.createdAt.toLocal());
        });
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final totalSeconds = d.inSeconds < 0 ? 0 : d.inSeconds;
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;

    final hStr = hours.toString().padLeft(2, '0');
    final mStr = minutes.toString().padLeft(2, '0');
    final sStr = seconds.toString().padLeft(2, '0');
    return hours > 0 ? '$hStr:$mStr:$sStr' : '$mStr:$sStr';
  }

  @override
  Widget build(BuildContext context) {
    final mins = _elapsed.inMinutes;
    final isCritical = mins >= 30;
    final isWarning = mins >= 15 && mins < 30;

    final Color bgColor = isCritical
        ? Colors.red.shade50
        : (isWarning ? Colors.amber.shade50 : Colors.blue.shade50);
    final Color borderColor = isCritical
        ? Colors.red.shade300
        : (isWarning ? Colors.amber.shade300 : Colors.blue.shade200);
    final Color textColor = isCritical
        ? Colors.red.shade900
        : (isWarning ? Colors.amber.shade900 : Colors.blue.shade900);

    final String headline = isCritical
        ? 'Нарушение SLA! Заказ без мастера более 30 мин'
        : (isWarning
              ? 'Внимание SLA: клиент ждет назначения более 15 мин'
              : 'Ожидание назначения исполнителя');

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor, width: isCritical ? 1.5 : 1.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isCritical ? LucideIcons.flame : LucideIcons.clock,
                color: textColor,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  headline,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13.5,
                    color: textColor,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: borderColor),
                ),
                child: Text(
                  _formatDuration(_elapsed),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: textColor,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
          if (widget.job.lastBroadcastAt != null) ...[
            const SizedBox(height: 6),
            Text(
              'Последняя Push-рассылка: ${DateFormat('HH:mm').format(widget.job.lastBroadcastAt!.toLocal())}',
              style: TextStyle(
                fontSize: 12,
                color: textColor.withValues(alpha: 0.8),
              ),
            ),
          ],
          if (isWarning || isCritical) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isCritical
                          ? Colors.red
                          : Colors.amber.shade800,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: widget.onBroadcastTap,
                    icon: const Icon(LucideIcons.megaphone, size: 16),
                    label: const Text(
                      'Push-рассылка',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: textColor,
                      side: BorderSide(color: borderColor),
                      backgroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: widget.onAssignTap,
                    icon: const Icon(LucideIcons.user_check, size: 16),
                    label: const Text(
                      'Выбрать вручную',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ==========================================
// FULL-SCREEN ZOOMABLE PHOTO GALLERY VIEWER
// ==========================================
class _FullScreenGalleryViewer extends StatefulWidget {
  final String title;
  final StringList photos;
  final int initialIndex;

  const _FullScreenGalleryViewer({
    required this.title,
    required this.photos,
    required this.initialIndex,
  });

  @override
  State<_FullScreenGalleryViewer> createState() =>
      _FullScreenGalleryViewerState();
}

class _FullScreenGalleryViewerState extends State<_FullScreenGalleryViewer> {
  late PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          '${widget.title} (${_currentIndex + 1}/${widget.photos.length})',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      body: PageView.builder(
        controller: _pageController,
        itemCount: widget.photos.length,
        onPageChanged: (idx) => setState(() => _currentIndex = idx),
        itemBuilder: (context, index) {
          return InteractiveViewer(
            minScale: 0.8,
            maxScale: 5.0,
            child: Center(
              child: Image.network(
                widget.photos[index],
                fit: BoxFit.contain,
                loadingBuilder: (ctx, child, progress) {
                  if (progress == null) return child;
                  return const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  );
                },
                errorBuilder: (_, __, ___) => const Center(
                  child: Icon(
                    LucideIcons.image_off,
                    color: Colors.white54,
                    size: 48,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ==========================================
// BOTTOM SHEET WIDGET: CATEGORY-FILTERED WORKER ASSIGNMENT
// ==========================================
class _AssignWorkerBottomSheet extends ConsumerStatefulWidget {
  final JobModel job;
  final WorkerSelectCallback onWorkerSelected;

  const _AssignWorkerBottomSheet({
    required this.job,
    required this.onWorkerSelected,
  });

  @override
  ConsumerState<_AssignWorkerBottomSheet> createState() =>
      _AssignWorkerBottomSheetState();
}

class _AssignWorkerBottomSheetState
    extends ConsumerState<_AssignWorkerBottomSheet> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  StringList _buildRequiredBadges() {
    final StringList badges = [];
    if (widget.job.categoryName != null &&
        widget.job.categoryName!.trim().isNotEmpty) {
      badges.add(widget.job.categoryName!.trim());
    }
    if (widget.job.subcategoryName != null &&
        widget.job.subcategoryName!.trim().isNotEmpty) {
      for (final sub in widget.job.subcategoryName!.split(',')) {
        final trimmed = sub.trim();
        if (trimmed.isNotEmpty && !badges.contains(trimmed)) {
          badges.add(trimmed);
        }
      }
    }
    return badges;
  }

  @override
  Widget build(BuildContext context) {
    final workersAsync = ref.watch(availableWorkersForJobProvider(widget.job));
    final requiredBadges = _buildRequiredBadges();

    return DraggableScrollableSheet(
      initialChildSize: 0.78,
      minChildSize: 0.5,
      maxChildSize: 0.94,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Expanded(
                    child: Text(
                      'Подходящие исполнители',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(LucideIcons.refresh_cw, size: 18),
                    tooltip: 'Обновить список',
                    onPressed: () => ref.invalidate(
                      availableWorkersForJobProvider(widget.job),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(LucideIcons.x),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            if (requiredBadges.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Фильтр по специализации заказа:',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: requiredBadges.map((badge) {
                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.blue.shade200),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                LucideIcons.check_check,
                                size: 13,
                                color: Colors.blue.shade700,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                badge,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.blue.shade900,
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: TextField(
                controller: _searchController,
                onChanged: (val) =>
                    setState(() => _searchQuery = val.trim().toLowerCase()),
                decoration: InputDecoration(
                  hintText: 'Поиск по имени, телефону или городу...',
                  prefixIcon: const Icon(LucideIcons.search, size: 18),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(LucideIcons.x, size: 16),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                  isDense: true,
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.shade200),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Divider(height: 1),

            Expanded(
              child: workersAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          LucideIcons.circle_alert,
                          color: Colors.red,
                          size: 36,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Ошибка загрузки исполнителей: $e',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton(
                          onPressed: () => ref.invalidate(
                            availableWorkersForJobProvider(widget.job),
                          ),
                          child: const Text('Повторить'),
                        ),
                      ],
                    ),
                  ),
                ),
                data: (workers) {
                  final filtered = _searchQuery.isEmpty
                      ? workers
                      : workers.where((w) {
                          final nameMatch = w.name.toLowerCase().contains(
                            _searchQuery,
                          );
                          final phoneMatch = (w.mobile ?? '')
                              .toLowerCase()
                              .contains(_searchQuery);
                          final cityMatch = (w.city ?? '')
                              .toLowerCase()
                              .contains(_searchQuery);
                          return nameMatch || phoneMatch || cityMatch;
                        }).toList();

                  if (filtered.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              LucideIcons.user_x,
                              size: 48,
                              color: Colors.grey.shade400,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              workers.isEmpty
                                  ? 'Нет активных подтвержденных исполнителей, зарегистрированных во всех категориях и подкатегориях этого заказа.'
                                  : 'По вашему запросу исполнители не найдены.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  return ListView.separated(
                    controller: scrollController,
                    itemCount: filtered.length,
                    separatorBuilder: (context, index) =>
                        const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final worker = filtered[index];
                      final hasAvatar =
                          worker.avatarUrl != null &&
                          worker.avatarUrl!.trim().isNotEmpty;

                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        leading: CircleAvatar(
                          radius: 24,
                          backgroundColor: Colors.blueGrey.shade50,
                          backgroundImage: hasAvatar
                              ? NetworkImage(worker.avatarUrl!)
                              : null,
                          child: !hasAvatar
                              ? const Icon(LucideIcons.user)
                              : null,
                        ),
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(
                                worker.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                            const Icon(
                              Icons.star_rounded,
                              size: 16,
                              color: Colors.amber,
                            ),
                            const SizedBox(width: 2),
                            Text(
                              worker.rating.toStringAsFixed(1),
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 2),
                            Text(
                              [
                                if (worker.mobile != null &&
                                    worker.mobile!.isNotEmpty)
                                  worker.mobile!,
                                if (worker.city != null &&
                                    worker.city!.isNotEmpty)
                                  worker.city!,
                                if (worker.hasVehicle) 'Есть авто',
                              ].join(' • '),
                              style: TextStyle(
                                fontSize: 12.5,
                                color: Colors.grey.shade700,
                              ),
                            ),
                            if (worker.categoryNames.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                worker.categoryNames.join(', '),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: Colors.blue.shade700,
                                ),
                              ),
                            ],
                          ],
                        ),
                        trailing: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          onPressed: () => widget.onWorkerSelected(worker.id),
                          child: const Text('Выбрать'),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

// ==========================================
// BOTTOM SHEET WIDGET: AUDIT LOGS
// ==========================================
class _AuditLogsBottomSheet extends ConsumerWidget {
  final JobModel job;
  final StatusTranslator statusTranslator;

  const _AuditLogsBottomSheet({
    required this.job,
    required this.statusTranslator,
  });

  Color _getEventColor(String eventType, String? newStatus) {
    if (newStatus == 'COMPLETED' ||
        eventType == 'JOB_COMPLETED_BY_WORKER' ||
        eventType == 'JOB_PAID_BY_CUSTOMER') {
      return Colors.green;
    }
    if (newStatus == 'CANCELLED' || newStatus == 'REFUSED') {
      return Colors.red;
    }
    if (eventType == 'WORKER_UNASSIGNED_BY_ADMIN' ||
        eventType == 'WORKER_REVOKED_BY_ADMIN') {
      return Colors.orange;
    }
    if (eventType == 'JOB_BROADCAST_SENT_BY_ADMIN') {
      return Colors.indigo;
    }
    if (newStatus == 'ACCEPTED' || eventType == 'WORKER_ASSIGNED_BY_ADMIN') {
      return Colors.blue;
    }
    if (newStatus == 'ONGOING') {
      return Colors.purple;
    }
    return Colors.grey.shade400;
  }

  String _formatEventName(String eventType) {
    switch (eventType) {
      case 'JOB_STATUS_CHANGED_BY_ADMIN':
        return 'Статус изменен администратором';
      case 'JOB_CREATED_BY_CUSTOMER':
        return 'Заказ создан';
      case 'WORKER_ASSIGNED_BY_ADMIN':
        return 'Назначен исполнитель';
      case 'WORKER_UNASSIGNED_BY_ADMIN':
      case 'WORKER_REVOKED_BY_ADMIN':
        return 'Исполнитель снят администратором';
      case 'JOB_BROADCAST_SENT_BY_ADMIN':
        return 'Отправлена Push-рассылка мастерам';
      case 'JOB_PRICE_NEGOTIATED_BY_ADMIN':
        return 'Стоимость изменена администратором';
      case 'JOB_COMPLETED_BY_WORKER':
        return 'Выполнено мастером (загружен фотоотчет)';
      case 'JOB_PAID_BY_CUSTOMER':
        return 'Оплата подтверждена (PAID)';
      case 'JOB_PAYMENT_REVERTED_BY_ADMIN':
        return 'Статус оплаты возвращен в ожидание';
      default:
        return eventType;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logsAsync = ref.watch(jobAuditLogsProvider(job.id));

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'История заказа',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    icon: const Icon(LucideIcons.x),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Expanded(
              child: logsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) =>
                    Center(child: Text('Ошибка загрузки истории: $e')),
                data: (logs) {
                  if (logs.isEmpty) {
                    return const Center(
                      child: Text(
                        'История пуста',
                        style: TextStyle(color: Colors.grey),
                      ),
                    );
                  }

                  return ListView.builder(
                    controller: scrollController,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    itemCount: logs.length,
                    itemBuilder: (context, index) {
                      final log = logs[index];

                      final localDate = log.createdAt.isUtc
                          ? log.createdAt.toLocal()
                          : log.createdAt;
                      final timeStr = DateFormat('dd.MM.yyyy HH:mm')
                          .format(localDate);

                      JsonMap payloadData = JsonMap();
                      if (log.payload != null) {
                        payloadData = log.payload!;
                      }

                      final newStatus = payloadData['newStatus']?.toString();
                      final workerAssignedId =
                          (payloadData['workerAssigned'] ??
                                  payloadData['workerId'])
                              ?.toString();
                      final newBudget = payloadData['newBudget']?.toString();
                      final sentCount = payloadData['sentCount']?.toString();
                      final photosCount = payloadData['completionPhotosCount']
                          ?.toString();

                      String? assignedName;
                      if (workerAssignedId != null &&
                          workerAssignedId.isNotEmpty) {
                        assignedName =
                            (workerAssignedId == job.workerId &&
                                job.workerName != null)
                            ? job.workerName
                            : 'ID: ${workerAssignedId.length >= 8 ? workerAssignedId.substring(0, 8) : workerAssignedId}...';
                      }

                      final dotColor = _getEventColor(log.eventType, newStatus);
                      final isCreationEvent =
                          log.eventType == 'JOB_CREATED_BY_CUSTOMER';
                      final showDetailsBox =
                          newStatus != null ||
                          assignedName != null ||
                          newBudget != null ||
                          sentCount != null ||
                          photosCount != null ||
                          isCreationEvent;

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 16.0),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Column(
                              children: [
                                Icon(
                                  LucideIcons.circle_dot,
                                  color: dotColor,
                                  size: 16,
                                ),
                                if (index != logs.length - 1)
                                  Container(
                                    height: showDetailsBox ? 70 : 50,
                                    width: 2,
                                    color: dotColor.withValues(alpha: 0.2),
                                  ),
                              ],
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _formatEventName(log.eventType),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    timeStr,
                                    style: const TextStyle(
                                      color: Colors.grey,
                                      fontSize: 12,
                                    ),
                                  ),
                                  if (showDetailsBox)
                                    Container(
                                      margin: const EdgeInsets.only(top: 8),
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: Colors.grey.shade50,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: Colors.grey.shade200,
                                        ),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          if (isCreationEvent &&
                                              job.customerName != null)
                                            Text(
                                              'Заказчик: ${job.customerName}',
                                              style: const TextStyle(
                                                fontSize: 13,
                                                color: Colors.blueGrey,
                                              ),
                                            ),
                                          if (newStatus != null)
                                            Padding(
                                              padding: EdgeInsets.only(
                                                top: isCreationEvent ? 4.0 : 0,
                                              ),
                                              child: Text(
                                                'Новый статус: ${statusTranslator(newStatus)}',
                                                style: const TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ),
                                          if (newBudget != null)
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                top: 4.0,
                                              ),
                                              child: Text(
                                                'Новая цена: $newBudget ₽',
                                                style: const TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ),
                                          if (sentCount != null)
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                top: 4.0,
                                              ),
                                              child: Text(
                                                'Охвачено мастеров: $sentCount чел.',
                                                style: const TextStyle(
                                                  fontSize: 13,
                                                  color: Colors.indigo,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ),
                                          if (photosCount != null)
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                top: 4.0,
                                              ),
                                              child: Text(
                                                'Прикреплено фото ПОСЛЕ: $photosCount шт.',
                                                style: const TextStyle(
                                                  fontSize: 13,
                                                  color: Colors.green,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ),
                                          if (assignedName != null)
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                top: 4.0,
                                              ),
                                              child: Text(
                                                'Исполнитель: $assignedName',
                                                style: const TextStyle(
                                                  fontSize: 13,
                                                  color: Colors.blueGrey,
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
