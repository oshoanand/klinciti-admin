import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/socket/socket_service.dart';

class NotificationModel {
  final String id;
  final String title;
  final String message;
  final String type;
  final String? link;
  final bool isRead;
  final String createdAt;
  final Map<String, dynamic>? data;

  const NotificationModel({
    required this.id,
    required this.title,
    required this.message,
    required this.type,
    this.link,
    required this.isRead,
    required this.createdAt,
    this.data,
  });

  NotificationModel copyWith({bool? isRead}) {
    return NotificationModel(
      id: id,
      title: title,
      message: message,
      type: type,
      link: link,
      isRead: isRead ?? this.isRead,
      createdAt: createdAt,
      data: data,
    );
  }

  factory NotificationModel.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic>? parsedData;
    final rawData = json['data'];
    if (rawData is Map) {
      parsedData = Map<String, dynamic>.from(rawData);
    } else if (rawData is String && rawData.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(rawData);
        if (decoded is Map) {
          parsedData = Map<String, dynamic>.from(decoded);
        }
      } catch (_) {}
    }

    final resolvedType =
        json['type']?.toString() ?? parsedData?['type']?.toString() ?? 'INFO';

    final resolvedLink =
        json['link']?.toString() ?? parsedData?['url']?.toString();

    return NotificationModel(
      id: (json['id'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      message: (json['message'] ?? json['body'] ?? '').toString(),
      type: resolvedType,
      link: resolvedLink,
      isRead: json['is_read'] == true || json['is_read'] == 1,
      createdAt: (json['created_at'] ?? '').toString(),
      data: parsedData,
    );
  }
}

class NotificationRepository {
  final ApiClient _api;
  NotificationRepository(this._api);

  Future<List<NotificationModel>> fetchNotifications() async {
    final res = await _api.dio.get('/notifications');
    final list = res.data is List ? res.data as List : const [];
    return list
        .whereType()
        .map((e) => NotificationModel.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<void> markAsRead(String id) async {
    await _api.dio.patch('/notifications/$id/read', data: {});
  }

  Future<void> markAllAsRead() async {
    await _api.dio.patch('/notifications/mark-all-read', data: {});
  }
}

final notificationRepositoryProvider = Provider<NotificationRepository>((ref) {
  return NotificationRepository(ref.watch(apiClientProvider));
});

final notificationsProvider =
    StateNotifierProvider<
      NotificationNotifier,
      AsyncValue<List<NotificationModel>>
    >((ref) {
      final repo = ref.watch(notificationRepositoryProvider);
      final socket = ref.watch(socketServiceProvider);
      return NotificationNotifier(repo, socket);
    });

class NotificationNotifier
    extends StateNotifier<AsyncValue<List<NotificationModel>>> {
  final NotificationRepository _repository;
  final SocketService _socket;

  NotificationNotifier(this._repository, this._socket)
    : super(const AsyncValue.loading()) {
    fetchInitial();
    _socket.listen('notification', _onSocketNotification);
  }

  void _onSocketNotification(dynamic _) {
    if (!mounted) return;
    fetchInitial(silent: true);
  }

  @override
  void dispose() {
    _socket.stopListening('notification', _onSocketNotification);
    super.dispose();
  }

  Future<void> fetchInitial({bool silent = false}) async {
    if (!silent && !state.hasValue && mounted) {
      state = const AsyncValue.loading();
    }
    try {
      final data = await _repository.fetchNotifications();
      if (!mounted) return;
      state = AsyncValue.data(data);
    } catch (e, st) {
      if (!mounted) return;
      // Preserve existing list during background socket syncs
      if (!silent || !state.hasValue) {
        state = AsyncValue.error(e, st);
      }
    }
  }

  Future<void> markAsRead(String id) async {
    final previous = state.valueOrNull;
    if (previous != null && mounted) {
      state = AsyncValue.data(
        previous.map((n) => n.id == id ? n.copyWith(isRead: true) : n).toList(),
      );
    }

    try {
      await _repository.markAsRead(id);
    } catch (_) {
      // Revert optimistic update on failure
      if (previous != null && mounted) {
        state = AsyncValue.data(previous);
      }
    }
  }

  Future<void> markAllAsRead() async {
    final previous = state.valueOrNull;
    if (previous != null && mounted) {
      state = AsyncValue.data(
        previous.map((n) => n.copyWith(isRead: true)).toList(),
      );
    }

    try {
      await _repository.markAllAsRead();
    } catch (_) {
      if (previous != null && mounted) {
        state = AsyncValue.data(previous);
      }
    }
  }
}

final unreadCountProvider = Provider<int>((ref) {
  final asyncNotifications = ref.watch(notificationsProvider);
  return asyncNotifications.maybeWhen(
    data: (notifications) => notifications.where((n) => !n.isRead).length,
    orElse: () => 0,
  );
});
