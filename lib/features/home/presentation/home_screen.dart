import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:go_router/go_router.dart';
import 'package:shimmer/shimmer.dart';

import '../../../core/router/route_names.dart';
import '../../jobs/providers/job_stats_provider.dart';
import '../../notifications/providers/notification_provider.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(jobStatsProvider);
    final unreadCount = ref.watch(unreadCountProvider);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        body: RefreshIndicator(
          onRefresh: () async => ref.refresh(jobStatsProvider),
          color: const Color(0xFF0F172A),
          backgroundColor: Colors.white,
          displacement: 60,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            slivers: [
              // ==========================================
              // MODERN SLIVER APP BAR
              // ==========================================
              SliverAppBar(
                expandedHeight: 120.0,
                collapsedHeight: 70.0,
                floating: false,
                pinned: true,
                backgroundColor: const Color(0xFFF8FAFC),
                surfaceTintColor: Colors.transparent,
                elevation: 0,
                flexibleSpace: FlexibleSpaceBar(
                  titlePadding: const EdgeInsets.only(
                    left: 20,
                    bottom: 16,
                    right: 20,
                  ),
                  title: const Text(
                    'Обзор заказов',
                    style: TextStyle(
                      color: Color(0xFF0F172A),
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
                  ),
                  centerTitle: false,
                ),
                actions: [
                  Padding(
                    padding: const EdgeInsets.only(right: 8, top: 8),
                    child: Row(
                      children: [
                        _HeaderIconButton(
                          icon: LucideIcons.bell,
                          badgeCount: unreadCount,
                          onTap: () => context.push(AppRoutes.notifications),
                        ),
                        const SizedBox(width: 12),
                      ],
                    ),
                  ),
                ],
              ),

              // ==========================================
              // BODY CONTENT
              // ==========================================
              SliverPadding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20.0,
                  vertical: 12.0,
                ),
                sliver: statsAsync.when(
                  loading: () =>
                      SliverToBoxAdapter(child: _buildShimmerLoading()),
                  error: (err, stack) => SliverFillRemaining(
                    hasScrollBody: false,
                    child: _buildErrorState(err.toString(), ref),
                  ),
                  data: (stats) => SliverList(
                    delegate: SliverChildListDelegate([
                      const Text(
                        'Актуальные статусы',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 16),

                      // TOP ROW: PENDING & ACCEPTED (Awaiting action)
                      Row(
                        children: [
                          Expanded(
                            child: _StatusCard(
                              title: 'Новые',
                              status: 'PENDING',
                              count: stats['PENDING'] ?? 0,
                              icon: LucideIcons.inbox,
                              color: const Color(0xFFEF4444), // Red
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _StatusCard(
                              title: 'Назначены',
                              status: 'ACCEPTED',
                              count: stats['ACCEPTED'] ?? 0,
                              icon: LucideIcons.user_check,
                              color: const Color(0xFF8B5CF6), // Purple
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // MIDDLE ROW: ONGOING & DISPUTED (Active jobs)
                      Row(
                        children: [
                          Expanded(
                            child: _StatusCard(
                              title: 'В процессе',
                              status: 'ONGOING',
                              count: stats['ONGOING'] ?? 0,
                              icon: LucideIcons.hammer,
                              color: const Color(0xFF3B82F6), // Blue
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _StatusCard(
                              title: 'Споры',
                              status: 'DISPUTED',
                              count: stats['DISPUTED'] ?? 0,
                              icon: LucideIcons.triangle_alert,
                              color: const Color(0xFFEAB308), // Yellow
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // 💰 FINANCE ROW: PENDING PAYMENT & PAID
                      Row(
                        children: [
                          Expanded(
                            child: _StatusCard(
                              title: 'Ждут оплаты',
                              status: 'PAYMENT_PENDING',
                              count: stats['PAYMENT_PENDING'] ?? 0,
                              icon: LucideIcons.clock,
                              color: const Color(0xFFF97316), // Orange
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _StatusCard(
                              title: 'Оплачены',
                              status: 'PAID',
                              count: stats['PAID'] ?? 0,
                              icon: LucideIcons.wallet,
                              color: const Color(0xFF14B8A6), // Teal
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // SUCCESS STATUS (Full Width Hero Card)
                      _StatusCard(
                        title: 'Все завершенные',
                        status: 'COMPLETED',
                        count: stats['COMPLETED'] ?? 0,
                        icon: LucideIcons.circle_check,
                        color: const Color(0xFF10B981), // Emerald Green
                        isFullWidth: true,
                      ),
                      const SizedBox(height: 16),

                      // FAILURE STATUSES (Bottom Row)
                      Row(
                        children: [
                          Expanded(
                            child: _StatusCard(
                              title: 'Отменены',
                              status: 'CANCELLED',
                              count: stats['CANCELLED'] ?? 0,
                              icon: LucideIcons.circle_x,
                              color: const Color(0xFFF59E0B), // Amber
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _StatusCard(
                              title: 'Отказ',
                              status: 'REFUSED',
                              count: stats['REFUSED'] ?? 0,
                              icon: LucideIcons.ban,
                              color: const Color(0xFF64748B), // Slate
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 40),
                    ]),
                  ),
                ),
              ),
            ],
          ),
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
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                LucideIcons.triangle_alert,
                color: Colors.red,
                size: 32,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Упс, что-то пошло не так',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              error,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => ref.refresh(jobStatsProvider),
              icon: const Icon(LucideIcons.refresh_cw, size: 16),
              label: const Text('Обновить данные'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0F172A),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 14,
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
  // ELEGANT SHIMMER SKELETON
  // ==========================================
  Widget _buildShimmerLoading() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Shimmer.fromColors(
          baseColor: Colors.grey.shade200,
          highlightColor: Colors.grey.shade50,
          child: Container(
            height: 20,
            width: 140,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(6),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(child: _buildShimmerCard()),
            const SizedBox(width: 16),
            Expanded(child: _buildShimmerCard()),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(child: _buildShimmerCard()),
            const SizedBox(width: 16),
            Expanded(child: _buildShimmerCard()),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(child: _buildShimmerCard()),
            const SizedBox(width: 16),
            Expanded(child: _buildShimmerCard()),
          ],
        ),
        const SizedBox(height: 16),
        _buildShimmerCard(isFullWidth: true),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(child: _buildShimmerCard()),
            const SizedBox(width: 16),
            Expanded(child: _buildShimmerCard()),
          ],
        ),
      ],
    );
  }

  Widget _buildShimmerCard({bool isFullWidth = false}) => Shimmer.fromColors(
    baseColor: Colors.grey.shade200,
    highlightColor: Colors.grey.shade50,
    child: Container(
      height: isFullWidth ? 110 : 130,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
    ),
  );
}

// ==========================================
// HEADER ACTION BUTTON (Glassmorphism feel)
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
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.02),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(icon, color: const Color(0xFF0F172A), size: 20),
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
// PREMIUM STATUS CARD
// ==========================================
class _StatusCard extends StatelessWidget {
  final String title;
  final String status;
  final int count;
  final IconData icon;
  final Color color;
  final bool isFullWidth;

  const _StatusCard({
    required this.title,
    required this.status,
    required this.count,
    required this.icon,
    required this.color,
    this.isFullWidth = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.06),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => context.push('${AppRoutes.jobsList}/$status'),
          borderRadius: BorderRadius.circular(24),
          highlightColor: color.withOpacity(0.03),
          splashColor: color.withOpacity(0.05),
          child: Padding(
            padding: EdgeInsets.all(isFullWidth ? 24.0 : 20.0),
            child: isFullWidth
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: _buildCardContent(),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: _buildCardContent(),
                  ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildCardContent() {
    return [
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Icon(icon, color: color, size: 24),
      ),
      if (!isFullWidth) const SizedBox(height: 24),
      Column(
        crossAxisAlignment: isFullWidth
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          Text(
            count.toString(),
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w900,
              color: Color(0xFF0F172A),
              height: 1.1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade500,
            ),
          ),
        ],
      ),
    ];
  }
}
