import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/socket/socket_service.dart';

class TypingNotifier extends ChangeNotifier {
  final SocketService _socket;
  final Map<String, bool> _typingMap = {};
  Timer? _debounceTimer;

  TypingNotifier(this._socket) {
    _socket.listen('user_typing', _onTypingStart);
    _socket.listen('user_stopped_typing', _onTypingStop);
  }

  bool isTyping(String userId) => _typingMap[userId] ?? false;

  void emitTyping(String receiverId) {
    // Notify server we are typing
    _socket.emit('typing', {'receiverId': receiverId});

    // Reset the stop timer
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(seconds: 2), () {
      _socket.emit('stop_typing', {'receiverId': receiverId});
    });
  }

  void _onTypingStart(dynamic payload) {
    try {
      final data = Map<String, dynamic>.from(payload as Map);
      final userId = data['userId']?.toString();
      if (userId != null) {
        _typingMap[userId] = true;
        notifyListeners();
      }
    } catch (_) {}
  }

  void _onTypingStop(dynamic payload) {
    try {
      final data = Map<String, dynamic>.from(payload as Map);
      final userId = data['userId']?.toString();
      if (userId != null) {
        _typingMap[userId] = false;
        notifyListeners();
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _socket.stopListening('user_typing', _onTypingStart);
    _socket.stopListening('user_stopped_typing', _onTypingStop);
    super.dispose();
  }
}

final typingProvider = ChangeNotifierProvider<TypingNotifier>((ref) {
  return TypingNotifier(ref.watch(socketServiceProvider));
});
