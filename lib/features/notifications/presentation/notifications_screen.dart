import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:go_router/go_router.dart';

import '../providers/notification_provider.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../shared/widgets/global_error_widget.dart';
import '../../../core/network/api_exceptions.dart';

// Helper for UI styling based on type
class NotifStyle {
  final IconData icon;
  final Color bgColor;
  final Color iconColor;

  NotifStyle(this.icon, this.bgColor, this.iconColor);
}

NotifStyle _getStyle(String type) {
  switch (type.toUpperCase()) {
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
        LucideIcons.triangle_alert,
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch the AsyncValue from the plural provider
    final notificationsAsync = ref.watch(notificationsProvider);
    final unreadCount = ref.watch(unreadCountProvider);
    final notifier = ref.read(notificationsProvider.notifier);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
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
          final apiError = ApiException.fromDioException(error);
          return GlobalErrorWidget(
            message: apiError.message,
            onRetry: () => notifier.fetchInitial(),
          );
        },
        data: (notifications) {
          if (notifications.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
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
                        fontSize: 24,
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
            );
          }

          return RefreshIndicator(
            onRefresh: () => notifier.fetchInitial(),
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: notifications.length,
              separatorBuilder: (context, index) =>
                  const Divider(height: 1, color: Color(0xFFE2E8F0)),
              itemBuilder: (context, index) {
                final notif = notifications[index];

                // Extract type and link from the dynamic data map
                final String notifType =
                    notif.data?['type']?.toString() ?? 'INFO';
                final String? notifLink = notif.data?['url']?.toString();

                final style = _getStyle(notifType);

                return InkWell(
                  onTap: () {
                    // Mark as read immediately for snappy UI
                    if (!notif.isRead) {
                      notifier.markAsRead(notif.id);
                    }

                    // Route based on dynamic data
                    if (notifLink != null && notifLink.isNotEmpty) {
                      context.push(notifLink);
                    } else if (notifType == 'CHAT' &&
                        notif.data?['sessionId'] != null) {
                      context.push('/chat-detail/${notif.data!['sessionId']}');
                    } else if (notifType == 'JOB') {
                      context.push('/orders');
                    }
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      color: !notif.isRead
                          ? const Color(0xFF0F172A).withOpacity(0.03)
                          : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Left Indicator Bar
                          Container(
                            width: 4,
                            decoration: BoxDecoration(
                              color: !notif.isRead
                                  ? const Color(0xFF0F172A)
                                  : Colors.transparent,
                              borderRadius: const BorderRadius.only(
                                topLeft: Radius.circular(16),
                                bottomLeft: Radius.circular(16),
                              ),
                            ),
                          ),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Icon Circle
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
                                  const SizedBox(width: 16),
                                  // Content
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          notif.title,
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: !notif.isRead
                                                ? FontWeight.bold
                                                : FontWeight.w600,
                                            color: !notif.isRead
                                                ? Colors.black
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
                                                : Colors.grey.shade500,
                                            height: 1.4,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          DateFormatter.formatTimeAgo(
                                            DateTime.tryParse(
                                                  notif.createdAt,
                                                ) ??
                                                DateTime.now(),
                                          ),
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.grey.shade400,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  // Right Dot indicator
                                  if (!notif.isRead)
                                    const Padding(
                                      padding: EdgeInsets.only(top: 8, left: 8),
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
