import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/socket/socket_service.dart';

class NotificationModel {
  final String id;
  final String title;
  final String message;
  final bool isRead;
  final String createdAt;
  final Map<String, dynamic>? data;

  NotificationModel({
    required this.id,
    required this.title,
    required this.message,
    required this.isRead,
    required this.createdAt,
    this.data,
  });

  factory NotificationModel.fromJson(Map<String, dynamic> json) {
    return NotificationModel(
      id: json['id'].toString(),
      title: json['title'] ?? '',
      message: json['message'] ?? '',
      isRead: json['is_read'] == true || json['is_read'] == 1,
      createdAt: json['created_at'] ?? '',
      data: json['data'] is Map<String, dynamic> ? json['data'] : null,
    );
  }
}

class NotificationRepository {
  final ApiClient _api;
  NotificationRepository(this._api);

  Future<List<NotificationModel>> fetchNotifications() async {
    final res = await _api.dio.get('/notifications');
    return (res.data as List)
        .map((e) => NotificationModel.fromJson(e))
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

    // =========================================================
    // BEST PRACTICE: BELL ICON AUTO-SYNC
    // Listen to the socket. When an event hits, silently fetch
    // the new list from the backend to instantly update the UI badge.
    // =========================================================
    _socket.listen('notification', (payload) {
      fetchInitial();
    });
  }

  Future<void> fetchInitial() async {
    try {
      final data = await _repository.fetchNotifications();
      state = AsyncValue.data(data);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> markAsRead(String id) async {
    if (state.hasValue) {
      final currentList = state.value!;
      state = AsyncValue.data(
        currentList
            .map(
              (n) => n.id == id
                  ? NotificationModel(
                      id: n.id,
                      title: n.title,
                      message: n.message,
                      isRead: true,
                      createdAt: n.createdAt,
                      data: n.data,
                    )
                  : n,
            )
            .toList(),
      );
    }
    await _repository.markAsRead(id);
  }

  Future<void> markAllAsRead() async {
    if (state.hasValue) {
      final currentList = state.value!;
      state = AsyncValue.data(
        currentList
            .map(
              (n) => NotificationModel(
                id: n.id,
                title: n.title,
                message: n.message,
                isRead: true,
                createdAt: n.createdAt,
                data: n.data,
              ),
            )
            .toList(),
      );
    }
    await _repository.markAllAsRead();
  }
}

// Automatically counts unread messages for the Red Bell Badge
final unreadCountProvider = Provider<int>((ref) {
  final asyncNotifications = ref.watch(notificationsProvider);
  return asyncNotifications.maybeWhen(
    data: (notifications) => notifications.where((n) => !n.isRead).length,
    orElse: () => 0,
  );
});
