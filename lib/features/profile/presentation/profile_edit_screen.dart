import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:image_picker/image_picker.dart';

import '../providers/profile_provider.dart';
import '../data/profile_model.dart';
import '../../../shared/widgets/global_error_widget.dart';
import '../../../core/network/api_exceptions.dart';

class ProfileEditScreen extends ConsumerStatefulWidget {
  const ProfileEditScreen({super.key});

  @override
  ConsumerState<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends ConsumerState<ProfileEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final ImagePicker _picker = ImagePicker();

  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _middleNameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _mobileCtrl = TextEditingController();

  bool _isInitialized = false;

  // Populate controllers once data is loaded
  void _populateForm(ProfileModel profile) {
    if (!_isInitialized) {
      _firstNameCtrl.text = profile.firstName ?? '';
      _lastNameCtrl.text = profile.lastName ?? '';
      _middleNameCtrl.text = profile.middleName ?? '';
      _emailCtrl.text = profile.email ?? '';
      _mobileCtrl.text = profile.mobile ?? '';

      _isInitialized = true;
    }
  }

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _middleNameCtrl.dispose();
    _emailCtrl.dispose();
    _mobileCtrl.dispose();

    super.dispose();
  }

  Future<void> _handleImageSelection(ImageSource source) async {
    final pickedFile = await _picker.pickImage(
      source: source,
      imageQuality: 70,
    );
    if (pickedFile != null) {
      try {
        await ref
            .read(profileMutationProvider.notifier)
            .uploadAndSetAvatar(File(pickedFile.path));

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Фото профиля успешно обновлено!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  void _showImageSourceSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) {
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(
                  LucideIcons.camera,
                  color: Color(0xFF0F172A),
                ),
                title: const Text('Сделать фото'),
                onTap: () {
                  Navigator.pop(context);
                  _handleImageSelection(ImageSource.camera);
                },
              ),
              ListTile(
                leading: const Icon(
                  LucideIcons.image,
                  color: Color(0xFF0F172A),
                ),
                title: const Text('Выбрать из галереи'),
                onTap: () {
                  Navigator.pop(context);
                  _handleImageSelection(ImageSource.gallery);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _submitForm(ProfileModel profile) async {
    if (!_formKey.currentState!.validate()) return;

    final data = <String, dynamic>{
      if (_firstNameCtrl.text.isNotEmpty)
        'firstName': _firstNameCtrl.text.trim(),
      if (_lastNameCtrl.text.isNotEmpty) 'lastName': _lastNameCtrl.text.trim(),
      if (_middleNameCtrl.text.isNotEmpty)
        'middleName': _middleNameCtrl.text.trim(),
    };

    // Only send email/mobile if they are NOT verified AND they have changed
    if (profile.emailVerified == null && _emailCtrl.text != profile.email) {
      data['email'] = _emailCtrl.text.trim();
    }
    if (profile.mobileVerified == null && _mobileCtrl.text != profile.mobile) {
      data['mobile'] = _mobileCtrl.text.trim();
    }

    try {
      await ref.read(profileMutationProvider.notifier).updateProfile(data);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Профиль успешно сохранен'),
            backgroundColor: Colors.green,
          ),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(customerProfileProvider);
    final isMutating = ref.watch(profileMutationProvider);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(LucideIcons.arrow_left, color: Colors.black),
          onPressed: () => context.pop(),
        ),
        title: const Text(
          'Редактировать профиль',
          style: TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
      ),
      body: profileAsync.when(
        data: (profile) {
          _populateForm(profile);

          final bool isEmailVerified = profile.emailVerified != null;
          final bool isMobileVerified = profile.mobileVerified != null;

          return Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                // AVATAR SECTION
                Center(
                  child: GestureDetector(
                    onTap: isMutating ? null : _showImageSourceSheet,
                    child: Stack(
                      children: [
                        Container(
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.grey.shade300,
                              width: 2,
                            ),
                          ),
                          child: ClipOval(
                            child:
                                profile.image != null &&
                                    profile.image!.isNotEmpty
                                ? CachedNetworkImage(
                                    imageUrl: profile.image!,
                                    fit: BoxFit.cover,
                                    placeholder: (context, url) => const Center(
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                                    errorWidget: (context, url, error) =>
                                        const Icon(
                                          LucideIcons.user,
                                          size: 40,
                                          color: Colors.grey,
                                        ),
                                  )
                                : const Icon(
                                    LucideIcons.user,
                                    size: 40,
                                    color: Colors.grey,
                                  ),
                          ),
                        ),
                        if (isMutating)
                          Container(
                            width: 100,
                            height: 100,
                            decoration: const BoxDecoration(
                              color: Colors.black45,
                              shape: BoxShape.circle,
                            ),
                            child: const Center(
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            ),
                          ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: const BoxDecoration(
                              color: Color(0xFF0F172A),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              LucideIcons.camera,
                              color: Colors.white,
                              size: 16,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 32),

                // NAME FIELDS
                _buildTextField(
                  'Имя',
                  _firstNameCtrl,
                  validator: (v) => v!.isEmpty ? 'Обязательное поле' : null,
                ),
                const SizedBox(height: 16),
                _buildTextField(
                  'Фамилия',
                  _lastNameCtrl,
                  validator: (v) => v!.isEmpty ? 'Обязательное поле' : null,
                ),
                const SizedBox(height: 16),
                _buildTextField('Отчество (если есть)', _middleNameCtrl),

                const SizedBox(height: 32),
                const Text(
                  'Контактные данные',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 16),

                // CONTACT FIELDS (Disabled if verified)
                _buildTextField(
                  'Телефон',
                  _mobileCtrl,
                  readOnly: isMobileVerified,
                  suffix: isMobileVerified
                      ? const Icon(
                          LucideIcons.shield_check,
                          color: Colors.green,
                        )
                      : null,
                ),
                const SizedBox(height: 16),
                _buildTextField(
                  'Email',
                  _emailCtrl,
                  readOnly: isEmailVerified,
                  suffix: isEmailVerified
                      ? const Icon(
                          LucideIcons.shield_check,
                          color: Colors.green,
                        )
                      : null,
                ),
                if (isMobileVerified || isEmailVerified)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Подтвержденные контакты нельзя изменить. Обратитесь в поддержку.',
                      style: TextStyle(
                        color: Colors.grey.shade500,
                        fontSize: 12,
                      ),
                    ),
                  ),

                const SizedBox(height: 32),
                const Text(
                  'Местоположение',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 16),

                const SizedBox(height: 48),

                // SAVE BUTTON
                ElevatedButton(
                  onPressed: isMutating ? null : () => _submitForm(profile),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0F172A),
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 56),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: isMutating
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text(
                          'Сохранить изменения',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
                const SizedBox(height: 32),
              ],
            ),
          );
        },
        loading: () => const Center(
          child: CircularProgressIndicator(color: Color(0xFF0F172A)),
        ),
        error: (error, _) {
          final apiError = ApiException.fromDioException(error);
          return GlobalErrorWidget(
            message: apiError.message,
            onRetry: () => ref.refresh(customerProfileProvider.future),
          );
        },
      ),
    );
  }

  Widget _buildTextField(
    String label,
    TextEditingController controller, {
    String? Function(String?)? validator,
    bool readOnly = false,
    Widget? suffix,
  }) {
    return TextFormField(
      controller: controller,
      readOnly: readOnly,
      validator: validator,
      style: TextStyle(color: readOnly ? Colors.grey.shade600 : Colors.black),
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: readOnly ? Colors.grey.shade200 : Colors.grey.shade50,
        suffixIcon: suffix,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}
