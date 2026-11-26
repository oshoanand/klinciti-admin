import 'dart:async';
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
// 4. AUTH CONTROLLER IMPLEMENTATION (ADMIN APP)
// ==========================================
class AuthController {
  static const String _jwtKey = 'jwt_token';
  static const String _userIdKey = 'user_id';
  static const String _userDataKey = 'user_data';
  static const Set<String> _allowedAdminRoles = {'ADMINISTRATOR', 'SUPPORT'};

  final ApiClient _api;
  final Ref _ref;

  AuthController(this._api, this._ref);

  // ------------------------------------------
  // IDENTIFIER NORMALIZATION
  // ------------------------------------------
  String normalizeIdentifier(String raw) {
    final trimmed = raw.trim();
    if (trimmed.contains('@')) {
      return trimmed.toLowerCase();
    }
    final digits = trimmed.replaceAll(RegExp(r'\D'), '');
    if (digits.length == 10) return '7$digits';
    if (digits.length == 11 && digits.startsWith('8')) {
      return '7${digits.substring(1)}';
    }
    return digits;
  }

  // ------------------------------------------
  // APP STARTUP CHECK
  // ------------------------------------------
  Future<void> checkInitialAuth() async {
    try {
      final results = await Future.wait([
        _api.storage.read(key: _jwtKey),
        _api.storage.read(key: _userIdKey),
        _api.storage.read(key: _userDataKey),
      ]);

      final token = results[0];
      final userId = results[1];
      final userDataStr = results[2];

      if (token != null &&
          token.isNotEmpty &&
          userId != null &&
          userId.isNotEmpty &&
          userDataStr != null &&
          userDataStr.isNotEmpty) {
        final decoded = jsonDecode(userDataStr);
        if (decoded is! Map) {
          throw const FormatException('Corrupt user_data format');
        }

        final userData = Map<String, dynamic>.from(decoded);
        final role = (userData['role'] ?? '').toString().toUpperCase();
        if (role.isNotEmpty && !_allowedAdminRoles.contains(role)) {
          await clearSession();
          return;
        }

        _ref.read(currentUserProvider.notifier).state = userData;
        _ref.read(isAuthenticatedProvider.notifier).state = true;

        unawaited(_initRealtimeServices(userId));
      } else {
        await clearSession();
      }
    } catch (e) {
      log('⚠️ Admin initial auth check failed, clearing corrupt session: $e');
      await clearSession();
    }
  }

  // ------------------------------------------
  // LOGIN LOGIC
  // ------------------------------------------
  Future<bool> login(String identifier, String password) async {
    try {
      final response = await _api.dio.post(
        '/auth/admin/login',
        data: {
          'identifier': normalizeIdentifier(identifier),
          'password': password,
        },
      );

      if (response.data is! Map) {
        throw ApiException('Некорректный ответ сервера при входе');
      }

      final map = Map<String, dynamic>.from(response.data as Map);
      final payload = map['data'] is Map
          ? Map<String, dynamic>.from(map['data'] as Map)
          : map;

      if (payload['needsVerification'] == true ||
          payload['requiresOtp'] == true) {
        return false; // Route UI to OTP verification
      }

      await saveSession(map);
      return true;
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException.fromDioException(e);
    }
  }

  // ------------------------------------------
  // FORGOT PASSWORD
  // ------------------------------------------
  Future<void> forgotPassword(String identifier) async {
    try {
      await _api.dio.post(
        '/auth/forgot-password',
        data: {'identifier': normalizeIdentifier(identifier)},
      );
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException.fromDioException(e);
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
          'identifier': normalizeIdentifier(identifier),
          'otp': otp.trim(),
          'context': contextType.name.toUpperCase(),
        },
      );

      if (contextType == OtpContext.reset) {
        return true;
      }

      if (res.data is! Map) {
        throw ApiException('Некорректный ответ сервера при проверке кода');
      }

      await saveSession(Map<String, dynamic>.from(res.data as Map));
      return true;
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException.fromDioException(e);
    }
  }

  // ------------------------------------------
  // RESEND OTP
  // ------------------------------------------
  Future<void> resendOtp(String identifier, OtpContext contextType) async {
    try {
      await _api.dio.post(
        '/auth/resend-otp',
        data: {
          'identifier': normalizeIdentifier(identifier),
          'context': contextType.name.toUpperCase(),
        },
      );
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException.fromDioException(e);
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
          'identifier': normalizeIdentifier(identifier),
          'otp': otp.trim(),
          'newPassword': newPassword,
        },
      );
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException.fromDioException(e);
    }
  }

  // ------------------------------------------
  // SAVE SESSION & CONNECT REAL-TIME SERVICES
  // ------------------------------------------
  Future<void> saveSession(Map<String, dynamic> data) async {
    final payload = data['data'] is Map
        ? Map<String, dynamic>.from(data['data'] as Map)
        : data;

    final String token = (payload['accessToken'] ?? payload['token'] ?? '')
        .toString()
        .trim();
    final Map<String, dynamic>? userObject = payload['user'] is Map
        ? Map<String, dynamic>.from(payload['user'] as Map)
        : null;
    final String userId = (userObject?['id'] ?? payload['userId'] ?? '')
        .toString()
        .trim();

    if (token.isEmpty || userId.isEmpty) {
      throw ApiException('Сервер не вернул токен или ID администратора');
    }

    // Enforce Admin/Support role access
    final String role = (userObject?['role'] ?? payload['role'] ?? '')
        .toString()
        .toUpperCase();
    if (role.isNotEmpty && !_allowedAdminRoles.contains(role)) {
      throw ApiException(
        'Доступ запрещен: требуется учетная запись администратора или поддержки.',
      );
    }

    await Future.wait([
      _api.storage.write(key: _jwtKey, value: token),
      _api.storage.write(key: _userIdKey, value: userId),
      if (userObject != null)
        _api.storage.write(key: _userDataKey, value: jsonEncode(userObject)),
    ]);

    if (userObject != null) {
      _ref.read(currentUserProvider.notifier).state = userObject;
    }
    _ref.read(isAuthenticatedProvider.notifier).state = true;

    unawaited(_initRealtimeServices(userId));
  }

  /// Syncs Riverpod state and secure storage after admin profile updates.
  Future<void> updateCurrentUser(Map<String, dynamic> updatedFields) async {
    final current = _ref.read(currentUserProvider) ?? <String, dynamic>{};
    final merged = <String, dynamic>{...current, ...updatedFields};

    _ref.read(currentUserProvider.notifier).state = merged;
    await _api.storage.write(key: _userDataKey, value: jsonEncode(merged));
  }

  // ------------------------------------------
  // LOGOUT & TEARDOWN
  // ------------------------------------------
  Future<void> logout(BuildContext context) async {
    try {
      // Unregister THIS device's FCM token while JWT is still present
      await _ref.read(notificationServiceProvider).unregisterTokenOnLogout();
    } catch (e) {
      log('⚠️ Admin FCM logout cleanup error (ignored): $e');
    } finally {
      await clearSession();

      if (context.mounted) {
        context.go('/login');
      }
    }
  }

  /// Context-free teardown for 401 interceptors and corrupt-storage recovery.
  Future<void> clearSession() async {
    _ref.read(socketServiceProvider).disconnect();

    await Future.wait([
      _api.storage.delete(key: _jwtKey),
      _api.storage.delete(key: _userIdKey),
      _api.storage.delete(key: _userDataKey),
    ]);

    _ref.read(isAuthenticatedProvider.notifier).state = false;
    _ref.read(currentUserProvider.notifier).state = null;
  }

  // ------------------------------------------
  // REAL-TIME SERVICES (DECOUPLED)
  // ------------------------------------------
  Future<void> _initRealtimeServices(String userId) async {
    await Future.wait([
      _ref
          .read(notificationServiceProvider)
          .registerTokenAfterLogin()
          .catchError((Object e) {
            log('⚠️ Admin FCM token registration skipped: $e');
          }),
      _ref.read(socketServiceProvider).connect(userId).catchError((Object e) {
        log('⚠️ Admin Socket connection skipped: $e');
      }),
    ]);
  }
}
