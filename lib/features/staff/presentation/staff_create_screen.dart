import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exceptions.dart';
import '../providers/staff_provider.dart';

class StaffCreateScreen extends ConsumerStatefulWidget {
  const StaffCreateScreen({super.key});

  @override
  ConsumerState<StaffCreateScreen> createState() => _StaffCreateScreenState();
}

class _StaffCreateScreenState extends ConsumerState<StaffCreateScreen> {
  final _formKey = GlobalKey<FormState>();

  bool _isLoading = false;
  bool _obscurePassword = true;

  String _firstName = '';
  String _lastName = '';
  String _middleName = '';
  String _email = '';
  String _mobile = '';
  String _password = '';
  String _role = 'ADMINISTRATOR';
  String _accessLevel = 'BASIC';

  String _normalizePhone(String rawInput) {
    final digits = rawInput.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return '';
    if (digits.startsWith('7') && digits.length == 11) {
      return '+$digits';
    }
    if (digits.startsWith('8') && digits.length == 11) {
      return '+7${digits.substring(1)}';
    }
    if (digits.length == 10) {
      return '+7$digits';
    }
    return '+7$digits';
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();

    setState(() => _isLoading = true);

    try {
      final api = ref.read(apiClientProvider);

      final payload = <String, dynamic>{
        'firstName': _firstName,
        'lastName': _lastName,
        if (_middleName.isNotEmpty) 'middleName': _middleName,
        'email': _email,
        if (_mobile.isNotEmpty) 'mobile': _mobile,
        'password': _password,
        'role': _role,
        'accessLevel': _accessLevel,
      };

      await api.dio.post('/users/staff', data: payload);

      // Invalidate all role filters ('ALL', 'ADMINISTRATOR', 'SUPPORT')
      ref.invalidate(staffListProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Сотрудник успешно создан'),
            backgroundColor: Colors.green,
          ),
        );
        context.pop();
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
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(LucideIcons.arrow_left, color: Color(0xFF0F172A)),
          onPressed: () => context.pop(),
        ),
        title: const Text(
          'Новый сотрудник',
          style: TextStyle(
            color: Color(0xFF0F172A),
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Text(
              'Личные данные',
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            TextFormField(
              decoration: const InputDecoration(
                labelText: 'Фамилия *',
                border: OutlineInputBorder(),
              ),
              validator: (val) => val == null || val.trim().isEmpty
                  ? 'Обязательное поле'
                  : null,
              onSaved: (val) => _lastName = val!.trim(),
            ),
            const SizedBox(height: 16),
            TextFormField(
              decoration: const InputDecoration(
                labelText: 'Имя *',
                border: OutlineInputBorder(),
              ),
              validator: (val) => val == null || val.trim().isEmpty
                  ? 'Обязательное поле'
                  : null,
              onSaved: (val) => _firstName = val!.trim(),
            ),
            const SizedBox(height: 16),
            TextFormField(
              decoration: const InputDecoration(
                labelText: 'Отчество (необязательно)',
                border: OutlineInputBorder(),
              ),
              onSaved: (val) => _middleName = val?.trim() ?? '',
            ),
            const SizedBox(height: 24),

            const Text(
              'Контакты и права доступа',
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            TextFormField(
              decoration: const InputDecoration(
                labelText: 'Email *',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.emailAddress,
              validator: (val) =>
                  val == null || !val.contains('@') || !val.contains('.')
                  ? 'Введите корректный email'
                  : null,
              onSaved: (val) => _email = val!.trim().toLowerCase(),
            ),
            const SizedBox(height: 16),
            TextFormField(
              decoration: const InputDecoration(
                labelText: 'Телефон',
                hintText: '999 123-45-67',
                border: OutlineInputBorder(),
                prefixText: '+7 ',
              ),
              keyboardType: TextInputType.phone,
              validator: (val) {
                if (val == null || val.trim().isEmpty) return null;
                final digits = val.replaceAll(RegExp(r'\D'), '');
                if (digits.length < 10) {
                  return 'Введите корректный номер телефона';
                }
                return null;
              },
              onSaved: (val) => _mobile = _normalizePhone(val ?? ''),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _role,
              decoration: const InputDecoration(
                labelText: 'Роль сотрудника',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(
                  value: 'SUPPORT',
                  child: Text('Поддержка (SUPPORT)'),
                ),
                DropdownMenuItem(
                  value: 'ADMINISTRATOR',
                  child: Text('Администратор (ADMINISTRATOR)'),
                ),
              ],
              onChanged: (val) {
                if (val != null) {
                  setState(() {
                    _role = val;
                    if (_role == 'ADMINISTRATOR') {
                      _accessLevel = 'FULL';
                    }
                  });
                }
              },
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _accessLevel,
              decoration: const InputDecoration(
                labelText: 'Уровень доступа',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(
                  value: 'BASIC',
                  child: Text('Базовый (BASIC)'),
                ),
                DropdownMenuItem(value: 'FULL', child: Text('Полный (FULL)')),
              ],
              onChanged: (val) {
                if (val != null) setState(() => _accessLevel = val);
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              decoration: InputDecoration(
                labelText: 'Пароль для входа *',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword ? LucideIcons.eye : LucideIcons.eye_off,
                  ),
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
              obscureText: _obscurePassword,
              validator: (val) =>
                  val == null || val.length < 6 ? 'Минимум 6 символов' : null,
              onSaved: (val) => _password = val!,
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: _isLoading ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0F172A),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Text(
                      'Создать сотрудника',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}
