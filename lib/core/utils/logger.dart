import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

class Log {
  static void info(String message, {String tag = 'INFO'}) {
    if (kDebugMode) {
      developer.log(message, name: tag);
    }
  }

  static void error(String message, [dynamic error, StackTrace? stackTrace]) {
    if (kDebugMode) {
      developer.log(
        message,
        name: 'ERROR',
        error: error,
        stackTrace: stackTrace,
      );
    }
    // TODO: Connect to Crashlytics or Sentry here for production
  }
}
