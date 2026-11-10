import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/network/api_exceptions.dart';
import '../../../core/network/api_client.dart';
import '../../../shared/widgets/global_error_widget.dart';
import '../../../core/socket/socket_service.dart';
import '../providers/customer_detail_provider.dart';
import '../providers/customers_list_provider.dart';
import '../../chat/data/chat_repository.dart';

class _StartChatButton extends ConsumerStatefulWidget {
  final String customerId;

  const _StartChatButton({required this.customerId});

  @override
  ConsumerState<_StartChatButton> createState() => _StartChatButtonState();
}

class _StartChatButtonState extends ConsumerState<_StartChatButton> {
  bool _isLoading = false;

  Future<void> _initiateChat() async {
    setState(() => _isLoading = true);

    try {
      final repo = ref.read(chatRepositoryProvider);
      final session = await repo.initiateChat(widget.customerId);

      if (mounted) {
        setState(() => _isLoading = false);
        context.push('/chat/${session.id}/${widget.customerId}');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        final errorMessage = e is ApiException
            ? e.message
            : 'Ошибка создания чата';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red.shade800,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: _isLoading ? null : _initiateChat,
      icon: _isLoading
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 2.5,
              ),
            )
          : const Icon(LucideIcons.message_circle),
      label: Text(
        _isLoading ? 'Загрузка...' : 'Написать',
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF3B82F6),
        foregroundColor: Colors.white,
        disabledBackgroundColor: const Color(0xFF3B82F6).withOpacity(0.6),
        disabledForegroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 16),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}

class CustomerDetailScreen extends ConsumerStatefulWidget {
  final String customerId;
  const CustomerDetailScreen({super.key, required this.customerId});

  @override
  ConsumerState<CustomerDetailScreen> createState() =>
      _CustomerDetailScreenState();
}

class _CustomerDetailScreenState extends ConsumerState<CustomerDetailScreen> {
  bool _isUpdating = false;

  @override
  void initState() {
    super.initState();
    // ✅ Start listening to Socket real-time events
    ref
        .read(socketServiceProvider)
        .listen('user_status_changed', _onUserStatusChanged);
  }

  void _onUserStatusChanged(dynamic data) {
    if (!mounted) return;
    try {
      final eventUserId = data['userId'] as String;

      // Only update if the event is for the customer we are currently viewing
      if (eventUserId == widget.customerId) {
        final isOnline = data['isOnline'] as bool;
        final lastSeenStr = data['lastSeen'] as String?;
        final lastSeen = lastSeenStr != null
            ? DateTime.parse(lastSeenStr)
            : null;

        // Update both the Detail screen and the main List provider instantly
        ref
            .read(customerDetailProvider(widget.customerId).notifier)
            .updatePresence(isOnline, lastSeen);
        ref
            .read(customersListProvider.notifier)
            .updateCustomerStatus(eventUserId, isOnline, lastSeen);
      }
    } catch (e) {
      debugPrint('Error parsing user_status_changed on detail screen: $e');
    }
  }

  @override
  void dispose() {
    // ✅ Remove the listener when we pop back
    ref
        .read(socketServiceProvider)
        .stopListening('user_status_changed', _onUserStatusChanged);
    super.dispose();
  }

  // ✅ Helper for Localized Timestamp
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

  Future<void> _toggleUserStatus(bool currentStatus) async {
    setState(() => _isUpdating = true);
    try {
      final api = ref.read(apiClientProvider);

      await api.dio.patch(
        '/customers/admin/${widget.customerId}/status',
        data: {'authStatus': currentStatus ? 'BLOCKED' : 'ACTIVE'},
      );

      ref.invalidate(customerDetailProvider(widget.customerId));
      ref.invalidate(customersListProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              currentStatus ? 'Клиент заблокирован' : 'Клиент разблокирован',
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
    final detailAsync = ref.watch(customerDetailProvider(widget.customerId));

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
          'Профиль клиента',
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
          onRetry: () =>
              ref.invalidate(customerDetailProvider(widget.customerId)),
        ),
        data: (customer) {
          final isOnline = customer.isOnline;

          return RefreshIndicator(
            color: const Color(0xFF0F172A),
            onRefresh: () async =>
                ref.invalidate(customerDetailProvider(widget.customerId)),
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(height: 16),

                  // ✅ Avatar with Presence Dot Overlay
                  Stack(
                    children: [
                      CircleAvatar(
                        radius: 50,
                        backgroundColor: const Color(0xFF0F172A)
                            .withOpacity(0.05),
                        backgroundImage: customer.image != null
                            ? NetworkImage(customer.image!)
                            : null,
                        child: customer.image == null
                            ? const Icon(
                                LucideIcons.user,
                                size: 40,
                                color: Colors.grey,
                              )
                            : null,
                      ),
                      Positioned(
                        right: 4,
                        bottom: 4,
                        child: Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            color: isOnline
                                ? Colors.green
                                : Colors.grey.shade400,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 3),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    customer.name,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),

                  // ✅ Real-time Presence Text
                  if (isOnline)
                    const Text(
                      'В сети',
                      style: TextStyle(
                        color: Colors.green,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    )
                  else if (customer.lastSeen != null)
                    Text(
                      _formatLastSeen(customer.lastSeen!),
                      style: const TextStyle(color: Colors.grey, fontSize: 14),
                    )
                  else
                    const Text(
                      'Не в сети',
                      style: TextStyle(color: Colors.grey, fontSize: 14),
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
                        if (customer.mobile != null &&
                            customer.mobile!.isNotEmpty)
                          ListTile(
                            leading: const Icon(
                              LucideIcons.phone,
                              color: Colors.grey,
                            ),
                            title: const Text('Телефон'),
                            subtitle: Text(customer.mobile!),
                            trailing: IconButton(
                              icon: const Icon(
                                LucideIcons.phone_call,
                                color: Colors.green,
                              ),
                              onPressed: () => launchUrl(
                                Uri.parse('tel:${customer.mobile}'),
                              ),
                            ),
                          ),
                        if (customer.email != null &&
                            customer.email!.isNotEmpty)
                          ListTile(
                            leading: const Icon(
                              LucideIcons.mail,
                              color: Colors.grey,
                            ),
                            title: const Text('Email'),
                            subtitle: Text(customer.email!),
                          ),
                        if (customer.city != null || customer.address != null)
                          ListTile(
                            leading: const Icon(
                              LucideIcons.map_pin,
                              color: Colors.grey,
                            ),
                            title: const Text('Адрес'),
                            subtitle: Text(
                              [
                                customer.city,
                                customer.address,
                              ].where((e) => e != null).join(', '),
                            ),
                          ),
                        const Divider(height: 1),
                        ListTile(
                          leading: Icon(
                            customer.isActive
                                ? LucideIcons.shield_check
                                : LucideIcons.shield_alert,
                            color: customer.isActive
                                ? Colors.green
                                : Colors.red,
                          ),
                          title: const Text('Статус аккаунта'),
                          subtitle: Text(
                            customer.isActive ? 'Активен' : 'Заблокирован',
                            style: TextStyle(
                              color: customer.isActive
                                  ? Colors.green
                                  : Colors.red,
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
                                  value: customer.isActive,
                                  activeColor: Colors.green,
                                  onChanged: (val) =>
                                      _toggleUserStatus(customer.isActive),
                                ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  Row(
                    children: [
                      Expanded(
                        child: _StartChatButton(customerId: customer.id),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
