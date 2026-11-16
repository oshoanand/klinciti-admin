import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exceptions.dart';
import '../../../shared/widgets/global_error_widget.dart';
import '../data/category_model.dart';
import '../providers/category_provider.dart';

class CategoriesView extends ConsumerStatefulWidget {
  const CategoriesView({super.key});

  @override
  ConsumerState<CategoriesView> createState() => _CategoriesViewState();
}

class _CategoriesViewState extends ConsumerState<CategoriesView> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _showHiddenOnly = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _showCategoryDialog(
    BuildContext context, {
    CategoryModel? category,
    String? parentId,
    String? parentName,
  }) {
    showDialog(
      context: context,
      builder: (_) => _CategoryDialog(
        category: category,
        parentId: parentId,
        parentName: parentName,
      ),
    );
  }

  Future<void> _quickToggleVisibility(CategoryModel category) async {
    final newStatus = !category.isActive;
    try {
      await ref
          .read(categoryProvider.notifier)
          .toggleCategoryActive(category.id, newStatus);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              newStatus
                  ? 'Категория «${category.name}» активирована'
                  : 'Категория «${category.name}» скрыта',
            ),
            backgroundColor: newStatus ? Colors.green : Colors.orange,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        final msg = e is ApiException ? e.message : 'Ошибка изменения статуса';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _confirmDelete(
    BuildContext context,
    CategoryModel category,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Удалить категорию?'),
        content: Text(
          'Вы уверены, что хотите удалить «${category.name}»?\n\nЕсли к категории уже привязаны мастера или заказы, рекомендуется скрыть её вместо удаления.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
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
              content: Text('Категория успешно удалена'),
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

  List<CategoryModel> _filterCategories(List<CategoryModel> categories) {
    final q = _searchQuery.trim().toLowerCase();

    return categories
        .map((parent) {
          final matchingSubs = parent.subcategories.where((sub) {
            if (_showHiddenOnly && sub.isActive) return false;
            if (q.isEmpty) return true;
            return sub.name.toLowerCase().contains(q) ||
                sub.slug.toLowerCase().contains(q);
          }).toList();

          final parentMatchesQuery =
              q.isEmpty ||
              parent.name.toLowerCase().contains(q) ||
              parent.slug.toLowerCase().contains(q);

          final parentMatchesHidden =
              !_showHiddenOnly || !parent.isActive || matchingSubs.isNotEmpty;

          if (!parentMatchesHidden) return null;
          if (!parentMatchesQuery && matchingSubs.isEmpty) return null;

          return CategoryModel(
            id: parent.id,
            name: parent.name,
            slug: parent.slug,
            icon: parent.icon,
            image: parent.image,
            parentId: parent.parentId,
            isActive: parent.isActive,
            workersCount: parent.workersCount,
            jobsCount: parent.jobsCount,
            subcategories: (q.isNotEmpty || _showHiddenOnly)
                ? matchingSubs
                : parent.subcategories,
          );
        })
        .whereType<CategoryModel>()
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(categoryProvider);

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
          'Управление категориями',
          style: TextStyle(
            color: Color(0xFF0F172A),
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(
              _showHiddenOnly ? LucideIcons.eye_off : LucideIcons.eye,
              size: 19,
              color: _showHiddenOnly ? Colors.red : const Color(0xFF0F172A),
            ),
            tooltip: _showHiddenOnly
                ? 'Показать все категории'
                : 'Показать только скрытые',
            onPressed: () => setState(() => _showHiddenOnly = !_showHiddenOnly),
          ),
          IconButton(
            icon: const Icon(
              LucideIcons.refresh_cw,
              size: 18,
              color: Color(0xFF0F172A),
            ),
            tooltip: 'Обновить',
            onPressed: () => ref.invalidate(categoryProvider),
          ),
        ],
      ),
      body: Column(
        children: [
          // Search Bar
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: TextField(
              controller: _searchController,
              onChanged: (val) => setState(() => _searchQuery = val),
              decoration: InputDecoration(
                hintText: 'Поиск категории или подкатегории...',
                prefixIcon: const Icon(LucideIcons.search, size: 18),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(LucideIcons.x, size: 16),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                isDense: true,
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade200),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade200),
                ),
              ),
            ),
          ),
          const Divider(height: 1),

          Expanded(
            child: categoriesAsync.when(
              loading: () => const Center(
                child: CircularProgressIndicator(color: Color(0xFF0F172A)),
              ),
              error: (err, _) => GlobalErrorWidget(
                message: err is ApiException
                    ? err.message
                    : 'Ошибка загрузки категорий',
                onRetry: () => ref.invalidate(categoryProvider),
              ),
              data: (categories) {
                final filtered = _filterCategories(categories);

                if (filtered.isEmpty) {
                  return RefreshIndicator(
                    onRefresh: () async => ref.invalidate(categoryProvider),
                    color: const Color(0xFF0F172A),
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        SizedBox(
                          height: MediaQuery.sizeOf(context).height * 0.6,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                LucideIcons.folder_open,
                                size: 60,
                                color: Colors.grey.shade300,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                categories.isEmpty
                                    ? 'Нет созданных категорий'
                                    : 'По вашему запросу ничего не найдено',
                                style: const TextStyle(
                                  color: Colors.grey,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return RefreshIndicator(
                  onRefresh: () async => ref.invalidate(categoryProvider),
                  color: const Color(0xFF0F172A),
                  child: ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final parent = filtered[index];
                      return _buildParentCategoryCard(context, parent);
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF0F172A),
        onPressed: () => _showCategoryDialog(context),
        icon: const Icon(LucideIcons.plus, color: Colors.white),
        label: const Text(
          'Новая категория',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _buildParentCategoryCard(BuildContext context, CategoryModel parent) {
    final hasImage = parent.image != null && parent.image!.trim().isNotEmpty;

    return Card(
      elevation: 0,
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: parent.isActive ? Colors.grey.shade200 : Colors.red.shade200,
        ),
      ),
      child: ExpansionTile(
        initiallyExpanded: _searchQuery.isNotEmpty,
        shape: const Border(),
        collapsedShape: const Border(),
        leading: CircleAvatar(
          backgroundColor: const Color(0xFFF1F5F9),
          backgroundImage: hasImage ? NetworkImage(parent.image!) : null,
          child: !hasImage
              ? Icon(
                  LucideIcons.folder,
                  color: parent.isActive
                      ? const Color(0xFF0F172A)
                      : Colors.grey,
                  size: 20,
                )
              : null,
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                parent.name,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15.5,
                  color: parent.isActive
                      ? const Color(0xFF0F172A)
                      : Colors.grey,
                ),
              ),
            ),
            if (!parent.isActive)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'Скрыта',
                  style: TextStyle(
                    color: Colors.red,
                    fontSize: 10.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'Подкатегорий: ${parent.subcategories.length}',
                style: const TextStyle(color: Colors.grey, fontSize: 12.5),
              ),
              Text(
                '• Мастеров: ${parent.workersCount}',
                style: TextStyle(color: Colors.blue.shade700, fontSize: 12),
              ),
              Text(
                '• Заказов: ${parent.jobsCount}',
                style: TextStyle(color: Colors.green.shade700, fontSize: 12),
              ),
            ],
          ),
        ),
        children: [
          const Divider(height: 1),
          ...parent.subcategories.map(
            (sub) => ListTile(
              contentPadding: const EdgeInsets.only(left: 20, right: 8),
              leading: Icon(
                LucideIcons.corner_down_right,
                size: 16,
                color: sub.isActive ? Colors.blueGrey : Colors.grey.shade400,
              ),
              title: Row(
                children: [
                  Expanded(
                    child: Text(
                      sub.name,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: sub.isActive
                            ? const Color(0xFF0F172A)
                            : Colors.grey,
                      ),
                    ),
                  ),
                  if (!sub.isActive)
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
                'slug: ${sub.slug} • Мастеров: ${sub.workersCount} • Заказов: ${sub.jobsCount}',
                style: const TextStyle(fontSize: 11.5, color: Colors.grey),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: Icon(
                      sub.isActive ? LucideIcons.eye : LucideIcons.eye_off,
                      size: 17,
                      color: sub.isActive ? Colors.green : Colors.grey,
                    ),
                    tooltip: sub.isActive ? 'Скрыть' : 'Активировать',
                    onPressed: () => _quickToggleVisibility(sub),
                  ),
                  IconButton(
                    icon: const Icon(
                      LucideIcons.pencil,
                      size: 17,
                      color: Colors.blue,
                    ),
                    tooltip: 'Редактировать',
                    onPressed: () => _showCategoryDialog(
                      context,
                      category: sub,
                      parentId: parent.id,
                      parentName: parent.name,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(
                      LucideIcons.trash,
                      size: 17,
                      color: Colors.red,
                    ),
                    tooltip: 'Удалить',
                    onPressed: () => _confirmDelete(context, sub),
                  ),
                ],
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(14),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  onPressed: () => _quickToggleVisibility(parent),
                  icon: Icon(
                    parent.isActive ? LucideIcons.eye : LucideIcons.eye_off,
                    size: 18,
                    color: parent.isActive ? Colors.green : Colors.grey,
                  ),
                  tooltip: parent.isActive
                      ? 'Скрыть категорию'
                      : 'Активировать категорию',
                ),
                IconButton(
                  onPressed: () => _confirmDelete(context, parent),
                  icon: const Icon(
                    LucideIcons.trash,
                    size: 18,
                    color: Colors.red,
                  ),
                  tooltip: 'Удалить категорию',
                ),
                TextButton.icon(
                  onPressed: () =>
                      _showCategoryDialog(context, category: parent),
                  icon: const Icon(LucideIcons.pencil, size: 15),
                  label: const Text('Изменить'),
                ),
                TextButton.icon(
                  onPressed: () => _showCategoryDialog(
                    context,
                    parentId: parent.id,
                    parentName: parent.name,
                  ),
                  icon: const Icon(LucideIcons.plus, size: 15),
                  label: const Text('Подкатегория'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ==========================================
// CREATE / EDIT CATEGORY DIALOG (With Auto-Slug)
// ==========================================
class _CategoryDialog extends ConsumerStatefulWidget {
  final CategoryModel? category;
  final String? parentId;
  final String? parentName;

  const _CategoryDialog({this.category, this.parentId, this.parentName});

  @override
  ConsumerState<_CategoryDialog> createState() => _CategoryDialogState();
}

class _CategoryDialogState extends ConsumerState<_CategoryDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _slugController;
  late final TextEditingController _imageController;
  late bool _isActive;
  bool _isLoading = false;
  bool _slugManuallyEdited = false;

  static const Map<String, String> _cyrillicToLatin = {
    'а': 'a',
    'б': 'b',
    'в': 'v',
    'г': 'g',
    'д': 'd',
    'е': 'e',
    'ё': 'yo',
    'ж': 'zh',
    'з': 'z',
    'и': 'i',
    'й': 'y',
    'к': 'k',
    'л': 'l',
    'м': 'm',
    'н': 'n',
    'о': 'o',
    'п': 'p',
    'р': 'r',
    'с': 's',
    'т': 't',
    'у': 'u',
    'ф': 'f',
    'х': 'kh',
    'ц': 'ts',
    'ч': 'ch',
    'ш': 'sh',
    'щ': 'shch',
    'ъ': '',
    'ы': 'y',
    'ь': '',
    'э': 'e',
    'ю': 'yu',
    'я': 'ya',
  };

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.category?.name ?? '');
    _slugController = TextEditingController(text: widget.category?.slug ?? '');
    _imageController = TextEditingController(
      text: widget.category?.image ?? '',
    );
    _isActive = widget.category?.isActive ?? true;
    _slugManuallyEdited = widget.category != null;

    _nameController.addListener(_onNameChanged);
  }

  void _onNameChanged() {
    if (_slugManuallyEdited) return;
    _slugController.text = _generateSlug(_nameController.text);
  }

  String _generateSlug(String input) {
    final lower = input.trim().toLowerCase();
    final buffer = StringBuffer();
    for (int i = 0; i < lower.length; i++) {
      final char = lower[i];
      if (_cyrillicToLatin.containsKey(char)) {
        buffer.write(_cyrillicToLatin[char]);
      } else if (RegExp(r'[a-z0-9]').hasMatch(char)) {
        buffer.write(char);
      } else if (char == ' ' || char == '-' || char == '_') {
        buffer.write('-');
      }
    }
    return buffer
        .toString()
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
  }

  @override
  void dispose() {
    _nameController.removeListener(_onNameChanged);
    _nameController.dispose();
    _slugController.dispose();
    _imageController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    final name = _nameController.text.trim();
    final slug = _slugController.text.trim().toLowerCase();
    final image = _imageController.text.trim();

    try {
      if (widget.category == null) {
        await ref
            .read(categoryProvider.notifier)
            .createCategory(
              name: name,
              slug: slug,
              parentId: widget.parentId,
              image: image.isNotEmpty ? image : null,
              isActive: _isActive,
            );
      } else {
        await ref
            .read(categoryProvider.notifier)
            .updateCategory(
              widget.category!.id,
              name: name,
              slug: slug,
              parentId: widget.category!.parentId ?? widget.parentId,
              image: image.isNotEmpty ? image : null,
              isActive: _isActive,
            );
      }
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.category == null
                  ? 'Категория «$name» создана'
                  : 'Изменения сохранены',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        final msg = e is ApiException ? e.message : 'Ошибка сохранения';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: Colors.red),
        );
      }
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
            ? (isSubcategory
                  ? 'Редактировать подкатегорию'
                  : 'Редактировать категорию')
            : (isSubcategory ? 'Новая подкатегория' : 'Новая категория'),
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      ),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.parentName != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Родительская категория: ${widget.parentName}',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: Colors.blue.shade900,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
              ],
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Название *',
                  hintText: 'Например: Уборка квартир',
                  border: OutlineInputBorder(),
                ),
                validator: (val) => val == null || val.trim().length < 2
                    ? 'Минимум 2 символа'
                    : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _slugController,
                onChanged: (_) => _slugManuallyEdited = true,
                decoration: const InputDecoration(
                  labelText: 'Slug (URL-имя) *',
                  hintText: 'uborka-kvartir',
                  border: OutlineInputBorder(),
                ),
                validator: (val) {
                  if (val == null || val.trim().length < 2) {
                    return 'Обязательное поле';
                  }
                  if (!RegExp(r'^[a-zA-Z0-9-_]+$').hasMatch(val.trim())) {
                    return 'Только латиница, цифры, - и _';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _imageController,
                decoration: const InputDecoration(
                  labelText: 'URL иконки / изображения (необязательно)',
                  hintText: 'https://...',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              SwitchListTile(
                title: const Text(
                  'Активна для клиентов и мастеров',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                ),
                value: _isActive,
                activeThumbColor: Colors.white,
                activeTrackColor: Colors.green,
                onChanged: (val) => setState(() => _isActive = val),
                contentPadding: EdgeInsets.zero,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.pop(context),
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
