import 'dart:async';
import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../network/api_client.dart';

typedef SocketEventCallback = void Function(dynamic data);

final socketServiceProvider = Provider<SocketService>((ref) {
  final storage = ref.watch(secureStorageProvider);
  final service = SocketService(storage);
  ref.onDispose(service.dispose);
  return service;
});

class SocketService {
  static const String _envSocketUrl = String.fromEnvironment('SOCKET_URL');

  io.Socket? _socket;
  final FlutterSecureStorage _storage;

  SocketService(this._storage);

  // Persistent listener registry so long-lived services (e.g. NotificationService)
  // automatically reattach after disconnect/reconnect or account switches.
  final Map<String, Set<SocketEventCallback>> _listeners = {};

  final StreamController<bool> _connectionController =
      StreamController<bool>.broadcast();

  String? _currentUserId;
  bool _isConnecting = false;
  bool _isDisposed = false;
  int _connectionEpoch = 0;

  bool get isConnected => _socket?.connected ?? false;
  String? get currentUserId => _currentUserId;
  Stream<bool> get connectionStream => _connectionController.stream;

  void _debugLog(String message) {
    if (kDebugMode) {
      log(message, name: 'SocketService');
    }
  }

  /// Resolves Socket.io origin from `--dart-define-from-file` (`SOCKET_URL`)
  /// with fallback to `ApiClient.baseUrl`'s origin. Enforces TLS in release mode.
  String? _resolveSocketUrl() {
    final raw = _envSocketUrl.trim().isNotEmpty
        ? _envSocketUrl.trim()
        : ApiClient.baseUrl;

    final uri = Uri.tryParse(raw);
    if (uri == null || uri.host.isEmpty) {
      _debugLog('❌ Invalid socket URL: $raw');
      return null;
    }

    final scheme = uri.scheme.toLowerCase();
    if (kReleaseMode && scheme != 'https' && scheme != 'wss') {
      throw StateError(
        'Production builds require an HTTPS/WSS SOCKET_URL (got: $raw)',
      );
    }

    return '${uri.scheme}://${uri.authority}';
  }

  Future<String?> _readToken() async {
    try {
      return await _storage.read(key: StorageKeys.jwtToken);
    } catch (e) {
      _debugLog('⚠️ Failed to read JWT from secure storage: $e');
      return null;
    }
  }

  bool _isAuthRejection(dynamic err) {
    final msg = err?.toString().toLowerCase() ?? '';
    return msg.contains('401') ||
        msg.contains('unauthorized') ||
        msg.contains('jwt') ||
        msg.contains('invalid token') ||
        msg.contains('expired');
  }

  Future<void> connect(String userId) async {
    final trimmedUserId = userId.trim();
    if (_isDisposed || trimmedUserId.isEmpty) return;

    // Already connected (or connecting) for this exact user
    if (_currentUserId == trimmedUserId &&
        (_socket?.connected == true || _isConnecting)) {
      return;
    }

    final int epoch = ++_connectionEpoch;
    _isConnecting = true;

    try {
      // Tear down any existing socket (stale or belonging to a different user)
      if (_socket != null) {
        _teardownSocket();
      }

      _currentUserId = trimmedUserId;
      final token = await _readToken();

      // Abort if disconnect(), dispose(), or a newer connect() ran during await
      if (_isDisposed || epoch != _connectionEpoch) {
        return;
      }

      if (token == null || token.trim().isEmpty) {
        _debugLog('⚠️ Skipping socket connect: missing JWT token');
        _currentUserId = null;
        _emitConnectionState(false);
        return;
      }

      final socketUrl = _resolveSocketUrl();
      if (socketUrl == null) {
        _currentUserId = null;
        _emitConnectionState(false);
        return;
      }

      final options = io.OptionBuilder()
          .setPath('/socket.io')
          .setTransports(['websocket'])
          .setTimeout(15000)
          .enableReconnection()
          .setReconnectionAttempts(99999)
          .setReconnectionDelay(1000)
          .setReconnectionDelayMax(30000)
          .setAuth({
            'token': token,
            'userId': trimmedUserId,
            'role': 'ADMINISTRATOR',
          })
          .disableAutoConnect()
          .build();

      // Force a fresh Manager per login & add reconnect jitter to avoid VPS storms
      options['forceNew'] = true;
      options['randomizationFactor'] = 0.5;

      final socket = io.io(socketUrl, options);
      _socket = socket;

      // Re-attach all registered listeners onto the fresh socket instance
      _listeners.forEach((event, callbacks) {
        for (final callback in callbacks) {
          socket.on(event, callback);
        }
      });

      socket.onConnect((_) {
        if (epoch != _connectionEpoch) return;
        _debugLog('✅ Socket Connected to $socketUrl (ID: ${socket.id})');
        _emitConnectionState(true);
      });

      socket.onDisconnect((_) {
        if (epoch != _connectionEpoch) return;
        _debugLog('⚠️ Socket Disconnected');
        _emitConnectionState(false);
      });

      socket.onReconnect((attempt) {
        if (epoch != _connectionEpoch) return;
        _debugLog('🔄 Socket Reconnected after $attempt attempts');
        _emitConnectionState(true);
      });

      socket.onReconnectAttempt((_) async {
        if (_isDisposed || epoch != _connectionEpoch) return;

        final freshToken = await _readToken();
        if (_isDisposed || epoch != _connectionEpoch || _socket == null) return;

        // Stop draining battery if session was cleared while offline
        if (freshToken == null ||
            freshToken.trim().isEmpty ||
            _currentUserId == null) {
          disconnect();
          return;
        }

        _socket!.auth = {
          'token': freshToken,
          'userId': _currentUserId!,
          'role': 'ADMINISTRATOR',
        };
      });

      socket.onConnectError((err) {
        if (epoch != _connectionEpoch) return;
        _debugLog('❌ Socket Connection Error: $err');
        _emitConnectionState(false);

        // Do not infinite-loop on rejected/expired JWT handshakes
        if (_isAuthRejection(err)) {
          _debugLog('🛑 Stopping socket reconnect after auth rejection');
          disconnect();
        }
      });

      socket.onError((err) => _debugLog('❌ Socket Error: $err'));
      socket.on('error', (data) {
        _debugLog('⚠️ Backend Socket Error Event: $data');
      });

      socket.connect();
    } finally {
      if (epoch == _connectionEpoch) {
        _isConnecting = false;
      }
    }
  }

  /// Updates the JWT on the active socket without dropping registered listeners.
  void updateAuthToken(String token) {
    final trimmed = token.trim();
    if (trimmed.isEmpty) return;
    if (_socket != null && _currentUserId != null) {
      _socket!.auth = {
        'token': trimmed,
        'userId': _currentUserId!,
        'role': 'ADMINISTRATOR',
      };
    }
  }

  void listen(String event, SocketEventCallback callback) {
    final callbacks = _listeners.putIfAbsent(
      event,
      () => <SocketEventCallback>{},
    );
    final wasAdded = callbacks.add(callback);

    // Attach immediately if a socket exists and this callback wasn't already bound
    if (wasAdded && _socket != null) {
      _socket!.on(event, callback);
    }
  }

  /// Removes a specific callback if provided, or all listeners for [event] if omitted.
  void stopListening(String event, [SocketEventCallback? callback]) {
    if (callback != null) {
      _listeners[event]?.remove(callback);
      if (_listeners[event]?.isEmpty ?? false) {
        _listeners.remove(event);
      }
      _socket?.off(event, callback);
    } else {
      _listeners.remove(event);
      _socket?.off(event);
    }
  }

  void emit(String event, dynamic data) {
    if (_socket != null && _socket!.connected) {
      _socket!.emit(event, data);
    } else if (_socket != null) {
      _debugLog('⏳ Queuing "$event" while socket reconnects');
      _socket!.emit(event, data);
    } else {
      _debugLog('⚠️ Tried to emit "$event" before socket was initialized.');
    }
  }

  /// Disconnects the active socket on logout while preserving persistent service listeners.
  void disconnect() {
    _connectionEpoch++;
    _isConnecting = false;
    _teardownSocket();
    _currentUserId = null;
    _emitConnectionState(false);
    _debugLog('🛑 Socket disconnected.');
  }

  void _teardownSocket() {
    if (_socket != null) {
      _socket!.clearListeners();
      _socket!.disconnect();
      _socket!.dispose();
      _socket = null;
    }
  }

  void _emitConnectionState(bool connected) {
    if (!_isDisposed && !_connectionController.isClosed) {
      _connectionController.add(connected);
    }
  }

  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    _connectionEpoch++;
    _isConnecting = false;
    _teardownSocket();
    _listeners.clear();
    _currentUserId = null;
    _connectionController.close();
  }
}
