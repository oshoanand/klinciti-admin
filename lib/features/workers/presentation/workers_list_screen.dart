import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exceptions.dart';
import '../../../shared/widgets/global_error_widget.dart';
import '../data/worker_model.dart';
import '../providers/workers_provider.dart';

class WorkersListScreen extends ConsumerStatefulWidget {
  final String? authStatus;
  final String? modStatus;

  const WorkersListScreen({super.key, this.authStatus, this.modStatus});

  @override
  ConsumerState<WorkersListScreen> createState() => _WorkersListScreenState();
}

class _WorkersListScreenState extends ConsumerState<WorkersListScreen> {
  final ScrollController _scrollController = ScrollController();
  late WorkerFilter _filter;

  @override
  void initState() {
    super.initState();
    _filter = WorkerFilter(
      authStatus: widget.authStatus,
      moderationStatus: widget.modStatus,
    );
    _scrollController.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(covariant WorkersListScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.authStatus != widget.authStatus ||
        oldWidget.modStatus != widget.modStatus) {
      setState(() {
        _filter = WorkerFilter(
          authStatus: widget.authStatus,
          moderationStatus: widget.modStatus,
        );
      });
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      ref.read(workersListProvider(_filter).notifier).loadMore();
    }
  }

  String _getScreenTitle() {
    if (widget.modStatus == 'PENDING') return 'Ждут модерации';
    if (widget.modStatus == 'APPROVED' && widget.authStatus == 'ACTIVE') {
      return 'Активные мастера';
    }
    if (widget.authStatus == 'BLOCKED') return 'Заблокированные';
    if (widget.modStatus == 'REJECTED') return 'Отклоненные';
    return 'Мастера';
  }

  Future<void> _openWorkerDetail(String workerId) async {
    await context.push('/worker/$workerId');
    if (mounted) {
      ref.invalidate(workersListProvider(_filter));
      ref.invalidate(workerStatsProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final workersAsync = ref.watch(workersListProvider(_filter));
    final notifier = ref.read(workersListProvider(_filter).notifier);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(LucideIcons.arrow_left, color: Color(0xFF0F172A)),
          onPressed: () => context.pop(),
        ),
        title: Text(
          _getScreenTitle(),
          style: const TextStyle(
            color: Color(0xFF0F172A),
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(
              LucideIcons.refresh_cw,
              size: 18,
              color: Color(0xFF0F172A),
            ),
            tooltip: 'Обновить',
            onPressed: () => ref.invalidate(workersListProvider(_filter)),
          ),
        ],
      ),
      body: workersAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: Color(0xFF0F172A)),
        ),
        error: (error, stack) {
          final errorMessage = error is ApiException
              ? error.message
              : 'Произошла ошибка при загрузке списка.';

          return GlobalErrorWidget(
            message: errorMessage,
            onRetry: () => ref.invalidate(workersListProvider(_filter)),
          );
        },
        data: (workers) {
          if (workers.isEmpty) {
            return RefreshIndicator(
              color: const Color(0xFF0F172A),
              onRefresh: () async {
                ref.invalidate(workersListProvider(_filter));
              },
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  SizedBox(
                    height: MediaQuery.of(context).size.height * 0.65,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          LucideIcons.users,
                          size: 64,
                          color: Colors.grey.shade300,
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Список пуст',
                          style: TextStyle(
                            color: Colors.grey,
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            color: const Color(0xFF0F172A),
            onRefresh: () async {
              ref.invalidate(workersListProvider(_filter));
            },
            child: ListView.separated(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: workers.length + (notifier.hasMore ? 1 : 0),
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                if (index == workers.length) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFF0F172A),
                      ),
                    ),
                  );
                }

                final worker = workers[index];
                return _buildWorkerCard(context, worker);
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildWorkerCard(BuildContext context, WorkerModel worker) {
    final hasAvatar =
        worker.avatarUrl != null && worker.avatarUrl!.trim().isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _openWorkerDetail(worker.id),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Avatar
                CircleAvatar(
                  radius: 30,
                  backgroundColor: Colors.grey.shade100,
                  backgroundImage: hasAvatar
                      ? NetworkImage(worker.avatarUrl!)
                      : null,
                  child: !hasAvatar
                      ? const Icon(LucideIcons.hard_hat, color: Colors.grey)
                      : null,
                ),
                const SizedBox(width: 16),

                // Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        worker.fullName,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        worker.mobile ?? 'Нет телефона',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 14,
                        ),
                      ),
                      if (worker.hasVehicle) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(
                              LucideIcons.car,
                              size: 14,
                              color: Colors.blue,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                (worker.vehicleModel != null &&
                                        worker.vehicleModel!.trim().isNotEmpty)
                                    ? worker.vehicleModel!
                                    : 'С автомобилем',
                                style: const TextStyle(
                                  color: Colors.blue,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),

                // Trailing Icon
                const Icon(LucideIcons.chevron_right, color: Colors.grey),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
