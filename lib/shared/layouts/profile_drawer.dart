import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_router.dart';
import '../../core/router/route_names.dart';
import '../../core/utils/phone_formatter.dart';
import '../../features/auth/providers/auth_provider.dart';

class ProfileDrawer extends ConsumerWidget {
  const ProfileDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAuthenticated = ref.watch(isAuthenticatedProvider);
    final user = ref.watch(currentUserProvider);

    final String? avatarUrl =
        user?['image']?.toString() ?? user?['photo']?.toString();
    String name =
        user?['name']?.toString() ?? user?['first_name']?.toString() ?? '';
    if (name.trim().isEmpty) name = 'Администратор';

    final String? mobile = user?['mobile']?.toString();
    final String? email = user?['email']?.toString();
    final String role = (user?['role'] ?? '').toString().toUpperCase();
    final bool isAdmin = role.isEmpty || role == 'ADMINISTRATOR';
    final bool isSupport = role == 'SUPPORT';

    return Drawer(
      width: MediaQuery.sizeOf(context).width * 0.85,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(right: Radius.circular(8)),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  if (isAuthenticated) ...[
                    // ==========================================
                    // LOGGED IN HEADER (READ-ONLY AVATAR)
                    // ==========================================
                    Container(
                      padding: const EdgeInsets.all(16),
                      margin: const EdgeInsets.only(bottom: 24, top: 16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              color: const Color(0xFF0F172A)
                                  .withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                            ),
                            child: ClipOval(
                              child: avatarUrl != null && avatarUrl.isNotEmpty
                                  ? Image.network(
                                      avatarUrl,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => const Icon(
                                        LucideIcons.user,
                                        color: Color(0xFF0F172A),
                                        size: 28,
                                      ),
                                    )
                                  : const Icon(
                                      LucideIcons.user,
                                      color: Color(0xFF0F172A),
                                      size: 28,
                                    ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                if (mobile != null && mobile.isNotEmpty)
                                  Text(
                                    PhoneFormatter.format(mobile),
                                    style: const TextStyle(
                                      color: Colors.grey,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                if (email != null && email.isNotEmpty)
                                  Text(
                                    email,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.grey,
                                      fontSize: 12,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    // ==========================================
                    // FINANCE, CASH & PAYMENTS SECTION
                    // ==========================================
                    if (isAdmin || isSupport) ...[
                      const Padding(
                        padding: EdgeInsets.only(left: 8, bottom: 6),
                        child: Text(
                          'ФИНАНСЫ И ПЛАТЕЖИ',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.8,
                            color: Color(0xFF94A3B8),
                          ),
                        ),
                      ),
                      _MenuItem(
                        icon: LucideIcons.banknote,
                        iconColor: const Color(0xFFE0780F),
                        title: 'Наличные и комиссии',
                        subtitle: 'Долги исполнителей, прием оплат и споры',
                        onTap: () {
                          Navigator.pop(context);
                          context.push(AppRoutes.cashMonitor);
                        },
                      ),
                      if (isAdmin) ...[
                        _MenuItem(
                          icon: LucideIcons.sliders_horizontal,
                          iconColor: const Color(0xFF2563EB),
                          title: 'Настройки комиссий и блокировок',
                          subtitle: 'Ставки %, лимиты долга и дни просрочки',
                          onTap: () {
                            Navigator.pop(context);
                            context.push(AppRoutes.cashSettings);
                          },
                        ),
                        _MenuItem(
                          icon: LucideIcons.receipt_text,
                          iconColor: const Color(0xFF0F766E),
                          title: 'История платежей и транзакций',
                          subtitle: 'Реестр T-Bank, возвраты и статусы',
                          onTap: () {
                            Navigator.pop(context);
                            context.push('${AppRoutes.finance}?tab=0');
                          },
                        ),
                        _MenuItem(
                          icon: LucideIcons.landmark,
                          iconColor: const Color(0xFFD97706),
                          title: 'Управление финансами',
                          subtitle: 'График выплат, комиссия и Kill Switch',
                          onTap: () {
                            Navigator.pop(context);
                            context.push('${AppRoutes.finance}?tab=1');
                          },
                        ),
                      ],
                      const Divider(height: 28, color: Color(0xFFF1F5F9)),
                    ],

                    // ==========================================
                    // GENERAL MANAGEMENT SECTION
                    // ==========================================
                    const Padding(
                      padding: EdgeInsets.only(left: 8, bottom: 6),
                      child: Text(
                        'УПРАВЛЕНИЕ',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                          color: Color(0xFF94A3B8),
                        ),
                      ),
                    ),
                    _MenuItem(
                      icon: LucideIcons.user_pen,
                      title: 'Редактировать профиль',
                      subtitle: 'Настройки и данные',
                      onTap: () {
                        Navigator.pop(context);
                        context.push(AppRoutes.profileEdit);
                      },
                    ),
                    _MenuItem(
                      icon: LucideIcons.users,
                      title: 'Пользователи',
                      subtitle: 'Управление сотрудниками',
                      onTap: () {
                        Navigator.pop(context);
                        context.push(AppRoutes.staffList);
                      },
                    ),
                    _MenuItem(
                      icon: LucideIcons.layout_list,
                      title: 'Категории',
                      subtitle: 'Управление услугами',
                      onTap: () {
                        Navigator.pop(context);
                        context.push(AppRoutes.categories);
                      },
                    ),

                    const Divider(height: 32, color: Color(0xFFF1F5F9)),
                    _MenuItem(
                      icon: LucideIcons.log_out,
                      title: 'Выйти',
                      subtitle: 'Завершить сеанс',
                      iconColor: Colors.red,
                      isDestructive: true,
                      onTap: () {
                        final navContext =
                            rootNavigatorKey.currentContext ?? context;
                        Navigator.pop(context);
                        ref.read(authControllerProvider).logout(navContext);
                      },
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color iconColor;
  final bool isDestructive;
  final VoidCallback onTap;

  const _MenuItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.iconColor = const Color(0xFF0F172A),
    this.isDestructive = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final Color effectiveColor = isDestructive ? Colors.red : iconColor;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: effectiveColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: effectiveColor, size: 22),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: isDestructive
                          ? Colors.red
                          : const Color(0xFF0F172A),
                    ),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                ],
              ),
            ),
            if (!isDestructive)
              const Icon(
                LucideIcons.chevron_right,
                size: 18,
                color: Color(0xFFCBD5E1),
              ),
          ],
        ),
      ),
    );
  }
}
