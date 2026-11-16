import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shimmer/shimmer.dart';

import '../../../core/router/route_names.dart';
import '../../jobs/providers/job_provider.dart';
import '../../notifications/providers/notification_provider.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  Future<void> _openJobsByStatus(
    BuildContext context,
    WidgetRef ref, {
    String? status,
  }) async {
    final String route = (status != null && status.isNotEmpty)
        ? '${AppRoutes.jobList}?status=$status'
        : AppRoutes.jobList;

    await context.push(route);
    ref.invalidate(jobStatsProvider);
  }

  Future<void> _refreshData(WidgetRef ref) async {
    ref.invalidate(jobStatsProvider);
    await ref.read(jobStatsProvider.future);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(jobStatsProvider);
    final unreadCount = ref.watch(unreadCountProvider);
    final topInset = MediaQuery.paddingOf(context).top;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        extendBodyBehindAppBar: true,
        body: MediaQuery.removePadding(
          context: context,
          removeTop: true,
          child: RefreshIndicator(
            onRefresh: () => _refreshData(ref),
            color: const Color(0xFF0F172A),
            backgroundColor: Colors.white,
            displacement: topInset + 24,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              slivers: [
                // ==========================================
                // COMPACT EDGE-TO-EDGE TOP TOOLBAR HEADER
                // Uses minimal status-bar inset so dashboard fills the screen
                // ==========================================
                SliverToBoxAdapter(
                  child: Container(
                    padding: EdgeInsets.fromLTRB(16, topInset + 8, 16, 10),
                    decoration: const BoxDecoration(color: Color(0xFFF8FAFC)),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Обзор заказов',
                                style: TextStyle(
                                  fontSize: 22,
                                  color: Color(0xFF0F172A),
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.5,
                                  height: 1.15,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Диспетчерская панель Klinciti',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Quick "All Jobs" pill button
                        InkWell(
                          onTap: () => _openJobsByStatus(context, ref),
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 9,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.grey.shade200),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  LucideIcons.list,
                                  size: 16,
                                  color: Color(0xFF0F172A),
                                ),
                                SizedBox(width: 6),
                                Text(
                                  'Все',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF0F172A),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _HeaderIconButton(
                          icon: LucideIcons.refresh_cw,
                          onTap: () => _refreshData(ref),
                        ),
                        const SizedBox(width: 8),
                        _HeaderIconButton(
                          icon: LucideIcons.bell,
                          badgeCount: unreadCount,
                          onTap: () => context.push(AppRoutes.notifications),
                        ),
                      ],
                    ),
                  ),
                ),

                // ==========================================
                // BODY CONTENT (Full-width compact padding)
                // ==========================================
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  sliver: statsAsync.when(
                    loading: () =>
                        SliverToBoxAdapter(child: _buildShimmerLoading()),
                    error: (err, stack) => SliverFillRemaining(
                      hasScrollBody: false,
                      child: _buildErrorState(err.toString(), ref),
                    ),
                    data: (stats) {
                      final int slaBreachedCount = stats['SLA_BREACHED'] ?? 0;

                      return SliverList(
                        delegate: SliverChildListDelegate([
                          // 1. URGENT SLA BREACH BANNER (if any unassigned job > 15m)
                          if (slaBreachedCount > 0) ...[
                            _buildSlaEmergencyBanner(
                              context,
                              ref,
                              slaBreachedCount,
                            ),
                            const SizedBox(height: 12),
                          ],

                          // 2. ROW 1: SLA BREACHED & PENDING (Immediate Dispatch)
                          Row(
                            children: [
                              Expanded(
                                child: _StatusCard(
                                  title: 'Просрочка SLA',
                                  subtitle: 'Ждут более 15 мин',
                                  status: 'SLA_BREACHED',
                                  count: slaBreachedCount,
                                  icon: LucideIcons.flame,
                                  color: const Color(0xFFDC2626),
                                  highlightBorder: slaBreachedCount > 0,
                                  onTap: () => _openJobsByStatus(
                                    context,
                                    ref,
                                    status: 'SLA_BREACHED',
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _StatusCard(
                                  title: 'Новые заявки',
                                  subtitle: 'Поиск мастера',
                                  status: 'PENDING',
                                  count: stats['PENDING'] ?? 0,
                                  icon: LucideIcons.inbox,
                                  color: const Color(0xFFEF4444),
                                  onTap: () => _openJobsByStatus(
                                    context,
                                    ref,
                                    status: 'PENDING',
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),

                          // 3. ROW 2: ACCEPTED & ONGOING
                          Row(
                            children: [
                              Expanded(
                                child: _StatusCard(
                                  title: 'Назначены',
                                  subtitle: 'Мастер принят',
                                  status: 'ACCEPTED',
                                  count: stats['ACCEPTED'] ?? 0,
                                  icon: LucideIcons.user_check,
                                  color: const Color(0xFF8B5CF6),
                                  onTap: () => _openJobsByStatus(
                                    context,
                                    ref,
                                    status: 'ACCEPTED',
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _StatusCard(
                                  title: 'В процессе',
                                  subtitle: 'Выполняются',
                                  status: 'ONGOING',
                                  count: stats['ONGOING'] ?? 0,
                                  icon: LucideIcons.hammer,
                                  color: const Color(0xFF3B82F6),
                                  onTap: () => _openJobsByStatus(
                                    context,
                                    ref,
                                    status: 'ONGOING',
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),

                          // 4. ROW 3: PAYMENT_PENDING (Before/After Photo Check) & PAID
                          Row(
                            children: [
                              Expanded(
                                child: _StatusCard(
                                  title: 'Ждут проверки',
                                  subtitle: 'Фото ДО/ПОСЛЕ и оплата',
                                  status: 'PAYMENT_PENDING',
                                  count: stats['PAYMENT_PENDING'] ?? 0,
                                  icon: LucideIcons.camera,
                                  color: const Color(0xFFF97316),
                                  highlightBorder:
                                      (stats['PAYMENT_PENDING'] ?? 0) > 0,
                                  onTap: () => _openJobsByStatus(
                                    context,
                                    ref,
                                    status: 'PAYMENT_PENDING',
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _StatusCard(
                                  title: 'Оплачены',
                                  subtitle: 'Расчет завершен',
                                  status: 'PAID',
                                  count: stats['PAID'] ?? 0,
                                  icon: LucideIcons.wallet,
                                  color: const Color(0xFF14B8A6),
                                  onTap: () => _openJobsByStatus(
                                    context,
                                    ref,
                                    status: 'PAID',
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),

                          // 5. ROW 4: DISPUTED & COMPLETED
                          Row(
                            children: [
                              Expanded(
                                child: _StatusCard(
                                  title: 'Споры',
                                  subtitle: 'Арбитраж',
                                  status: 'DISPUTED',
                                  count: stats['DISPUTED'] ?? 0,
                                  icon: LucideIcons.triangle_alert,
                                  color: const Color(0xFFEAB308),
                                  highlightBorder: (stats['DISPUTED'] ?? 0) > 0,
                                  onTap: () => _openJobsByStatus(
                                    context,
                                    ref,
                                    status: 'DISPUTED',
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _StatusCard(
                                  title: 'Все завершенные',
                                  subtitle: 'Выполнены',
                                  status: 'COMPLETED',
                                  count: stats['COMPLETED'] ?? 0,
                                  icon: LucideIcons.circle_check,
                                  color: const Color(0xFF10B981),
                                  onTap: () => _openJobsByStatus(
                                    context,
                                    ref,
                                    status: 'COMPLETED',
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),

                          // 6. ROW 5: CANCELLED & REFUSED
                          Row(
                            children: [
                              Expanded(
                                child: _StatusCard(
                                  title: 'Отменены',
                                  subtitle: 'Отмена заказа',
                                  status: 'CANCELLED',
                                  count: stats['CANCELLED'] ?? 0,
                                  icon: LucideIcons.circle_x,
                                  color: const Color(0xFFF59E0B),
                                  onTap: () => _openJobsByStatus(
                                    context,
                                    ref,
                                    status: 'CANCELLED',
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _StatusCard(
                                  title: 'Отказ',
                                  subtitle: 'Отказ мастера',
                                  status: 'REFUSED',
                                  count: stats['REFUSED'] ?? 0,
                                  icon: LucideIcons.ban,
                                  color: const Color(0xFF64748B),
                                  onTap: () => _openJobsByStatus(
                                    context,
                                    ref,
                                    status: 'REFUSED',
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ]),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ==========================================
  // SLA BREACH TOP BANNER
  // ==========================================
  Widget _buildSlaEmergencyBanner(
    BuildContext context,
    WidgetRef ref,
    int count,
  ) {
    return InkWell(
      onTap: () => _openJobsByStatus(context, ref, status: 'SLA_BREACHED'),
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.red.shade700, Colors.red.shade500],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.red.withValues(alpha: 0.22),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                LucideIcons.flame,
                color: Colors.white,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Нарушение SLA: $count зак. без мастера > 15 мин!',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'Нажмите для срочного назначения или Push-рассылки',
                    style: TextStyle(color: Colors.white, fontSize: 11.5),
                  ),
                ],
              ),
            ),
            const Icon(
              LucideIcons.chevron_right,
              color: Colors.white,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // PREMIUM ERROR STATE
  // ==========================================
  Widget _buildErrorState(String error, WidgetRef ref) {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                LucideIcons.triangle_alert,
                color: Colors.red,
                size: 28,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Не удалось загрузить данные',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              error,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () => _refreshData(ref),
              icon: const Icon(LucideIcons.refresh_cw, size: 16),
              label: const Text('Обновить данные'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0F172A),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // SHIMMER SKELETON
  // ==========================================
  Widget _buildShimmerLoading() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: List.generate(5, (index) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            children: [
              Expanded(child: _buildShimmerCard()),
              const SizedBox(width: 12),
              Expanded(child: _buildShimmerCard()),
            ],
          ),
        );
      }),
    );
  }

  Widget _buildShimmerCard() => Shimmer.fromColors(
    baseColor: Colors.grey.shade200,
    highlightColor: Colors.grey.shade50,
    child: Container(
      height: 112,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
    ),
  );
}

// ==========================================
// HEADER ACTION BUTTON
// ==========================================
class _HeaderIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final int badgeCount;

  const _HeaderIconButton({
    required this.icon,
    required this.onTap,
    this.badgeCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    Widget button = InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(icon, color: const Color(0xFF0F172A), size: 19),
      ),
    );

    if (badgeCount > 0) {
      return Badge(
        label: Text(
          badgeCount > 99 ? '99+' : badgeCount.toString(),
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10),
        ),
        backgroundColor: const Color(0xFFEF4444),
        offset: const Offset(-2, 2),
        child: button,
      );
    }

    return button;
  }
}

// ==========================================
// COMPACT FULL-WIDTH STATUS CARD
// ==========================================
class _StatusCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String status;
  final int count;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final bool highlightBorder;

  const _StatusCard({
    required this.title,
    required this.subtitle,
    required this.status,
    required this.count,
    required this.icon,
    required this.color,
    required this.onTap,
    this.highlightBorder = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: highlightBorder
            ? Border.all(color: color.withValues(alpha: 0.65), width: 1.5)
            : Border.all(color: Colors.grey.shade100),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          highlightColor: color.withValues(alpha: 0.04),
          splashColor: color.withValues(alpha: 0.06),
          child: Padding(
            padding: const EdgeInsets.all(14.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(9),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(icon, color: color, size: 20),
                    ),
                    Text(
                      count.toString(),
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        color: highlightBorder
                            ? color
                            : const Color(0xFF0F172A),
                        height: 1.0,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey.shade500,
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
