import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/uploader_service.dart';
import 'models/chat_message_model.dart';
import 'models/chat_session_model.dart';

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
    final list = response.data as List? ?? const [];

    return list
        .map(
          (json) =>
              ChatSessionModel.fromJson(Map<String, dynamic>.from(json as Map)),
        )
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
    final list = response.data as List? ?? const [];

    return list
        .map(
          (json) =>
              ChatMessageModel.fromJson(Map<String, dynamic>.from(json as Map)),
        )
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

    return ChatSessionModel.fromJson(
      Map<String, dynamic>.from(response.data as Map),
    );
  }

  // ============================================================
  // 4. MARK SESSION AS READ (HTTP COMPANION TO SOCKET)
  // POST /api/chats/sessions/:sessionId/read
  // ============================================================
  Future<void> markSessionAsRead(String sessionId) async {
    if (sessionId.startsWith('new_')) return;
    await _api.dio.post('/chats/sessions/$sessionId/read');
  }

  // ============================================================
  // 5. ADMIN CONTACT DIRECTORY (START CHAT WITH ANYONE)
  // GET /api/chats/admin/contacts
  // ============================================================
  Future<List<Map<String, dynamic>>> searchAdminContacts({
    String search = '',
    String role = 'ALL',
    int limit = 30,
  }) async {
    final response = await _api.dio.get(
      '/chats/admin/contacts',
      queryParameters: {
        if (search.trim().isNotEmpty) 'search': search.trim(),
        'role': role,
        'limit': limit,
      },
    );
    final list = response.data as List? ?? const [];

    return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  // ============================================================
  // 6. UPLOAD CHAT IMAGE
  // Delegates compression and MinIO PUT to UploaderService
  // ============================================================
  Future<String> uploadChatImage(File file, {String? sessionId}) async {
    return _uploader.uploadFileDirectly(
      file: file,
      endpoint: '/chats/upload/presigned-url',
      payloadData: {
        if (sessionId != null && !sessionId.startsWith('new_'))
          'sessionId': sessionId,
      },
      imageContext: 'chats',
      isGetRequest: true, // Chat routes use GET for presigned URLs
    );
  }
}
