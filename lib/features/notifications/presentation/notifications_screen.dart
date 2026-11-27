import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exceptions.dart';
import '../../../core/router/route_names.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../shared/widgets/global_error_widget.dart';
import '../providers/notification_provider.dart';

class NotifStyle {
  final IconData icon;
  final Color bgColor;
  final Color iconColor;

  const NotifStyle(this.icon, this.bgColor, this.iconColor);
}

NotifStyle _getStyle(String type, String subType) {
  final upperType = type.toUpperCase();
  final upperSub = subType.toUpperCase();

  if (upperSub.startsWith('ADMIN_WORKER_') ||
      upperSub == 'ADMIN_CASH_DISPUTE') {
    return NotifStyle(
      LucideIcons.banknote,
      Colors.orange.shade50,
      Colors.orange.shade700,
    );
  }

  switch (upperType) {
    case 'JOB':
      return NotifStyle(
        LucideIcons.package,
        Colors.blue.shade50,
        Colors.blue.shade600,
      );
    case 'CHAT':
    case 'CHAT_FCM':
      return NotifStyle(
        LucideIcons.message_square,
        Colors.green.shade50,
        Colors.green.shade600,
      );
    case 'ALERT':
    case 'SYSTEM_ALERT':
      return NotifStyle(
        LucideIcons.triangle_exclamation_point,
        Colors.red.shade50,
        Colors.red.shade600,
      );
    default:
      return NotifStyle(
        LucideIcons.info,
        Colors.grey.shade100,
        Colors.grey.shade600,
      );
  }
}

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  void _handleNotificationTap(BuildContext context, NotificationModel notif) {
    final data = notif.data ?? const <String, dynamic>{};
    final type = notif.type.toUpperCase();
    final subType = (data['subType'] ?? '').toString().toUpperCase();
    final url = (notif.link ?? data['url'] ?? '').toString().trim();
    final sessionId = data['sessionId']?.toString();
    final partnerId = data['partnerId']?.toString();
    final workerId = data['workerId']?.toString();
    final jobId = data['jobId']?.toString();

    // 1. Cash Monitor alerts
    if (url.startsWith(AppRoutes.cashMonitor) ||
        subType.startsWith('ADMIN_WORKER_') ||
        subType == 'ADMIN_CASH_DISPUTE') {
      context.push(AppRoutes.cashMonitor);
      return;
    }

    // 2. Chat messages
    if (sessionId != null && sessionId.isNotEmpty) {
      final path = (partnerId != null && partnerId.isNotEmpty)
          ? '${AppRoutes.chatDetail}/$sessionId/$partnerId'
          : '${AppRoutes.chatDetail}/$sessionId';
      context.push(path);
      return;
    }

    // 3. Finance / Payments
    if (type.contains('PAYOUT') ||
        type.contains('PAYMENT') ||
        type.contains('REFUND')) {
      context.push(AppRoutes.finance);
      return;
    }

    // 4. Entity deep links
    if (workerId != null && workerId.isNotEmpty) {
      context.push('${AppRoutes.workerDetail}/$workerId');
      return;
    }
    if (jobId != null && jobId.isNotEmpty) {
      context.push('${AppRoutes.jobDetail}/$jobId');
      return;
    }

    // 5. Safe internal URL (never push '/' or shell branch roots)
    if (url.startsWith('/') &&
        !url.startsWith('//') &&
        url != '/' &&
        url != AppRoutes.home &&
        url != AppRoutes.customers &&
        url != AppRoutes.workers &&
        url != AppRoutes.chatList &&
        url != AppRoutes.notifications) {
      context.push(url);
      return;
    }

    if (type == 'JOB') {
      context.go(AppRoutes.home);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notificationsAsync = ref.watch(notificationsProvider);
    final unreadCount = ref.watch(unreadCountProvider);
    final notifier = ref.read(notificationsProvider.notifier);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black,
        title: const Text(
          'Уведомления',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        actions: [
          if (unreadCount > 0)
            TextButton.icon(
              onPressed: () => notifier.markAllAsRead(),
              icon: const Icon(
                LucideIcons.check_check,
                size: 18,
                color: Color(0xFF0F172A),
              ),
              label: const Text(
                'Прочитать все',
                style: TextStyle(
                  color: Color(0xFF0F172A),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
      body: notificationsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) {
          final message = ApiException.fromDioException(error).message;
          return GlobalErrorWidget(
            message: message,
            onRetry: () => notifier.fetchInitial(),
          );
        },
        data: (notifications) {
          if (notifications.isEmpty) {
            return RefreshIndicator(
              onRefresh: () => notifier.fetchInitial(),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  const SizedBox(height: 120),
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 96,
                          height: 96,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            LucideIcons.bell,
                            size: 40,
                            color: Colors.grey.shade400,
                          ),
                        ),
                        const SizedBox(height: 24),
                        const Text(
                          'У вас нет уведомлений',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Здесь будут появляться сообщения о статусе заказов, ответы поддержки и системные оповещения.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey, fontSize: 15),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () => notifier.fetchInitial(),
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              itemCount: notifications.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final notif = notifications[index];
                final subType = notif.data?['subType']?.toString() ?? '';
                final style = _getStyle(notif.type, subType);
                final createdAt =
                    DateTime.tryParse(notif.createdAt)?.toLocal() ??
                    DateTime.now();

                return Material(
                  color: !notif.isRead
                      ? const Color(0xFF0F172A).withValues(alpha: 0.04)
                      : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () {
                      if (!notif.isRead) {
                        notifier.markAsRead(notif.id);
                      }
                      _handleNotificationTap(context, notif);
                    },
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: !notif.isRead
                              ? const Color(0xFF0F172A).withValues(alpha: 0.18)
                              : const Color(0xFFE2E8F0),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: style.bgColor,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              style.icon,
                              color: style.iconColor,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  notif.title,
                                  style: TextStyle(
                                    fontSize: 15.5,
                                    fontWeight: !notif.isRead
                                        ? FontWeight.bold
                                        : FontWeight.w600,
                                    color: !notif.isRead
                                        ? const Color(0xFF0F172A)
                                        : Colors.grey.shade700,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  notif.message,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: !notif.isRead
                                        ? Colors.black87
                                        : Colors.grey.shade600,
                                    height: 1.4,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  DateFormatter.formatTimeAgo(createdAt),
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.grey.shade500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (!notif.isRead)
                            const Padding(
                              padding: EdgeInsets.only(top: 6, left: 8),
                              child: Icon(
                                Icons.circle,
                                size: 10,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
