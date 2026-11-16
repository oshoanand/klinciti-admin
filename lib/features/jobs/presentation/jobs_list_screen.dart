import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/network/api_exceptions.dart';
import '../../../core/router/route_names.dart';
import '../../../shared/widgets/global_error_widget.dart';
import '../data/job_model.dart';
import '../providers/job_provider.dart';

// Alias so any existing references to `JobsListScreen` work seamlessly
typedef JobsListScreen = JobListScreen;

class JobListScreen extends ConsumerStatefulWidget {
  final String? status;
  final String? initialStatus;

  const JobListScreen({super.key, this.status, this.initialStatus});

  String? get effectiveStatus => status ?? initialStatus;

  @override
  ConsumerState<JobListScreen> createState() => _JobListScreenState();
}

class _JobListScreenState extends ConsumerState<JobListScreen> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final double threshold = _scrollController.position.maxScrollExtent - 200.0;
    if (_scrollController.position.pixels >= threshold) {
      ref.read(jobsListProvider(widget.effectiveStatus).notifier).loadMore();
    }
  }

  String _getScreenTitle() {
    switch (widget.effectiveStatus) {
      case 'SLA_BREACHED':
        return 'Просрочка SLA (15м+)';
      case 'PENDING':
        return 'Поиск исполнителя';
      case 'ACCEPTED':
        return 'Мастер назначен';
      case 'ONGOING':
        return 'В процессе';
      case 'PAYMENT_PENDING':
        return 'Проверка фото и оплаты';
      case 'PAID':
        return 'Оплаченные заказы';
      case 'COMPLETED':
        return 'Завершенные';
      case 'DISPUTED':
        return 'Споры по заказам';
      case 'CANCELLED':
        return 'Отмененные';
      case 'REFUSED':
        return 'Отказы мастеров';
      default:
        return 'Все заказы';
    }
  }

  Future<void> _openJobDetail(String jobId) async {
    await context.push('${AppRoutes.jobDetail}/$jobId');
    if (mounted) {
      ref.invalidate(jobsListProvider(widget.effectiveStatus));
      ref.invalidate(jobStatsProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeStatus = widget.effectiveStatus;
    final jobsAsync = ref.watch(jobsListProvider(activeStatus));
    final notifier = ref.read(jobsListProvider(activeStatus).notifier);

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
            tooltip: 'Обновить список',
            onPressed: () => ref.invalidate(jobsListProvider(activeStatus)),
          ),
        ],
      ),
      body: jobsAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: Color(0xFF0F172A)),
        ),
        error: (error, _) {
          final errorMessage = error is ApiException
              ? error.message
              : 'Не удалось загрузить список заказов.';
          return GlobalErrorWidget(
            message: errorMessage,
            onRetry: () => ref.invalidate(jobsListProvider(activeStatus)),
          );
        },
        data: (jobs) {
          if (jobs.isEmpty) {
            final double emptyStateHeight =
                MediaQuery.sizeOf(context).height * 0.65;

            return RefreshIndicator(
              color: const Color(0xFF0F172A),
              onRefresh: () async {
                ref.invalidate(jobsListProvider(activeStatus));
                await ref.read(jobsListProvider(activeStatus).future);
              },
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  SizedBox(
                    height: emptyStateHeight,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          LucideIcons.clipboard_list,
                          size: 64,
                          color: Colors.grey.shade300,
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Заказов в этой категории нет',
                          style: TextStyle(
                            color: Colors.grey,
                            fontSize: 17,
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
              ref.invalidate(jobsListProvider(activeStatus));
              await ref.read(jobsListProvider(activeStatus).future);
            },
            child: ListView.separated(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: jobs.length + (notifier.hasMore ? 1 : 0),
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                if (index == jobs.length) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFF0F172A),
                      ),
                    ),
                  );
                }

                final job = jobs[index];
                return _buildJobCard(context, job);
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildJobCard(BuildContext context, JobModel job) {
    final shortId = job.id.length >= 8
        ? job.id.substring(0, 8).toUpperCase()
        : job.id.toUpperCase();

    final isSlaCritical = job.slaLevel == SlaAlertLevel.critical;
    final isSlaWarning = job.slaLevel == SlaAlertLevel.warning;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
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
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: isSlaCritical
                ? Colors.red.shade300
                : (isSlaWarning ? Colors.amber.shade300 : Colors.grey.shade100),
            width: (isSlaCritical || isSlaWarning) ? 1.4 : 1.0,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _openJobDetail(job.id),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Row: Status Badge, SLA Live Timer (if unassigned), and Order ID
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: _getStatusColor(job.status)
                            .withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _getStatusText(job.status),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: _getStatusColor(job.status),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),

                    // Live SLA Timer Badge for Unassigned PENDING Jobs
                    if (job.isWaitingForWorker)
                      _LiveSlaTimerBadge(createdAt: job.createdAt),

                    // Completion Photos & Payment Badges for COMPLETED Jobs
                    if (job.status == 'COMPLETED') ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: job.paymentStatus == 'PAID'
                              ? Colors.green.shade50
                              : Colors.amber.shade50,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          job.paymentStatus == 'PAID'
                              ? 'Оплачен'
                              : 'Ждет проверки',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: job.paymentStatus == 'PAID'
                                ? Colors.green.shade800
                                : Colors.amber.shade900,
                          ),
                        ),
                      ),
                      if (job.completionPhotos.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                LucideIcons.camera,
                                size: 12,
                                color: Colors.blue.shade700,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '${job.completionPhotos.length}',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue.shade800,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],

                    const Spacer(),
                    Text(
                      '№ $shortId',
                      style: const TextStyle(
                        color: Colors.grey,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Category & Subcategories + Budget
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            job.categoryName ?? 'Без категории',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          if (job.subcategoryName != null &&
                              job.subcategoryName!.trim().isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              job.subcategoryName!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      job.budget != null
                          ? '${job.budget!.toStringAsFixed(0)} ₽'
                          : 'Договорная',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // Address
                Row(
                  children: [
                    Icon(
                      LucideIcons.map_pin,
                      size: 15,
                      color: Colors.grey.shade500,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        job.pickupAddress ?? 'Адрес не указан',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ),
                  ],
                ),
                const Divider(height: 22),

                // Bottom Row: Customer, Assigned Worker, and Timestamp
                Row(
                  children: [
                    Icon(
                      LucideIcons.user,
                      size: 14,
                      color: Colors.grey.shade600,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        job.customerName ?? 'Заказчик',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    if (job.workerName != null &&
                        job.workerName!.trim().isNotEmpty) ...[
                      const Icon(
                        LucideIcons.hard_hat,
                        size: 14,
                        color: Colors.blue,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          job.workerName!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: Colors.blue,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                    ],
                    Text(
                      DateFormat('dd.MM HH:mm').format(job.createdAt.toLocal()),
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'PENDING':
        return Colors.orange;
      case 'ACCEPTED':
        return Colors.blue;
      case 'ONGOING':
        return Colors.purple;
      case 'COMPLETED':
        return Colors.green;
      case 'CANCELLED':
        return Colors.red;
      case 'DISPUTED':
        return Colors.redAccent;
      default:
        return Colors.grey;
    }
  }

  String _getStatusText(String status) {
    switch (status) {
      case 'PENDING':
        return 'Поиск мастера';
      case 'ACCEPTED':
        return 'Принят';
      case 'ONGOING':
        return 'В работе';
      case 'COMPLETED':
        return 'Завершен';
      case 'CANCELLED':
        return 'Отменен';
      case 'DISPUTED':
        return 'Спор';
      default:
        return status;
    }
  }
}

// ==========================================
// COMPACT LIVE SLA TIMER BADGE FOR JOB CARDS
// ==========================================
class _LiveSlaTimerBadge extends StatefulWidget {
  final DateTime createdAt;

  const _LiveSlaTimerBadge({required this.createdAt});

  @override
  State<_LiveSlaTimerBadge> createState() => _LiveSlaTimerBadgeState();
}

class _LiveSlaTimerBadgeState extends State<_LiveSlaTimerBadge> {
  Timer? _timer;
  late Duration _elapsed;

  @override
  void initState() {
    super.initState();
    _elapsed = DateTime.now().difference(widget.createdAt.toLocal());
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {
          _elapsed = DateTime.now().difference(widget.createdAt.toLocal());
        });
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _formatCompact(Duration d) {
    final secs = d.inSeconds < 0 ? 0 : d.inSeconds;
    final hours = secs ~/ 3600;
    final mins = (secs % 3600) ~/ 60;
    final remSecs = secs % 60;

    if (hours > 0) {
      return '${hours}ч ${mins.toString().padLeft(2, '0')}м';
    }
    return '${mins.toString().padLeft(2, '0')}:${remSecs.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final mins = _elapsed.inMinutes;
    final isCritical = mins >= 30;
    final isWarning = mins >= 15 && mins < 30;

    final Color bgColor = isCritical
        ? Colors.red.shade50
        : (isWarning ? Colors.amber.shade50 : Colors.blueGrey.shade50);
    final Color fgColor = isCritical
        ? Colors.red.shade800
        : (isWarning ? Colors.amber.shade900 : Colors.blueGrey.shade700);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isCritical
              ? Colors.red.shade300
              : (isWarning ? Colors.amber.shade300 : Colors.transparent),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isCritical ? LucideIcons.flame : LucideIcons.clock,
            size: 12,
            color: fgColor,
          ),
          const SizedBox(width: 4),
          Text(
            _formatCompact(_elapsed),
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.bold,
              color: fgColor,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
