import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exceptions.dart';
import '../../../shared/widgets/global_error_widget.dart';
import '../../../core/socket/socket_service.dart'; // ✅ Required for real-time presence
import '../providers/customers_list_provider.dart';
import '../data/customer_model.dart';

class CustomersScreen extends ConsumerStatefulWidget {
  const CustomersScreen({super.key});

  @override
  ConsumerState<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends ConsumerState<CustomersScreen> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);

    // ✅ Listen to Socket events
    ref
        .read(socketServiceProvider)
        .listen('user_status_changed', _onUserStatusChanged);
  }

  void _onUserStatusChanged(dynamic data) {
    if (!mounted) return;
    try {
      final userId = data['userId'] as String;
      final isOnline = data['isOnline'] as bool;
      final lastSeenStr = data['lastSeen'] as String?;

      final lastSeen = lastSeenStr != null ? DateTime.parse(lastSeenStr) : null;

      // ✅ Instantly update Riverpod state so the UI reacts without API calls
      ref
          .read(customersListProvider.notifier)
          .updateCustomerStatus(userId, isOnline, lastSeen);
    } catch (e) {
      debugPrint('Error parsing user_status_changed: $e');
    }
  }

  void _onScroll() {
    // ✅ FIX: Added subtraction operator
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      ref.read(customersListProvider.notifier).loadMore();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    ref
        .read(socketServiceProvider)
        .stopListening('user_status_changed', _onUserStatusChanged);
    super.dispose();
  }

  // ✅ Helper method to format "last seen" time nicely
  String _formatLastSeen(DateTime date) {
    final localDate = date.toLocal();
    final now = DateTime.now();
    final difference = now.difference(localDate);

    final timeString =
        '${localDate.hour.toString().padLeft(2, '0')}:${localDate.minute.toString().padLeft(2, '0')}';

    if (difference.inDays == 0 && now.day == localDate.day) {
      return 'Был(а) сегодня в $timeString';
    } else if (difference.inDays == 1 ||
        (difference.inDays == 0 && now.day != localDate.day)) {
      return 'Был(а) вчера в $timeString';
    }

    final dateString =
        '${localDate.day.toString().padLeft(2, '0')}.${localDate.month.toString().padLeft(2, '0')}.${localDate.year}';
    return 'Был(а) $dateString в $timeString';
  }

  @override
  Widget build(BuildContext context) {
    final listAsync = ref.watch(customersListProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Клиенты',
          style: TextStyle(
            color: Color(0xFF0F172A),
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: listAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: Color(0xFF0F172A)),
        ),
        error: (error, _) => GlobalErrorWidget(
          message: error is ApiException
              ? error.message
              : 'Ошибка загрузки клиентов.',
          onRetry: () => ref.invalidate(customersListProvider),
        ),
        data: (customers) {
          if (customers.isEmpty) {
            return const Center(
              child: Text(
                'Список клиентов пуст',
                style: TextStyle(color: Colors.grey),
              ),
            );
          }

          return RefreshIndicator(
            color: const Color(0xFF0F172A),
            onRefresh: () async => ref.invalidate(customersListProvider),
            child: ListView.separated(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: customers.length + 1,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                if (index == customers.length) {
                  if (customers.length < 20) return const SizedBox.shrink();
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFF0F172A),
                      ),
                    ),
                  );
                }

                return _buildCustomerCard(context, customers[index]);
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildCustomerCard(BuildContext context, CustomerModel customer) {
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
          onTap: () => context.push('/customers/detail/${customer.id}'),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // ✅ Overlay Status Dot using a Stack
                Stack(
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: const Color(0xFF0F172A)
                          .withOpacity(0.05),
                      backgroundImage: customer.image != null
                          ? NetworkImage(customer.image!)
                          : null,
                      child: customer.image == null
                          ? const Icon(LucideIcons.user, color: Colors.grey)
                          : null,
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          color: customer.isOnline
                              ? Colors.green
                              : Colors.grey.shade400,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white,
                            width: 2,
                          ), // Separates dot from avatar
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              customer.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (!customer.isActive)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.red.shade50,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text(
                                'Заблокирован',
                                style: TextStyle(
                                  color: Colors.red,
                                  fontSize: 10,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),

                      // ✅ Real-time online text format
                      if (customer.isOnline)
                        const Text(
                          'В сети',
                          style: TextStyle(
                            color: Colors.green,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        )
                      else if (customer.lastSeen != null)
                        Text(
                          _formatLastSeen(customer.lastSeen!),
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 12,
                          ),
                        )
                      else
                        const Text(
                          'Не в сети',
                          style: TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                      const SizedBox(height: 4),

                      if (customer.mobile != null || customer.email != null)
                        Text(
                          customer.mobile ?? customer.email!,
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 13,
                          ),
                        ),
                      if (customer.city != null) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(
                              LucideIcons.map_pin,
                              size: 12,
                              color: Colors.grey,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              customer.city!,
                              style: const TextStyle(
                                color: Colors.grey,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
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
