import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/network/api_client.dart';
import '../../chat/data/chat_repository.dart';
import '../providers/workers_provider.dart';
import '../data/worker_model.dart';

class WorkerDetailScreen extends ConsumerStatefulWidget {
  final String workerId;
  const WorkerDetailScreen({super.key, required this.workerId});

  @override
  ConsumerState<WorkerDetailScreen> createState() => _WorkerDetailScreenState();
}

class _WorkerDetailScreenState extends ConsumerState<WorkerDetailScreen> {
  bool _isProcessing = false;

  // ==========================================
  // HARDWARE INTEGRATIONS
  // ==========================================
  Future<void> _makeCall(String? mobile) async {
    if (mobile == null || mobile.isEmpty) return;

    // Clean the string: remove spaces, dashes, parentheses
    final Uri launchUri = Uri(
      scheme: 'tel',
      path: mobile.replaceAll(RegExp(r'[^\d+]'), ''),
    );

    try {
      if (await canLaunchUrl(launchUri)) {
        await launchUrl(launchUri);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Невозможно открыть набор номера на этом устройстве',
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ошибка при вызове номера')),
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ошибка создания чата. Попробуйте позже.'),
          ),
        );
      }
    }
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

      // If approving, also automatically set AUTH status to ACTIVE
      if (status == 'APPROVED') {
        await api.dio.patch(
          '/workers/admin/${widget.workerId}/auth-status',
          data: {'authStatus': 'ACTIVE'},
        );
      }

      // Invalidate caches to refresh data on screen
      ref.invalidate(workerDetailProvider(widget.workerId));
      ref.invalidate(workerStatsProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              status == 'APPROVED' ? 'Мастер одобрен' : 'Мастер отклонен',
            ),
            backgroundColor: status == 'APPROVED' ? Colors.green : Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ошибка при обновлении статуса модерации'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ошибка обновления статуса доступа')),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  // ==========================================
  // REJECTION DIALOG
  // ==========================================
  void _showRejectDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Причина отказа'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'Укажите причину для мастера...',
          ),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              if (controller.text.trim().isEmpty) return;
              Navigator.pop(context);
              _updateModeration('REJECTED', reason: controller.text.trim());
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

  // ==========================================
  // BUILD METHOD
  // ==========================================
  @override
  Widget build(BuildContext context) {
    final workerAsync = ref.watch(workerDetailProvider(widget.workerId));

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Профиль мастера'),
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (workerAsync.value != null &&
              workerAsync.value!.authStatus == 'ACTIVE')
            IconButton(
              icon: const Icon(LucideIcons.ban, color: Colors.red),
              tooltip: 'Заблокировать',
              onPressed: () => _updateAuthStatus('BLOCKED'),
            ),
          if (workerAsync.value != null &&
              workerAsync.value!.authStatus == 'BLOCKED')
            IconButton(
              icon: const Icon(LucideIcons.lock_open, color: Colors.green),
              tooltip: 'Разблокировать',
              onPressed: () => _updateAuthStatus('ACTIVE'),
            ),
        ],
      ),
      body: workerAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Ошибка загрузки профиля: $err')),
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
                // ==========================================
                // 1. HEADER CARD (Contact & Stats)
                // ==========================================
                Container(
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
                    children: [
                      CircleAvatar(
                        radius: 40,
                        backgroundColor: Colors.grey.shade100,
                        backgroundImage: worker.avatarUrl != null
                            ? NetworkImage(worker.avatarUrl!)
                            : null,
                        child: worker.avatarUrl == null
                            ? const Icon(
                                LucideIcons.user,
                                size: 40,
                                color: Colors.grey,
                              )
                            : null,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        worker.name,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        worker.mobile ?? 'Нет телефона',
                        style: const TextStyle(color: Colors.grey),
                      ),
                      const SizedBox(height: 16),

                      // Communication Buttons
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(
                            onPressed: () => _makeCall(worker.mobile),
                            icon: const Icon(
                              LucideIcons.phone,
                              color: Colors.green,
                            ),
                            style: IconButton.styleFrom(
                              backgroundColor: Colors.green.shade50,
                            ),
                            tooltip: 'Позвонить',
                          ),
                          const SizedBox(width: 16),
                          IconButton(
                            onPressed: _startChat,
                            icon: const Icon(
                              LucideIcons.message_circle,
                              color: Colors.blue,
                            ),
                            style: IconButton.styleFrom(
                              backgroundColor: Colors.blue.shade50,
                            ),
                            tooltip: 'Написать',
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
                            worker.rating.toString(),
                            LucideIcons.star,
                            Colors.amber,
                          ),
                          _buildStat(
                            'Заказов',
                            worker.totalJobsCompleted.toString(),
                            LucideIcons.circle_check,
                            Colors.green,
                          ),
                          _buildStat(
                            'Доход',
                            '${worker.totalIncome.toStringAsFixed(0)} ₽',
                            LucideIcons.wallet,
                            Colors.blue,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // ==========================================
                // 2. ACTION PANEL FOR PENDING MODERATION
                // ==========================================
                if (worker.moderationStatus == 'PENDING') ...[
                  const SizedBox(height: 24),
                  const Text(
                    'Решение по анкете',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: _isProcessing
                              ? null
                              : () => _updateModeration('APPROVED'),
                          child: _isProcessing
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text(
                                  'Одобрить',
                                  style: TextStyle(color: Colors.white),
                                ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: _isProcessing ? null : _showRejectDialog,
                          child: const Text(
                            'Отклонить',
                            style: TextStyle(color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],

                // Show Rejection Reason if previously rejected
                if (worker.moderationStatus == 'REJECTED' &&
                    worker.rejectionReason != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Icon(LucideIcons.circle_alert, color: Colors.red),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Причина отказа: ${worker.rejectionReason}',
                            style: const TextStyle(color: Colors.red),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                // ==========================================
                // 3. VERIFICATION DOCUMENTS (KYC)
                // ==========================================
                const SizedBox(height: 24),
                const Text(
                  'Документы (KYC)',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 120,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      if (worker.idDocumentFrontUrl != null)
                        _buildDocThumb(
                          'Паспорт (Лицевая)',
                          worker.idDocumentFrontUrl!,
                        ),
                      if (worker.selfieWithIdUrl != null)
                        _buildDocThumb(
                          'Селфи с паспортом',
                          worker.selfieWithIdUrl!,
                        ),
                      if (worker.idDocumentBackUrl != null)
                        _buildDocThumb(
                          'Паспорт (Оборот)',
                          worker.idDocumentBackUrl!,
                        ),
                      if (worker.driversLicenseUrl != null)
                        _buildDocThumb('ВУ', worker.driversLicenseUrl!),

                      // Empty state for docs
                      if (worker.idDocumentFrontUrl == null &&
                          worker.selfieWithIdUrl == null &&
                          worker.idDocumentBackUrl == null &&
                          worker.driversLicenseUrl == null)
                        const Padding(
                          padding: EdgeInsets.only(top: 16),
                          child: Text(
                            'Документы не загружены',
                            style: TextStyle(
                              color: Colors.grey,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),

                // ==========================================
                // 4. TRANSPORT INFO
                // ==========================================
                if (worker.hasVehicle) ...[
                  const SizedBox(height: 24),
                  const Text(
                    'Транспорт',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: ListTile(
                      leading: const Icon(
                        LucideIcons.car,
                        color: Colors.blueGrey,
                      ),
                      title: Text(
                        worker.vehicleModel ?? 'Модель не указана',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(worker.vehicleNumber ?? 'Номер не указан'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ==========================================
  // HELPER WIDGETS
  // ==========================================
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

  Widget _buildDocThumb(String label, String url) {
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: Column(
        children: [
          InkWell(
            onTap: () {
              // Optional: Open a full-screen image viewer here
            },
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                url,
                width: 90,
                height: 90,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  width: 90,
                  height: 90,
                  color: Colors.grey.shade200,
                  child: const Icon(LucideIcons.image_off, color: Colors.grey),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: 90, // Match image width
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                color: Colors.grey,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
