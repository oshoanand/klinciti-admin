import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'dart:convert';

import 'package:url_launcher/url_launcher.dart';

import '../../../core/network/api_client.dart';
import '../../chat/data/chat_repository.dart';
import '../data/job_model.dart';
import '../providers/job_detail_provider.dart';

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
    if (mobile == null || mobile.isEmpty) return;

    // Clean the phone number (keep only digits and the plus sign)
    final cleanNumber = mobile.replaceAll(RegExp(r'[^\d+]'), '');
    final Uri launchUri = Uri(scheme: 'tel', path: cleanNumber);

    try {
      // ✅ Attempt to launch without relying solely on canLaunchUrl
      await launchUrl(launchUri, mode: LaunchMode.externalApplication);
    } catch (e) {
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
      if (mounted) context.push('/chat/${session.id}/$participantId');
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Ошибка создания чата')));
    }
  }

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
            content: Text('Исполнитель успешно снят'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ошибка снятия исполнителя'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  // ==========================================
  // API MUTATIONS
  // ==========================================
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
      ref.invalidate(jobAuditLogsProvider(widget.jobId)); // Refresh logs too

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Статус заказа обновлен'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ошибка обновления статуса'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  // ==========================================
  // MODALS
  // ==========================================
  void _showAssignWorkerModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _AssignWorkerBottomSheet(
        onWorkerSelected: (workerId) {
          Navigator.pop(context);
          _updateJobStatus('ACCEPTED', workerId: workerId);
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
      builder: (context) => _AuditLogsBottomSheet(
        job: job,
        statusTranslator: _getStatusText, // Pass the translation function
      ),
    );
  }

  void _showCancelDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Отменить заказ?'),
        content: const Text(
          'Вы уверены, что хотите отменить этот заказ? Это действие нельзя отменить.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Нет'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.pop(context);
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
      builder: (context) => AlertDialog(
        title: const Text('Снять исполнителя?'),
        content: const Text(
          'Вы уверены, что хотите снять текущего исполнителя? Заказ снова перейдет в статус поиска, и вам нужно будет назначить нового мастера.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            onPressed: () {
              Navigator.pop(context); // Close the dialog
              _unassignWorker(); // Call the API method
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
        elevation: 0,

        // Inside your build() method AppBar actions:
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
        error: (err, _) => Center(child: Text('Ошибка загрузки заказа: $err')),
        data: (job) => RefreshIndicator(
          onRefresh: () async =>
              ref.invalidate(jobDetailProvider(widget.jobId)),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeaderCard(job),
                const SizedBox(height: 16),

                if (job.customerId != null)
                  _buildProfileTile(
                    title: 'Заказчик',
                    name: job.customerName ?? 'Неизвестно',
                    mobile: job.customerMobile,
                    imageUrl: job.customerImage,
                    participantId: job.customerId!,
                  ),
                const SizedBox(height: 16),

                if (job.workerId != null)
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
                    job.description ?? 'Описание отсутствует',
                    style: const TextStyle(fontSize: 15),
                  ),
                ),

                const SizedBox(height: 24),

                if (job.status != 'COMPLETED' && job.status != 'CANCELLED')
                  _buildAdminActionPanel(job),

                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // UI Helpers (Same as before)
  Widget _buildHeaderCard(JobModel job) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
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
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: _getStatusColor(job.status).withOpacity(0.1),
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
              Text(
                '№ ${job.id.substring(0, 8).toUpperCase()}',
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
          if (job.subcategoryName != null)
            Text(
              job.subcategoryName!,
              style: const TextStyle(color: Colors.grey),
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
                backgroundImage: imageUrl != null
                    ? NetworkImage(imageUrl)
                    : null,
                child: imageUrl == null
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
                      mobile ?? 'Нет телефона',
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Действия администратора',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            // ✅ If NO worker is assigned, show Assign Button
            if (job.status == 'PENDING' && job.workerId == null)
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: _isProcessing ? null : _showAssignWorkerModal,
                  icon: _isProcessing
                      ? const SizedBox.shrink()
                      : const Icon(LucideIcons.user_check, color: Colors.white),
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

            // ✅ If a worker IS assigned (and job is active), show Unassign Button
            if (job.workerId != null &&
                (job.status == 'ACCEPTED' || job.status == 'ONGOING'))
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
// BOTTOM SHEET WIDGET: WORKER ASSIGNMENT
// ==========================================
class _AssignWorkerBottomSheet extends ConsumerWidget {
  final Function(String) onWorkerSelected;
  const _AssignWorkerBottomSheet({required this.onWorkerSelected});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // ✅ Now uses the new availableWorkersProvider
    final workersAsync = ref.watch(availableWorkersProvider);

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
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
                    'Выберите исполнителя',
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
              child: workersAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Ошибка загрузки: $e')),
                data: (workers) {
                  if (workers.isEmpty)
                    return const Center(
                      child: Text('Нет активных исполнителей'),
                    );

                  return ListView.separated(
                    controller: scrollController,
                    itemCount: workers.length,
                    separatorBuilder: (context, index) =>
                        const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final worker = workers[index];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundImage: worker.avatarUrl != null
                              ? NetworkImage(worker.avatarUrl!)
                              : null,
                          child: worker.avatarUrl == null
                              ? const Icon(LucideIcons.user)
                              : null,
                        ),
                        title: Text(worker.name),
                        subtitle: Text(worker.mobile ?? ''),
                        trailing: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                          ),
                          onPressed: () => onWorkerSelected(worker.id),
                          child: const Text(
                            'Выбрать',
                            style: TextStyle(color: Colors.white),
                          ),
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
  final String Function(String) statusTranslator;

  const _AuditLogsBottomSheet({
    required this.job,
    required this.statusTranslator,
  });
  Color _getEventColor(String eventType, String? newStatus) {
    if (newStatus == 'COMPLETED' || eventType == 'JOB_COMPLETED_BY_WORKER')
      return Colors.green;
    if (newStatus == 'CANCELLED' || newStatus == 'REFUSED') return Colors.red;
    if (eventType == 'WORKER_UNASSIGNED_BY_ADMIN')
      return Colors.orange; // ✅ Orange for unassign
    if (newStatus == 'ACCEPTED' || eventType == 'WORKER_ASSIGNED_BY_ADMIN')
      return Colors.blue;
    if (newStatus == 'ONGOING') return Colors.purple;
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
        return 'Исполнитель снят администратором'; // ✅ Translation added
      case 'JOB_COMPLETED_BY_WORKER':
        return 'Выполнено исполнителем';
      case 'JOB_PAID_BY_CUSTOMER':
        return 'Заказ оплачен';
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

                      Map<String, dynamic> payloadData = {};
                      if (log.payload != null) {
                        payloadData = log.payload!;
                      }

                      final newStatus = payloadData['newStatus'] as String?;
                      final workerAssignedId =
                          payloadData['workerAssigned'] as String?;

                      String? assignedName;
                      if (workerAssignedId != null) {
                        assignedName = (workerAssignedId == job.workerId)
                            ? job.workerName
                            : 'ID: ${workerAssignedId.substring(0, 8)}...';
                      }

                      final dotColor = _getEventColor(log.eventType, newStatus);

                      // ✅ Check if this is the creation event
                      final isCreationEvent =
                          log.eventType == 'JOB_CREATED_BY_CUSTOMER';

                      // ✅ Show the box if we have a status, a worker, OR it's a creation event
                      final showDetailsBox =
                          newStatus != null ||
                          assignedName != null ||
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
                                    color: dotColor.withOpacity(0.2),
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

                                  // Details Box
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
                                          // ✅ Display Customer Name on creation
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
