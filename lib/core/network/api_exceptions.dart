import 'package:dio/dio.dart';

class ApiException implements Exception {
  final String message;
  final int? statusCode;

  ApiException(this.message, {this.statusCode});

  factory ApiException.fromDioException(dynamic error) {
    if (error is DioException) {
      // FIXED: First check if the data is actually a JSON Map before reading keys!
      if (error.response?.data != null &&
          error.response?.data is Map<String, dynamic>) {
        final data = error.response!.data as Map<String, dynamic>;

        if (data.containsKey('error') && data['error'] != null) {
          return ApiException(
            data['error'].toString(),
            statusCode: error.response?.statusCode,
          );
        }
      }

      // Handle Network timeouts and No Internet
      if (error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.receiveTimeout ||
          error.type == DioExceptionType.connectionError) {
        return ApiException(
          'Нет подключения к серверу. Проверьте интернет.',
          statusCode: error.response?.statusCode,
        );
      }

      // If it's a 500 error or a non-JSON response (like an HTML error page)
      return ApiException(
        'Упс! Что-то пошло не так. Повторите попытку позже.',
        statusCode: error.response?.statusCode,
      );
    }

    return ApiException('Упс! Что-то пошло не так. Повторите попытку позже.');
  }

  @override
  String toString() => message;
}
