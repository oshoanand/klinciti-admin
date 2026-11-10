import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exceptions.dart';
import '../../../shared/widgets/global_error_widget.dart';
import '../providers/staff_list_provider.dart';
import '../data/staff_model.dart';

class StaffListScreen extends ConsumerStatefulWidget {
  const StaffListScreen({super.key});

  @override
  ConsumerState<StaffListScreen> createState() => _StaffListScreenState();
}

class _StaffListScreenState extends ConsumerState<StaffListScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final List<String> _roles = ['ALL', 'ADMINISTRATOR', 'SUPPORT'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _roles.length, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Сотрудники',
          style: TextStyle(
            color: Color(0xFF0F172A),
            fontWeight: FontWeight.bold,
          ),
        ),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          labelColor: const Color(0xFF0F172A),
          unselectedLabelColor: Colors.grey,
          indicatorColor: const Color(0xFF0F172A),
          tabs: const [
            Tab(text: 'Все'),
            Tab(text: 'Админы'),
            Tab(text: 'Поддержка'),
            Tab(text: 'Исполнители'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: _roles.map((role) => _StaffListView(role: role)).toList(),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFF0F172A),
        onPressed: () => context.push('/staff/new'), // ROUTES TO CREATE SCREEN
        child: const Icon(LucideIcons.plus, color: Colors.white),
      ),
    );
  }
}

class _StaffListView extends ConsumerStatefulWidget {
  final String role;
  const _StaffListView({required this.role});

  @override
  ConsumerState<_StaffListView> createState() => _StaffListViewState();
}

class _StaffListViewState extends ConsumerState<_StaffListView> {
  @override
  Widget build(BuildContext context) {
    final staffAsync = ref.watch(staffListProvider(widget.role));

    return staffAsync.when(
      loading: () => const Center(
        child: CircularProgressIndicator(color: Color(0xFF0F172A)),
      ),
      error: (error, _) => GlobalErrorWidget(
        message: error is ApiException
            ? error.message
            : 'Ошибка загрузки сотрудников.',
        onRetry: () => ref.invalidate(staffListProvider(widget.role)),
      ),
      data: (staffList) {
        if (staffList.isEmpty) {
          return const Center(
            child: Text(
              'Нет сотрудников в этой категории',
              style: TextStyle(color: Colors.grey),
            ),
          );
        }

        return RefreshIndicator(
          color: const Color(0xFF0F172A),
          onRefresh: () async => ref.invalidate(staffListProvider(widget.role)),
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: staffList.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              return _buildStaffCard(context, staffList[index]);
            },
          ),
        );
      },
    );
  }

  Widget _buildStaffCard(BuildContext context, StaffModel staff) {
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
          onTap: () => context.push('/staff/detail/${staff.id}'),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: const Color(0xFF0F172A).withOpacity(0.05),
                  child: const Icon(LucideIcons.user, color: Colors.grey),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              staff.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (!staff.isActive)
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
                      Text(
                        _getTranslatedRole(staff.role),
                        style: TextStyle(
                          color: Colors.blue.shade700,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (staff.mobile != null || staff.email != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4.0),
                          child: Text(
                            staff.mobile ?? staff.email!,
                            style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 13,
                            ),
                          ),
                        ),
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

  String _getTranslatedRole(String role) {
    switch (role) {
      case 'ADMINISTRATOR':
        return 'Администратор';
      case 'SUPPORT':
        return 'Поддержка';

      default:
        return role;
    }
  }
}
