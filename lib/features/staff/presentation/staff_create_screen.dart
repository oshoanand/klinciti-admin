import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exceptions.dart';
import '../providers/staff_list_provider.dart';

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
  String _role = 'SUPPORT';
  final String _accessLevel = 'BASIC'; // Adjust based on your DB defaults

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();

    setState(() => _isLoading = true);

    try {
      final api = ref.read(apiClientProvider);

      final payload = {
        'firstName': _firstName,
        'lastName': _lastName,
        'middleName': _middleName,
        'email': _email,
        'mobile': _mobile,
        'password': _password,
        'role': _role,
        'accessLevel': _accessLevel,
      };

      await api.dio.post('/users/staff', data: payload);

      // Refresh list to show new staff
      ref.invalidate(staffListProvider('ALL'));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Сотрудник успешно создан'),
            backgroundColor: Colors.green,
          ),
        );
        context.pop(); // Go back to list
      }
    } catch (e) {
      if (mounted) {
        final message = e is ApiException
            ? e.message
            : 'Ошибка при создании сотрудника';
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
                labelText: 'Фамилия',
                border: OutlineInputBorder(),
              ),
              validator: (val) =>
                  val == null || val.isEmpty ? 'Обязательное поле' : null,
              onSaved: (val) => _lastName = val!.trim(),
            ),
            const SizedBox(height: 16),
            TextFormField(
              decoration: const InputDecoration(
                labelText: 'Имя',
                border: OutlineInputBorder(),
              ),
              validator: (val) =>
                  val == null || val.isEmpty ? 'Обязательное поле' : null,
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
              'Контакты и доступ',
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            TextFormField(
              decoration: const InputDecoration(
                labelText: 'Email',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.emailAddress,
              validator: (val) => val == null || !val.contains('@')
                  ? 'Введите корректный email'
                  : null,
              onSaved: (val) => _email = val!.trim(),
            ),
            const SizedBox(height: 16),
            TextFormField(
              decoration: const InputDecoration(
                labelText: 'Телефон',
                border: OutlineInputBorder(),
                prefixText: '+7 ',
              ),
              keyboardType: TextInputType.phone,
              onSaved: (val) => _mobile =
                  '+7${val!.trim()}', // Format to match your DB expectations
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _role,
              decoration: const InputDecoration(
                labelText: 'Роль',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'SUPPORT', child: Text('Поддержка')),
                DropdownMenuItem(
                  value: 'ADMINISTRATOR',
                  child: Text('Администратор'),
                ),
                DropdownMenuItem(value: 'WORKER', child: Text('Исполнитель')),
              ],
              onChanged: (val) => setState(() => _role = val!),
            ),
            const SizedBox(height: 16),
            TextFormField(
              decoration: InputDecoration(
                labelText: 'Пароль для входа',
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
