import 'dart:developer';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../network/api_client.dart';

final socketServiceProvider = Provider<SocketService>((ref) {
  return SocketService();
});

class SocketService {
  io.Socket? _socket;
  final _storage = const FlutterSecureStorage();

  // Cache listeners if services try to listen BEFORE the user logs in!
  final Map<String, List<Function(dynamic)>> _pendingListeners = {};

  bool get isConnected => _socket?.connected ?? false;

  Future<void> connect(String userId) async {
    if (_socket?.connected == true) return;

    final token = await _storage.read(key: 'jwt_token');

    // Safely parse URI. `authority` perfectly handles "host:port"
    // or just "host" for standard http/https, while stripping "/api" paths.
    final uri = Uri.parse(ApiClient.baseUrl);
    final String socketUrl = '${uri.scheme}://${uri.authority}';

    _socket = io.io(
      socketUrl,
      io.OptionBuilder()
          .setPath('/socket.io')
          //  Force WebSocket. Polling causes duplicate connection IDs
          // and dropping if sticky sessions aren't perfectly configured on the server.
          .setTransports(['websocket'])
          .enableReconnection()
          .setReconnectionAttempts(
            99999,
          ) // ✅ Infinite retries for background/foreground recovery
          .setReconnectionDelay(1000)
          .setReconnectionDelayMax(5000)
          .setAuth({
            'token': token ?? '',
            'userId': userId,
            'role': 'ADMINISTRATOR',
          })
          .disableAutoConnect() // Initialize the object first without connecting
          .build(),
    );

    // Apply any listeners that were requested before the socket was initialized
    _pendingListeners.forEach((event, callbacks) {
      for (var callback in callbacks) {
        _socket?.on(event, callback);
      }
    });
    _pendingListeners.clear();

    _socket?.onConnect((_) {
      log('✅ Socket Connected to $socketUrl (ID:${_socket?.id})');
    });

    _socket?.onDisconnect((_) {
      log('⚠️ Socket Disconnected');
    });

    _socket?.onReconnect((attempt) {
      log('🔄 Socket Reconnected after $attempt attempts');
    });

    _socket?.onConnectError((err) => log('❌ Socket Connection Error: $err'));
    _socket?.onError((err) => log('❌ Socket Error: $err'));

    // Finally, connect to the server
    _socket?.connect();
  }

  void listen(String event, Function(dynamic) callback) {
    if (_socket != null) {
      _socket?.on(event, callback);
    } else {
      // If socket isn't connected yet, save the listener for later!
      _pendingListeners.putIfAbsent(event, () => []).add(callback);
    }
  }

  // Added optional callback.
  // If you don't pass the callback, it wipes ALL listeners for that event (dangerous).
  // If you pass it, it only removes that specific screen's listener.
  void stopListening(String event, [Function(dynamic)? callback]) {
    if (_socket != null) {
      if (callback != null) {
        _socket?.off(event, callback);
      } else {
        _socket?.off(event);
      }
    } else {
      if (callback != null) {
        _pendingListeners[event]?.remove(callback);
      } else {
        _pendingListeners.remove(event);
      }
    }
  }

  void emit(String event, dynamic data) {
    if (_socket != null) {
      // Let Socket.io handle native offline buffering.
      _socket?.emit(event, data);
    } else {
      log('⚠️ Warning: Tried to emit "$event" before socket was initialized.');
    }
  }

  void disconnect() {
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
    _pendingListeners.clear();
    log('🛑 Socket manually disposed.');
  }
}
