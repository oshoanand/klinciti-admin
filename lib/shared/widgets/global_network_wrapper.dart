import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/network_monitor.dart';

class GlobalNetworkWrapper extends ConsumerStatefulWidget {
  final Widget child;

  const GlobalNetworkWrapper({super.key, required this.child});

  @override
  ConsumerState<GlobalNetworkWrapper> createState() =>
      _GlobalNetworkWrapperState();
}

class _GlobalNetworkWrapperState extends ConsumerState<GlobalNetworkWrapper> {
  bool _wasOffline = false;

  @override
  Widget build(BuildContext context) {
    // Listen to network changes
    ref.listen<bool>(networkMonitorProvider, (previous, isOnline) {
      if (!isOnline) {
        _wasOffline = true;
        _showSnackbar(
          'Нет подключения к серверу',
          Colors.red.shade600,
          LucideIcons.wifi_off,
        );
      } else if (isOnline && _wasOffline) {
        _wasOffline = false;
        _showSnackbar(
          'Подключение восстановлено',
          Colors.green.shade600,
          LucideIcons.wifi,
        );
      }
    });

    return widget.child;
  }

  void _showSnackbar(String message, Color color, IconData icon) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 12),
            Text(
              message,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 4),
      ),
    );
  }
}
