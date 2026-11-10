import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/uploader_service.dart';
import './models/chat_session_model.dart';
import './models/chat_message_model.dart';

final chatRepositoryProvider = Provider<ChatRepository>((ref) {
  return ChatRepository(
    ref.read(apiClientProvider),
    ref.read(uploaderServiceProvider),
  );
});

class ChatRepository {
  final ApiClient _api;
  final UploaderService _uploader;

  ChatRepository(this._api, this._uploader);

  // ============================================================
  // 1. FETCH INBOX SESSIONS
  // GET /api/chats/sessions
  // ============================================================
  Future<List<ChatSessionModel>> fetchSessions() async {
    final response = await _api.dio.get('/chats/sessions');

    return (response.data as List)
        .map((json) => ChatSessionModel.fromJson(json))
        .toList();
  }

  // ============================================================
  // 2. FETCH MESSAGES FOR A SESSION
  // GET /api/chats/sessions/:sessionId/messages
  // ============================================================
  Future<List<ChatMessageModel>> fetchMessages(
    String sessionId, {
    int limit = 50,
    int offset = 0,
  }) async {
    final response = await _api.dio.get(
      '/chats/sessions/$sessionId/messages',
      queryParameters: {'limit': limit, 'offset': offset},
    );

    return (response.data as List)
        .map((json) => ChatMessageModel.fromJson(json))
        .toList();
  }

  // ============================================================
  // 3. INITIATE OR RESUME A CHAT
  // POST /api/chats/sessions/initiate
  // ============================================================
  Future<ChatSessionModel> initiateChat(String partnerId) async {
    final response = await _api.dio.post(
      '/chats/sessions/initiate',
      data: {'partnerId': partnerId},
    );

    return ChatSessionModel.fromJson(response.data);
  }

  // ============================================================
  // 4. UPLOAD CHAT IMAGE
  // Delegates compression and MinIO PUT to UploaderService
  // ============================================================
  Future<String> uploadChatImage(File file, {String? sessionId}) async {
    return await _uploader.uploadFileDirectly(
      file: file,
      endpoint: '/chats/upload/presigned-url',
      payloadData: {
        if (sessionId != null && !sessionId.startsWith('new_'))
          'sessionId': sessionId,
      },
      imageContext: 'chats',
      isGetRequest: true, // Crucial: Chat routes use GET for presigned URLs
    );
  }
}
