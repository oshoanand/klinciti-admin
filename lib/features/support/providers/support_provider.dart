import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/uploader_service.dart';

// ==========================================
// 1. DOMAIN MODEL
// ==========================================
class TicketModel {
  final String id;
  final String subject;
  final String description;
  final String status;
  final DateTime createdAt;

  TicketModel.fromJson(Map<String, dynamic> json)
    : id = json['id'],
      subject = json['subject'] ?? '',
      description = json['description'] ?? '',
      status = json['status'] ?? 'OPEN',
      createdAt = json['created_at'] != null || json['createdAt'] != null
          ? DateTime.parse(json['created_at'] ?? json['createdAt'])
          : DateTime.now();
}

// ==========================================
// 2. QUERY PROVIDER (Fetch Tickets)
// ==========================================
final supportTicketsProvider = FutureProvider.autoDispose<List<TicketModel>>((
  ref,
) async {
  final api = ref.watch(apiClientProvider);
  final response = await api.dio.get('/support'); // Matches your API endpoint

  final List data = response.data is List
      ? response.data
      : response.data['data'] ?? [];
  return data.map((t) => TicketModel.fromJson(t)).toList();
});

// ==========================================
// 3. MUTATION PROVIDER (Create Ticket)
// ==========================================
final createTicketProvider = StateNotifierProvider<CreateTicketNotifier, bool>((
  ref,
) {
  return CreateTicketNotifier(
    ref.watch(apiClientProvider),
    ref.watch(uploaderServiceProvider),
    ref,
  );
});

class CreateTicketNotifier extends StateNotifier<bool> {
  final ApiClient _api;
  final UploaderService _uploader;
  final Ref _ref;

  CreateTicketNotifier(this._api, this._uploader, this._ref) : super(false);

  Future<void> submitTicket({
    required String subject,
    required String description,
    required List<File> photos,
  }) async {
    state = true;
    try {
      final List<String> remoteUrls = [];

      // Upload photos directly to MinIO (using the uploader you built previously)
      for (final file in photos) {
        final url = await _uploader.uploadFileDirectly(
          file: file,
          endpoint: '/support/presigned-url', // Matches your Web API endpoint
        );
        remoteUrls.add(url);
      }

      // Submit the ticket
      await _api.dio.post(
        '/support',
        data: {
          'subject': subject,
          'description': description,
          'attachments': remoteUrls,
        },
      );

      // Refresh the tickets list automatically
      _ref.invalidate(supportTicketsProvider);
    } finally {
      state = false;
    }
  }
}
