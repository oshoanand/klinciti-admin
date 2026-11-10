import 'dart:io';
import 'dart:convert';
import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../network/api_client.dart';
import '../router/app_router.dart';
import '../socket/socket_service.dart';
import '../../core/router/route_names.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  log('Background FCM received: ${message.messageId}');
}

final notificationServiceProvider = Provider<NotificationService>((ref) {
  return NotificationService(
    ref.watch(apiClientProvider),
    rootNavigatorKey,
    ref.watch(socketServiceProvider),
  );
});

class NotificationService {
  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localPlugin =
      FlutterLocalNotificationsPlugin();

  final ApiClient _apiClient;
  final GlobalKey<NavigatorState> _navigatorKey;
  final SocketService _socketService;

  // Prevents duplicate notifications if BOTH Socket and FCM deliver the same message
  final Set<String> _recentNotificationIds = {};

  NotificationService(this._apiClient, this._navigatorKey, this._socketService);

  Future<void> initialize() async {
    final settings = await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: true, // Allows silent fallback if user denies full popup
    );

    // Accept both authorized and provisional states
    if (settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional) {
      // CREATE THE BRAND NEW HIGH PRIORITY CHANNEL
      const AndroidNotificationChannel channel = AndroidNotificationChannel(
        'klinciti_high_priority',
        'Важные уведомления',
        description: 'Уведомления о заказах и сообщениях',
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

      final token = await _fcm.getToken();
      if (token != null) await _registerDeviceToken(token);
      _fcm.onTokenRefresh.listen(_registerDeviceToken);

      FirebaseMessaging.onMessage.listen(_handleFcmForegroundMessage);
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
      FirebaseMessaging.onMessageOpenedApp.listen(
        (msg) => _routeFromData(msg.data),
      );

      final initialMessage = await FirebaseMessaging.instance
          .getInitialMessage();
      if (initialMessage != null) {
        Future.delayed(
          const Duration(milliseconds: 500),
          () => _routeFromData(initialMessage.data),
        );
      }

      _socketService.listen('notification', _handleSocketMessage);
    }
  }

  void _processIncomingNotification({
    required String id,
    required String title,
    required String body,
    required Map<dynamic, dynamic> payloadData,
  }) {
    if (_recentNotificationIds.contains(id)) return;
    _recentNotificationIds.add(id);
    if (_recentNotificationIds.length > 50) _recentNotificationIds.clear();

    final context = _navigatorKey.currentContext;
    if (context != null) {
      try {
        // Ask the router delegate directly for the current URI
        final router = GoRouter.of(context);
        final currentRoute = router.routerDelegate.currentConfiguration.uri
            .toString();

        final type = payloadData['type']?.toString().toUpperCase() ?? '';

        // ✅ FIXED: Correctly check the active chat route to suppress the local banner
        if ((type == 'CHAT' || type == 'CHAT_FCM') &&
            payloadData['sessionId'] != null) {
          final targetSessionId = payloadData['sessionId'];

          if (currentRoute.contains('/chat/$targetSessionId')) {
            return; // Suppress OS banner only if user is actively in this exact chat
          }
        }
      } catch (e) {
        log(
          '⚠️ Route check failed, proceeding to show notification anyway: $e',
        );
      }
    }

    // Safely encode JSON to prevent crashes
    String stringifiedPayload = '{}';
    try {
      stringifiedPayload = jsonEncode(payloadData);
    } catch (_) {}

    _localPlugin.show(
      id.hashCode,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'klinciti_high_priority', // Must match the channel in AndroidManifest
          'Важные уведомления',
          channelDescription: 'Уведомления о заказах и сообщениях',
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

  // ==============================================================
  // AUTH BRIDGES
  // ==============================================================

  Future<void> registerTokenAfterLogin() async {
    try {
      final fcmToken = await _fcm.getToken();
      if (fcmToken != null) {
        await _registerDeviceToken(fcmToken, forceRegister: true);
      }
    } catch (e) {
      log('Failed to register token after login: $e');
    }
  }

  Future<void> subscribeToUserTopics(String? mobile) async {
    try {
      await _fcm.subscribeToTopic('kilinciti_admins_topic');
      if (mobile != null && mobile.isNotEmpty) {
        final String digits = mobile.replaceAll(RegExp(r'\D'), '');
        String userTopic = '';
        if (digits.length == 11 &&
            (digits.startsWith('7') || digits.startsWith('8'))) {
          userTopic = 'user_${digits.substring(1)}';
        } else if (digits.isNotEmpty) {
          userTopic = 'user_$digits';
        }
        if (userTopic.isNotEmpty) await _fcm.subscribeToTopic(userTopic);
      }
    } catch (e) {
      log('❌ Failed to subscribe to topics: $e');
    }
  }

  Future<void> unsubscribeFromTopics(String? mobile) async {
    try {
      await _fcm.unsubscribeFromTopic('kilinciti_admins_topic');
      if (mobile != null && mobile.isNotEmpty) {
        final String digits = mobile.replaceAll(RegExp(r'\D'), '');
        String userTopic = '';
        if (digits.length == 11 &&
            (digits.startsWith('7') || digits.startsWith('8'))) {
          userTopic = 'user_${digits.substring(1)}';
        } else if (digits.isNotEmpty) {
          userTopic = 'user_$digits';
        }
        if (userTopic.isNotEmpty) await _fcm.unsubscribeFromTopic(userTopic);
      }
    } catch (e) {}
  }

  // ==============================================================
  // INTERNAL HELPERS
  // ==============================================================

  Future<void> _registerDeviceToken(
    String fcmToken, {
    bool forceRegister = false,
  }) async {
    try {
      final token = await _apiClient.storage.read(key: 'jwt_token');
      if (!forceRegister && (token == null || token.isEmpty)) return;

      String deviceType = Platform.isIOS ? 'IOS' : 'ANDROID';
      await _apiClient.dio.post(
        '/fcm/save-fcm',
        data: {'fcmToken': fcmToken, 'deviceType': deviceType},
      );
      log('✅ FCM Token registered ($deviceType)');
    } catch (e) {
      log('❌ FCM Token registration failed.');
    }
  }

  void _handleFcmForegroundMessage(RemoteMessage message) {
    if (message.notification != null) {
      _processIncomingNotification(
        id: message.messageId ?? DateTime.now().toString(),
        title: message.notification!.title ?? 'Уведомление',
        body: message.notification!.body ?? '',
        payloadData: message.data,
      );
    }
  }

  void _handleSocketMessage(dynamic payload) {
    try {
      final Map<String, dynamic> data = payload is String
          ? Map<String, dynamic>.from(jsonDecode(payload))
          : Map<String, dynamic>.from(payload as Map);

      final String uniqueId =
          data['id']?.toString() ?? DateTime.now().toString();

      // Safely parse nested data
      final Map<dynamic, dynamic> rawData = data['data'] is Map
          ? data['data']
          : {};
      final String title = data['title'] ?? rawData['title'] ?? 'Уведомление';
      final String body = data['body'] ?? data['message'] ?? '';

      _processIncomingNotification(
        id: uniqueId,
        title: title,
        body: body,
        payloadData: rawData,
      );
    } catch (e) {
      log('❌ Socket Payload Parse Error: $e');
    }
  }

  void _onSelectNotification(NotificationResponse response) {
    if (response.payload != null) _routeFromData(jsonDecode(response.payload!));
  }

  void _routeFromData(Map<String, dynamic> data) {
    final context = _navigatorKey.currentContext;
    if (context == null) return;

    final type = data['type']?.toString().toUpperCase();

    if (type == 'CHAT_FCM' || type == 'CHAT') {
      final sessionId = data['sessionId'] ?? data['chatId'];
      final partnerId = data['partnerId'];

      if (sessionId != null && partnerId != null) {
        context.go('${AppRoutes.chatDetail}/$sessionId/$partnerId');
      } else {
        context.go(AppRoutes.chatList);
      }
    } else if (type == 'JOB') {
      context.go('${AppRoutes.jobsList}/NEW');
    } else {
      context.go(AppRoutes.notifications);
    }
  }
}
