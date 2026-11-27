import 'package:flutter/material.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:overlay_support/overlay_support.dart';

import '../../../core/socket/socket_service.dart';
import '../../auth/providers/auth_provider.dart';
import '../data/chat_repository.dart';
import '../data/models/chat_session_model.dart';
import 'active_chat_provider.dart';

final chatSessionsProvider =
    AsyncNotifierProvider<ChatSessionsNotifier, List<ChatSessionModel>>(
      ChatSessionsNotifier.new,
    );

/// Standalone total unread count for optimized bottom-nav badge rebuilds.
final totalUnreadChatCountProvider = Provider<int>((ref) {
  final sessions = ref.watch(chatSessionsProvider).valueOrNull ?? const [];
  return sessions.fold<int>(0, (sum, s) => sum + s.unreadCount);
});

class ChatSessionsNotifier extends AsyncNotifier<List<ChatSessionModel>> {
  late SocketService _socket;

  @override
  Future<List<ChatSessionModel>> build() async {
    _socket = ref.watch(socketServiceProvider);

    // Real-time inbox listeners
    _socket.listen('receive_message', _onMessageReceived);
    _socket.listen('messages_read_by_recipient', _onMessagesRead);
    _socket.listen('read_status_synced', _onReadStatusSynced);
    _socket.listen('user_status_changed', _onUserStatusChanged);
    _socket.listen('user_typing', _onUserTyping);
    _socket.listen('user_stopped_typing', _onUserStoppedTyping);

    ref.onDispose(() {
      _socket.stopListening('receive_message', _onMessageReceived);
      _socket.stopListening('messages_read_by_recipient', _onMessagesRead);
      _socket.stopListening('read_status_synced', _onReadStatusSynced);
      _socket.stopListening('user_status_changed', _onUserStatusChanged);
      _socket.stopListening('user_typing', _onUserTyping);
      _socket.stopListening('user_stopped_typing', _onUserStoppedTyping);
    });

    return _fetchInitialSessions();
  }

  Future<List<ChatSessionModel>> _fetchInitialSessions() {
    return ref.read(chatRepositoryProvider).fetchSessions();
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(_fetchInitialSessions);
  }

  /// Refreshes the inbox in the background without flashing a loading spinner.
  Future<void> _silentRefresh() async {
    try {
      final fresh = await _fetchInitialSessions();
      state = AsyncValue.data(fresh);
    } catch (_) {
      // Keep existing inbox list on transient network errors
    }
  }

  // ==========================================
  // INCOMING MESSAGES
  // ==========================================
  void _onMessageReceived(dynamic payload) {
    if (!state.hasValue || payload is! Map) return;

    try {
      final data = Map<String, dynamic>.from(payload);
      final sessionId =
          data['chat_session_id']?.toString() ??
          data['chatSessionId']?.toString();
      if (sessionId == null || sessionId.isEmpty) return;

      final rawText = data['text']?.toString().trim();
      final previewText = (rawText != null && rawText.isNotEmpty)
          ? rawText
          : '📷 Фото';
      final senderId =
          data['sender_id']?.toString() ?? data['senderId']?.toString();

      final currentUser = ref.read(currentUserProvider);
      final currentUserId = currentUser?['id']?.toString();
      final isMe = senderId != null && senderId == currentUserId;

      final currentlyActiveSessionId = ref.read(activeChatSessionProvider);
      final isViewingThisChat = currentlyActiveSessionId == sessionId;

      // Play sound and show overlay banner only when not actively viewing this chat
      if (!isMe && !isViewingThisChat) {
        FlutterRingtonePlayer().playNotification();

        showOverlayNotification((context) {
          return SafeArea(
            child: Material(
              color: Colors.transparent,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.15),
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  leading: CircleAvatar(
                    backgroundColor: const Color(0xFF3B82F6)
                        .withValues(alpha: 0.1),
                    child: const Icon(
                      Icons.message_rounded,
                      color: Color(0xFF3B82F6),
                    ),
                  ),
                  title: const Text(
                    'Новое сообщение',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  subtitle: Text(
                    previewText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                  onTap: () {
                    OverlaySupportEntry.of(context)?.dismiss();
                  },
                ),
              ),
            ),
          );
        }, duration: const Duration(seconds: 4));
      }

      final currentSessions = state.value!;
      final index = currentSessions.indexWhere((s) => s.id == sessionId);

      if (index != -1) {
        final session = currentSessions[index];
        final updatedSession = session.copyWith(
          lastMessage: previewText,
          updatedAt: DateTime.now().toUtc().toIso8601String(),
          unreadCount: (isMe || isViewingThisChat)
              ? session.unreadCount
              : session.unreadCount + 1,
          isTyping: false,
        );

        final newList = [...currentSessions];
        newList.removeAt(index);
        newList.insert(0, updatedSession);
        state = AsyncValue.data(newList);
      } else {
        // Brand-new session from someone not yet in the inbox
        _silentRefresh();
      }
    } catch (_) {
      // Ignore malformed payloads gracefully
    }
  }

  // ==========================================
  // READ RECEIPTS
  // ==========================================
  void _onMessagesRead(dynamic payload) {
    // Handled inside ChatMessagesNotifier for message-level double-check marks
  }

  void _onReadStatusSynced(dynamic payload) {
    if (!state.hasValue || payload is! Map) return;

    try {
      final data = Map<String, dynamic>.from(payload);
      final sessionId =
          data['chatSessionId']?.toString() ??
          data['chat_session_id']?.toString();
      final partnerId = data['partnerId']?.toString();

      final currentSessions = state.value!;
      final index = currentSessions.indexWhere(
        (s) =>
            (sessionId != null && s.id == sessionId) ||
            (partnerId != null && s.partnerId == partnerId),
      );

      if (index != -1) {
        final session = currentSessions[index];
        if (session.unreadCount == 0) return;

        final newList = [...currentSessions];
        newList[index] = session.copyWith(unreadCount: 0);
        state = AsyncValue.data(newList);
      }
    } catch (_) {}
  }

  // ==========================================
  // REAL-TIME PRESENCE (ONLINE / OFFLINE)
  // ==========================================
  void _onUserStatusChanged(dynamic payload) {
    if (!state.hasValue || payload is! Map) return;

    try {
      final data = Map<String, dynamic>.from(payload);
      final userId = data['userId']?.toString();
      if (userId == null) return;

      final isOnline = data['isOnline'] == true;
      final lastSeen = data['lastSeen']?.toString();

      final currentSessions = state.value!;
      final index = currentSessions.indexWhere((s) => s.partnerId == userId);

      if (index != -1) {
        final session = currentSessions[index];
        if (session.isOnline == isOnline && session.lastSeen == lastSeen) {
          return;
        }

        final newList = [...currentSessions];
        newList[index] = session.copyWith(
          isOnline: isOnline,
          lastSeen: isOnline ? null : lastSeen,
        );
        state = AsyncValue.data(newList);
      }
    } catch (_) {}
  }

  // ==========================================
  // TYPING INDICATORS
  // ==========================================
  void _onUserTyping(dynamic payload) => _updateTypingState(payload, true);

  void _onUserStoppedTyping(dynamic payload) =>
      _updateTypingState(payload, false);

  void _updateTypingState(dynamic payload, bool isTyping) {
    if (!state.hasValue || payload is! Map) return;

    try {
      final data = Map<String, dynamic>.from(payload);
      final userId = data['userId']?.toString();
      if (userId == null) return;

      final currentSessions = state.value!;
      final index = currentSessions.indexWhere((s) => s.partnerId == userId);

      if (index != -1) {
        final session = currentSessions[index];
        if (session.isTyping == isTyping) return;

        final newList = [...currentSessions];
        newList[index] = session.copyWith(isTyping: isTyping);
        state = AsyncValue.data(newList);
      }
    } catch (_) {}
  }
}
