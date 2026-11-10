import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'profile_drawer.dart';

import '../../features/chat/providers/chat_sessions_provider.dart';

class MainScaffold extends ConsumerStatefulWidget {
  final StatefulNavigationShell navigationShell;

  const MainScaffold({super.key, required this.navigationShell});

  @override
  ConsumerState<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends ConsumerState<MainScaffold> {
  // 1. Create a GlobalKey to control the Scaffold
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  void _onTabClick(int index) {
    // Tab 4 is Profile (Drawer trigger, not a real route branch)
    if (index == 4) {
      // 2. Open the drawer using the key
      _scaffoldKey.currentState?.openDrawer();
      return;
    }

    widget.navigationShell.goBranch(
      index,
      initialLocation: index == widget.navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentIndex = widget.navigationShell.currentIndex;

    // ✅ Watch the chat sessions state to dynamically calculate total unread messages
    final chatSessionsState = ref.watch(chatSessionsProvider);
    int totalUnreadChats = 0;

    if (chatSessionsState.hasValue && chatSessionsState.value != null) {
      // Fold the array to sum up the unreadCount from every active chat session
      totalUnreadChats = chatSessionsState.value!.fold(
        0,
        (sum, session) => sum + session.unreadCount,
      );
    }

    return Scaffold(
      key: _scaffoldKey, // 3. Attach the key to the Scaffold
      drawer: const ProfileDrawer(),
      body: widget.navigationShell,
      extendBody: true,
      bottomNavigationBar: Container(
        margin: EdgeInsets.only(
          bottom: MediaQuery.of(context).padding.bottom + 8,
          left: 16,
          right: 16,
        ),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.95),
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 20,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _NavItem(
                  icon: LucideIcons.briefcase,
                  label: 'Заказы',
                  isSelected: currentIndex == 0,
                  onTap: () => _onTabClick(0),
                ),
                _NavItem(
                  icon: LucideIcons.users,
                  label: 'Клиенты',
                  isSelected: currentIndex == 1,
                  onTap: () => _onTabClick(1),
                ),
                _NavItem(
                  icon: LucideIcons.hard_hat,
                  label: 'Работники',
                  isSelected: currentIndex == 2,
                  onTap: () => _onTabClick(2),
                ),
                _NavItem(
                  icon: LucideIcons.message_circle_more,
                  label: 'Чат',
                  isSelected: currentIndex == 3,
                  // ✅ Pass the dynamically calculated total to the badge
                  badge: totalUnreadChats,
                  onTap: () => _onTabClick(3),
                ),
                // Profile Button triggers drawer
                _NavItem(
                  icon: LucideIcons.user,
                  label: 'Профиль',
                  isSelected:
                      false, // The drawer button doesn't stay highlighted
                  onTap: () => _onTabClick(4),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final int badge;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.badge = 0,
  });

  @override
  Widget build(BuildContext context) {
    // 4. Update the styling logic
    final color = isSelected ? const Color(0xFF0F172A) : Colors.grey.shade400;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min, // Wrap content tightly vertically
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Icon(icon, color: color, size: 24),
              // ✅ The badge will automatically hide if the value is 0
              if (badge > 0)
                Positioned(
                  right: -4,
                  top: -4,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      badge > 99 ? '99+' : badge.toString(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 8,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4), // Space between icon and text
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              fontSize: 10, // Smaller font for bottom nav labels
            ),
          ),
        ],
      ),
    );
  }
}
