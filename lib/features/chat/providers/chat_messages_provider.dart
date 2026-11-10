import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/socket/socket_service.dart';
import '../data/models/chat_message_model.dart';
import '../data/chat_repository.dart';

final chatMessagesProvider = AsyncNotifierProvider.family
    .autoDispose<ChatMessagesNotifier, List<ChatMessageModel>, String>(() {
      return ChatMessagesNotifier();
    });

class ChatMessagesNotifier
    extends AutoDisposeFamilyAsyncNotifier<List<ChatMessageModel>, String> {
  late SocketService _socket;
  bool _hasMore = true;
  bool _isLoadingMore = false;
  int _offset = 0;
  final int _limit = 50;

  @override
  Future<List<ChatMessageModel>> build(String arg) async {
    _socket = ref.watch(socketServiceProvider);

    // Setup socket listeners for real-time events
    _socket.listen('receive_message', _onReceiveMessage);
    _socket.listen('message_confirmed', _onMessageConfirmed);
    _socket.listen('read_status_synced', _onReadStatusSynced);

    ref.onDispose(() {
      _socket.stopListening('receive_message');
      _socket.stopListening('message_confirmed');
      _socket.stopListening('read_status_synced');
    });

    return _fetchMessages(offset: 0);
  }

  Future<List<ChatMessageModel>> _fetchMessages({required int offset}) async {
    try {
      final messages = await ref
          .read(chatRepositoryProvider)
          .fetchMessages(
            arg, // sessionId passed as 'arg'
            limit: _limit,
            offset: offset,
          );

      if (messages.length < _limit) {
        _hasMore = false;
      }
      return messages;
    } catch (e, st) {
      throw AsyncValue.error(e, st);
    }
  }

  Future<void> loadMore() async {
    if (!_hasMore || _isLoadingMore || !state.hasValue) return;

    _isLoadingMore = true;
    _offset += _limit;

    try {
      final olderMessages = await _fetchMessages(offset: _offset);
      state = AsyncValue.data([...state.value!, ...olderMessages]);
    } catch (e) {
      // Revert offset on error so the user can try again
      _offset -= _limit;
    } finally {
      _isLoadingMore = false;
    }
  }

  // ✅ UPDATED: Robust Send Message (HTTP + Socket + FCM)
  Future<void> sendMessage({
    required String text,
    required String receiverId,
    String? imageUrl,
  }) async {
    // Prevent sending entirely empty messages
    if (text.trim().isEmpty && (imageUrl == null || imageUrl.isEmpty)) return;

    try {
      final api = ref.read(apiClientProvider);

      // 1. Send via HTTP to trigger DB save and FCM push notification
      final response = await api.dio.post(
        '/chats/messages',
        data: {
          'sessionId': arg,
          'content': text.trim(),
          if (imageUrl != null) 'imageUrl': imageUrl,
        },
      );

      // 2. Parse the confirmed message from the backend
      final newMessage = ChatMessageModel.fromJson(response.data);

      // 3. Append to local state (optimistic UI update)
      if (state.hasValue) {
        final currentMessages = state.value!;
        // Prevent duplicates if Socket already delivered it faster than HTTP response
        if (!currentMessages.any((m) => m.id == newMessage.id)) {
          state = AsyncValue.data([newMessage, ...currentMessages]);
        }
      }

      // 4. Broadcast via socket for instant delivery to active partner
      // The backend Socket server should relay this to the receiver's active socket
      _socket.emit('send_message', {
        'receiverId': receiverId,
        'chatSessionId': arg,
        'text': text,
        'imageUrl': imageUrl,
        'messageId': newMessage.id, // Pass real DB ID to prevent duplicates
      });
    } catch (e) {
      // Graceful error handling (in production, you could log this to Sentry/Crashlytics)
      print("❌ Failed to send message: $e");
    }
  }

  void markAsRead(String senderId) {
    try {
      _socket.emit('mark_messages_read', {
        'chatSessionId': arg,
        'senderId': senderId,
      });

      // Optimistically update local state so UI clears the unread badge immediately
      if (state.hasValue) {
        final updatedList = state.value!.map((msg) {
          if (msg.senderId == senderId && !msg.isRead) {
            return msg.copyWith(isRead: true);
          }
          return msg;
        }).toList();
        state = AsyncValue.data(updatedList);
      }
    } catch (_) {}
  }

  void _onReceiveMessage(dynamic payload) {
    if (!state.hasValue) return;
    try {
      final msg = ChatMessageModel.fromJson(Map<String, dynamic>.from(payload));

      // Ensure the message belongs to this specific chat room
      if (msg.chatSessionId == arg) {
        final currentMessages = state.value!;
        // Avoid duplicates if HTTP response or 'message_confirmed' already added it
        if (!currentMessages.any((m) => m.id == msg.id)) {
          state = AsyncValue.data([msg, ...currentMessages]);
        }
      }
    } catch (_) {}
  }

  void _onMessageConfirmed(dynamic payload) {
    if (!state.hasValue) return;
    try {
      final data = Map<String, dynamic>.from(payload);
      final msg = ChatMessageModel.fromJson(
        Map<String, dynamic>.from(data['message']),
      );
      if (msg.chatSessionId == arg) {
        final currentMessages = state.value!;
        if (!currentMessages.any((m) => m.id == msg.id)) {
          state = AsyncValue.data([msg, ...currentMessages]);
        }
      }
    } catch (_) {}
  }

  void _onReadStatusSynced(dynamic payload) {
    if (!state.hasValue) return;
    try {
      // The partner has read our messages, update the local UI to reflect it
      final updatedList = state.value!
          .map((m) => m.copyWith(isRead: true))
          .toList();
      state = AsyncValue.data(updatedList);
    } catch (_) {}
  }
}
