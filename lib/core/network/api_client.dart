import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Provider for FlutterSecureStorage so it can be injected globally
final secureStorageProvider = Provider<FlutterSecureStorage>((ref) {
  return const FlutterSecureStorage();
});

/// Provider for the ApiClient
final apiClientProvider = Provider<ApiClient>((ref) {
  final storage = ref.watch(secureStorageProvider);
  return ApiClient(storage);
});

class ApiClient {
  // Use 10.0.2.2 for Android Emulator, 127.0.0.1 for iOS Simulator, .
  // static const String baseUrl = 'http://10.0.2.2:8800/api';

  // local IPv4 address (e.g., 192.168.1.X) for physical devices
  static const String baseUrl = 'http://192.168.0.237:8800/api';

  final Dio dio;

  // Exposed publicly so controllers (like AuthController) can easily manage tokens
  final FlutterSecureStorage storage;

  ApiClient(this.storage)
    : dio = Dio(
        BaseOptions(
          baseUrl: baseUrl,
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 15),
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
        ),
      ) {
    dio.interceptors.add(
      InterceptorsWrapper(
        // ==========================================
        // 1. SMART TOKEN INJECTION
        // ==========================================
        onRequest: (options, handler) async {
          // ✅ Protect against token leaks and MinIO Auth conflicts:
          // Only attach the JWT token if the request is going to our Fastify backend.
          // Relative paths (starting with '/') or paths containing our baseUrl are safe.
          final isOurBackend =
              options.path.startsWith('/') || options.path.startsWith(baseUrl);

          if (isOurBackend) {
            final token = await storage.read(key: 'jwt_token');
            if (token != null && token.isNotEmpty) {
              options.headers['Authorization'] = 'Bearer $token';
            }
          }

          return handler.next(options);
        },

        // ==========================================
        // 2. HANDLE ERRORS (e.g., 401 UNAUTHORIZED)
        // ==========================================
        onError: (DioException error, handler) async {
          // If the token is expired or invalid, the backend returns 401.
          // We wipe the local token here. GoRouter's redirect logic will
          // automatically detect this and kick the user to the Login screen.
          if (error.response?.statusCode == 401) {
            await storage.delete(key: 'jwt_token');
            await storage.delete(key: 'user_id');
            // If you have a user_data key, it's good practice to clear it too
            await storage.delete(key: 'user_data');
          }
          return handler.next(error);
        },
      ),
    );
  }
}
