import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:go_router/go_router.dart';

import '../providers/category_provider.dart';
import '../data/category_model.dart';
import '../../../shared/widgets/global_error_widget.dart';
import '../../../core/network/api_exceptions.dart';

class CategoriesView extends ConsumerWidget {
  const CategoriesView({super.key});

  void _showCategoryDialog(
    BuildContext context,
    WidgetRef ref, {
    CategoryModel? category,
    String? parentId,
  }) {
    showDialog(
      context: context,
      builder: (context) =>
          _CategoryDialog(category: category, parentId: parentId),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    CategoryModel category,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить категорию?'),
        content: Text('Вы уверены, что хотите удалить "${category.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );

    if (confirm == true && context.mounted) {
      try {
        await ref.read(categoryProvider.notifier).deleteCategory(category.id);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Категория удалена'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          final message = e is ApiException ? e.message : 'Ошибка при удалении';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(message),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 4),
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoriesAsync = ref.watch(categoryProvider);

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
          'Категории',
          style: TextStyle(
            color: Color(0xFF0F172A),
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: categoriesAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: Color(0xFF0F172A)),
        ),
        error: (err, _) => GlobalErrorWidget(
          message: 'Ошибка загрузки категорий',
          onRetry: () => ref.invalidate(categoryProvider),
        ),
        data: (categories) {
          if (categories.isEmpty) {
            return const Center(
              child: Text(
                'Нет категорий',
                style: TextStyle(color: Colors.grey),
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(categoryProvider),
            color: const Color(0xFF0F172A),
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: categories.length,
              itemBuilder: (context, index) {
                final parent = categories[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ExpansionTile(
                    title: Row(
                      children: [
                        Expanded(
                          child: Text(
                            parent.name,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: parent.isActive
                                  ? Colors.black
                                  : Colors.grey,
                            ),
                          ),
                        ),
                        if (!parent.isActive)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.red.shade50,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'Скрыта',
                              style: TextStyle(color: Colors.red, fontSize: 10),
                            ),
                          ),
                      ],
                    ),
                    subtitle: Text(
                      '${parent.subcategories.length} подкатегорий',
                      style: const TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                    leading: const CircleAvatar(
                      backgroundColor: Color(0xFFF1F5F9),
                      child: Icon(
                        LucideIcons.folder,
                        color: Color(0xFF0F172A),
                        size: 20,
                      ),
                    ),
                    children: [
                      ...parent.subcategories.map(
                        (sub) => ListTile(
                          contentPadding: const EdgeInsets.only(
                            left: 72,
                            right: 8,
                          ),
                          title: Text(
                            sub.name,
                            style: TextStyle(
                              color: sub.isActive
                                  ? Colors.black87
                                  : Colors.grey,
                            ),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(
                                  LucideIcons.pencil,
                                  size: 18,
                                  color: Colors.blue,
                                ),
                                onPressed: () => _showCategoryDialog(
                                  context,
                                  ref,
                                  category: sub,
                                  parentId: parent.id,
                                ),
                              ),
                              IconButton(
                                icon: const Icon(
                                  LucideIcons.trash,
                                  size: 18,
                                  color: Colors.red,
                                ),
                                onPressed: () =>
                                    _confirmDelete(context, ref, sub),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: const BorderRadius.vertical(
                            bottom: Radius.circular(12),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            IconButton(
                              onPressed: () =>
                                  _confirmDelete(context, ref, parent),
                              icon: const Icon(
                                LucideIcons.trash,
                                size: 18,
                                color: Colors.red,
                              ),
                              tooltip: 'Удалить категорию',
                            ),
                            TextButton.icon(
                              onPressed: () => _showCategoryDialog(
                                context,
                                ref,
                                category: parent,
                              ),
                              icon: const Icon(LucideIcons.pencil, size: 16),
                              label: const Text('Изменить'),
                            ),
                            TextButton.icon(
                              onPressed: () => _showCategoryDialog(
                                context,
                                ref,
                                parentId: parent.id,
                              ),
                              icon: const Icon(LucideIcons.plus, size: 16),
                              label: const Text('Подкатегория'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF0F172A),
        onPressed: () => _showCategoryDialog(context, ref),
        icon: const Icon(LucideIcons.plus, color: Colors.white),
        label: const Text('Категория', style: TextStyle(color: Colors.white)),
      ),
    );
  }
}

class _CategoryDialog extends ConsumerStatefulWidget {
  final CategoryModel? category;
  final String? parentId;
  const _CategoryDialog({this.category, this.parentId});

  @override
  ConsumerState<_CategoryDialog> createState() => _CategoryDialogState();
}

class _CategoryDialogState extends ConsumerState<_CategoryDialog> {
  final _formKey = GlobalKey<FormState>();
  late String _name;
  late String _slug;
  late bool _isActive;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _name = widget.category?.name ?? '';
    _slug = widget.category?.slug ?? '';
    _isActive = widget.category?.isActive ?? true;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();
    setState(() => _isLoading = true);

    try {
      if (widget.category == null) {
        await ref
            .read(categoryProvider.notifier)
            .createCategory(
              name: _name,
              slug: _slug,
              parentId: widget.parentId,
              isActive: _isActive,
            );
      } else {
        await ref
            .read(categoryProvider.notifier)
            .updateCategory(
              widget.category!.id,
              name: _name,
              slug: _slug,
              parentId: widget.category!.parentId,
              isActive: _isActive,
            );
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ошибка сохранения'),
            backgroundColor: Colors.red,
          ),
        );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.category != null;
    final isSubcategory =
        widget.parentId != null || widget.category?.parentId != null;

    return AlertDialog(
      title: Text(
        isEditing
            ? 'Редактировать'
            : (isSubcategory ? 'Новая подкатегория' : 'Новая категория'),
      ),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              initialValue: _name,
              decoration: const InputDecoration(
                labelText: 'Название',
                border: OutlineInputBorder(),
              ),
              validator: (val) =>
                  val == null || val.isEmpty ? 'Обязательное поле' : null,
              onSaved: (val) => _name = val!.trim(),
            ),
            const SizedBox(height: 16),
            TextFormField(
              initialValue: _slug,
              decoration: const InputDecoration(
                labelText: 'Slug (url-имя)',
                border: OutlineInputBorder(),
              ),
              validator: (val) =>
                  val == null || val.isEmpty ? 'Обязательное поле' : null,
              onSaved: (val) => _slug = val!.trim(),
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              title: const Text('Активна'),
              value: _isActive,
              onChanged: (val) => setState(() => _isActive = val),
              contentPadding: EdgeInsets.zero,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF0F172A),
            foregroundColor: Colors.white,
          ),
          child: _isLoading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
              : const Text('Сохранить'),
        ),
      ],
    );
  }
}
