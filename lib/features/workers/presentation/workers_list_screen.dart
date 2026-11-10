import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exceptions.dart';
import '../../../shared/widgets/global_error_widget.dart';
import '../providers/workers_provider.dart';
import '../data/worker_model.dart';

class WorkersListScreen extends ConsumerStatefulWidget {
  final String? authStatus;
  final String? modStatus;

  const WorkersListScreen({super.key, this.authStatus, this.modStatus});

  @override
  ConsumerState<WorkersListScreen> createState() => _WorkersListScreenState();
}

class _WorkersListScreenState extends ConsumerState<WorkersListScreen> {
  final ScrollController _scrollController = ScrollController();
  late final WorkerFilter _filter;

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
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
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

  @override
  Widget build(BuildContext context) {
    final workersAsync = ref.watch(workersListProvider(_filter));

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
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
            return Center(
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
              itemCount: workers.length + 1,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                if (index == workers.length) {
                  // Show loading indicator at the bottom if fetching more
                  if (workers.length < 20) return const SizedBox.shrink();
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
    return Container(
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
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
          onTap: () {
            // Route to Worker Detail Screen
            context.push('/worker/${worker.id}');
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Avatar
                CircleAvatar(
                  radius: 30,
                  backgroundColor: Colors.grey.shade100,
                  backgroundImage: worker.avatarUrl != null
                      ? NetworkImage(worker.avatarUrl!)
                      : null,
                  child: worker.avatarUrl == null
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
                        worker.name,
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
                                worker.vehicleModel ?? 'С автомобилем',
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
