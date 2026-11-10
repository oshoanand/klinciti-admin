import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../providers/chat_sessions_provider.dart';

class ChatInboxScreen extends ConsumerWidget {
  const ChatInboxScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionsState = ref.watch(chatSessionsProvider);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC), // Premium Slate background
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          leading: Padding(
            padding: const EdgeInsets.only(left: 12.0),
            child: IconButton(
              icon: const Icon(
                LucideIcons.arrow_left,
                color: Color(0xFF0F172A),
              ),
              onPressed: () => context.pop(),
            ),
          ),
          title: const Text(
            'Список чатов',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: Color(0xFF0F172A),
              letterSpacing: -0.5,
              fontSize: 22,
            ),
          ),
          centerTitle: false,
        ),
        body: RefreshIndicator(
          color: const Color(0xFF0F172A),
          backgroundColor: Colors.white,
          onRefresh: () => ref.read(chatSessionsProvider.notifier).refresh(),
          child: sessionsState.when(
            loading: () => const Center(
              child: CircularProgressIndicator(color: Color(0xFF0F172A)),
            ),
            error: (err, _) => Center(
              child: Container(
                padding: const EdgeInsets.all(32),
                margin: const EdgeInsets.symmetric(horizontal: 24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.03),
                      blurRadius: 24,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        LucideIcons.circle_alert,
                        color: Colors.red,
                        size: 32,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Ошибка загрузки\n$err',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            data: (sessions) {
              if (sessions.isEmpty) {
                return ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    const SizedBox(height: 120),
                    Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.03),
                                  blurRadius: 16,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: Icon(
                              LucideIcons.message_square,
                              size: 40,
                              color: Colors.grey.shade400,
                            ),
                          ),
                          const SizedBox(height: 24),
                          const Text(
                            'Нет активных чатов',
                            style: TextStyle(
                              color: Color(0xFF0F172A),
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Здесь появятся ваши переписки\nс клиентами и мастерами.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey.shade500),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              }

              return ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                padding: const EdgeInsets.only(top: 8, bottom: 32),
                itemCount: sessions.length,
                separatorBuilder: (context, index) => Padding(
                  padding: const EdgeInsets.only(left: 88, right: 24),
                  child: Divider(height: 1, color: Colors.grey.shade200),
                ),
                itemBuilder: (context, index) {
                  final session = sessions[index];
                  final date = DateTime.parse(session.updatedAt).toLocal();
                  final isUnread = session.unreadCount > 0;

                  return Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => context.push(
                        '/chat/${session.id}/${session.partnerId}',
                      ),
                      highlightColor: Colors.grey.shade100,
                      splashColor: Colors.grey.shade50,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 16,
                        ),
                        child: Row(
                          children: [
                            // 🟢 Avatar with real-time presence dot
                            Stack(
                              children: [
                                CircleAvatar(
                                  radius: 28,
                                  backgroundColor: const Color(0xFF0F172A)
                                      .withOpacity(0.05),
                                  backgroundImage: session.partnerAvatar != null
                                      ? NetworkImage(session.partnerAvatar!)
                                      : null,
                                  child: session.partnerAvatar == null
                                      ? const Icon(
                                          LucideIcons.user,
                                          color: Color(0xFF64748B),
                                          size: 24,
                                        )
                                      : null,
                                ),
                                Positioned(
                                  right: 0,
                                  bottom: 0,
                                  child: Container(
                                    width: 14,
                                    height: 14,
                                    decoration: BoxDecoration(
                                      color: session.isOnline
                                          ? Colors.green
                                          : Colors.grey.shade400,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: Colors.white,
                                        width: 2,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(width: 16),
                            // Content
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      // 👤 Fallback to ID if name is missing
                                      Expanded(
                                        child: Text(
                                          session.partnerName ??
                                              'ID: ${session.partnerId.substring(0, 6)}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontWeight: isUnread
                                                ? FontWeight.w800
                                                : FontWeight.w600,
                                            fontSize: 16,
                                            color: const Color(0xFF0F172A),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        _formatLastMessageDate(date),
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: isUnread
                                              ? const Color(0xFF3B82F6)
                                              : Colors.grey.shade500,
                                          fontWeight: isUnread
                                              ? FontWeight.bold
                                              : FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: session.isTyping
                                            ? const Text(
                                                'Печатает...',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  color: Color(0xFF3B82F6), // Blue to match the unread badge
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 14,
                                                  fontStyle: FontStyle.italic,
                                                ),
                                              )
                                            : Text(
                                                session.lastMessage ??
                                                    '📷 Вложение',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  color: isUnread
                                                      ? const Color(0xFF0F172A)
                                                      : Colors.grey.shade600,
                                                  fontWeight: isUnread
                                                      ? FontWeight.w600
                                                      : FontWeight.normal,
                                                  fontSize: 14,
                                                ),
                                              ),
                                      ),
                                      if (isUnread)
                                        Container(
                                          margin: const EdgeInsets.only(
                                            left: 8,
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
                                          decoration: const BoxDecoration(
                                            color: Color(0xFF3B82F6),
                                            shape: BoxShape.circle,
                                          ),
                                          child: Text(
                                            session.unreadCount.toString(),
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                              height: 1,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  // Helper method for clean date formatting in the list view
  String _formatLastMessageDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final msgDay = DateTime(date.year, date.month, date.day);

    if (msgDay == today) {
      return DateFormat('HH:mm').format(date);
    } else if (msgDay == yesterday) {
      return 'Вчера';
    } else {
      return DateFormat('dd.MM.yy').format(date);
    }
  }
}
