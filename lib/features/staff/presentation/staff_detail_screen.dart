import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/network/api_exceptions.dart';
import '../../../core/network/api_client.dart';
import '../../../shared/widgets/global_error_widget.dart';
import '../providers/staff_detail_provider.dart';
import '../providers/staff_list_provider.dart';
import '../data/staff_model.dart';

class StaffDetailScreen extends ConsumerStatefulWidget {
  final String staffId;
  const StaffDetailScreen({super.key, required this.staffId});

  @override
  ConsumerState<StaffDetailScreen> createState() => _StaffDetailScreenState();
}

class _StaffDetailScreenState extends ConsumerState<StaffDetailScreen> {
  bool _isUpdating = false;

  Future<void> _toggleUserStatus(bool currentStatus) async {
    setState(() => _isUpdating = true);
    try {
      final api = ref.read(apiClientProvider);

      await api.dio.patch(
        '/users/staff/${widget.staffId}', // Maps to PATCH /staff/:id
        data: {'authStatus': currentStatus ? 'SUSPENDED' : 'ACTIVE'},
      );

      ref.invalidate(staffDetailProvider(widget.staffId));
      ref.invalidate(staffListProvider('ALL'));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              currentStatus
                  ? 'Сотрудник заблокирован'
                  : 'Сотрудник разблокирован',
            ),
            backgroundColor: currentStatus ? Colors.red : Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        final message = e is ApiException
            ? e.message
            : 'Ошибка при обновлении статуса';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final detailAsync = ref.watch(staffDetailProvider(widget.staffId));

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(LucideIcons.arrow_left, color: Color(0xFF0F172A)),
          onPressed: () => context.pop(),
        ),
        title: const Text(
          'Профиль сотрудника',
          style: TextStyle(
            color: Color(0xFF0F172A),
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: detailAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: Color(0xFF0F172A)),
        ),
        error: (error, _) => GlobalErrorWidget(
          message: error is ApiException ? error.message : 'Ошибка загрузки.',
          onRetry: () => ref.invalidate(staffDetailProvider(widget.staffId)),
        ),
        data: (staff) => RefreshIndicator(
          color: const Color(0xFF0F172A),
          onRefresh: () async =>
              ref.invalidate(staffDetailProvider(widget.staffId)),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(height: 16),
                CircleAvatar(
                  radius: 50,
                  backgroundColor: const Color(0xFF0F172A).withOpacity(0.05),
                  child: const Icon(
                    LucideIcons.user,
                    size: 40,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  staff.name,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  staff.role,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.blue,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 24),

                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Column(
                    children: [
                      if (staff.mobile != null && staff.mobile!.isNotEmpty)
                        ListTile(
                          leading: const Icon(
                            LucideIcons.phone,
                            color: Colors.grey,
                          ),
                          title: const Text('Телефон'),
                          subtitle: Text(staff.mobile!),
                          trailing: IconButton(
                            icon: const Icon(
                              LucideIcons.phone_call,
                              color: Colors.green,
                            ),
                            onPressed: () =>
                                launchUrl(Uri.parse('tel:${staff.mobile}')),
                          ),
                        ),
                      if (staff.email != null && staff.email!.isNotEmpty)
                        ListTile(
                          leading: const Icon(
                            LucideIcons.mail,
                            color: Colors.grey,
                          ),
                          title: const Text('Email'),
                          subtitle: Text(staff.email!),
                        ),
                      const Divider(height: 1),
                      ListTile(
                        leading: Icon(
                          staff.isActive
                              ? LucideIcons.shield_check
                              : LucideIcons.shield_alert,
                          color: staff.isActive ? Colors.green : Colors.red,
                        ),
                        title: const Text('Статус аккаунта'),
                        subtitle: Text(
                          staff.isActive ? 'Активен' : 'Заблокирован',
                          style: TextStyle(
                            color: staff.isActive ? Colors.green : Colors.red,
                          ),
                        ),
                        trailing: _isUpdating
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Switch(
                                value: staff.isActive,
                                activeColor: Colors.green,
                                onChanged: (val) =>
                                    _toggleUserStatus(staff.isActive),
                              ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => context.push('/chat/new/${staff.id}'),
                    icon: const Icon(LucideIcons.message_circle),
                    label: const Text('Написать сообщение'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
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
