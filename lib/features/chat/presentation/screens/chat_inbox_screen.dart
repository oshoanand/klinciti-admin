import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../data/chat_repository.dart';
import '../../providers/chat_sessions_provider.dart';

class ChatInboxScreen extends ConsumerStatefulWidget {
  const ChatInboxScreen({super.key});

  @override
  ConsumerState<ChatInboxScreen> createState() => _ChatInboxScreenState();
}

class _ChatInboxScreenState extends ConsumerState<ChatInboxScreen> {
  final _inboxSearchCtrl = TextEditingController();
  String _inboxQuery = '';

  @override
  void dispose() {
    _inboxSearchCtrl.dispose();
    super.dispose();
  }

  Future<void> _openNewChatPicker() async {
    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(sheetCtx).bottom,
        ),
        child: SafeArea(
          top: false,
          child: DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.78,
            maxChildSize: 0.94,
            builder: (ctx, scrollCtrl) => _AdminContactPickerSheet(
              scrollController: scrollCtrl,
              onContactSelected: (contact) async {
                Navigator.of(ctx, rootNavigator: true).pop();
                try {
                  final session = await ref
                      .read(chatRepositoryProvider)
                      .initiateChat(contact['id'].toString());
                  ref.read(chatSessionsProvider.notifier).refresh();
                  if (!mounted) return;
                  context.push(
                    '/chat/${session.id}/${session.partnerId}',
                    extra: {
                      'partnerName': session.partnerName ?? contact['name'],
                      'partnerAvatar':
                          session.partnerAvatar ?? contact['avatar'],
                    },
                  );
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Не удалось открыть чат: $e')),
                    );
                  }
                }
              },
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sessionsState = ref.watch(chatSessionsProvider);
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
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
            'Чаты',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: Color(0xFF0F172A),
              letterSpacing: -0.5,
              fontSize: 22,
            ),
          ),
          actions: [
            IconButton(
              tooltip: 'Публичная FCM-рассылка (акции, поздравления)',
              icon: const Icon(LucideIcons.megaphone, color: Color(0xFFE0780F)),
              onPressed: () => context.push('/admin/broadcast'),
            ),
            const SizedBox(width: 4),
          ],
        ),
        floatingActionButton: Padding(
          padding: EdgeInsets.only(bottom: bottomInset + 76),
          child: FloatingActionButton.extended(
            onPressed: _openNewChatPicker,
            backgroundColor: const Color(0xFF0F172A),
            foregroundColor: Colors.white,
            icon: const Icon(LucideIcons.message_square_plus, size: 20),
            label: const Text('Написать'),
          ),
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                controller: _inboxSearchCtrl,
                onChanged: (v) =>
                    setState(() => _inboxQuery = v.trim().toLowerCase()),
                decoration: InputDecoration(
                  hintText: 'Поиск по диалогам...',
                  prefixIcon: const Icon(LucideIcons.search, size: 18),
                  suffixIcon: _inboxQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(LucideIcons.x, size: 16),
                          onPressed: () {
                            _inboxSearchCtrl.clear();
                            setState(() => _inboxQuery = '');
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: Colors.white,
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                ),
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                color: const Color(0xFF0F172A),
                backgroundColor: Colors.white,
                onRefresh: () =>
                    ref.read(chatSessionsProvider.notifier).refresh(),
                child: sessionsState.when(
                  loading: () => const Center(
                    child: CircularProgressIndicator(color: Color(0xFF0F172A)),
                  ),
                  error: (err, _) => ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      const SizedBox(height: 100),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Text(
                          'Ошибка загрузки чатов: $err',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Color(0xFF64748B)),
                        ),
                      ),
                    ],
                  ),
                  data: (allSessions) {
                    final sessions = _inboxQuery.isEmpty
                        ? allSessions
                        : allSessions.where((s) {
                            final name = (s.partnerName ?? '').toLowerCase();
                            final msg = (s.lastMessage ?? '').toLowerCase();
                            return name.contains(_inboxQuery) ||
                                msg.contains(_inboxQuery);
                          }).toList();

                    if (sessions.isEmpty) {
                      return ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: const [
                          SizedBox(height: 100),
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: 24),
                            child: Text(
                              'Диалоги не найдены. Нажмите «Написать», чтобы начать чат с любым пользователем.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Color(0xFF64748B)),
                            ),
                          ),
                        ],
                      );
                    }

                    return ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(
                        parent: BouncingScrollPhysics(),
                      ),
                      padding: EdgeInsets.only(
                        top: 4,
                        bottom: bottomInset + 160,
                      ),
                      itemCount: sessions.length,
                      separatorBuilder: (_, __) => Padding(
                        padding: const EdgeInsets.only(left: 84, right: 20),
                        child: Divider(height: 1, color: Colors.grey.shade200),
                      ),
                      itemBuilder: (context, index) {
                        final session = sessions[index];
                        final date =
                            DateTime.tryParse(session.updatedAt)?.toLocal() ??
                            DateTime.now();
                        final isUnread = session.unreadCount > 0;
                        final fallbackId = session.partnerId.length >= 6
                            ? session.partnerId.substring(0, 6)
                            : session.partnerId;

                        return InkWell(
                          onTap: () => context.push(
                            '/chat/${session.id}/${session.partnerId}',
                            extra: {
                              'partnerName': session.partnerName,
                              'partnerAvatar': session.partnerAvatar,
                            },
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 14,
                            ),
                            child: Row(
                              children: [
                                Stack(
                                  children: [
                                    CircleAvatar(
                                      radius: 26,
                                      backgroundColor: const Color(0xFF0F172A)
                                          .withValues(alpha: 0.06),
                                      backgroundImage:
                                          session.partnerAvatar != null &&
                                              session.partnerAvatar!.isNotEmpty
                                          ? NetworkImage(session.partnerAvatar!)
                                          : null,
                                      child:
                                          session.partnerAvatar == null ||
                                              session.partnerAvatar!.isEmpty
                                          ? const Icon(
                                              LucideIcons.user,
                                              color: Color(0xFF64748B),
                                              size: 22,
                                            )
                                          : null,
                                    ),
                                    Positioned(
                                      right: 0,
                                      bottom: 0,
                                      child: Container(
                                        width: 13,
                                        height: 13,
                                        decoration: BoxDecoration(
                                          color: session.isOnline
                                              ? const Color(0xFF22C55E)
                                              : Colors.grey.shade400,
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: Colors.white,
                                            width: 2,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              session.partnerName ??
                                                  'ID: $fallbackId',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontWeight: isUnread
                                                    ? FontWeight.w800
                                                    : FontWeight.w600,
                                                fontSize: 15.5,
                                                color: const Color(0xFF0F172A),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            _formatLastMessageDate(date),
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: isUnread
                                                  ? const Color(0xFF2563EB)
                                                  : Colors.grey.shade500,
                                              fontWeight: isUnread
                                                  ? FontWeight.bold
                                                  : FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: session.isTyping
                                                ? const Text(
                                                    'Печатает...',
                                                    style: TextStyle(
                                                      color: Color(0xFF2563EB),
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      fontSize: 13.5,
                                                      fontStyle:
                                                          FontStyle.italic,
                                                    ),
                                                  )
                                                : Text(
                                                    session.lastMessage ??
                                                        'Нет сообщений',
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                      color: isUnread
                                                          ? const Color(
                                                              0xFF0F172A,
                                                            )
                                                          : Colors
                                                                .grey
                                                                .shade600,
                                                      fontWeight: isUnread
                                                          ? FontWeight.w600
                                                          : FontWeight.normal,
                                                      fontSize: 13.5,
                                                    ),
                                                  ),
                                          ),
                                          if (isUnread)
                                            Container(
                                              margin: const EdgeInsets.only(
                                                left: 8,
                                              ),
                                              constraints: const BoxConstraints(
                                                minWidth: 20,
                                                minHeight: 20,
                                              ),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 6,
                                                    vertical: 2,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFF2563EB),
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                              ),
                                              alignment: Alignment.center,
                                              child: Text(
                                                session.unreadCount > 99
                                                    ? '99+'
                                                    : '${session.unreadCount}',
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatLastMessageDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final msgDay = DateTime(date.year, date.month, date.day);

    if (msgDay == today) return DateFormat('HH:mm').format(date);
    if (msgDay == yesterday) return 'Вчера';
    return DateFormat('dd.MM.yy').format(date);
  }
}

class _AdminContactPickerSheet extends ConsumerStatefulWidget {
  final ScrollController scrollController;
  final Future<void> Function(Map<String, dynamic> contact) onContactSelected;

  const _AdminContactPickerSheet({
    required this.scrollController,
    required this.onContactSelected,
  });

  @override
  ConsumerState<_AdminContactPickerSheet> createState() =>
      _AdminContactPickerSheetState();
}

class _AdminContactPickerSheetState
    extends ConsumerState<_AdminContactPickerSheet> {
  static const List<(String, String)> _roleFilters = [
    ('ALL', 'Все'),
    ('CUSTOMER', 'Клиенты'),
    ('WORKER', 'Исполнители'),
    ('ADMINISTRATOR', 'Админы'),
  ];

  final _searchCtrl = TextEditingController();
  Timer? _debounce;
  String _role = 'ALL';
  bool _loading = true;
  String? _error;
  List<dynamic> _contacts = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await ref
          .read(chatRepositoryProvider)
          .searchAdminContacts(search: _searchCtrl.text, role: _role);
      if (mounted) {
        setState(() => _contacts = list);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Не удалось загрузить контакты: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFE2E8F0),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Новый чат с пользователем',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _searchCtrl,
            onChanged: (_) {
              _debounce?.cancel();
              _debounce = Timer(const Duration(milliseconds: 300), _load);
            },
            decoration: const InputDecoration(
              hintText: 'Имя, телефон или email...',
              prefixIcon: Icon(LucideIcons.search, size: 18),
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _roleFilters.map((entry) {
                final selected = _role == entry.$1;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(entry.$2),
                    selected: selected,
                    onSelected: (_) {
                      setState(() => _role = entry.$1);
                      _load();
                    },
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? Center(
                    child: Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Color(0xFFDC2626)),
                    ),
                  )
                : _contacts.isEmpty
                ? const Center(
                    child: Text(
                      'Пользователи не найдены',
                      style: TextStyle(color: Color(0xFF64748B)),
                    ),
                  )
                : ListView.builder(
                    controller: widget.scrollController,
                    itemCount: _contacts.length,
                    itemBuilder: (_, i) {
                      final c = _contacts[i];
                      final avatar = c['avatar']?.toString();
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundImage: avatar != null && avatar.isNotEmpty
                              ? NetworkImage(avatar)
                              : null,
                          child: avatar == null || avatar.isEmpty
                              ? const Icon(LucideIcons.user, size: 18)
                              : null,
                        ),
                        title: Text(
                          (c['name'] ?? 'Без имени').toString(),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          '${c['role']} • ${c['mobile'] ?? c['email'] ?? ''}',
                          style: const TextStyle(fontSize: 12),
                        ),
                        trailing: c['isOnline'] == true
                            ? const Icon(
                                Icons.circle,
                                color: Color(0xFF22C55E),
                                size: 10,
                              )
                            : null,
                        onTap: () => widget.onContactSelected(c),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
