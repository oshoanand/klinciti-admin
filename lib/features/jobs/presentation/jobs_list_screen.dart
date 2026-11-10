import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';

import '../../../core/network/api_exceptions.dart';
import '../../../shared/widgets/global_error_widget.dart';

import '../providers/jobs_by_status_provider.dart';
import '../data/job_model.dart';

class JobsListScreen extends ConsumerStatefulWidget {
  final String initialStatus;

  const JobsListScreen({super.key, required this.initialStatus});

  @override
  ConsumerState<JobsListScreen> createState() => _JobsListScreenState();
}

class _JobsListScreenState extends ConsumerState<JobsListScreen> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    initializeDateFormatting('ru', null);
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    // ✅ FIX: Corrected subtraction syntax for infinite scroll trigger
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      ref.read(jobsByStatusProvider(widget.initialStatus).notifier).loadMore();
    }
  }

  String _getTranslatedStatus(String status) {
    switch (status) {
      case 'PENDING':
        return 'Новые заказы';
      case 'ACCEPTED':
        return 'Назначенные';
      case 'ONGOING':
        return 'В процессе';
      case 'DISPUTED':
        return 'Споры';
      case 'COMPLETED':
        return 'Все Завершенные';
      case 'PAYMENT_PENDING':
        return 'Ждут оплаты';
      case 'PAID':
        return 'Оплаченные';
      case 'CANCELLED':
        return 'Отменены';
      case 'REFUSED':
        return 'Отказ';
      default:
        return status;
    }
  }

  String _getTranslatedTiming(String timing) {
    switch (timing) {
      case 'asap':
        return 'Срочно (Как можно скорее)';
      case 'today':
        return 'Сегодня';
      case 'week':
        return 'В течение недели';
      case 'flexible':
        return 'Не срочно (Гибко)';
      default:
        return 'Не указано';
    }
  }

  Color _getTimingColor(String timing) {
    switch (timing) {
      case 'asap':
        return const Color(0xFFEF4444); // Red
      case 'today':
        return const Color(0xFFF97316); // Orange
      case 'week':
        return const Color(0xFF3B82F6); // Blue
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final jobsAsync = ref.watch(jobsByStatusProvider(widget.initialStatus));

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
          _getTranslatedStatus(widget.initialStatus),
          style: const TextStyle(
            color: Color(0xFF0F172A),
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: jobsAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: Color(0xFF0F172A)),
        ),
        error: (error, stack) {
          final errorMessage = error is ApiException
              ? error.message
              : 'Произошла непредвиденная ошибка. Пожалуйста, попробуйте еще раз.';

          return GlobalErrorWidget(
            message: errorMessage,
            onRetry: () =>
                ref.invalidate(jobsByStatusProvider(widget.initialStatus)),
          );
        },
        data: (jobs) {
          if (jobs.isEmpty) {
            return const Center(
              child: Text(
                'Заказов в этом статусе нет',
                style: TextStyle(color: Colors.grey, fontSize: 16),
              ),
            );
          }

          return RefreshIndicator(
            color: const Color(0xFF0F172A),
            onRefresh: () async {
              ref.invalidate(jobsByStatusProvider(widget.initialStatus));
            },
            child: ListView.separated(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: jobs.length + 1,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                if (index == jobs.length) {
                  if (jobs.length < 20) return const SizedBox.shrink();
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

  // ==========================================
  // JOB CARD WIDGET
  // ==========================================
  Widget _buildJobCard(BuildContext context, JobModel job) {
    // Add safety formatting for the date
    final dateStr = DateFormat(
      'dd MMM yyyy, HH:mm',
      'ru',
    ).format(job.createdAt);

    return Container(
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => context.push('/job/${job.id}'),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header: ID and Budget
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Заказ #${job.id.substring(0, 8).toUpperCase()}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.grey,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A).withOpacity(0.05),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${job.budget ?? 0} ₽',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Category & Date
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        job.categoryName ?? 'Без категории',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Text(
                      dateStr,
                      style: TextStyle(
                        color: Colors.grey.shade500,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),

                // Timing / Priority Field (New functionality)
                if (job.timing != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        LucideIcons.clock,
                        size: 16,
                        color: _getTimingColor(job.timing!),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _getTranslatedTiming(job.timing!),
                        style: TextStyle(
                          color: _getTimingColor(job.timing!),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],

                // Address
                if (job.pickupAddress != null &&
                    job.pickupAddress!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(
                        LucideIcons.map_pin,
                        size: 16,
                        color: Colors.grey,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          job.pickupAddress!,
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 13,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],

                // Users (Customer & Worker)
                const SizedBox(height: 12),
                const Divider(height: 1),
                const SizedBox(height: 12),

                Row(
                  children: [
                    if (job.customerName != null) ...[
                      const Icon(
                        LucideIcons.user,
                        size: 16,
                        color: Colors.grey,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        job.customerName!,
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],

                    // Worker Info (Crucial for ONGOING / DISPUTED / COMPLETED)
                    if (job.workerName != null) ...[
                      const Icon(
                        LucideIcons.hard_hat,
                        size: 16,
                        color: Colors.blueGrey,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        job.workerName!,
                        style: const TextStyle(
                          color: Colors.blueGrey,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ] else if (widget.initialStatus == 'ACCEPTED') ...[
                      // If it's accepted but no worker is assigned yet
                      const Text(
                        'Ожидает мастера',
                        style: TextStyle(
                          color: Colors.orange,
                          fontSize: 13,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ],
                ),

                // PHOTOS GALLERY
                if (job.photos.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 70,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: job.photos.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(width: 8),
                      itemBuilder: (context, index) {
                        return ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(
                            job.photos[index],
                            height: 70,
                            width: 70,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                Container(
                                  height: 70,
                                  width: 70,
                                  color: Colors.grey.shade200,
                                  child: const Icon(
                                    LucideIcons.image_off,
                                    color: Colors.grey,
                                  ),
                                ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
