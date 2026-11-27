import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/route_names.dart';
import '../providers/job_provider.dart';

class JobDashboardScreen extends ConsumerWidget {
  const JobDashboardScreen({super.key});

  Future<void> _openJobList(
    BuildContext context,
    WidgetRef ref, {
    String? status,
  }) async {
    final uri = (status != null && status.isNotEmpty)
        ? '${AppRoutes.jobList}?status=$status'
        : AppRoutes.jobList;
    await context.push(uri);
    ref.invalidate(jobStatsProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(jobStatsProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text(
          'Управление заказами',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Color(0xFF0F172A),
          ),
        ),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        actions: [
          TextButton.icon(
            onPressed: () => _openJobList(context, ref),
            icon: const Icon(LucideIcons.list, size: 18),
            label: const Text('Все заказы'),
          ),
          IconButton(
            icon: const Icon(
              LucideIcons.refresh_cw,
              size: 18,
              color: Color(0xFF0F172A),
            ),
            tooltip: 'Обновить статистику',
            onPressed: () => ref.invalidate(jobStatsProvider),
          ),
        ],
      ),
      body: statsAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: Color(0xFF0F172A)),
        ),
        error: (err, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  LucideIcons.circle_exclamation_point,
                  color: Colors.red,
                  size: 40,
                ),
                const SizedBox(height: 12),
                Text(
                  'Ошибка загрузки статистики: $err',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () => ref.invalidate(jobStatsProvider),
                  child: const Text('Повторить'),
                ),
              ],
            ),
          ),
        ),
        data: (stats) {
          final int slaBreachedCount = stats['SLA_BREACHED'] ?? 0;

          return RefreshIndicator(
            color: const Color(0xFF0F172A),
            onRefresh: () async {
              ref.invalidate(jobStatsProvider);
              await ref.read(jobStatsProvider.future);
            },
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                // 1. URGENT SLA BREACH ALERT BANNER (Shown when SLA_BREACHED > 0)
                if (slaBreachedCount > 0)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                      child: _buildSlaEmergencyBanner(
                        context,
                        ref,
                        slaBreachedCount,
                      ),
                    ),
                  ),

                // 2. MAIN STATUS GRID
                SliverPadding(
                  padding: const EdgeInsets.all(16),
                  sliver: SliverGrid.count(
                    crossAxisCount: 2,
                    crossAxisSpacing: 14,
                    mainAxisSpacing: 14,
                    childAspectRatio: 1.12,
                    children: [
                      _buildGridCard(
                        context,
                        title: 'Просрочка SLA (15м+)',
                        subtitle: 'Без исполнителя',
                        count: slaBreachedCount,
                        icon: LucideIcons.flame,
                        color: slaBreachedCount > 0
                            ? Colors.red
                            : Colors.blueGrey,
                        highlightBorder: slaBreachedCount > 0,
                        onTap: () =>
                            _openJobList(context, ref, status: 'SLA_BREACHED'),
                      ),
                      _buildGridCard(
                        context,
                        title: 'Поиск мастера',
                        subtitle: 'Новые заявки',
                        count: stats['PENDING'] ?? 0,
                        icon: LucideIcons.search,
                        color: Colors.orange,
                        onTap: () =>
                            _openJobList(context, ref, status: 'PENDING'),
                      ),
                      _buildGridCard(
                        context,
                        title: 'Мастер назначен',
                        subtitle: 'Приняты в работу',
                        count: stats['ACCEPTED'] ?? 0,
                        icon: LucideIcons.user_check,
                        color: Colors.blue,
                        onTap: () =>
                            _openJobList(context, ref, status: 'ACCEPTED'),
                      ),
                      _buildGridCard(
                        context,
                        title: 'Выполняются',
                        subtitle: 'В процессе',
                        count: stats['ONGOING'] ?? 0,
                        icon: LucideIcons.play,
                        color: Colors.purple,
                        onTap: () =>
                            _openJobList(context, ref, status: 'ONGOING'),
                      ),
                      _buildGridCard(
                        context,
                        title: 'Проверка и оплата',
                        subtitle: 'Ждут проверки фото',
                        count: stats['PAYMENT_PENDING'] ?? 0,
                        icon: LucideIcons.camera,
                        color: Colors.amber.shade800,
                        onTap: () => _openJobList(
                          context,
                          ref,
                          status: 'PAYMENT_PENDING',
                        ),
                      ),
                      _buildGridCard(
                        context,
                        title: 'Оплачены (PAID)',
                        subtitle: 'Полностью закрыты',
                        count: stats['PAID'] ?? 0,
                        icon: LucideIcons.circle_check,
                        color: Colors.green,
                        onTap: () => _openJobList(context, ref, status: 'PAID'),
                      ),
                      _buildGridCard(
                        context,
                        title: 'Споры',
                        subtitle: 'Требуют арбитража',
                        count: stats['DISPUTED'] ?? 0,
                        icon: LucideIcons.scale,
                        color: Colors.redAccent,
                        highlightBorder: (stats['DISPUTED'] ?? 0) > 0,
                        onTap: () =>
                            _openJobList(context, ref, status: 'DISPUTED'),
                      ),
                      _buildGridCard(
                        context,
                        title: 'Отменены',
                        subtitle: 'Отмена / отказ',
                        count: stats['CANCELLED'] ?? 0,
                        icon: LucideIcons.circle_x,
                        color: Colors.grey.shade700,
                        onTap: () =>
                            _openJobList(context, ref, status: 'CANCELLED'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildSlaEmergencyBanner(
    BuildContext context,
    WidgetRef ref,
    int count,
  ) {
    return InkWell(
      onTap: () => _openJobList(context, ref, status: 'SLA_BREACHED'),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.red.shade700, Colors.red.shade500],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.red.withValues(alpha: 0.25),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                LucideIcons.flame,
                color: Colors.white,
                size: 24,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Нарушение SLA: $count зак. ждут более 15 мин!',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 3),
                  const Text(
                    'Нажмите, чтобы назначить мастера или отправить Push-рассылку',
                    style: TextStyle(color: Colors.white, fontSize: 12.5),
                  ),
                ],
              ),
            ),
            const Icon(LucideIcons.chevron_right, color: Colors.white),
          ],
        ),
      ),
    );
  }

  Widget _buildGridCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required int count,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    bool highlightBorder = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: highlightBorder
              ? Border.all(color: color.withValues(alpha: 0.6), width: 1.5)
              : Border.all(color: Colors.grey.shade100),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
                Text(
                  count.toString(),
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: highlightBorder ? color : const Color(0xFF0F172A),
                  ),
                ),
              ],
            ),
            const Spacer(),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF0F172A),
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
