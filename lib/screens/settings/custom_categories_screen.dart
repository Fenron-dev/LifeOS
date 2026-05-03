import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../db/database.dart';
import '../../providers/categories_provider.dart';

class CustomCategoriesScreen extends ConsumerWidget {
  const CustomCategoriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoriesAsync = ref.watch(categoryDefinitionsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Eigene Kategorien')),
      body: categoriesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Fehler: $e')),
        data: (categories) => categories.isEmpty
            ? _EmptyHint(
                onAdd: () => _openSheet(context, ref, null),
              )
            : ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: categories.length,
                separatorBuilder: (context, i) =>
                    const Divider(height: 1, indent: 56),
                itemBuilder: (context, i) =>
                    _CategoryTile(cat: categories[i]),
              ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openSheet(context, ref, null),
        tooltip: 'Kategorie hinzufügen',
        child: const Icon(Icons.add),
      ),
    );
  }

  void _openSheet(
      BuildContext context, WidgetRef ref, CategoryDefinition? cat) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _CategorySheet(existing: cat),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyHint extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyHint({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.category_outlined,
                size: 64, color: cs.onSurfaceVariant.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            Text(
              'Noch keine eigenen Kategorien',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Erstelle eigene Kategorien, um Artikel nach deinen\nBedürfnissen zu gruppieren (z.B. Fitness, Mealprep).',
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: const Text('Kategorie erstellen'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Single tile ───────────────────────────────────────────────────────────────

class _CategoryTile extends ConsumerWidget {
  final CategoryDefinition cat;
  const _CategoryTile({required this.cat});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: cs.primaryContainer,
        child: Icon(
          _iconData(cat.iconName),
          color: cs.onPrimaryContainer,
          size: 20,
        ),
      ),
      title: Text(cat.name),
      subtitle: cat.iconName != null
          ? Text(cat.iconName!,
              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant))
          : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Bearbeiten',
            onPressed: () => showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              useSafeArea: true,
              builder: (_) => _CategorySheet(existing: cat),
            ),
          ),
          IconButton(
            icon: Icon(Icons.delete_outline, color: cs.error),
            tooltip: 'Löschen',
            onPressed: () => _confirmDelete(context, ref),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Kategorie löschen?'),
            content: Text(
                '„${cat.name}" wird gelöscht. Artikel in dieser Kategorie '
                'behalten ihre Kategorie-ID, werden aber als unbekannte '
                'Kategorie angezeigt.'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('Abbrechen')),
              FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: const Text('Löschen')),
            ],
          ),
        ) ??
        false;
    if (ok) {
      await ref.read(categoryOpsProvider.notifier).deleteCategory(cat.id);
    }
  }
}

// ── Create / Edit sheet ───────────────────────────────────────────────────────

class _CategorySheet extends ConsumerStatefulWidget {
  final CategoryDefinition? existing;
  const _CategorySheet({this.existing});

  @override
  ConsumerState<_CategorySheet> createState() => _CategorySheetState();
}

class _CategorySheetState extends ConsumerState<_CategorySheet> {
  late final TextEditingController _nameCtrl;
  String? _iconName;
  bool _saving = false;

  // Curated icon list for quick picking
  static const _icons = <(String, IconData)>[
    ('category', Icons.category_outlined),
    ('fitness_center', Icons.fitness_center),
    ('restaurant', Icons.restaurant_outlined),
    ('local_cafe', Icons.local_cafe_outlined),
    ('sports', Icons.sports_outlined),
    ('spa', Icons.spa_outlined),
    ('medical_services', Icons.medical_services_outlined),
    ('school', Icons.school_outlined),
    ('work', Icons.work_outline),
    ('home', Icons.home_outlined),
    ('pets', Icons.pets_outlined),
    ('child_care', Icons.child_care_outlined),
    ('nature', Icons.nature_outlined),
    ('local_grocery_store', Icons.local_grocery_store_outlined),
    ('kitchen', Icons.kitchen_outlined),
    ('outdoor_grill', Icons.outdoor_grill_outlined),
    ('blender', Icons.blender_outlined),
    ('emoji_food_beverage', Icons.emoji_food_beverage_outlined),
    ('set_meal', Icons.set_meal_outlined),
    ('bakery_dining', Icons.bakery_dining_outlined),
  ];

  @override
  void initState() {
    super.initState();
    _nameCtrl =
        TextEditingController(text: widget.existing?.name ?? '');
    _iconName = widget.existing?.iconName;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  bool get _isEdit => widget.existing != null;

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    setState(() => _saving = true);
    try {
      if (_isEdit) {
        await ref.read(categoryOpsProvider.notifier).updateCategory(
              id: widget.existing!.id,
              name: name,
              iconName: _iconName,
              sortOrder: widget.existing!.sortOrder,
            );
      } else {
        await ref.read(categoryOpsProvider.notifier).addCategory(
              name: name,
              iconName: _iconName,
            );
      }
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 12, 16, bottom + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: cs.onSurfaceVariant.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _isEdit ? 'Kategorie bearbeiten' : 'Neue Kategorie',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _nameCtrl,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Name',
              hintText: 'z.B. Fitness, Mealprep, Babynahrung',
              border: OutlineInputBorder(),
            ),
            textCapitalization: TextCapitalization.sentences,
            onFieldSubmitted: (_) => _save(),
          ),
          const SizedBox(height: 16),
          Text('Symbol (optional)',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: cs.onSurfaceVariant)),
          const SizedBox(height: 8),
          SizedBox(
            height: 52,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _icons.length,
              separatorBuilder: (context, i) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final (name, icon) = _icons[i];
                final selected = _iconName == name;
                return GestureDetector(
                  onTap: () =>
                      setState(() => _iconName = selected ? null : name),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: selected
                          ? cs.primaryContainer
                          : cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                      border: selected
                          ? Border.all(color: cs.primary, width: 2)
                          : null,
                    ),
                    child: Icon(
                      icon,
                      size: 22,
                      color: selected
                          ? cs.onPrimaryContainer
                          : cs.onSurfaceVariant,
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Abbrechen'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _saving ||
                        _nameCtrl.text.trim().isEmpty
                    ? null
                    : _save,
                child: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : Text(_isEdit ? 'Speichern' : 'Erstellen'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Icon helper ───────────────────────────────────────────────────────────────

IconData _iconData(String? name) {
  return switch (name) {
    'fitness_center' => Icons.fitness_center,
    'restaurant' => Icons.restaurant_outlined,
    'local_cafe' => Icons.local_cafe_outlined,
    'sports' => Icons.sports_outlined,
    'spa' => Icons.spa_outlined,
    'medical_services' => Icons.medical_services_outlined,
    'school' => Icons.school_outlined,
    'work' => Icons.work_outline,
    'home' => Icons.home_outlined,
    'pets' => Icons.pets_outlined,
    'child_care' => Icons.child_care_outlined,
    'nature' => Icons.nature_outlined,
    'local_grocery_store' => Icons.local_grocery_store_outlined,
    'kitchen' => Icons.kitchen_outlined,
    'outdoor_grill' => Icons.outdoor_grill_outlined,
    'blender' => Icons.blender_outlined,
    'emoji_food_beverage' => Icons.emoji_food_beverage_outlined,
    'set_meal' => Icons.set_meal_outlined,
    'bakery_dining' => Icons.bakery_dining_outlined,
    _ => Icons.category_outlined,
  };
}
