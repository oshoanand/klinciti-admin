import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exceptions.dart';
import '../../../core/router/route_names.dart';
import '../../../shared/widgets/global_error_widget.dart';
import '../data/staff_model.dart';
import '../providers/staff_provider.dart';

class StaffListScreen extends ConsumerStatefulWidget {
  const StaffListScreen({super.key});

  @override
  ConsumerState<StaffListScreen> createState() => _StaffListScreenState();
}

class _StaffListScreenState extends ConsumerState<StaffListScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _selectedRole = 'ALL'; // 'ALL' | 'ADMINISTRATOR' | 'SUPPORT'
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<StaffModel> _filterStaff(List<StaffModel> allStaff) {
    return allStaff.where((staff) {
      // 1. Role card filter
      if (_selectedRole != 'ALL' && staff.role != _selectedRole) {
        return false;
      }

      // 2. Search query filter
      if (_searchQuery.isEmpty) return true;
      final q = _searchQuery.toLowerCase();
      final nameMatch = staff.name.toLowerCase().contains(q);
      final phoneMatch = (staff.mobile ?? '').toLowerCase().contains(q);
      final emailMatch = (staff.email ?? '').toLowerCase().contains(q);
      return nameMatch || phoneMatch || emailMatch;
    }).toList();
  }

  Future<void> _openCreateStaff() async {
    await context.push(AppRoutes.staffCreate);
    if (mounted) {
      ref.invalidate(staffListProvider);
    }
  }

  Future<void> _openStaffDetail(String staffId) async {
    await context.push('${AppRoutes.staffDetail}/$staffId');
    if (mounted) {
      ref.invalidate(staffListProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final staffAsync = ref.watch(staffListProvider('ALL'));

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        leading: context.canPop()
            ? IconButton(
                icon: const Icon(
                  LucideIcons.arrow_left,
                  color: Color(0xFF0F172A),
                ),
                onPressed: () => context.pop(),
              )
            : null,
        title: const Text(
          'Сотрудники',
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
            onPressed: () => ref.invalidate(staffListProvider),
          ),
        ],
      ),
      body: staffAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: Color(0xFF0F172A)),
        ),
        error: (error, _) => GlobalErrorWidget(
          message: error is ApiException
              ? error.message
              : 'Ошибка загрузки сотрудников.',
          onRetry: () => ref.invalidate(staffListProvider),
        ),
        data: (allStaff) {
          final int totalCount = allStaff.length;
          final int adminCount = allStaff
              .where((s) => s.role == 'ADMINISTRATOR')
              .length;
          final int supportCount = allStaff
              .where((s) => s.role == 'SUPPORT')
              .length;

          final filteredStaff = _filterStaff(allStaff);

          return RefreshIndicator(
            color: const Color(0xFF0F172A),
            onRefresh: () async {
              ref.invalidate(staffListProvider);
              await ref.read(staffListProvider('ALL').future);
            },
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                // ==========================================
                // 1. ROLE FILTER CARDS SECTION (Replaces TabBar)
                // ==========================================
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: _RoleSummaryCard(
                                title: 'Все',
                                subtitle: 'Штат',
                                count: totalCount,
                                icon: LucideIcons.users,
                                color: const Color(0xFF0F172A),
                                isSelected: _selectedRole == 'ALL',
                                onTap: () =>
                                    setState(() => _selectedRole = 'ALL'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _RoleSummaryCard(
                                title: 'Админы',
                                subtitle: 'Управление',
                                count: adminCount,
                                icon: LucideIcons.shield_check,
                                color: const Color(0xFF3B82F6),
                                isSelected: _selectedRole == 'ADMINISTRATOR',
                                onTap: () => setState(
                                  () => _selectedRole = 'ADMINISTRATOR',
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _RoleSummaryCard(
                                title: 'Поддержка',
                                subtitle: 'Операторы',
                                count: supportCount,
                                icon: LucideIcons.headset,
                                color: const Color(0xFF8B5CF6),
                                isSelected: _selectedRole == 'SUPPORT',
                                onTap: () =>
                                    setState(() => _selectedRole = 'SUPPORT'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),

                        // Search Bar
                        TextField(
                          controller: _searchController,
                          onChanged: (val) =>
                              setState(() => _searchQuery = val.trim()),
                          decoration: InputDecoration(
                            hintText: 'Поиск по имени, телефону или email...',
                            prefixIcon: const Icon(
                              LucideIcons.search,
                              size: 18,
                            ),
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
                            fillColor: Colors.white,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(
                                color: Colors.grey.shade200,
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(
                                color: Colors.grey.shade200,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // ==========================================
                // 2. FILTERED STAFF LIST OR EMPTY STATE
                // ==========================================
                if (filteredStaff.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              LucideIcons.user_x,
                              size: 56,
                              color: Colors.grey.shade300,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              allStaff.isEmpty ? 'Список сотрудников пуст' : 'В выбранной категории сотрудники не найдены',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.grey,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 88),
                    sliver: SliverList.separated(
                      itemCount: filteredStaff.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        return _buildStaffCard(context, filteredStaff[index]);
                      },
                    ),
                  ),
              ],
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF0F172A),
        onPressed: _openCreateStaff,
        icon: const Icon(LucideIcons.user_plus, color: Colors.white, size: 18),
        label: const Text(
          'Добавить',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _buildStaffCard(BuildContext context, StaffModel staff) {
    final isAdmin = staff.role == 'ADMINISTRATOR';
    final roleColor = isAdmin
        ? const Color(0xFF3B82F6)
        : const Color(0xFF8B5CF6);

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
          onTap: () => _openStaffDetail(staff.id),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: roleColor.withValues(alpha: 0.1),
                  child: Icon(
                    isAdmin ? LucideIcons.shield_check : LucideIcons.headset,
                    color: roleColor,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              staff.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: Color(0xFF0F172A),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: staff.isActive
                                  ? Colors.green.shade50
                                  : Colors.red.shade50,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              staff.isActive ? 'Активен' : 'Заблокирован',
                              style: TextStyle(
                                color: staff.isActive
                                    ? Colors.green.shade700
                                    : Colors.red.shade700,
                                fontSize: 10.5,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _getTranslatedRole(staff.role),
                        style: TextStyle(
                          color: roleColor,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if ((staff.mobile != null && staff.mobile!.isNotEmpty) ||
                          (staff.email != null && staff.email!.isNotEmpty))
                        Padding(
                          padding: const EdgeInsets.only(top: 4.0),
                          child: Text(
                            [
                              if (staff.mobile != null &&
                                  staff.mobile!.isNotEmpty)
                                staff.mobile!,
                              if (staff.email != null &&
                                  staff.email!.isNotEmpty)
                                staff.email!,
                            ].join(' • '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 12.5,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(LucideIcons.chevron_right, color: Colors.grey),
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
        return 'Специалист поддержки';
      default:
        return role;
    }
  }
}

// ==========================================
// INTERACTIVE ROLE SUMMARY CARD
// ==========================================
class _RoleSummaryCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final int count;
  final IconData icon;
  final Color color;
  final bool isSelected;
  final VoidCallback onTap;

  const _RoleSummaryCard({
    required this.title,
    required this.subtitle,
    required this.count,
    required this.icon,
    required this.color,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isSelected ? color : Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected ? color : Colors.grey.shade200,
              width: isSelected ? 1.5 : 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: isSelected
                    ? color.withValues(alpha: 0.22)
                    : Colors.black.withValues(alpha: 0.02),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? Colors.white.withValues(alpha: 0.2)
                          : color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      icon,
                      size: 16,
                      color: isSelected ? Colors.white : color,
                    ),
                  ),
                  Text(
                    count.toString(),
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: isSelected
                          ? Colors.white
                          : const Color(0xFF0F172A),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: isSelected ? Colors.white : const Color(0xFF0F172A),
                ),
              ),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  color: isSelected
                      ? Colors.white.withValues(alpha: 0.8)
                      : Colors.grey.shade500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
