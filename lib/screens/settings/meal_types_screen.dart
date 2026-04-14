import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../db/database.dart';
import '../../providers/vault_provider.dart';

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------

final _mealTypesProvider = StreamProvider<List<MealType>>((ref) {
  final db = ref.watch(databaseProvider);
  if (db == null) return const Stream.empty();
  return db.watchAllMealTypes();
});

final _assignmentsProvider =
    StreamProvider.family<List<MealTypeAssignment>, String>((ref, mealTypeId) {
  final db = ref.watch(databaseProvider);
  if (db == null) return const Stream.empty();
  return db.watchAssignmentsForMealType(mealTypeId);
});

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class MealTypesScreen extends ConsumerWidget {
  const MealTypesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mealTypesAsync = ref.watch(_mealTypesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Mahlzeiten')),
      body: mealTypesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Fehler: $e')),
        data: (types) => types.isEmpty
            ? _EmptyState()
            : ReorderableListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                itemCount: types.length,
                onReorder: (oldIndex, newIndex) =>
                    _reorder(ref, types, oldIndex, newIndex),
                itemBuilder: (context, i) =>
                    _MealTypeCard(key: ValueKey(types[i].id), mealType: types[i]),
              ),
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'add_meal_type',
        onPressed: () => _showForm(context, ref),
        tooltip: 'Mahlzeit hinzufügen',
        child: const Icon(Icons.add),
      ),
    );
  }

  Future<void> _reorder(
      WidgetRef ref, List<MealType> types, int oldIndex, int newIndex) async {
    if (newIndex > oldIndex) newIndex--;
    final db = ref.read(databaseProvider);
    if (db == null) return;
    final moved = types[oldIndex];
    final reordered = [...types]..removeAt(oldIndex)..insert(newIndex, moved);
    for (var i = 0; i < reordered.length; i++) {
      await db.updateMealType(MealTypesCompanion(
        id: Value(reordered[i].id),
        sortOrder: Value(i),
      ));
    }
  }

  void _showForm(BuildContext context, WidgetRef ref, [MealType? mealType]) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _MealTypeForm(mealType: mealType),
    );
  }
}

// ---------------------------------------------------------------------------
// Meal type card
// ---------------------------------------------------------------------------

class _MealTypeCard extends ConsumerWidget {
  final MealType mealType;
  const _MealTypeCard({super.key, required this.mealType});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final assignmentsAsync = ref.watch(_assignmentsProvider(mealType.id));
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.primaryContainer,
          child: Icon(
            _iconFromName(mealType.iconName),
            color: theme.colorScheme.onPrimaryContainer,
            size: 20,
          ),
        ),
        title: Text(mealType.name),
        subtitle: assignmentsAsync.when(
          loading: () => const Text('…'),
          error: (e, _) => const SizedBox.shrink(),
          data: (a) => Text(
            '${a.length} Gericht${a.length == 1 ? '' : 'e'}/Rezept${a.length == 1 ? '' : 'e'}',
            style: const TextStyle(fontSize: 12),
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 20),
              onPressed: () => showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                builder: (_) => _MealTypeForm(mealType: mealType),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 20),
              onPressed: () => _confirmDelete(context, ref),
            ),
            const Icon(Icons.drag_handle),
          ],
        ),
        children: [
          assignmentsAsync.when(
            loading: () => const Padding(
                padding: EdgeInsets.all(8),
                child: CircularProgressIndicator()),
            error: (e, _) => Text('Fehler: $e'),
            data: (assignments) => _AssignmentList(
                mealType: mealType, assignments: assignments),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mahlzeit löschen?'),
        content: Text('«${mealType.name}» und alle Zuweisungen werden gelöscht.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Abbrechen')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Löschen')),
        ],
      ),
    );
    if (ok == true) {
      final db = ref.read(databaseProvider);
      if (db == null) return;
      await db.deleteAssignmentsForMealType(mealType.id);
      await db.deleteMealType(mealType.id);
    }
  }

  IconData _iconFromName(String? name) {
    return switch (name) {
      'free_breakfast'  => Icons.free_breakfast,
      'lunch_dining'    => Icons.lunch_dining,
      'dinner_dining'   => Icons.dinner_dining,
      'apple'           => Icons.apple,
      'cake'            => Icons.cake,
      'local_cafe'      => Icons.local_cafe,
      'more_horiz'      => Icons.more_horiz,
      _                 => Icons.restaurant,
    };
  }
}

// ---------------------------------------------------------------------------
// Assignment list inside card
// ---------------------------------------------------------------------------

class _AssignmentList extends ConsumerWidget {
  final MealType mealType;
  final List<MealTypeAssignment> assignments;
  const _AssignmentList(
      {required this.mealType, required this.assignments});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.read(databaseProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (assignments.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text('Keine Gerichte/Rezepte zugewiesen.',
                style: TextStyle(color: Colors.grey, fontSize: 13)),
          ),
        ...assignments.map((a) => ListTile(
              dense: true,
              leading: Icon(
                a.dishId != null
                    ? Icons.restaurant_menu_outlined
                    : Icons.menu_book_outlined,
                size: 18,
              ),
              title: Text(a.dishId != null
                  ? 'Gericht: ${a.dishId}'
                  : 'Rezept: ${a.recipeId}'),
              trailing: IconButton(
                icon: const Icon(Icons.remove_circle_outline, size: 16,
                    color: Colors.red),
                onPressed: () => db?.deleteMealTypeAssignment(a.id),
              ),
            )),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Row(
            children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.restaurant_menu_outlined, size: 16),
                label: const Text('Gericht'),
                onPressed: () => _assignDish(context, ref),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.menu_book_outlined, size: 16),
                label: const Text('Rezept'),
                onPressed: () => _assignRecipe(context, ref),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _assignDish(BuildContext context, WidgetRef ref) async {
    final db = ref.read(databaseProvider);
    if (db == null) return;
    final meals = await db.watchAllMeals().first;
    if (!context.mounted) return;

    final selected = await showDialog<StandardMeal>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Gericht auswählen'),
        children: meals
            .map((m) => SimpleDialogOption(
                  onPressed: () => Navigator.of(ctx).pop(m),
                  child: Text(m.name),
                ))
            .toList(),
      ),
    );
    if (selected == null) return;
    await db.insertMealTypeAssignment(MealTypeAssignmentsCompanion.insert(
      id: const Uuid().v4(),
      mealTypeId: mealType.id,
      dishId: Value(selected.id),
    ));
  }

  Future<void> _assignRecipe(BuildContext context, WidgetRef ref) async {
    final db = ref.read(databaseProvider);
    if (db == null) return;
    final recipeList = await db.watchAllRecipes().first;
    if (!context.mounted) return;

    final selected = await showDialog<Recipe>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Rezept auswählen'),
        children: recipeList
            .map((r) => SimpleDialogOption(
                  onPressed: () => Navigator.of(ctx).pop(r),
                  child: Text(r.name),
                ))
            .toList(),
      ),
    );
    if (selected == null) return;
    await db.insertMealTypeAssignment(MealTypeAssignmentsCompanion.insert(
      id: const Uuid().v4(),
      mealTypeId: mealType.id,
      recipeId: Value(selected.id),
    ));
  }
}

// ---------------------------------------------------------------------------
// Form to create / edit a meal type
// ---------------------------------------------------------------------------

class _MealTypeForm extends ConsumerStatefulWidget {
  final MealType? mealType;
  const _MealTypeForm({this.mealType});

  @override
  ConsumerState<_MealTypeForm> createState() => _MealTypeFormState();
}

class _MealTypeFormState extends ConsumerState<_MealTypeForm> {
  final _nameCtrl = TextEditingController();
  String? _selectedIcon;

  static const _icons = [
    ('Frühstück',   'free_breakfast',  Icons.free_breakfast),
    ('Mittagessen', 'lunch_dining',    Icons.lunch_dining),
    ('Abendessen',  'dinner_dining',   Icons.dinner_dining),
    ('Snack',       'apple',           Icons.apple),
    ('Süßigkeit',   'cake',            Icons.cake),
    ('Getränk',     'local_cafe',      Icons.local_cafe),
    ('Sonstiges',   'more_horiz',      Icons.more_horiz),
    ('Restaurant',  'restaurant',      Icons.restaurant),
  ];

  @override
  void initState() {
    super.initState();
    if (widget.mealType != null) {
      _nameCtrl.text = widget.mealType!.name;
      _selectedIcon = widget.mealType!.iconName;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty) return;
    final db = ref.read(databaseProvider);
    if (db == null) return;

    if (widget.mealType == null) {
      await db.insertMealType(MealTypesCompanion.insert(
        id: const Uuid().v4(),
        name: _nameCtrl.text.trim(),
        iconName: Value(_selectedIcon),
      ));
    } else {
      await db.updateMealType(MealTypesCompanion(
        id: Value(widget.mealType!.id),
        name: Value(_nameCtrl.text.trim()),
        iconName: Value(_selectedIcon),
      ));
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.mealType == null ? 'Neue Mahlzeit' : 'Mahlzeit bearbeiten',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Name *',
                border: OutlineInputBorder(),
              ),
              autofocus: true,
            ),
            const SizedBox(height: 12),
            Text('Symbol', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _icons.map((entry) {
                final (label, key, icon) = entry;
                final selected = _selectedIcon == key;
                return ChoiceChip(
                  avatar: Icon(icon, size: 18),
                  label: Text(label),
                  selected: selected,
                  onSelected: (_) => setState(() => _selectedIcon = key),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _save,
              child: Text(widget.mealType == null ? 'Erstellen' : 'Speichern'),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Empty state
// ---------------------------------------------------------------------------

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.restaurant_outlined,
              size: 64, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 16),
          Text('Noch keine Mahlzeiten',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          const Text('z. B. Frühstück, Mittagessen, Snack…'),
        ],
      ),
    );
  }
}
