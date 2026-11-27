import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/chat/providers/chat_sessions_provider.dart';
import 'profile_drawer.dart';

class MainScaffold extends ConsumerStatefulWidget {
  final StatefulNavigationShell navigationShell;

  const MainScaffold({super.key, required this.navigationShell});

  @override
  ConsumerState<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends ConsumerState<MainScaffold> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  void _onTabClick(int index) {
    // Tab 4 opens ProfileDrawer instead of navigating to a branch
    if (index == 4) {
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
    final totalUnreadChats = ref.watch(totalUnreadChatCountProvider);
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return PopScope(
      canPop: currentIndex == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
          _scaffoldKey.currentState?.closeDrawer();
          return;
        }
        if (currentIndex != 0) {
          widget.navigationShell.goBranch(0);
        }
      },
      child: Scaffold(
        key: _scaffoldKey,
        drawer: const ProfileDrawer(),
        body: widget.navigationShell,
        extendBody: true,
        bottomNavigationBar: Container(
          margin: EdgeInsets.only(bottom: bottomInset + 8, left: 16, right: 16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.96),
            borderRadius: BorderRadius.circular(30),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 20,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: _NavItem(
                    icon: LucideIcons.briefcase,
                    label: 'Заказы',
                    isSelected: currentIndex == 0,
                    onTap: () => _onTabClick(0),
                  ),
                ),
                Expanded(
                  child: _NavItem(
                    icon: LucideIcons.users,
                    label: 'Клиенты',
                    isSelected: currentIndex == 1,
                    onTap: () => _onTabClick(1),
                  ),
                ),
                Expanded(
                  child: _NavItem(
                    icon: LucideIcons.hard_hat,
                    label: 'Работники',
                    isSelected: currentIndex == 2,
                    onTap: () => _onTabClick(2),
                  ),
                ),
                Expanded(
                  child: _NavItem(
                    icon: LucideIcons.message_circle_more,
                    label: 'Чат',
                    isSelected: currentIndex == 3,
                    badge: totalUnreadChats,
                    onTap: () => _onTabClick(3),
                  ),
                ),
                Expanded(
                  child: _NavItem(
                    icon: LucideIcons.user,
                    label: 'Профиль',
                    isSelected: false,
                    onTap: () => _onTabClick(4),
                  ),
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
    final color = isSelected ? const Color(0xFF0F172A) : Colors.grey.shade400;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(icon, color: color, size: 24),
                if (badge > 0)
                  Positioned(
                    right: -8,
                    top: -6,
                    child: Container(
                      constraints: const BoxConstraints(
                        minWidth: 16,
                        minHeight: 16,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFDC2626),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        badge > 99 ? '99+' : badge.toString(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          height: 1.1,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
