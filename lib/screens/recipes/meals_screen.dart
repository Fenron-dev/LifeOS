import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../db/database.dart';
import '../../providers/recipes_provider.dart';
import '../../providers/units_provider.dart';
import '../../providers/vault_provider.dart';

class MealsScreen extends ConsumerWidget {
  const MealsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mealsAsync = ref.watch(allMealsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Mahlzeiten')),
      body: mealsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Fehler: $e')),
        data: (meals) => meals.isEmpty
            ? _EmptyState()
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                itemCount: meals.length,
                itemBuilder: (context, i) => _MealCard(meal: meals[i]),
              ),
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'add_meal',
        onPressed: () => _showMealDialog(context, ref),
        tooltip: 'Mahlzeit hinzufügen',
        child: const Icon(Icons.add),
      ),
    );
  }

  void _showMealDialog(BuildContext context, WidgetRef ref, [StandardMeal? meal]) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _MealForm(meal: meal),
    );
  }
}

class _MealCard extends ConsumerWidget {
  final StandardMeal meal;
  const _MealCard({required this.meal});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ingsAsync = ref.watch(mealIngredientsProvider(meal.id));

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        leading: const CircleAvatar(child: Icon(Icons.restaurant_menu)),
        title: Text(meal.name),
        subtitle: ingsAsync.when(
          loading: () => const Text('…'),
          error: (err, st) => const SizedBox.shrink(),
          data: (ings) => Text(
            '${ings.length} Zutat${ings.length == 1 ? '' : 'en'}',
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
                builder: (ctx) => _MealForm(meal: meal),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 20),
              onPressed: () => _confirmDelete(context, ref),
            ),
          ],
        ),
        children: [
          ingsAsync.when(
            loading: () =>
                const Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator()),
            error: (e, _) => Text('Fehler: $e'),
            data: (ings) => ings.isEmpty
                ? const ListTile(
                    title: Text('Keine Zutaten'), dense: true)
                : Column(
                    children: ings.map((ing) {
                      final qty = ing.quantity == ing.quantity.truncateToDouble()
                          ? ing.quantity.toInt().toString()
                          : ing.quantity.toStringAsFixed(1);
                      return ListTile(
                        dense: true,
                        leading: const Icon(Icons.fiber_manual_record, size: 8),
                        title: Text('$qty ${ing.unit}  ${ing.name}'),
                      );
                    }).toList(),
                  ),
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
        content: Text('«${meal.name}» wird gelöscht.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Löschen')),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(mealsNotifierProvider.notifier).deleteMeal(meal.id);
    }
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.restaurant_menu_outlined,
              size: 64, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 16),
          Text('Noch keine Mahlzeiten',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          const Text('Tippe + um eine Mahlzeit hinzuzufügen.'),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Meal form (bottom sheet)
// ---------------------------------------------------------------------------

class _MealForm extends ConsumerStatefulWidget {
  final StandardMeal? meal;
  const _MealForm({this.meal});

  @override
  ConsumerState<_MealForm> createState() => _MealFormState();
}

class _MealFormState extends ConsumerState<_MealForm> {
  final _nameCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final List<_IngRow> _ingredients = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    if (widget.meal != null) {
      _nameCtrl.text = widget.meal!.name;
      _notesCtrl.text = widget.meal!.notes ?? '';
      final db = ref.read(databaseProvider);
      if (db != null) {
        final ings = await db.ingredientsForMeal(widget.meal!.id);
        for (final ing in ings) {
          _ingredients.add(_IngRow(
            nameCtrl: TextEditingController(text: ing.name),
            qtyCtrl: TextEditingController(
                text: ing.quantity == ing.quantity.truncateToDouble()
                    ? ing.quantity.toInt().toString()
                    : ing.quantity.toStringAsFixed(1)),
            unit: ing.unit,
          ));
        }
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _notesCtrl.dispose();
    for (final r in _ingredients) {
      r.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final units = List<String>.from(ref.watch(unitNamesProvider));
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottom),
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    widget.meal == null ? 'Neue Mahlzeit' : 'Mahlzeit bearbeiten',
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

                  // Ingredients
                  Row(
                    children: [
                      Text('Zutaten', style: Theme.of(context).textTheme.titleSmall),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: () => setState(() => _ingredients.add(_IngRow())),
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('Hinzufügen'),
                      ),
                    ],
                  ),
                  ..._ingredients.asMap().entries.map((e) {
                    final row = e.value;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 56,
                            child: TextField(
                              controller: row.qtyCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Menge',
                                border: OutlineInputBorder(),
                                contentPadding: EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 8),
                              ),
                              keyboardType: const TextInputType.numberWithOptions(
                                  decimal: true),
                            ),
                          ),
                          const SizedBox(width: 4),
                          SizedBox(
                            width: 80,
                            child: InputDecorator(
                              decoration: const InputDecoration(
                                border: OutlineInputBorder(),
                                contentPadding: EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 4),
                              ),
                              child: DropdownButton<String>(
                                value: units.contains(row.unit)
                                    ? row.unit
                                    : (units.isNotEmpty ? units.first : null),
                                isExpanded: true,
                                underline: const SizedBox.shrink(),
                                isDense: true,
                                items: units
                                    .map((u) => DropdownMenuItem(
                                        value: u, child: Text(u)))
                                    .toList(),
                                onChanged: (v) =>
                                    setState(() => row.unit = v ?? row.unit),
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: TextField(
                              controller: row.nameCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Zutat',
                                border: OutlineInputBorder(),
                                contentPadding: EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 8),
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: () =>
                                setState(() => _ingredients.removeAt(e.key)),
                          ),
                        ],
                      ),
                    );
                  }),

                  const SizedBox(height: 8),
                  TextField(
                    controller: _notesCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Notizen',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _save,
                    child: Text(widget.meal == null ? 'Erstellen' : 'Speichern'),
                  ),
                ],
              ),
            ),
    );
  }

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty) return;

    final ings = _ingredients
        .where((r) => r.nameCtrl.text.trim().isNotEmpty)
        .map((r) => IngredientInput(
              name: r.nameCtrl.text.trim(),
              quantity:
                  double.tryParse(r.qtyCtrl.text.replaceAll(',', '.')) ?? 1,
              unit: r.unit,
            ))
        .toList();

    final notifier = ref.read(mealsNotifierProvider.notifier);
    if (widget.meal == null) {
      await notifier.createMeal(
        name: _nameCtrl.text.trim(),
        notes:
            _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        ingredients: ings,
      );
    } else {
      await notifier.updateMeal(
        widget.meal!,
        ingredients: ings,
      );
    }
    if (mounted) Navigator.of(context).pop();
  }
}

class _IngRow {
  final TextEditingController nameCtrl;
  final TextEditingController qtyCtrl;
  String unit;

  _IngRow({
    TextEditingController? nameCtrl,
    TextEditingController? qtyCtrl,
    String? unit,
  })  : nameCtrl = nameCtrl ?? TextEditingController(),
        qtyCtrl = qtyCtrl ?? TextEditingController(text: '1'),
        unit = unit ?? 'Stück';

  void dispose() {
    nameCtrl.dispose();
    qtyCtrl.dispose();
  }
}
