import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;

import '../../core/network/api_client.dart';
import '../../core/router/route_names.dart';
import '../../core/utils/phone_formatter.dart';
import '../../features/auth/providers/auth_provider.dart';

final isAvatarUploadingProvider = StateProvider.autoDispose<bool>(
  (ref) => false,
);

class ProfileDrawer extends ConsumerWidget {
  const ProfileDrawer({super.key});

  // ==========================================
  // UPLOAD LOGIC
  // ==========================================
  Future<void> _pickAndUploadAvatar(
    BuildContext context,
    WidgetRef ref,
    ImageSource source,
  ) async {
    Navigator.pop(context); // Close the camera/gallery bottom sheet

    final picker = ImagePicker();
    final XFile? pickedImage = await picker.pickImage(
      source: source,
      imageQuality: 70,
      maxWidth: 800,
    );

    if (pickedImage == null) return;

    ref.read(isAvatarUploadingProvider.notifier).state = true;

    try {
      final file = File(pickedImage.path);
      final fileName = p.basename(file.path);
      final api = ref.read(apiClientProvider);

      // 1. Get Presigned URL
      final presignedRes = await api.dio.post(
        '/admin/presigned-url',
        data: {'fileName': fileName, 'folderName': 'profileImage'},
      );
      final String uploadUrl = presignedRes.data['presignedUrl'].toString();
      final String publicUrl = presignedRes.data['publicUrl'].toString();

      // 2. Upload to MinIO directly
      final rawDio = Dio(
        BaseOptions(
          sendTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 30),
        ),
      );

      String contentType = 'image/jpeg';
      final lower = fileName.toLowerCase();
      if (lower.endsWith('.png')) contentType = 'image/png';
      if (lower.endsWith('.webp')) contentType = 'image/webp';

      await rawDio.put(
        uploadUrl,
        data: file.openRead(),
        options: Options(
          headers: {
            Headers.contentLengthHeader: await file.length(),
            Headers.contentTypeHeader: contentType,
          },
        ),
      );

      // 3. Save URL to backend profile
      await api.dio.patch(
        '/admin/photo',
        data: {'imageUrl': publicUrl, 'imageType': 'profileImage'},
      );

      // 4. Update Riverpod state & secure storage atomically
      await ref.read(authControllerProvider).updateCurrentUser({
        'image': publicUrl,
      });
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ошибка при загрузке фото. Попробуйте еще раз.'),
          ),
        );
      }
    } finally {
      ref.read(isAvatarUploadingProvider.notifier).state = false;
    }
  }

  void _showImageSourcePicker(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(
                  LucideIcons.camera,
                  color: Color(0xFF0F172A),
                ),
                title: const Text(
                  'Сделать фото',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                onTap: () =>
                    _pickAndUploadAvatar(sheetCtx, ref, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(
                  LucideIcons.image,
                  color: Color(0xFF0F172A),
                ),
                title: const Text(
                  'Выбрать из галереи',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                onTap: () =>
                    _pickAndUploadAvatar(sheetCtx, ref, ImageSource.gallery),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ==========================================
  // UI BUILD
  // ==========================================
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAuthenticated = ref.watch(isAuthenticatedProvider);
    final user = ref.watch(currentUserProvider);
    final isUploading = ref.watch(isAvatarUploadingProvider);

    final String? avatarUrl =
        user?['image']?.toString() ?? user?['photo']?.toString();
    String name =
        user?['name']?.toString() ?? user?['first_name']?.toString() ?? '';
    if (name.trim().isEmpty) name = 'Администратор';

    final String? mobile = user?['mobile']?.toString();
    final String? email = user?['email']?.toString();
    final String role = (user?['role'] ?? '').toString().toUpperCase();
    final bool isAdmin = role.isEmpty || role == 'ADMINISTRATOR';

    return Drawer(
      width: MediaQuery.of(context).size.width * 0.85,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(right: Radius.circular(8)),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  if (isAuthenticated) ...[
                    // ==========================================
                    // LOGGED IN HEADER WITH AVATAR STACK
                    // ==========================================
                    Container(
                      padding: const EdgeInsets.all(16),
                      margin: const EdgeInsets.only(bottom: 24, top: 16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Row(
                        children: [
                          GestureDetector(
                            onTap: () => _showImageSourcePicker(context, ref),
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                Container(
                                  width: 80,
                                  height: 80,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF0F172A)
                                        .withValues(alpha: 0.1),
                                    shape: BoxShape.circle,
                                    image:
                                        avatarUrl != null &&
                                            avatarUrl.isNotEmpty
                                        ? DecorationImage(
                                            image: NetworkImage(avatarUrl),
                                            fit: BoxFit.cover,
                                          )
                                        : null,
                                  ),
                                  child: avatarUrl == null || avatarUrl.isEmpty
                                      ? const Icon(
                                          LucideIcons.user,
                                          color: Color(0xFF0F172A),
                                          size: 28,
                                        )
                                      : null,
                                ),
                                if (isUploading)
                                  Positioned.fill(
                                    child: Container(
                                      decoration: const BoxDecoration(
                                        color: Colors.black26,
                                        shape: BoxShape.circle,
                                      ),
                                      padding: const EdgeInsets.all(16),
                                      child: const CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 3,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                if (mobile != null && mobile.isNotEmpty)
                                  Text(
                                    PhoneFormatter.format(mobile),
                                    style: const TextStyle(
                                      color: Colors.grey,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                if (email != null && email.isNotEmpty)
                                  Text(
                                    email,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.grey,
                                      fontSize: 12,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    // ==========================================
                    // FINANCE & PAYMENTS SECTION (ADMIN ONLY)
                    // ==========================================
                    if (isAdmin) ...[
                      const Padding(
                        padding: EdgeInsets.only(left: 8, bottom: 6),
                        child: Text(
                          'ФИНАНСЫ И ПЛАТЕЖИ',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.8,
                            color: Color(0xFF94A3B8),
                          ),
                        ),
                      ),
                      _MenuItem(
                        icon: LucideIcons.receipt_text,
                        iconColor: const Color(0xFF0F766E),
                        title: 'История платежей и транзакций',
                        subtitle: 'Реестр T-Bank, возвраты и статусы',
                        onTap: () {
                          Navigator.pop(context);
                          context.push('${AppRoutes.finance}?tab=0');
                        },
                      ),
                      _MenuItem(
                        icon: LucideIcons.landmark,
                        iconColor: const Color(0xFFD97706),
                        title: 'Управление финансами',
                        subtitle: 'График выплат, комиссия и Kill Switch',
                        onTap: () {
                          Navigator.pop(context);
                          context.push('${AppRoutes.finance}?tab=1');
                        },
                      ),
                      const Divider(height: 28, color: Color(0xFFF1F5F9)),
                    ],

                    // ==========================================
                    // GENERAL MANAGEMENT SECTION
                    // ==========================================
                    const Padding(
                      padding: EdgeInsets.only(left: 8, bottom: 6),
                      child: Text(
                        'УПРАВЛЕНИЕ',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                          color: Color(0xFF94A3B8),
                        ),
                      ),
                    ),
                    _MenuItem(
                      icon: LucideIcons.user_pen,
                      title: 'Редактировать профиль',
                      subtitle: 'Настройки и данные',
                      onTap: () {
                        Navigator.pop(context);
                        context.push(AppRoutes.profileEdit);
                      },
                    ),
                    _MenuItem(
                      icon: LucideIcons.users,
                      title: 'Пользователи',
                      subtitle: 'Управление сотрудниками',
                      onTap: () {
                        Navigator.pop(context);
                        context.push(AppRoutes.staffList);
                      },
                    ),
                    _MenuItem(
                      icon: LucideIcons.layout_list,
                      title: 'Категории',
                      subtitle: 'Управление услугами',
                      onTap: () {
                        Navigator.pop(context);
                        context.push(AppRoutes.categories);
                      },
                    ),

                    const Divider(height: 32, color: Color(0xFFF1F5F9)),
                    _MenuItem(
                      icon: LucideIcons.log_out,
                      title: 'Выйти',
                      subtitle: 'Завершить сеанс',
                      iconColor: Colors.red,
                      isDestructive: true,
                      onTap: () {
                        Navigator.pop(context);
                        ref.read(authControllerProvider).logout(context);
                      },
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color iconColor;
  final bool isDestructive;
  final VoidCallback onTap;

  const _MenuItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.iconColor = const Color(0xFF0F172A),
    this.isDestructive = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final Color effectiveColor = isDestructive ? Colors.red : iconColor;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: (isDestructive ? Colors.red : iconColor).withValues(
                  alpha: 0.1,
                ),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: effectiveColor, size: 22),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: isDestructive
                          ? Colors.red
                          : const Color(0xFF0F172A),
                    ),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                ],
              ),
            ),
            if (!isDestructive)
              const Icon(
                LucideIcons.chevron_right,
                size: 18,
                color: Color(0xFFCBD5E1),
              ),
          ],
        ),
      ),
    );
  }
}
