import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exceptions.dart';
import '../../../core/router/route_names.dart';
import '../../../shared/widgets/global_error_widget.dart';
import '../../chat/data/chat_repository.dart';
import '../providers/staff_provider.dart';

class StaffDetailScreen extends ConsumerStatefulWidget {
  final String staffId;
  const StaffDetailScreen({super.key, required this.staffId});

  @override
  ConsumerState<StaffDetailScreen> createState() => _StaffDetailScreenState();
}

class _StaffDetailScreenState extends ConsumerState<StaffDetailScreen> {
  bool _isUpdating = false;
  bool _isStartingChat = false;

  Future<void> _makeCall(String? mobile) async {
    if (mobile == null || mobile.trim().isEmpty) return;

    final cleanNumber = mobile.replaceAll(RegExp(r'[^\d+]'), '');
    final Uri launchUri = Uri(scheme: 'tel', path: cleanNumber);

    try {
      await launchUrl(launchUri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Невозможно открыть набор номера на этом устройстве'),
          ),
        );
      }
    }
  }

  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label скопирован в буфер обмена'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _startChat(String staffId) async {
    setState(() => _isStartingChat = true);
    try {
      final session = await ref
          .read(chatRepositoryProvider)
          .initiateChat(staffId);
      if (mounted) {
        context.push('${AppRoutes.chatDetail}/${session.id}/$staffId');
      }
    } catch (e) {
      if (mounted) {
        final msg = e is ApiException
            ? e.message
            : ApiException.fromDioException(e).message;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка открытия чата: $msg'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isStartingChat = false);
    }
  }

  Future<void> _confirmAndToggleStatus(bool isCurrentlyActive) async {
    if (isCurrentlyActive) {
      final bool? confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Заблокировать сотрудника?'),
          content: const Text(
            'Заблокированный сотрудник потеряет доступ к панели управления Klinciti до разблокировки.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Отмена'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text(
                'Заблокировать',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    await _toggleUserStatus(isCurrentlyActive);
  }

  Future<void> _toggleUserStatus(bool currentStatus) async {
    setState(() => _isUpdating = true);
    try {
      final api = ref.read(apiClientProvider);

      await api.dio.patch(
        '/users/staff/${widget.staffId}',
        data: {'authStatus': currentStatus ? 'SUSPENDED' : 'ACTIVE'},
      );

      ref.invalidate(staffDetailProvider(widget.staffId));
      ref.invalidate(staffListProvider);

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
            : ApiException.fromDioException(e).message;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  String _getTranslatedRole(String role) {
    switch (role) {
      case 'ADMINISTRATOR':
        return 'АДМИНИСТРАТОР';
      case 'SUPPORT':
        return 'ПОДДЕРЖКА';
      default:
        return role;
    }
  }

  @override
  Widget build(BuildContext context) {
    final detailAsync = ref.watch(staffDetailProvider(widget.staffId));

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
        title: const Text(
          'Профиль сотрудника',
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
            tooltip: 'Обновить',
            onPressed: () =>
                ref.invalidate(staffDetailProvider(widget.staffId)),
          ),
        ],
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
                  radius: 48,
                  backgroundColor: const Color(0xFF0F172A)
                      .withValues(alpha: 0.06),
                  child: Icon(
                    staff.role == 'ADMINISTRATOR'
                        ? LucideIcons.shield_check
                        : LucideIcons.headset,
                    size: 40,
                    color: const Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  staff.name,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _getTranslatedRole(staff.role),
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.blue.shade800,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.8,
                    ),
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
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(
                                  LucideIcons.copy,
                                  size: 18,
                                  color: Colors.blueGrey,
                                ),
                                tooltip: 'Скопировать телефон',
                                onPressed: () =>
                                    _copyToClipboard(staff.mobile!, 'Телефон'),
                              ),
                              IconButton(
                                icon: const Icon(
                                  LucideIcons.phone_call,
                                  color: Colors.green,
                                ),
                                tooltip: 'Позвонить',
                                onPressed: () => _makeCall(staff.mobile),
                              ),
                            ],
                          ),
                        ),
                      if (staff.email != null && staff.email!.isNotEmpty) ...[
                        const Divider(height: 1),
                        ListTile(
                          leading: const Icon(
                            LucideIcons.mail,
                            color: Colors.grey,
                          ),
                          title: const Text('Email'),
                          subtitle: Text(staff.email!),
                          trailing: IconButton(
                            icon: const Icon(
                              LucideIcons.copy,
                              size: 18,
                              color: Colors.blueGrey,
                            ),
                            tooltip: 'Скопировать Email',
                            onPressed: () =>
                                _copyToClipboard(staff.email!, 'Email'),
                          ),
                        ),
                      ],
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
                            fontWeight: FontWeight.w600,
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
                                activeThumbColor: Colors.white,
                                activeTrackColor: Colors.green,
                                onChanged: (_) =>
                                    _confirmAndToggleStatus(staff.isActive),
                              ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isStartingChat
                        ? null
                        : () => _startChat(staff.id),
                    icon: _isStartingChat
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(LucideIcons.message_circle),
                    label: Text(
                      _isStartingChat
                          ? 'Открытие чата...'
                          : 'Написать сообщение',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF3B82F6),
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
