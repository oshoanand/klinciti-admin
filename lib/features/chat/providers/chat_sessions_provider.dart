import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:overlay_support/overlay_support.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'package:flutter/material.dart';

import '../../../core/socket/socket_service.dart';
import '../data/models/chat_session_model.dart';
import '../data/chat_repository.dart';
import '../../auth/providers/auth_provider.dart';
import 'active_chat_provider.dart'; // ✅ Add import

final chatSessionsProvider =
    AsyncNotifierProvider<ChatSessionsNotifier, List<ChatSessionModel>>(() {
      return ChatSessionsNotifier();
    });

class ChatSessionsNotifier extends AsyncNotifier<List<ChatSessionModel>> {
  late SocketService _socket;

  @override
  Future<List<ChatSessionModel>> build() async {
    _socket = ref.watch(socketServiceProvider);

    // Setup real-time listeners for inbox updates
    _socket.listen('receive_message', _onMessageReceived);
    _socket.listen('messages_read_by_recipient', _onMessagesRead);

    // ✅ 1. Listen for when YOUR read receipts are confirmed by the server
    _socket.listen('read_status_synced', _onReadStatusSynced);

    // Real-time Presence
    _socket.listen('user_status_changed', _onUserStatusChanged);

    // Real-time Typing Indicators
    _socket.listen('user_typing', _onUserTyping);
    _socket.listen('user_stopped_typing', _onUserStoppedTyping);

    ref.onDispose(() {
      _socket.stopListening('receive_message', _onMessageReceived);
      _socket.stopListening('messages_read_by_recipient', _onMessagesRead);
      // ✅ 2. Clean up the new listener
      _socket.stopListening('read_status_synced', _onReadStatusSynced);
      _socket.stopListening('user_status_changed', _onUserStatusChanged);
      _socket.stopListening('user_typing', _onUserTyping);
      _socket.stopListening('user_stopped_typing', _onUserStoppedTyping);
    });

    return _fetchInitialSessions();
  }

  Future<List<ChatSessionModel>> _fetchInitialSessions() async {
    try {
      return await ref.read(chatRepositoryProvider).fetchSessions();
    } catch (e, st) {
      throw AsyncValue.error(e, st);
    }
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _fetchInitialSessions());
  }

  // ==========================================
  // INCOMING MESSAGES
  // ==========================================

  void _onMessageReceived(dynamic payload) {
    if (!state.hasValue) return;

    try {
      final data = Map<String, dynamic>.from(payload);
      final sessionId =
          data['chat_session_id']?.toString() ??
          data['chatSessionId']?.toString();
      final text = data['text']?.toString();
      final senderId =
          data['sender_id']?.toString() ?? data['senderId']?.toString();

      final currentUser = ref.read(currentUserProvider);
      final currentUserId = currentUser?['id']?.toString();
      final isMe = senderId == currentUserId;

      // ✅ Check which room is currently open on the screen
      final currentlyActiveSessionId = ref.read(activeChatSessionProvider);

      // ✅ Only play sound and show banner if we are NOT in this specific chat room
      if (!isMe && currentlyActiveSessionId != sessionId) {
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
                      color: Colors.black.withOpacity(0.15),
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
                    backgroundColor: const Color(0xFF3B82F6).withOpacity(0.1),
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
                    text ?? '📷 Фото',
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
          lastMessage: text ?? '📷 Фото',
          updatedAt: DateTime.now().toIso8601String(),
          unreadCount: isMe ? session.unreadCount : session.unreadCount + 1,
          isTyping: false,
        );

        final newList = [...currentSessions];
        newList.removeAt(index);
        newList.insert(0, updatedSession);
        state = AsyncValue.data(newList);
      } else {
        refresh();
      }
    } catch (e) {
      // Graceful degradation
    }
  }

  // ==========================================
  // READ RECEIPTS
  // ==========================================
  void _onMessagesRead(dynamic payload) {
    if (!state.hasValue) return;
    try {
      // Logic for when the PARTNER reads your messages
    } catch (_) {}
  }

  // ✅ 3. NEW HANDLER: Instantly clears the unread count when you open the chat
  void _onReadStatusSynced(dynamic payload) {
    if (!state.hasValue) return;

    try {
      final data = Map<String, dynamic>.from(payload);
      final partnerId = data['partnerId'] as String;

      final currentSessions = state.value!;
      final index = currentSessions.indexWhere((s) => s.partnerId == partnerId);

      if (index != -1) {
        final session = currentSessions[index];

        // If it's already 0, skip rebuilding the UI
        if (session.unreadCount == 0) return;

        // Zero out the unread count for this specific session
        final updatedSession = session.copyWith(unreadCount: 0);

        final newList = [...currentSessions];
        newList[index] = updatedSession;
        state = AsyncValue.data(newList);
      }
    } catch (e) {
      // Ignore parsing errors
    }
  }

  // ==========================================
  // REAL-TIME PRESENCE (Online/Offline)
  // ==========================================
  void _onUserStatusChanged(dynamic payload) {
    if (!state.hasValue) return;

    try {
      final data = Map<String, dynamic>.from(payload);
      final userId = data['userId'] as String;
      final isOnline = data['isOnline'] as bool;
      final lastSeen = data['lastSeen'] as String?;

      final currentSessions = state.value!;
      final index = currentSessions.indexWhere((s) => s.partnerId == userId);

      if (index != -1) {
        final session = currentSessions[index];

        if (session.isOnline == isOnline) return;

        final updatedSession = session.copyWith(
          isOnline: isOnline,
          lastSeen: lastSeen,
        );

        final newList = [...currentSessions];
        newList[index] = updatedSession;
        state = AsyncValue.data(newList);
      }
    } catch (e) {
      // Ignore parsing errors
    }
  }

  // ==========================================
  // TYPING INDICATORS
  // ==========================================
  void _onUserTyping(dynamic payload) {
    _updateTypingState(payload, true);
  }

  void _onUserStoppedTyping(dynamic payload) {
    _updateTypingState(payload, false);
  }

  void _updateTypingState(dynamic payload, bool isTyping) {
    if (!state.hasValue) return;

    try {
      final data = Map<String, dynamic>.from(payload);
      final userId = data['userId'] as String;

      final currentSessions = state.value!;
      final index = currentSessions.indexWhere((s) => s.partnerId == userId);

      if (index != -1) {
        final session = currentSessions[index];

        if (session.isTyping == isTyping) return;

        final updatedSession = session.copyWith(isTyping: isTyping);

        final newList = [...currentSessions];
        newList[index] = updatedSession;
        state = AsyncValue.data(newList);
      }
    } catch (e) {
      // Ignore parsing errors
    }
  }
}
