import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/socket/socket_service.dart';

class UserPresence {
  final bool isOnline;
  final DateTime? lastSeen;

  const UserPresence({required this.isOnline, this.lastSeen});
}

class UserPresenceNotifier extends ChangeNotifier {
  final SocketService _socket;
  final Map<String, UserPresence> _presenceMap = {};

  UserPresenceNotifier(this._socket) {
    _socket.listen('user_presence', _onPresenceUpdate);
    _socket.listen('user_status_changed', _onPresenceUpdate);
  }

  Map<String, UserPresence> get presenceMap => Map.unmodifiable(_presenceMap);

  void checkPresence(String userId) {
    try {
      _socket.emit('check_presence', {'userId': userId});
    } catch (_) {}
  }

  void _onPresenceUpdate(dynamic payload) {
    try {
      final data = Map<String, dynamic>.from(payload as Map);
      final userId = data['userId']?.toString();
      if (userId == null) return;

      final isOnline = data['isOnline'] == true || data['isOnline'] == 'true';
      final lastSeenStr = data['lastSeen']?.toString();
      final lastSeen = lastSeenStr != null
          ? DateTime.parse(lastSeenStr).toLocal()
          : null;

      _presenceMap[userId] = UserPresence(
        isOnline: isOnline,
        lastSeen: lastSeen,
      );
      notifyListeners();
    } catch (_) {}
  }

  @override
  void dispose() {
    _socket.stopListening('user_presence', _onPresenceUpdate);
    _socket.stopListening('user_status_changed', _onPresenceUpdate);
    super.dispose();
  }
}

final userPresenceProvider = ChangeNotifierProvider<UserPresenceNotifier>((
  ref,
) {
  final socket = ref.watch(socketServiceProvider);
  return UserPresenceNotifier(socket);
});
