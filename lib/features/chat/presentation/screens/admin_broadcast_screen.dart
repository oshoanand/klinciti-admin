import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_exceptions.dart';

class AdminBroadcastScreen extends ConsumerStatefulWidget {
  const AdminBroadcastScreen({super.key});

  @override
  ConsumerState<AdminBroadcastScreen> createState() =>
      _AdminBroadcastScreenState();
}

class _AdminBroadcastScreenState extends ConsumerState<AdminBroadcastScreen> {
  final _titleCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();
  final _imageUrlCtrl = TextEditingController();
  final _deepLinkCtrl = TextEditingController(text: '/');

  String _audience = 'ALL';
  String _category = 'PROMO';
  bool _saveToInApp = true;
  bool _useTopic = true;
  bool _sending = false;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    _imageUrlCtrl.dispose();
    _deepLinkCtrl.dispose();
    super.dispose();
  }

  void _applyTemplate({
    required String category,
    required String title,
    required String body,
  }) {
    setState(() {
      _category = category;
      _titleCtrl.text = title;
      _bodyCtrl.text = body;
    });
  }

  Future<void> _sendBroadcast() async {
    final title = _titleCtrl.text.trim();
    final body = _bodyCtrl.text.trim();
    if (title.length < 2 || body.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Заполните заголовок и текст сообщения')),
      );
      return;
    }

    final audienceLabel = switch (_audience) {
      'CUSTOMER' => 'всем КЛИЕНТАМ (klinciti_customers_topic)',
      'WORKER' => 'всем ИСПОЛНИТЕЛЯМ (klinciti_workers_topic)',
      'ADMIN' => 'всем АДМИНАМ (admin_alerts)',
      _ => 'ВСЕМ клиентам и исполнителям',
    };

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Подтвердить массовую рассылку?'),
        content: Text(
          'Push-уведомление «$title» будет отправлено $audienceLabel.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFE0780F),
            ),
            child: const Text('Отправить'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _sending = true);
    try {
      final api = ref.read(apiClientProvider);
      final res = await api.dio.post(
        '/admin/notifications/broadcast',
        data: {
          'title': title,
          'body': body,
          'audience': _audience,
          'category': _category,
          if (_imageUrlCtrl.text.trim().isNotEmpty)
            'imageUrl': _imageUrlCtrl.text.trim(),
          'deepLink': _deepLinkCtrl.text.trim().isEmpty
              ? '/'
              : _deepLinkCtrl.text.trim(),
          'saveToInApp': _saveToInApp,
          'useTopic': _useTopic,
          'idempotencyKey': 'bc_${DateTime.now().millisecondsSinceEpoch}',
        },
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            (res.data['message'] ?? 'Рассылка отправлена').toString(),
          ),
        ),
      );
      _titleCtrl.clear();
      _bodyCtrl.clear();
      _imageUrlCtrl.clear();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(ApiException.fromDioException(e).message),
            backgroundColor: const Color(0xFFDC2626),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        title: const Text(
          'Публичная FCM-рассылка',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Быстрые шаблоны',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ActionChip(
                avatar: const Icon(LucideIcons.sparkles, size: 16),
                label: const Text('С Новым годом!'),
                onPressed: () => _applyTemplate(
                  category: 'GREETING',
                  title: 'С Новым годом от Klinciti! 🎄',
                  body: 'Поздравляем с праздником! Желаем уюта, чистоты и отличного настроения в новом году.',
                ),
              ),
              ActionChip(
                avatar: const Icon(LucideIcons.percent, size: 16),
                label: const Text('Скидка 15%'),
                onPressed: () => _applyTemplate(
                  category: 'PROMO',
                  title: 'Скидка 15% на уборку 🎉',
                  body: 'Только на этих выходных закажите генеральную уборку со скидкой 15%. Успейте забронировать!',
                ),
              ),
              ActionChip(
                avatar: const Icon(LucideIcons.megaphone, size: 16),
                label: const Text('Объявление'),
                onPressed: () => _applyTemplate(
                  category: 'ANNOUNCEMENT',
                  title: 'Важное обновление сервиса',
                  body: 'Мы улучшили работу приложения и добавили новые удобные функции.',
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'Получатели',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'ALL', label: Text('Все')),
              ButtonSegment(value: 'CUSTOMER', label: Text('Клиенты')),
              ButtonSegment(value: 'WORKER', label: Text('Мастера')),
              ButtonSegment(value: 'ADMIN', label: Text('Админы')),
            ],
            selected: {_audience},
            onSelectionChanged: (s) => setState(() => _audience = s.first),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _titleCtrl,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Заголовок уведомления',
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _bodyCtrl,
            maxLines: 4,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Текст сообщения',
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _imageUrlCtrl,
            decoration: const InputDecoration(
              labelText: 'URL баннера / картинки (опционально)',
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _deepLinkCtrl,
            decoration: const InputDecoration(
              labelText: 'Экран при нажатии (например / или /jobs/create)',
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Сохранить в колокольчике приложения'),
            value: _saveToInApp,
            onChanged: (v) => setState(() => _saveToInApp = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Отправить через FCM Topic'),
            subtitle: const Text(
              'Вкл = топики fcm-stream-consumer; Выкл = прямая multicast-доставка по токенам',
            ),
            value: _useTopic,
            onChanged: (v) => setState(() => _useTopic = v),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 50,
            child: FilledButton.icon(
              onPressed: _sending ? null : _sendBroadcast,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF0F172A),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: _sending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(LucideIcons.send, size: 18),
              label: const Text(
                'Отправить рассылку',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
