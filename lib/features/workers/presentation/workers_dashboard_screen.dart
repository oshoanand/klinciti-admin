import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:go_router/go_router.dart';

import '../providers/workers_provider.dart';

class WorkersDashboardScreen extends ConsumerWidget {
  const WorkersDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(workerStatsProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text(
          'Управление мастерами',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: statsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Ошибка: $err')),
        data: (stats) {
          return RefreshIndicator(
            onRefresh: () async => ref.refresh(workerStatsProvider),
            child: GridView.count(
              crossAxisCount: 2,
              padding: const EdgeInsets.all(16),
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              children: [
                _buildGridCard(
                  context,
                  title: 'Ждут модерации',
                  count: stats['PENDING_MODERATION'] ?? 0,
                  icon: LucideIcons.user_search,
                  color: Colors.orange,
                  onTap: () => context.push('/workers/list?modStatus=PENDING'),
                ),
                _buildGridCard(
                  context,
                  title: 'Активные',
                  count: stats['ACTIVE'] ?? 0,
                  icon: LucideIcons.user_check,
                  color: Colors.green,
                  onTap: () => context.push(
                    '/workers/list?authStatus=ACTIVE&modStatus=APPROVED',
                  ),
                ),
                _buildGridCard(
                  context,
                  title: 'Заблокированы',
                  count: stats['BLOCKED'] ?? 0,
                  icon: LucideIcons.user_x,
                  color: Colors.red,
                  onTap: () => context.push('/workers/list?authStatus=BLOCKED'),
                ),
                _buildGridCard(
                  context,
                  title: 'Отклонены',
                  count: stats['REJECTED'] ?? 0,
                  icon: LucideIcons.ban,
                  color: Colors.grey.shade700,
                  onTap: () => context.push('/workers/list?modStatus=REJECTED'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildGridCard(
    BuildContext context, {
    required String title,
    required int count,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color),
            ),
            const Spacer(),
            Text(
              count.toString(),
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            ),
            Text(
              title,
              style: TextStyle(
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
