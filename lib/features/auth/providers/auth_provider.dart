import 'dart:convert';
import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exceptions.dart';
import '../../../core/notifications/notification_service.dart';
import '../../../core/socket/socket_service.dart';

// ==========================================
// 1. GLOBAL AUTH STATE
// ==========================================
final isAuthenticatedProvider = StateProvider<bool>((ref) => false);
final currentUserProvider = StateProvider<Map<String, dynamic>?>((ref) => null);

// ==========================================
// 2. ENUMS FOR OTP CONTEXT
// ==========================================
enum OtpContext { auth, register, reset }

// ==========================================
// 3. AUTH CONTROLLER PROVIDER
// ==========================================
final authControllerProvider = Provider<AuthController>((ref) {
  return AuthController(ref.watch(apiClientProvider), ref);
});

// ==========================================
// 4. AUTH CONTROLLER IMPLEMENTATION
// ==========================================
class AuthController {
  final ApiClient _api;
  final Ref _ref;

  AuthController(this._api, this._ref);

  // ------------------------------------------
  // APP STARTUP CHECK
  // ------------------------------------------
  Future<void> checkInitialAuth() async {
    try {
      final token = await _api.storage.read(key: 'jwt_token');
      final userId = await _api.storage.read(key: 'user_id');
      final userDataStr = await _api.storage.read(key: 'user_data');

      if (token != null &&
          token.isNotEmpty &&
          userId != null &&
          userDataStr != null) {
        final userData = jsonDecode(userDataStr) as Map<String, dynamic>;
        _ref.read(currentUserProvider.notifier).state = userData;
        _ref.read(isAuthenticatedProvider.notifier).state = true;

        try {
          final mobile = userData['mobile']?.toString();
          final notifService = _ref.read(notificationServiceProvider);

          await notifService.registerTokenAfterLogin();
          await notifService.subscribeToUserTopics(mobile);
          await _ref.read(socketServiceProvider).connect(userId);
        } catch (e) {
          log('FCM/Socket Setup Error (Ignored): $e');
        }
      } else {
        _ref.read(isAuthenticatedProvider.notifier).state = false;
        _ref.read(currentUserProvider.notifier).state = null;
      }
    } catch (e) {
      _ref.read(isAuthenticatedProvider.notifier).state = false;
      _ref.read(currentUserProvider.notifier).state = null;
    }
  }

  // ------------------------------------------
  // LOGIN LOGIC
  // ------------------------------------------
  Future<bool> login(String identifier, String password) async {
    try {
      final response = await _api.dio.post(
        '/auth/admin/login',
        data: {'identifier': identifier, 'password': password},
      );

      if (response.data['needsVerification'] == true) {
        return false; // Tells the UI to route to the OTP screen
      }

      await saveSession(response.data);
      return true; // Success, tell UI to route Home
    } catch (e) {
      throw e is ApiException ? e : ApiException.fromDioException(e as dynamic);
    }
  }

  // ------------------------------------------
  // FORGOT PASSWORD
  // ------------------------------------------
  Future<void> forgotPassword(String identifier) async {
    try {
      await _api.dio.post(
        '/auth/forgot-password',
        data: {'identifier': identifier},
      );
    } catch (e) {
      throw e is ApiException ? e : ApiException.fromDioException(e as dynamic);
    }
  }

  // ------------------------------------------
  // VERIFY OTP
  // ------------------------------------------
  Future<bool> verifyOtp(
    String identifier,
    String otp,
    OtpContext contextType,
  ) async {
    try {
      final res = await _api.dio.post(
        '/auth/verify-otp',
        data: {
          'identifier': identifier,
          'otp': otp,
          'context': contextType.name.toUpperCase(),
        },
      );

      if (contextType == OtpContext.reset) {
        return true;
      } else {
        await saveSession(res.data);
        return true;
      }
    } catch (e) {
      throw e is ApiException ? e : ApiException.fromDioException(e as dynamic);
    }
  }

  // ------------------------------------------
  // RESET PASSWORD
  // ------------------------------------------
  Future<void> resetPassword(
    String identifier,
    String otp,
    String newPassword,
  ) async {
    try {
      await _api.dio.post(
        '/auth/reset-password',
        data: {
          'identifier': identifier,
          'otp': otp,
          'newPassword': newPassword,
        },
      );
    } catch (e) {
      throw e is ApiException ? e : ApiException.fromDioException(e as dynamic);
    }
  }

  // ------------------------------------------
  // SAVE SESSION & CONNECT SOCKETS
  // ------------------------------------------
  Future<void> saveSession(Map<String, dynamic> data) async {
    final token = data['accessToken'] ?? data['token'];
    final userObject = data['user'];
    final userId = userObject?['id'] ?? data['userId'];

    if (token != null) {
      await _api.storage.write(key: 'jwt_token', value: token);

      if (userId != null) {
        await _api.storage.write(key: 'user_id', value: userId.toString());
      }

      if (userObject != null) {
        await _api.storage.write(
          key: 'user_data',
          value: jsonEncode(userObject),
        );

        _ref.read(currentUserProvider.notifier).state =
            Map<String, dynamic>.from(userObject);

        try {
          final mobile = userObject['mobile']?.toString();
          final notifService = _ref.read(notificationServiceProvider);

          await notifService.registerTokenAfterLogin();
          await notifService.subscribeToUserTopics(mobile);
          await _ref.read(socketServiceProvider).connect(userId.toString());
        } catch (e) {
          log('Setup Error on Login (Ignored): $e');
        }
      }

      _ref.read(isAuthenticatedProvider.notifier).state = true;
    }
  }

  // ------------------------------------------
  // LOGOUT
  // ------------------------------------------
  Future<void> logout(BuildContext context) async {
    try {
      final currentUser = _ref.read(currentUserProvider);

      if (currentUser != null) {
        try {
          await _api.dio.post('/fcm/remove-fcm', data: {});
          final mobile = currentUser['mobile']?.toString();
          await _ref
              .read(notificationServiceProvider)
              .unsubscribeFromTopics(mobile);
        } catch (e) {
          log('FCM Unsubscribe Error (Ignored): $e');
        }
      }
    } catch (_) {
    } finally {
      _ref.read(socketServiceProvider).disconnect();

      await _api.storage.delete(key: 'jwt_token');
      await _api.storage.delete(key: 'user_id');
      await _api.storage.delete(key: 'user_data');

      _ref.read(isAuthenticatedProvider.notifier).state = false;
      _ref.read(currentUserProvider.notifier).state = null;

      if (context.mounted) {
        context.go('/login');
      }
    }
  }
}
