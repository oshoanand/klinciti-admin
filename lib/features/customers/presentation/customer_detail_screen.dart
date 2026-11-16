import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exceptions.dart';
import '../../../core/router/route_names.dart';
import '../../../core/socket/socket_service.dart';
import '../../../shared/widgets/global_error_widget.dart';
import '../../chat/data/chat_repository.dart';
import '../providers/customer_detail_provider.dart';
import '../providers/customers_list_provider.dart';

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
        context.push(
          '${AppRoutes.chatDetail}/${session.id}/${widget.customerId}',
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        final errorMessage = e is ApiException
            ? e.message
            : ApiException.fromDioException(e).message;
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
        _isLoading ? 'Загрузка...' : 'Написать клиенту',
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF3B82F6),
        foregroundColor: Colors.white,
        disabledBackgroundColor: const Color(0xFF3B82F6).withValues(alpha: 0.6),
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
  late final SocketService _socketService;

  @override
  void initState() {
    super.initState();
    // Cache SocketService instance so dispose() never calls ref.read()
    _socketService = ref.read(socketServiceProvider);
    _socketService.listen('user_status_changed', _onUserStatusChanged);
  }

  void _onUserStatusChanged(dynamic data) {
    if (!mounted || data is! Map) return;
    try {
      final eventUserId = data['userId']?.toString();

      if (eventUserId == widget.customerId) {
        final isOnline = data['isOnline'] == true;
        final lastSeenStr = data['lastSeen']?.toString();
        final lastSeen = lastSeenStr != null
            ? DateTime.tryParse(lastSeenStr)
            : null;

        ref
            .read(customerDetailProvider(widget.customerId).notifier)
            .updatePresence(isOnline, lastSeen);
        ref
            .read(customersListProvider.notifier)
            .updateCustomerStatus(eventUserId!, isOnline, lastSeen);
      }
    } catch (e) {
      debugPrint('Error parsing user_status_changed on detail screen: $e');
    }
  }

  @override
  void dispose() {
    _socketService.stopListening('user_status_changed', _onUserStatusChanged);
    super.dispose();
  }

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

  Future<void> _confirmAndToggleStatus(bool isCurrentlyActive) async {
    if (isCurrentlyActive) {
      final bool? confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Заблокировать клиента?'),
          content: const Text(
            'Заблокированный клиент не сможет создавать новые заказы и входить в приложение. Вы сможете разблокировать его в любой момент.',
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
            : ApiException.fromDioException(e).message;
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
        surfaceTintColor: Colors.white,
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
        actions: [
          IconButton(
            icon: const Icon(
              LucideIcons.refresh_cw,
              size: 18,
              color: Color(0xFF0F172A),
            ),
            tooltip: 'Обновить',
            onPressed: () =>
                ref.invalidate(customerDetailProvider(widget.customerId)),
          ),
        ],
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
          final hasImage =
              customer.image != null && customer.image!.trim().isNotEmpty;

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
                  const SizedBox(height: 12),

                  // Avatar with Presence Dot Overlay
                  Stack(
                    children: [
                      CircleAvatar(
                        radius: 50,
                        backgroundColor: const Color(0xFF0F172A)
                            .withValues(alpha: 0.05),
                        backgroundImage: hasImage
                            ? NetworkImage(customer.image!)
                            : null,
                        child: !hasImage
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
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 4),

                  // Real-time Presence Text
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

                  // Contact & Account Card
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
                                  onPressed: () => _copyToClipboard(
                                    customer.mobile!,
                                    'Телефон',
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(
                                    LucideIcons.phone_call,
                                    color: Colors.green,
                                  ),
                                  tooltip: 'Позвонить',
                                  onPressed: () => _makeCall(customer.mobile),
                                ),
                              ],
                            ),
                          ),
                        if (customer.email != null &&
                            customer.email!.isNotEmpty) ...[
                          const Divider(height: 1),
                          ListTile(
                            leading: const Icon(
                              LucideIcons.mail,
                              color: Colors.grey,
                            ),
                            title: const Text('Email'),
                            subtitle: Text(customer.email!),
                            trailing: IconButton(
                              icon: const Icon(
                                LucideIcons.copy,
                                size: 18,
                                color: Colors.blueGrey,
                              ),
                              tooltip: 'Скопировать Email',
                              onPressed: () =>
                                  _copyToClipboard(customer.email!, 'Email'),
                            ),
                          ),
                        ],
                        if ((customer.city != null &&
                                customer.city!.trim().isNotEmpty) ||
                            (customer.address != null &&
                                customer.address!.trim().isNotEmpty)) ...[
                          const Divider(height: 1),
                          ListTile(
                            leading: const Icon(
                              LucideIcons.map_pin,
                              color: Colors.grey,
                            ),
                            title: const Text('Адрес'),
                            subtitle: Text(
                              [customer.city, customer.address]
                                  .where(
                                    (e) => e != null && e.trim().isNotEmpty,
                                  )
                                  .join(', '),
                            ),
                          ),
                        ],
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
                              fontWeight: FontWeight.w600,
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
                                  activeThumbColor: Colors.white,
                                  activeTrackColor: Colors.green,
                                  onChanged: (_) => _confirmAndToggleStatus(
                                    customer.isActive,
                                  ),
                                ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Action Buttons Row
                  Row(
                    children: [
                      if (customer.mobile != null &&
                          customer.mobile!.trim().isNotEmpty) ...[
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _makeCall(customer.mobile),
                            icon: const Icon(LucideIcons.phone, size: 18),
                            label: const Text(
                              'Позвонить',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.green.shade700,
                              side: BorderSide(color: Colors.green.shade400),
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                      ],
                      Expanded(
                        flex: 2,
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
