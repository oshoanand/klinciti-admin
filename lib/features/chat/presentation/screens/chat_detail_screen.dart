import 'dart:io';
import 'dart:async'; // Required for typing debouncer

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../widgets/chat_bubble.dart';
import '../widgets/chat_input.dart';
import '../../providers/chat_messages_provider.dart';
import '../../providers/active_chat_provider.dart';
import '../../../../core/socket/socket_service.dart';
import '../../data/chat_repository.dart';
import '../../../auth/providers/auth_provider.dart';

class ChatDetailScreen extends ConsumerStatefulWidget {
  final String sessionId;
  final String partnerId;
  final String? partnerName; // ✅ Added
  final String? partnerAvatar; // ✅ Added

  const ChatDetailScreen({
    super.key,
    required this.sessionId,
    required this.partnerId,
    this.partnerName,
    this.partnerAvatar,
  });

  @override
  ConsumerState<ChatDetailScreen> createState() => _ChatDetailScreenState();
}

class _ChatDetailScreenState extends ConsumerState<ChatDetailScreen>
    with WidgetsBindingObserver {
  final ScrollController _scrollController = ScrollController();
  final ImagePicker _picker = ImagePicker();

  bool _isUploading = false;

  // Real-time State Variables
  bool _partnerIsTyping = false;
  bool _partnerIsOnline = false;
  DateTime? _partnerLastSeen;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addObserver(this);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      // ✅ Register this room as currently active
      ref.read(activeChatSessionProvider.notifier).state = widget.sessionId;
      // Mark messages as read on open
      ref
          .read(chatMessagesProvider(widget.sessionId).notifier)
          .markAsRead(widget.partnerId);

      // ✅ Setup Socket Listeners for this specific room
      final socket = ref.read(socketServiceProvider);
      socket.listen('user_typing', _onPartnerTyping);
      socket.listen('user_stopped_typing', _onPartnerStoppedTyping);
      socket.listen('user_status_changed', _onUserStatusChanged);

      // ✅ Request initial presence
      socket.emit('check_presence', {'userId': widget.partnerId});
      socket.listen('user_presence', _onUserStatusChanged);
    });
  }

  // ==========================================
  // REAL-TIME SOCKET HANDLERS
  // ==========================================

  void _onPartnerTyping(dynamic payload) {
    if (!mounted) return;
    try {
      final data = Map<String, dynamic>.from(payload);
      if (data['userId'] == widget.partnerId) {
        setState(() => _partnerIsTyping = true);
        _scrollToBottom(); // ✅ Scroll down to show the typing bubble
      }
    } catch (_) {}
  }

  void _onPartnerStoppedTyping(dynamic payload) {
    if (!mounted) return;
    try {
      final data = Map<String, dynamic>.from(payload);
      if (data['userId'] == widget.partnerId) {
        setState(() => _partnerIsTyping = false);
      }
    } catch (_) {}
  }

  void _onUserStatusChanged(dynamic payload) {
    if (!mounted) return;
    try {
      final data = Map<String, dynamic>.from(payload);
      if (data['userId'] == widget.partnerId) {
        setState(() {
          _partnerIsOnline = data['isOnline'] as bool;
          final lastSeenStr = data['lastSeen'] as String?;
          if (lastSeenStr != null) {
            _partnerLastSeen = DateTime.parse(lastSeenStr);
          }
        });
      }
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(socketServiceProvider).emit('check_presence', {
        'userId': widget.partnerId,
      });
      ref
          .read(chatMessagesProvider(widget.sessionId).notifier)
          .markAsRead(widget.partnerId);
    }
  }

  void _onScroll() {
    // ✅ FIXED: Subtraction operator restored
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      ref.read(chatMessagesProvider(widget.sessionId).notifier).loadMore();
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0.0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  // ==========================================
  // IMAGE UPLOAD
  // ==========================================

  Future<void> _pickAndUploadImage(ImageSource source) async {
    try {
      final XFile? image = await _picker.pickImage(
        source: source,
        imageQuality: 70,
      );

      if (image == null) return;

      setState(() => _isUploading = true);

      final repo = ref.read(chatRepositoryProvider);
      final imageUrl = await repo.uploadChatImage(
        File(image.path),
        sessionId: widget.sessionId,
      );

      ref
          .read(chatMessagesProvider(widget.sessionId).notifier)
          .sendMessage(
            text: '',
            receiverId: widget.partnerId,
            imageUrl: imageUrl,
          );

      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Ошибка загрузки фото: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
      }
    }
  }

  void _showAttachmentOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: const Text('Сделать фото'),
              onTap: () {
                Navigator.pop(context);
                _pickAndUploadImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Выбрать из галереи'),
              onTap: () {
                Navigator.pop(context);
                _pickAndUploadImage(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // UI BUILDERS
  // ==========================================

  Widget _buildDateSeparator(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    // ✅ FIXED: Using safe .subtract instead of error-prone math
    final yesterday = today.subtract(const Duration(days: 1));
    final msgDay = DateTime(date.year, date.month, date.day);

    String dateText;
    if (msgDay == today) {
      dateText = 'Сегодня';
    } else if (msgDay == yesterday) {
      dateText = 'Вчера';
    } else {
      dateText = DateFormat('d MMMM', 'ru').format(date);
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 16),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        dateText,
        style: TextStyle(
          fontSize: 12,
          color: Colors.grey.shade600,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildAppBarTitle() {
    String statusText = _partnerIsTyping ? 'Печатает...' : 'Не в сети';
    Color dotColor = _partnerIsTyping
        ? Colors.blueAccent
        : (_partnerIsOnline
              ? Colors.greenAccent.shade400
              : Colors.grey.shade400);

    if (!_partnerIsTyping) {
      if (_partnerIsOnline) {
        statusText = 'В сети';
      } else if (_partnerLastSeen != null) {
        final lastSeen = _partnerLastSeen!.toLocal(); // ✅ Force Local Time
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        final yesterday = today.subtract(const Duration(days: 1));
        final msgDay = DateTime(lastSeen.year, lastSeen.month, lastSeen.day);

        if (msgDay == today) {
          statusText = 'Сегодня в ${DateFormat('HH:mm').format(lastSeen)}';
        } else if (msgDay == yesterday) {
          statusText = 'Вчера в ${DateFormat('HH:mm').format(lastSeen)}';
        } else {
          statusText =
              '${DateFormat('d MMM', 'ru').format(lastSeen)} в ${DateFormat('HH:mm').format(lastSeen)}';
        }
      }
    }

    return Row(
      children: [
        // ✅ Partner Avatar
        Stack(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: Colors.grey.shade200,
              backgroundImage: widget.partnerAvatar != null
                  ? NetworkImage(widget.partnerAvatar!)
                  : null,
              child: widget.partnerAvatar == null
                  ? const Icon(Icons.person, color: Colors.grey, size: 20)
                  : null,
            ),
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: dotColor,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(width: 12),
        // ✅ Partner Name and Status
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                widget.partnerName ?? 'Чат ${widget.partnerId.substring(0, 6)}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                statusText,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: _partnerIsTyping
                      ? FontWeight.w600
                      : FontWeight.normal,
                  color: _partnerIsTyping
                      ? Colors.blueAccent.shade700
                      : Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    // ✅ Unregister this room when we leave the screen
    ref.read(activeChatSessionProvider.notifier).state = null;
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.dispose();

    // ✅ Clean up socket listeners
    final socket = ref.read(socketServiceProvider);
    socket.stopListening('user_typing', _onPartnerTyping);
    socket.stopListening('user_stopped_typing', _onPartnerStoppedTyping);
    socket.stopListening('user_status_changed', _onUserStatusChanged);
    socket.stopListening('user_presence', _onUserStatusChanged);

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final messagesState = ref.watch(chatMessagesProvider(widget.sessionId));
    final currentUser = ref.watch(currentUserProvider);
    final currentUserId = currentUser?['id']?.toString() ?? '';

    // ✅ Auto-scroll when a new message arrives while we are at the bottom
    // ref.listen(chatMessagesProvider(widget.sessionId), (previous, next) {
    //   if (next.hasValue && previous?.value != null) {
    //     if (next.value!.length > previous.value!.length) {
    //       if (_scrollController.hasClients && _scrollController.offset < 100) {
    //         _scrollToBottom();
    //       }
    //     }
    //   }
    // });

    // ✅ Auto-scroll when a new message arrives while we are at the bottom
    ref.listen(chatMessagesProvider(widget.sessionId), (previous, next) {
      final currentMessages = next.value;
      final previousMessages = previous?.value;

      if (currentMessages != null && previousMessages != null) {
        if (currentMessages.length > previousMessages.length) {
          if (_scrollController.hasClients && _scrollController.offset < 100) {
            _scrollToBottom();
          }
        }
      }
    });

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        titleSpacing: 0,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        title: _buildAppBarTitle(),
      ),
      body: Column(
        children: [
          Expanded(
            child: messagesState.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) =>
                  Center(child: Text('Ошибка загрузки: $error')),
              data: (messages) {
                if (messages.isEmpty) {
                  return const Center(
                    child: Text(
                      'Напишите первое сообщение',
                      style: TextStyle(color: Colors.grey),
                    ),
                  );
                }

                if (messages.isNotEmpty &&
                    messages.first.senderId == widget.partnerId &&
                    !messages.first.isRead) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    ref
                        .read(chatMessagesProvider(widget.sessionId).notifier)
                        .markAsRead(widget.partnerId);
                  });
                }

                return ListView.builder(
                  controller: _scrollController,
                  reverse: true, // index 0 is at the bottom (newest)
                  // ✅ Add +1 to length if partner is typing to show the bubble at the bottom
                  itemCount: messages.length + (_partnerIsTyping ? 1 : 0),
                  itemBuilder: (context, index) {
                    // ✅ Inject Typing Bubble at index 0 (the bottom)
                    if (_partnerIsTyping) {
                      if (index == 0) {
                        return Padding(
                          padding: const EdgeInsets.only(
                            left: 16,
                            bottom: 8,
                            top: 4,
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: const Text(
                                  'Печатает...',
                                  style: TextStyle(
                                    color: Colors.blueAccent,
                                    fontStyle: FontStyle.italic,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }
                      // Shift all actual messages up by 1
                      index -= 1;
                    }

                    final msg = messages[index];
                    final msgDate = DateTime.parse(msg.createdAt).toLocal();

                    bool showDateSeparator = false;

                    // ✅ FIXED: Subtraction operator restored
                    if (index == messages.length - 1) {
                      showDateSeparator = true;
                    } else {
                      final nextOlderMsg = messages[index + 1];
                      final nextOlderDate = DateTime.parse(
                        nextOlderMsg.createdAt,
                      ).toLocal();

                      if (msgDate.year != nextOlderDate.year ||
                          msgDate.month != nextOlderDate.month ||
                          msgDate.day != nextOlderDate.day) {
                        showDateSeparator = true;
                      }
                    }

                    final bubble = ChatBubble(
                      message: msg,
                      isMe: msg.senderId == currentUserId,
                    );

                    if (showDateSeparator) {
                      return Column(
                        children: [_buildDateSeparator(msgDate), bubble],
                      );
                    }

                    return bubble;
                  },
                );
              },
            ),
          ),
          ChatInput(
            isUploading: _isUploading,
            onSend: (text) {
              ref
                  .read(chatMessagesProvider(widget.sessionId).notifier)
                  .sendMessage(text: text, receiverId: widget.partnerId);

              // ✅ Stop typing when message is sent
              ref.read(socketServiceProvider).emit('stop_typing', {
                'receiverId': widget.partnerId,
              });

              _scrollToBottom();
            },
            onTyping: () {
              // ✅ Emit typing event to backend
              ref.read(socketServiceProvider).emit('typing', {
                'receiverId': widget.partnerId,
              });
            },
            onAttachmentPressed: _showAttachmentOptions,
          ),
        ],
      ),
    );
  }
}
