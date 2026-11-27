import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/chat/providers/active_chat_provider.dart';
import '../network/api_client.dart';
import '../router/app_router.dart';
import '../router/route_names.dart';
import '../socket/socket_service.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  log('Background Admin FCM received: ${message.messageId}');
}

final notificationServiceProvider = Provider<NotificationService>((ref) {
  final service = NotificationService(
    ref,
    ref.watch(apiClientProvider),
    rootNavigatorKey,
    ref.watch(socketServiceProvider),
  );
  ref.onDispose(service.dispose);
  return service;
});

class NotificationService {
  static const String _androidChannelId = 'klinciti_high_priority';
  static const Duration _dedupeWindow = Duration(seconds: 60);

  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localPlugin =
      FlutterLocalNotificationsPlugin();

  final Ref _ref;
  final ApiClient _apiClient;
  final GlobalKey<NavigatorState> _navigatorKey;
  final SocketService _socketService;

  final Map<String, DateTime> _recentNotificationIds = {};

  StreamSubscription<String>? _tokenRefreshSub;
  StreamSubscription<RemoteMessage>? _onMessageSub;
  StreamSubscription<RemoteMessage>? _onMessageOpenedSub;

  bool _isInitialized = false;
  bool _isLocalPluginReady = false;

  NotificationService(
    this._ref,
    this._apiClient,
    this._navigatorKey,
    this._socketService,
  );

  void dispose() {
    _socketService.stopListening('notification', _handleSocketMessage);
    _tokenRefreshSub?.cancel();
    _onMessageSub?.cancel();
    _onMessageOpenedSub?.cancel();
  }

  Future<void> initialize() async {
    if (_isInitialized) return;
    _isInitialized = true;

    await _initLocalNotifications();
    _socketService.listen('notification', _handleSocketMessage);

    final settings = await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional) {
      if (!kIsWeb && Platform.isIOS) {
        await _fcm.setForegroundNotificationPresentationOptions(
          alert: false,
          badge: true,
          sound: false,
        );
      }

      final token = await _fcm.getToken();
      if (token != null && token.isNotEmpty) {
        await _registerDeviceToken(token);
      }

      _tokenRefreshSub = _fcm.onTokenRefresh.listen(
        (newToken) => unawaited(_registerDeviceToken(newToken)),
      );

      _onMessageSub = FirebaseMessaging.onMessage.listen(
        _handleFcmForegroundMessage,
      );

      _onMessageOpenedSub = FirebaseMessaging.onMessageOpenedApp.listen(
        (msg) => _routeFromData(msg.data),
      );

      final initialMessage = await _fcm.getInitialMessage();
      if (initialMessage != null) {
        Future.delayed(
          const Duration(milliseconds: 500),
          () => _routeFromData(initialMessage.data),
        );
      }
    }
  }

  Future<void> _initLocalNotifications() async {
    if (_isLocalPluginReady) return;

    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      _androidChannelId,
      'Системные уведомления Admin',
      description: 'Новые заявки, споры, модерация и финансовые оповещения',
      importance: Importance.max,
      enableVibration: true,
      playSound: true,
    );

    await _localPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(channel);

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings();

    await _localPlugin.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
      onDidReceiveNotificationResponse: _onSelectNotification,
    );

    _isLocalPluginReady = true;
  }

  Future<void> registerTokenAfterLogin() async {
    try {
      final fcmToken = await _fcm.getToken();
      if (fcmToken != null && fcmToken.isNotEmpty) {
        await _registerDeviceToken(fcmToken, forceRegister: true);
      }
    } catch (e) {
      log('❌ Failed to register Admin FCM token: $e');
    }
  }

  Future<void> unregisterTokenOnLogout() async {
    try {
      final fcmToken = await _fcm.getToken();
      await _apiClient.dio.post(
        '/fcm/remove-fcm',
        data: {
          if (fcmToken != null && fcmToken.isNotEmpty) 'fcmToken': fcmToken,
        },
      );
      _recentNotificationIds.clear();
      log('✅ Admin FCM token unregistered on logout');
    } catch (e) {
      log('⚠️ Failed to unregister Admin FCM token: $e');
    }
  }

  Future<void> _registerDeviceToken(
    String fcmToken, {
    bool forceRegister = false,
  }) async {
    try {
      final token = await _apiClient.storage.read(key: StorageKeys.jwtToken);
      if (!forceRegister && (token == null || token.isEmpty)) return;

      final String deviceType = (!kIsWeb && Platform.isIOS) ? 'IOS' : 'ANDROID';
      await _apiClient.dio.post(
        '/fcm/save-fcm',
        data: {'fcmToken': fcmToken, 'deviceType': deviceType},
      );
      log('✅ Admin FCM Token registered ($deviceType)');
    } catch (e) {
      log('❌ Admin FCM Token registration failed: $e');
    }
  }

  bool _shouldSuppressChatNotification(Map<String, dynamic> data) {
    final type = data['type']?.toString().toUpperCase() ?? '';
    final sessionId = data['sessionId']?.toString();
    if (type != 'CHAT_FCM' || sessionId == null || sessionId.isEmpty) {
      return false;
    }
    return _ref.read(activeChatSessionProvider) == sessionId;
  }

  void _processIncomingNotification({
    required String id,
    required String title,
    required String body,
    required Map<String, dynamic> payloadData,
  }) {
    if (!_isLocalPluginReady) return;
    if (_shouldSuppressChatNotification(payloadData)) return;

    final now = DateTime.now();
    _recentNotificationIds.removeWhere(
      (_, timestamp) => now.difference(timestamp) > _dedupeWindow,
    );
    if (_recentNotificationIds.containsKey(id)) return;
    _recentNotificationIds[id] = now;

    String stringifiedPayload = '{}';
    try {
      stringifiedPayload = jsonEncode(payloadData);
    } catch (_) {}

    _localPlugin.show(
      id.hashCode & 0x7FFFFFFF,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _androidChannelId,
          'Системные уведомления Admin',
          channelDescription:
              'Новые заявки, споры, модерация и финансовые оповещения',
          importance: Importance.max,
          priority: Priority.high,
          enableVibration: true,
          playSound: true,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: stringifiedPayload,
    );
  }

  void _handleFcmForegroundMessage(RemoteMessage message) {
    final data = Map<String, dynamic>.from(message.data);
    final title = message.notification?.title ?? data['title']?.toString();
    final body = message.notification?.body ?? data['body']?.toString();
    if ((title == null || title.isEmpty) && (body == null || body.isEmpty)) {
      return;
    }

    final sharedId =
        data['notificationId']?.toString() ??
        data['id']?.toString() ??
        message.messageId ??
        DateTime.now().millisecondsSinceEpoch.toString();

    _processIncomingNotification(
      id: sharedId,
      title: title ?? 'Системное уведомление',
      body: body ?? '',
      payloadData: data,
    );
  }

  void _handleSocketMessage(dynamic payload) {
    try {
      final Map<String, dynamic> data = payload is String
          ? Map<String, dynamic>.from(jsonDecode(payload) as Map)
          : Map<String, dynamic>.from(payload as Map);

      Map<String, dynamic> nestedData = {};
      if (data['data'] is Map) {
        nestedData = Map<String, dynamic>.from(data['data'] as Map);
      }

      final Map<String, dynamic> mergedPayload = {
        if (data['notificationId'] != null)
          'notificationId': data['notificationId'],
        if (data['type'] != null) 'type': data['type'],
        if (data['subType'] != null) 'subType': data['subType'],
        if (data['url'] != null) 'url': data['url'],
        if (data['sessionId'] != null) 'sessionId': data['sessionId'],
        if (data['partnerId'] != null) 'partnerId': data['partnerId'],
        if (data['jobId'] != null) 'jobId': data['jobId'],
        if (data['workerId'] != null) 'workerId': data['workerId'],
        if (data['paymentId'] != null) 'paymentId': data['paymentId'],
        ...nestedData,
      };

      final uniqueId =
          mergedPayload['notificationId']?.toString() ??
          data['notificationId']?.toString() ??
          data['id']?.toString() ??
          DateTime.now().millisecondsSinceEpoch.toString();

      _processIncomingNotification(
        id: uniqueId,
        title:
            data['title']?.toString() ??
            mergedPayload['title']?.toString() ??
            'Системное уведомление',
        body:
            data['body']?.toString() ??
            data['message']?.toString() ??
            mergedPayload['body']?.toString() ??
            '',
        payloadData: mergedPayload,
      );
    } catch (e) {
      log('❌ Admin Socket Payload Parse Error: $e');
    }
  }

  void _onSelectNotification(NotificationResponse response) {
    final rawPayload = response.payload;
    if (rawPayload != null && rawPayload.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawPayload);
        if (decoded is Map) {
          _routeFromData(Map<String, dynamic>.from(decoded));
        }
      } catch (e) {
        log('❌ Admin notification tap decode error: $e');
      }
    }
  }

  // ==============================================================
  // ADMIN DEEP-LINK ROUTER
  // ==============================================================
  void _routeFromData(Map<String, dynamic> data) {
    final context = _navigatorKey.currentContext;
    if (context == null) return;

    final type = data['type']?.toString().toUpperCase() ?? '';
    final subType = data['subType']?.toString().toUpperCase() ?? '';
    final url = data['url']?.toString().trim() ?? '';
    final sessionId = data['sessionId']?.toString();
    final partnerId = data['partnerId']?.toString();
    final jobId = data['jobId']?.toString();
    final workerId = data['workerId']?.toString();

    // 1. Cash Monitor alerts (debt caps, overdue workers, cash disputes)
    if (url.startsWith(AppRoutes.cashMonitor) ||
        subType.startsWith('ADMIN_WORKER_') ||
        subType == 'ADMIN_CASH_DISPUTE') {
      context.push(AppRoutes.cashMonitor);
      return;
    }

    // 2. Chat messages (preserve partnerId so typing/presence/read-receipts work)
    if (sessionId != null && sessionId.isNotEmpty) {
      final path = (partnerId != null && partnerId.isNotEmpty)
          ? '${AppRoutes.chatDetail}/$sessionId/$partnerId'
          : '${AppRoutes.chatDetail}/$sessionId';
      context.push(path);
      return;
    }

    // 3. Finance / T-Bank payouts & refunds
    if (type.contains('PAYOUT') ||
        type.contains('PAYMENT') ||
        type.contains('REFUND')) {
      context.push(AppRoutes.finance);
      return;
    }

    // 4. Direct internal URL fallback from broadcasts or system alerts
    if (url.startsWith('/') && !url.startsWith('//') && url != '/') {
      context.push(url);
      return;
    }

    // 5. Entity fallbacks
    if (workerId != null && workerId.isNotEmpty) {
      context.push('${AppRoutes.workerDetail}/$workerId');
      return;
    }
    if (jobId != null && jobId.isNotEmpty) {
      context.push('${AppRoutes.jobDetail}/$jobId');
      return;
    }

    context.push(AppRoutes.notifications);
  }
}
