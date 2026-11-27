import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/socket/socket_service.dart';
import '../../auth/providers/auth_provider.dart';
import '../data/chat_repository.dart';
import '../data/models/chat_message_model.dart';

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
  late String _resolvedSessionId;

  @override
  Future<List<ChatMessageModel>> build(String arg) async {
    _resolvedSessionId = arg;
    _socket = ref.watch(socketServiceProvider);

    _socket.listen('receive_message', _onReceiveMessage);
    _socket.listen('messages_read_by_recipient', _onMessagesReadByRecipient);

    ref.onDispose(() {
      // Pass exact callbacks so ChatSessionsNotifier listeners stay alive!
      _socket.stopListening('receive_message', _onReceiveMessage);
      _socket.stopListening(
        'messages_read_by_recipient',
        _onMessagesReadByRecipient,
      );
    });

    return _fetchMessages(offset: 0);
  }

  Future<List<ChatMessageModel>> _fetchMessages({required int offset}) async {
    final messages = await ref
        .read(chatRepositoryProvider)
        .fetchMessages(_resolvedSessionId, limit: _limit, offset: offset);

    if (messages.length < _limit) {
      _hasMore = false;
    }
    return messages;
  }

  Future<void> loadMore() async {
    if (!_hasMore || _isLoadingMore || !state.hasValue) return;

    _isLoadingMore = true;
    _offset += _limit;

    try {
      final olderMessages = await _fetchMessages(offset: _offset);
      state = AsyncValue.data([...state.value!, ...olderMessages]);
    } catch (_) {
      _offset -= _limit;
    } finally {
      _isLoadingMore = false;
    }
  }

  Future<void> sendMessage({
    required String text,
    required String receiverId,
    String? imageUrl,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty && (imageUrl == null || imageUrl.isEmpty)) return;

    final currentUserId =
        ref.read(currentUserProvider)?['id']?.toString() ?? '';
    final tempId = 'temp_${DateTime.now().microsecondsSinceEpoch}';

    // 1. Optimistic insert for instant UI feel
    final optimisticMsg = ChatMessageModel(
      id: tempId,
      chatSessionId: _resolvedSessionId,
      senderId: currentUserId,
      text: trimmed.isEmpty ? null : trimmed,
      imageUrl: imageUrl,
      isRead: false,
      createdAt: DateTime.now().toUtc().toIso8601String(),
    );

    if (state.hasValue) {
      state = AsyncValue.data([optimisticMsg, ...state.value!]);
    }

    try {
      final api = ref.read(apiClientProvider);
      // Backend saves to DB, emits Socket.io `receive_message` to both rooms, and sends FCM
      final response = await api.dio.post(
        '/chats/messages',
        data: {
          'sessionId': _resolvedSessionId,
          'partnerId': receiverId,
          if (trimmed.isNotEmpty) 'text': trimmed,
          if (imageUrl != null && imageUrl.isNotEmpty) 'imageUrl': imageUrl,
        },
      );

      final resMap = Map<String, dynamic>.from(response.data as Map);
      if (resMap['sessionId'] != null) {
        _resolvedSessionId = resMap['sessionId'].toString();
      }
      final msgJson = Map<String, dynamic>.from(
        (resMap['message'] ?? resMap) as Map,
      );
      final confirmedMsg = ChatMessageModel.fromJson(msgJson);

      if (state.hasValue) {
        final list = state.value!
            .where((m) => m.id != tempId && m.id != confirmedMsg.id)
            .toList();
        state = AsyncValue.data([confirmedMsg, ...list]);
      }
    } catch (e) {
      // Roll back optimistic message on failure
      if (state.hasValue) {
        state = AsyncValue.data(
          state.value!.where((m) => m.id != tempId).toList(),
        );
      }
      rethrow;
    }
  }

  Future<void> markAsRead(String senderId) async {
    if (_resolvedSessionId.startsWith('new_')) return;

    try {
      _socket.emit('mark_messages_read', {
        'chatSessionId': _resolvedSessionId,
        'senderId': senderId,
      });

      // Reliable HTTP fallback
      await ref
          .read(apiClientProvider)
          .dio
          .post('/chats/sessions/$_resolvedSessionId/read');

      if (state.hasValue) {
        state = AsyncValue.data(
          state.value!
              .map(
                (msg) => msg.senderId == senderId && !msg.isRead
                    ? msg.copyWith(isRead: true)
                    : msg,
              )
              .toList(),
        );
      }
    } catch (_) {}
  }

  void _onReceiveMessage(dynamic payload) {
    if (!state.hasValue) return;
    try {
      final msg = ChatMessageModel.fromJson(Map<String, dynamic>.from(payload));
      if (msg.chatSessionId == _resolvedSessionId) {
        final currentMessages = state.value!;
        if (!currentMessages.any((m) => m.id == msg.id)) {
          state = AsyncValue.data([msg, ...currentMessages]);
        }
      }
    } catch (_) {}
  }

  void _onMessagesReadByRecipient(dynamic payload) {
    if (!state.hasValue) return;
    try {
      final data = Map<String, dynamic>.from(payload);
      final eventSessionId =
          data['chatSessionId']?.toString() ??
          data['chat_session_id']?.toString();
      if (eventSessionId != null && eventSessionId != _resolvedSessionId) {
        return;
      }
      state = AsyncValue.data(
        state.value!.map((m) => m.copyWith(isRead: true)).toList(),
      );
    } catch (_) {}
  }
}
