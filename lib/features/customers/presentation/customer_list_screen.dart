import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exceptions.dart';
import '../../../core/router/route_names.dart';
import '../../../core/socket/socket_service.dart';
import '../../../shared/widgets/global_error_widget.dart';
import '../data/customer_model.dart';
import '../providers/customers_list_provider.dart';

enum _CustomerQuickFilter { all, online, active, blocked }

class CustomersScreen extends ConsumerStatefulWidget {
  const CustomersScreen({super.key});

  @override
  ConsumerState<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends ConsumerState<CustomersScreen> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  late final SocketService _socketService;

  String _searchQuery = '';
  _CustomerQuickFilter _selectedFilter = _CustomerQuickFilter.all;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);

    // Cache SocketService reference so we can safely detach in dispose()
    _socketService = ref.read(socketServiceProvider);
    _socketService.listen('user_status_changed', _onUserStatusChanged);
  }

  void _onUserStatusChanged(dynamic data) {
    if (!mounted || data is! Map) return;
    try {
      final userId = data['userId']?.toString();
      if (userId == null || userId.isEmpty) return;

      final isOnline = data['isOnline'] == true;
      final lastSeenStr = data['lastSeen']?.toString();
      final lastSeen = lastSeenStr != null
          ? DateTime.tryParse(lastSeenStr)
          : null;

      ref
          .read(customersListProvider.notifier)
          .updateCustomerStatus(userId, isOnline, lastSeen);
    } catch (e) {
      debugPrint('Error parsing user_status_changed: $e');
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final double threshold = _scrollController.position.maxScrollExtent - 200.0;
    if (_scrollController.position.pixels >= threshold) {
      ref.read(customersListProvider.notifier).loadMore();
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _searchController.dispose();
    _socketService.stopListening('user_status_changed', _onUserStatusChanged);
    super.dispose();
  }

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

  List<CustomerModel> _applyLocalFilters(List<CustomerModel> customers) {
    return customers.where((c) {
      // 1. Apply status chip filter
      switch (_selectedFilter) {
        case _CustomerQuickFilter.online:
          if (!c.isOnline) return false;
          break;
        case _CustomerQuickFilter.active:
          if (!c.isActive) return false;
          break;
        case _CustomerQuickFilter.blocked:
          if (c.isActive) return false;
          break;
        case _CustomerQuickFilter.all:
          break;
      }

      // 2. Apply search query filter
      if (_searchQuery.isEmpty) return true;
      final q = _searchQuery.toLowerCase();
      final nameMatch = c.name.toLowerCase().contains(q);
      final phoneMatch = (c.mobile ?? '').toLowerCase().contains(q);
      final emailMatch = (c.email ?? '').toLowerCase().contains(q);
      final cityMatch = (c.city ?? '').toLowerCase().contains(q);
      return nameMatch || phoneMatch || emailMatch || cityMatch;
    }).toList();
  }

  Future<void> _openCustomerDetail(String customerId) async {
    await context.push('${AppRoutes.customerDetail}/$customerId');
    if (mounted) {
      ref.invalidate(customersListProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final listAsync = ref.watch(customersListProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Клиенты',
          style: TextStyle(
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
            onPressed: () => ref.invalidate(customersListProvider),
          ),
        ],
      ),
      body: Column(
        children: [
          // Search & Quick Filter Bar
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Column(
              children: [
                TextField(
                  controller: _searchController,
                  onChanged: (val) => setState(() => _searchQuery = val.trim()),
                  decoration: InputDecoration(
                    hintText: 'Поиск по имени, телефону, email или городу...',
                    prefixIcon: const Icon(LucideIcons.search, size: 18),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(LucideIcons.x, size: 16),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                    isDense: true,
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade200),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade200),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildFilterChip('Все', _CustomerQuickFilter.all),
                      const SizedBox(width: 8),
                      _buildFilterChip('В сети', _CustomerQuickFilter.online),
                      const SizedBox(width: 8),
                      _buildFilterChip('Активные', _CustomerQuickFilter.active),
                      const SizedBox(width: 8),
                      _buildFilterChip(
                        'Заблокированные',
                        _CustomerQuickFilter.blocked,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Customers List
          Expanded(
            child: listAsync.when(
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
                final filtered = _applyLocalFilters(customers);

                if (filtered.isEmpty) {
                  final double emptyHeight =
                      MediaQuery.sizeOf(context).height * 0.55;

                  return RefreshIndicator(
                    color: const Color(0xFF0F172A),
                    onRefresh: () async {
                      ref.invalidate(customersListProvider);
                    },
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        SizedBox(
                          height: emptyHeight,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                LucideIcons.users,
                                size: 60,
                                color: Colors.grey.shade300,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                customers.isEmpty ? 'Список клиентов пуст' : 'По выбранным фильтрам клиенты не найдены',
                                style: const TextStyle(
                                  color: Colors.grey,
                                  fontSize: 16,
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

                final bool showBottomLoader =
                    _searchQuery.isEmpty &&
                    _selectedFilter == _CustomerQuickFilter.all &&
                    customers.length >= 20;

                return RefreshIndicator(
                  color: const Color(0xFF0F172A),
                  onRefresh: () async => ref.invalidate(customersListProvider),
                  child: ListView.separated(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: filtered.length + (showBottomLoader ? 1 : 0),
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      if (index == filtered.length) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Center(
                            child: CircularProgressIndicator(
                              color: Color(0xFF0F172A),
                            ),
                          ),
                        );
                      }

                      return _buildCustomerCard(context, filtered[index]);
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, _CustomerQuickFilter filter) {
    final isSelected = _selectedFilter == filter;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => setState(() => _selectedFilter = filter),
      selectedColor: const Color(0xFF0F172A),
      backgroundColor: const Color(0xFFF8FAFC),
      labelStyle: TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w600,
        color: isSelected ? Colors.white : const Color(0xFF0F172A),
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: isSelected ? const Color(0xFF0F172A) : Colors.grey.shade300,
        ),
      ),
      showCheckmark: false,
    );
  }

  Widget _buildCustomerCard(BuildContext context, CustomerModel customer) {
    final hasImage =
        customer.image != null && customer.image!.trim().isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
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
          onTap: () => _openCustomerDetail(customer.id),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Avatar with Online Presence Dot
                Stack(
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: const Color(0xFF0F172A)
                          .withValues(alpha: 0.05),
                      backgroundImage: hasImage
                          ? NetworkImage(customer.image!)
                          : null,
                      child: !hasImage
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
                          border: Border.all(color: Colors.white, width: 2),
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
                                color: Color(0xFF0F172A),
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
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),

                      // Real-time online text format
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

                      if ((customer.mobile != null &&
                              customer.mobile!.isNotEmpty) ||
                          (customer.email != null &&
                              customer.email!.isNotEmpty))
                        Text(
                          (customer.mobile != null &&
                                  customer.mobile!.isNotEmpty)
                              ? customer.mobile!
                              : customer.email!,
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 13,
                          ),
                        ),
                      if (customer.city != null &&
                          customer.city!.trim().isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(
                              LucideIcons.map_pin,
                              size: 12,
                              color: Colors.grey,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                customer.city!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.grey,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const Icon(LucideIcons.chevron_right, color: Colors.grey),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
