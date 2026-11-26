import 'package:dio/dio.dart';

class ApiException implements Exception {
  static const String oauthOnboardingRequiredCode = 'OAUTH_ONBOARDING_REQUIRED';

  final String message;
  final int? statusCode;
  final String? code;
  final int? retryAfter;

  ApiException(this.message, {this.statusCode, this.code, this.retryAfter});

  bool get isOAuthOnboardingRequired =>
      statusCode == 403 && code == oauthOnboardingRequiredCode;

  factory ApiException.fromDioException(dynamic error) {
    if (error is ApiException) return error;

    if (error is DioException) {
      final statusCode = error.response?.statusCode;
      final rawData = error.response?.data;

      if (rawData is Map) {
        final data = Map<String, dynamic>.from(rawData);
        final code = data['code']?.toString().trim();
        final retryAfter = data['retryAfter'] is num
            ? (data['retryAfter'] as num).toInt()
            : int.tryParse(data['retryAfter']?.toString() ?? '');

        final extractedMessage = _extractServerMessage(data);
        if (extractedMessage != null) {
          return ApiException(
            extractedMessage,
            statusCode: statusCode,
            code: (code != null && code.isNotEmpty) ? code : null,
            retryAfter: retryAfter,
          );
        }
      }

      // Handle network timeouts, offline states, and cancelled requests
      switch (error.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
        case DioExceptionType.connectionError:
          return ApiException(
            'Нет подключения к серверу. Проверьте интернет.',
            statusCode: statusCode,
          );
        case DioExceptionType.cancel:
          return ApiException('Запрос был отменен.', statusCode: statusCode);
        case DioExceptionType.badCertificate:
          return ApiException(
            'Ошибка защищенного соединения с сервером.',
            statusCode: statusCode,
          );
        default:
          // Covers badResponse, transformTimeout, unknown, and any future Dio types
          return ApiException(
            'Упс! Что-то пошло не так. Повторите попытку позже.',
            statusCode: statusCode,
          );
      }
    }

    return ApiException('Упс! Что-то пошло не так. Повторите попытку позже.');
  }

  /// Handles both custom Fastify `{ error: "Русский текст" }` responses and
  /// built-in Fastify `{ statusCode, error: "Bad Request", message: "..." }` payloads.
  static String? _extractServerMessage(Map<String, dynamic> data) {
    final errStr = data['error']?.toString().trim();
    final msgStr = data['message']?.toString().trim();

    const genericHttpErrors = {
      'Bad Request',
      'Unauthorized',
      'Forbidden',
      'Not Found',
      'Conflict',
      'Too Many Requests',
      'Internal Server Error',
    };

    if (errStr != null &&
        errStr.isNotEmpty &&
        !genericHttpErrors.contains(errStr)) {
      return errStr;
    }
    if (msgStr != null && msgStr.isNotEmpty) {
      return msgStr;
    }
    if (errStr != null && errStr.isNotEmpty) {
      return errStr;
    }
    return null;
  }

  @override
  String toString() => message;
}
