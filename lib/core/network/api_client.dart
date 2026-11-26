import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'api_exceptions.dart';

/// Centralized secure storage keys
abstract final class StorageKeys {
  static const String jwtToken = 'jwt_token';
  static const String userId = 'user_id';
  static const String userData = 'user_data';
}

/// Provider for FlutterSecureStorage (v10+ AES-GCM hardware-backed keystore)
final secureStorageProvider = Provider<FlutterSecureStorage>((ref) {
  return const FlutterSecureStorage(
    aOptions: AndroidOptions(resetOnError: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );
});

/// Optional callback hook for syncing Riverpod auth state on 401
final onUnauthorizedProvider = StateProvider<VoidCallback?>((ref) => null);

/// Optional callback hook for opening the OAuth completion sheet on 403
final onOAuthOnboardingRequiredProvider = StateProvider<VoidCallback?>(
  (ref) => null,
);

/// Provider for the ApiClient
final apiClientProvider = Provider<ApiClient>((ref) {
  final storage = ref.watch(secureStorageProvider);
  final client = ApiClient(
    storage,
    onUnauthorized: () => ref.read(onUnauthorizedProvider)?.call(),
    onOAuthOnboardingRequired: () =>
        ref.read(onOAuthOnboardingRequiredProvider)?.call(),
  );
  ref.onDispose(client.dispose);
  return client;
});

class ApiClient {
  static const String _envBaseUrl = String.fromEnvironment('API_BASE_URL');

  /// Resolves API base URL from `--dart-define` / `--dart-define-from-file`.
  static String get baseUrl {
    final resolved = _envBaseUrl.trim().isNotEmpty
        ? _envBaseUrl.trim()
        : (kReleaseMode
              ? 'https://api.eventomir.ru/api'
              : 'http://192.168.0.237:8800/api');

    if (kReleaseMode && !resolved.startsWith('https://')) {
      throw StateError(
        'Production builds require an HTTPS API_BASE_URL (got: $resolved)',
      );
    }

    return resolved;
  }

  final Dio dio;
  final FlutterSecureStorage storage;
  final VoidCallback? onUnauthorized;
  final VoidCallback? onOAuthOnboardingRequired;
  final Uri _baseUri;

  bool _isHandlingUnauthorized = false;
  bool _isHandlingOAuthRequired = false;

  ApiClient(this.storage, {this.onUnauthorized, this.onOAuthOnboardingRequired})
    : _baseUri = Uri.parse(baseUrl),
      dio = Dio(
        BaseOptions(
          baseUrl: baseUrl,
          connectTimeout: const Duration(seconds: 15),
          sendTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 20),
          headers: const {'Accept': 'application/json'},
        ),
      ) {
    if (kDebugMode) {
      debugPrint(
        '🌐 ApiClient baseUrl: $baseUrl '
        '(from env: ${_envBaseUrl.trim().isNotEmpty})',
      );
    }

    dio.interceptors.add(
      InterceptorsWrapper(
        // ==========================================
        // 1. STRICT ORIGIN-SCOPED TOKEN INJECTION
        // ==========================================
        onRequest: (options, handler) async {
          final isOurBackend = _isBackendUri(options.uri);

          // Set JSON Content-Type only when sending a non-FormData body
          // (prevents Fastify FST_ERR_CTP_EMPTY_JSON_BODY on empty PATCH/DELETE)
          if (options.data == null || options.data is FormData) {
            options.contentType = null;
            options.headers.removeWhere(
              (k, _) => k.toLowerCase() == Headers.contentTypeHeader,
            );
          } else {
            options.contentType ??= Headers.jsonContentType;
          }

          if (isOurBackend) {
            final token = await getToken();
            if (token != null && token.isNotEmpty) {
              options.headers['Authorization'] = 'Bearer $token';
            }
          } else {
            // Never forward backend JWTs to presigned MinIO/S3 or external hosts
            options.headers.remove('Authorization');
          }

          return handler.next(options);
        },

        // ==========================================
        // 2. DEBOUNCED 401 & 403 OAUTH HANDLERS
        // ==========================================
        onError: (DioException error, handler) async {
          final isOurBackend = _isBackendUri(error.requestOptions.uri);
          final statusCode = error.response?.statusCode;
          final hadAuthHeader =
              error.requestOptions.headers['Authorization'] != null;

          // A. 401 Session Expiration (debounced across parallel in-flight requests)
          if (isOurBackend &&
              hadAuthHeader &&
              statusCode == 401 &&
              !_isHandlingUnauthorized) {
            _isHandlingUnauthorized = true;
            try {
              await clearSession();
              onUnauthorized?.call();
            } finally {
              Future.delayed(const Duration(seconds: 1), () {
                _isHandlingUnauthorized = false;
              });
            }
          }

          // B. 403 OAuth Onboarding Required (preserves JWT so user can verify phone)
          final responseData = error.response?.data;
          final errorCode = responseData is Map
              ? responseData['code']?.toString()
              : null;

          if (isOurBackend &&
              statusCode == 403 &&
              errorCode == ApiException.oauthOnboardingRequiredCode &&
              !_isHandlingOAuthRequired) {
            _isHandlingOAuthRequired = true;
            try {
              onOAuthOnboardingRequired?.call();
            } finally {
              Future.delayed(const Duration(seconds: 1), () {
                _isHandlingOAuthRequired = false;
              });
            }
          }

          return handler.next(error);
        },
      ),
    );

    // Full debug logging (completely stripped in release builds)
    if (kDebugMode) {
      dio.interceptors.add(
        LogInterceptor(
          request: true,
          requestHeader: true,
          requestBody: true,
          responseHeader: false,
          responseBody: true,
          error: true,
        ),
      );
    }
  }

  /// Strictly verifies scheme, host, and port so Bearer tokens cannot leak to
  /// spoofed prefix domains or presigned storage URLs.
  bool _isBackendUri(Uri uri) {
    return uri.scheme == _baseUri.scheme &&
        uri.host == _baseUri.host &&
        uri.port == _baseUri.port;
  }

  // ==========================================
  // 3. SAFE LIVE TOKEN & SESSION HELPERS
  // ==========================================
  Future<String?> getToken() async {
    try {
      return await storage.read(key: StorageKeys.jwtToken);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveToken(String token) async {
    await storage.write(key: StorageKeys.jwtToken, value: token);
  }

  Future<void> clearSession() async {
    try {
      await Future.wait([
        storage.delete(key: StorageKeys.jwtToken),
        storage.delete(key: StorageKeys.userId),
        storage.delete(key: StorageKeys.userData),
      ]);
    } catch (_) {
      // Ignore storage cleanup errors on corrupted keystore
    }
  }

  void dispose() {
    dio.close();
  }
}
