import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';

final networkMonitorProvider = StateNotifierProvider<NetworkMonitor, bool>((
  ref,
) {
  return NetworkMonitor(ref.watch(apiClientProvider));
});

// State: true = Online, false = Offline
class NetworkMonitor extends StateNotifier<bool> {
  final ApiClient _api;
  Timer? _timer;

  NetworkMonitor(this._api) : super(true) {
    _startMonitoring();
  }

  void _startMonitoring() {
    // Ping immediately on startup
    _checkConnection();

    // Ping every 15 seconds to ensure real connection to the backend
    _timer = Timer.periodic(const Duration(seconds: 15), (_) {
      _checkConnection();
    });
  }

  Future<void> _checkConnection() async {
    try {
      // Using a fast HEAD request to the root or health endpoint
      // Update this path if your backend has a dedicated '/health' route
      await _api.dio.head(
        '/health',
        options: Options(
          receiveTimeout: const Duration(seconds: 5),
          sendTimeout: const Duration(seconds: 5),
        ),
      );
      if (!state) state = true; // Back online
    } catch (e) {
      // If connection times out or fails, we are offline
      if (e is DioException &&
          (e.type == DioExceptionType.connectionTimeout ||
              e.type == DioExceptionType.connectionError)) {
        if (state) state = false; // Went offline
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
