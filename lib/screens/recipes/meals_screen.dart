import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../db/database.dart';
import '../../providers/groups_provider.dart';
import '../../providers/items_provider.dart';
import '../../providers/recipe_suggestions_provider.dart';
import '../../providers/recipes_provider.dart';
import '../../providers/units_provider.dart';
import '../../providers/vault_provider.dart';

class MealsScreen extends ConsumerStatefulWidget {
  final bool filterExpiring;
  const MealsScreen({super.key, this.filterExpiring = false});

  @override
  ConsumerState<MealsScreen> createState() => _MealsScreenState();
}

class _MealsScreenState extends ConsumerState<MealsScreen> {
  late bool _filterExpiring;

  @override
  void initState() {
    super.initState();
    _filterExpiring = widget.filterExpiring;
  }

  @override
  Widget build(BuildContext context) {
    final mealsAsync = ref.watch(allMealsProvider);
    final suggestionsAsync = _filterExpiring
        ? ref.watch(recipeSuggestionsForExpiringProvider)
        : null;
    final expiringIds = _filterExpiring
        ? ref.watch(expiringItemIdsProvider)
        : const <String>{};

    // When filter is active, get suggested meal IDs from recipe suggestions
    // AND also check meals whose ingredients match expiring items
    final suggestedMealIds = suggestionsAsync?.valueOrNull
            ?.map((r) => r.id)
            .toSet() ??
        {};

    return Scaffold(
      appBar: AppBar(
        title: const Text('Gerichte'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(40),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                FilterChip(
                  label: const Text('Ablaufende Zutaten'),
                  avatar: Icon(
                    Icons.event_busy_outlined,
                    size: 16,
                    color: _filterExpiring
                        ? Theme.of(context).colorScheme.onSecondaryContainer
                        : null,
                  ),
                  selected: _filterExpiring,
                  onSelected: (v) => setState(() => _filterExpiring = v),
                ),
              ],
            ),
          ),
        ),
      ),
      body: mealsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Fehler: $e')),
        data: (meals) {
          final filtered = _filterExpiring
              ? meals
                  .where((m) => suggestedMealIds.contains(m.id))
                  .toList()
              : meals;

          if (filtered.isEmpty && _filterExpiring) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle_outline,
                      size: 48,
                      color: Theme.of(context).colorScheme.outline),
                  const SizedBox(height: 12),
                  const Text('Keine passenden Gerichte gefunden'),
                  const SizedBox(height: 4),
                  TextButton(
                    onPressed: () => setState(() => _filterExpiring = false),
                    child: const Text('Filter entfernen'),
                  ),
                ],
              ),
            );
          }

          return filtered.isEmpty
              ? _EmptyState()
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                  itemCount: filtered.length,
                  itemBuilder: (context, i) => _MealCard(
                    meal: filtered[i],
                    expiringItemIds: expiringIds,
                  ),
                );
        },
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'add_meal',
        onPressed: () => _showMealDialog(context, ref),
        tooltip: 'Gericht hinzufügen',
        child: const Icon(Icons.add),
      ),
    );
  }

  void _showMealDialog(BuildContext context, WidgetRef ref,
      [StandardMeal? meal]) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _MealForm(meal: meal),
    );
  }
}

// ---------------------------------------------------------------------------
// Meal card
// ---------------------------------------------------------------------------

class _MealCard extends ConsumerWidget {
  final StandardMeal meal;
  final Set<String> expiringItemIds;
  const _MealCard({required this.meal, this.expiringItemIds = const {}});

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
          data: (ings) {
            final expiringCount = ings
                .where((i) =>
                    i.itemId != null &&
                    expiringItemIds.contains(i.itemId))
                .length;
            return Row(
              children: [
                Text(
                  '${ings.length} Zutat${ings.length == 1 ? '' : 'en'}',
                  style: const TextStyle(fontSize: 12),
                ),
                if (expiringCount > 0) ...[
                  const SizedBox(width: 6),
                  Icon(Icons.event_busy_outlined,
                      size: 12,
                      color: Theme.of(context).colorScheme.error),
                  const SizedBox(width: 2),
                  Text(
                    '$expiringCount ablaufend',
                    style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.error),
                  ),
                ],
              ],
            );
          },
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
            loading: () => const Padding(
                padding: EdgeInsets.all(8),
                child: CircularProgressIndicator()),
            error: (e, _) => Text('Fehler: $e'),
            data: (ings) => ings.isEmpty
                ? const ListTile(title: Text('Keine Zutaten'), dense: true)
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ...ings.map((ing) {
                        final qty = ing.quantity ==
                                ing.quantity.truncateToDouble()
                            ? ing.quantity.toInt().toString()
                            : ing.quantity.toStringAsFixed(1);
                        return ListTile(
                          dense: true,
                          leading: Icon(
                            ing.itemId != null
                                ? Icons.inventory_2_outlined
                                : ing.itemGroupId != null
                                    ? Icons.category_outlined
                                    : Icons.fiber_manual_record,
                            size: ing.itemId != null || ing.itemGroupId != null
                                ? 16
                                : 8,
                          ),
                          title: Text('$qty ${ing.unit}  ${ing.name}'),
                        );
                      }),
                      _MealNutritionRow(mealId: meal.id),
                    ],
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
        title: const Text('Gericht löschen?'),
        content: Text('«${meal.name}» wird gelöscht.'),
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
      await ref.read(mealsNotifierProvider.notifier).deleteMeal(meal.id);
    }
  }
}

// ---------------------------------------------------------------------------
// Nutrition summary row for a meal
// ---------------------------------------------------------------------------

class _MealNutritionRow extends ConsumerWidget {
  final String mealId;
  const _MealNutritionRow({required this.mealId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nutrAsync = ref.watch(mealNutritionProvider(mealId));
    return nutrAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (e, _) => const SizedBox.shrink(),
      data: (nutr) {
        if (nutr == null || nutr.kcal == 0) return const SizedBox.shrink();
        String fmt(double v) => v.round().toString();
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Card(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            elevation: 0,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _NutrCell(
                      label: 'kcal',
                      value: fmt(nutr.kcal),
                      color: Theme.of(context).colorScheme.primary),
                  _NutrCell(label: 'Protein', value: '${fmt(nutr.proteinG)}g'),
                  _NutrCell(
                      label: 'Kohlenhydrate', value: '${fmt(nutr.carbsG)}g'),
                  _NutrCell(label: 'Fett', value: '${fmt(nutr.fatG)}g'),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _NutrCell extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  const _NutrCell({required this.label, required this.value, this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(value,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.bold,
                )),
        Text(label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                )),
      ],
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
          Icon(Icons.restaurant_menu_outlined,
              size: 64, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 16),
          Text('Noch keine Gerichte',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          const Text('Tippe + um ein Gericht hinzuzufügen.'),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Meal form (bottom sheet)
// ---------------------------------------------------------------------------

/// A search option representing either an Item or an ItemGroup.
class _IngOption {
  final String id;
  final String name;
  final String? subtitle;
  final bool isGroup;

  const _IngOption({
    required this.id,
    required this.name,
    this.subtitle,
    required this.isGroup,
  });
}

class _MealForm extends ConsumerStatefulWidget {
  final StandardMeal? meal;
  const _MealForm({this.meal});

  @override
  ConsumerState<_MealForm> createState() => _MealFormState();
}

class _MealFormState extends ConsumerState<_MealForm> {
  final _nameCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _kcalCtrl = TextEditingController();
  final _proteinCtrl = TextEditingController();
  final _carbsCtrl = TextEditingController();
  final _fatCtrl = TextEditingController();
  String _servingUnit = 'Portion';
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
      final m = widget.meal!;
      _servingUnit = m.servingUnit;
      if (m.kcalTotal != null) _kcalCtrl.text = m.kcalTotal!.toStringAsFixed(0);
      if (m.proteinG != null) _proteinCtrl.text = m.proteinG!.toStringAsFixed(1);
      if (m.carbsG != null) _carbsCtrl.text = m.carbsG!.toStringAsFixed(1);
      if (m.fatG != null) _fatCtrl.text = m.fatG!.toStringAsFixed(1);
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
            linkedItemId: ing.itemId,
            linkedGroupId: ing.itemGroupId,
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
    _kcalCtrl.dispose();
    _proteinCtrl.dispose();
    _carbsCtrl.dispose();
    _fatCtrl.dispose();
    for (final r in _ingredients) {
      r.dispose();
    }
    super.dispose();
  }

  List<_IngOption> _buildOptions(
      List<Item> items, List<ItemGroup> groups, String query) {
    final q = query.toLowerCase();
    final opts = <_IngOption>[];
    for (final item in items) {
      if (item.name.toLowerCase().contains(q) ||
          (item.brand?.toLowerCase().contains(q) ?? false)) {
        opts.add(_IngOption(
          id: item.id,
          name: item.name,
          subtitle: item.brand,
          isGroup: false,
        ));
      }
    }
    for (final group in groups) {
      if (group.name.toLowerCase().contains(q)) {
        opts.add(_IngOption(
          id: group.id,
          name: group.name,
          subtitle: 'Gruppe',
          isGroup: true,
        ));
      }
    }
    return opts;
  }

  @override
  Widget build(BuildContext context) {
    final units = List<String>.from(ref.watch(unitNamesProvider));
    final itemsAsync = ref.watch(allItemsProvider);
    final groupsAsync = ref.watch(allGroupsProvider);
    final allItems = itemsAsync.valueOrNull ?? [];
    final allGroups = groupsAsync.valueOrNull ?? [];
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
                    widget.meal == null ? 'Neues Gericht' : 'Gericht bearbeiten',
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

                  // Serving unit
                  InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Einheit pro Portion',
                      border: OutlineInputBorder(),
                    ),
                    child: DropdownButton<String>(
                      value: _servingUnit,
                      isExpanded: true,
                      underline: const SizedBox.shrink(),
                      items: const [
                        DropdownMenuItem(value: 'Portion', child: Text('Portion')),
                        DropdownMenuItem(value: 'Stück', child: Text('Stück')),
                        DropdownMenuItem(value: 'g', child: Text('g (Gramm)')),
                        DropdownMenuItem(value: 'ml', child: Text('ml')),
                      ],
                      onChanged: (v) {
                        if (v != null) setState(() => _servingUnit = v);
                      },
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Ingredients header
                  Row(
                    children: [
                      Text('Zutaten',
                          style: Theme.of(context).textTheme.titleSmall),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: () =>
                            setState(() => _ingredients.add(_IngRow())),
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('Hinzufügen'),
                      ),
                    ],
                  ),

                  // Ingredient rows
                  ..._ingredients.asMap().entries.map((e) {
                    final row = e.value;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: _IngredientRowWidget(
                        key: ObjectKey(row),
                        row: row,
                        units: units,
                        allItems: allItems,
                        allGroups: allGroups,
                        buildOptions: _buildOptions,
                        onRemove: () =>
                            setState(() => _ingredients.removeAt(e.key)),
                        onChanged: () => setState(() {}),
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
                  Text('Nährwerte (pro Gericht, optional)',
                      style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 4),
                  Text(
                    'Wird als Fallback genutzt wenn keine verlinkten Zutaten mit Nährwerten vorhanden sind.',
                    style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _NutrField(
                            controller: _kcalCtrl, label: 'kcal gesamt'),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _NutrField(
                            controller: _proteinCtrl, label: 'Protein (g)'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _NutrField(
                            controller: _carbsCtrl,
                            label: 'Kohlenhydrate (g)'),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _NutrField(
                            controller: _fatCtrl, label: 'Fett (g)'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _save,
                    child:
                        Text(widget.meal == null ? 'Erstellen' : 'Speichern'),
                  ),
                ],
              ),
            ),
    );
  }

  double? _parseNutr(TextEditingController c) {
    final v = c.text.trim().replaceAll(',', '.');
    if (v.isEmpty) return null;
    return double.tryParse(v);
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
              itemId: r.linkedItemId,
              itemGroupId: r.linkedGroupId,
            ))
        .toList();

    final kcal = _parseNutr(_kcalCtrl);
    final protein = _parseNutr(_proteinCtrl);
    final carbs = _parseNutr(_carbsCtrl);
    final fat = _parseNutr(_fatCtrl);

    final notifier = ref.read(mealsNotifierProvider.notifier);
    if (widget.meal == null) {
      await notifier.createMeal(
        name: _nameCtrl.text.trim(),
        notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        servingUnit: _servingUnit,
        ingredients: ings,
        kcalTotal: kcal,
        proteinG: protein,
        carbsG: carbs,
        fatG: fat,
      );
    } else {
      await notifier.updateMeal(
        widget.meal!,
        ingredients: ings,
        servingUnit: _servingUnit,
        kcalTotal: kcal,
        proteinG: protein,
        carbsG: carbs,
        fatG: fat,
        clearNutrition: kcal == null && protein == null && carbs == null && fat == null,
      );
    }
    if (mounted) Navigator.of(context).pop();
  }
}

// ---------------------------------------------------------------------------
// Ingredient row widget (stateful to manage autocomplete focus)
// ---------------------------------------------------------------------------

class _IngredientRowWidget extends StatefulWidget {
  final _IngRow row;
  final List<String> units;
  final List<Item> allItems;
  final List<ItemGroup> allGroups;
  final List<_IngOption> Function(List<Item>, List<ItemGroup>, String)
      buildOptions;
  final VoidCallback onRemove;
  final VoidCallback onChanged;

  const _IngredientRowWidget({
    super.key,
    required this.row,
    required this.units,
    required this.allItems,
    required this.allGroups,
    required this.buildOptions,
    required this.onRemove,
    required this.onChanged,
  });

  @override
  State<_IngredientRowWidget> createState() => _IngredientRowWidgetState();
}

class _IngredientRowWidgetState extends State<_IngredientRowWidget> {
  @override
  Widget build(BuildContext context) {
    final row = widget.row;
    final isLinked = row.linkedItemId != null || row.linkedGroupId != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            // Quantity
            SizedBox(
              width: 56,
              child: TextField(
                controller: row.qtyCtrl,
                decoration: const InputDecoration(
                  labelText: 'Menge',
                  border: OutlineInputBorder(),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                ),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
              ),
            ),
            const SizedBox(width: 4),
            // Unit
            SizedBox(
              width: 80,
              child: InputDecorator(
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                ),
                child: DropdownButton<String>(
                  value: widget.units.contains(row.unit)
                      ? row.unit
                      : (widget.units.isNotEmpty ? widget.units.first : null),
                  isExpanded: true,
                  underline: const SizedBox.shrink(),
                  isDense: true,
                  items: widget.units
                      .map((u) =>
                          DropdownMenuItem(value: u, child: Text(u)))
                      .toList(),
                  onChanged: (v) {
                    setState(() => row.unit = v ?? row.unit);
                    widget.onChanged();
                  },
                ),
              ),
            ),
            const SizedBox(width: 4),
            // Name with autocomplete
            Expanded(
              child: Autocomplete<_IngOption>(
                initialValue: TextEditingValue(text: row.nameCtrl.text),
                optionsBuilder: (value) {
                  if (value.text.trim().isEmpty) return const [];
                  return widget.buildOptions(
                      widget.allItems, widget.allGroups, value.text);
                },
                displayStringForOption: (opt) => opt.name,
                onSelected: (opt) {
                  setState(() {
                    row.nameCtrl.text = opt.name;
                    if (opt.isGroup) {
                      row.linkedGroupId = opt.id;
                      row.linkedItemId = null;
                    } else {
                      row.linkedItemId = opt.id;
                      row.linkedGroupId = null;
                    }
                  });
                  widget.onChanged();
                },
                fieldViewBuilder:
                    (context, controller, focusNode, onFieldSubmitted) {
                  // Sync external nameCtrl ↔ autocomplete controller
                  controller.text = row.nameCtrl.text;
                  controller.addListener(() {
                    if (row.nameCtrl.text != controller.text) {
                      row.nameCtrl.text = controller.text;
                      // Clear link if user manually edits
                      if (row.linkedItemId != null ||
                          row.linkedGroupId != null) {
                        setState(() {
                          row.linkedItemId = null;
                          row.linkedGroupId = null;
                        });
                      }
                    }
                  });
                  return TextField(
                    controller: controller,
                    focusNode: focusNode,
                    decoration: InputDecoration(
                      labelText: 'Zutat',
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 8),
                      suffixIcon: isLinked
                          ? Tooltip(
                              message: row.linkedGroupId != null
                                  ? 'Gruppe verknüpft'
                                  : 'Artikel verknüpft',
                              child: Icon(
                                row.linkedGroupId != null
                                    ? Icons.category_outlined
                                    : Icons.inventory_2_outlined,
                                size: 16,
                                color:
                                    Theme.of(context).colorScheme.primary,
                              ),
                            )
                          : null,
                    ),
                  );
                },
                optionsViewBuilder: (context, onSelected, options) {
                  return Align(
                    alignment: Alignment.topLeft,
                    child: Material(
                      elevation: 4,
                      borderRadius: BorderRadius.circular(8),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 200),
                        child: ListView.builder(
                          padding: EdgeInsets.zero,
                          shrinkWrap: true,
                          itemCount: options.length,
                          itemBuilder: (context, i) {
                            final opt = options.elementAt(i);
                            return ListTile(
                              dense: true,
                              leading: Icon(opt.isGroup
                                  ? Icons.category_outlined
                                  : Icons.inventory_2_outlined),
                              title: Text(opt.name),
                              subtitle: opt.subtitle != null
                                  ? Text(opt.subtitle!)
                                  : null,
                              onTap: () => onSelected(opt),
                            );
                          },
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              onPressed: widget.onRemove,
            ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Ingredient row data model
// ---------------------------------------------------------------------------

class _IngRow {
  final TextEditingController nameCtrl;
  final TextEditingController qtyCtrl;
  String unit;
  String? linkedItemId;
  String? linkedGroupId;

  _IngRow({
    TextEditingController? nameCtrl,
    TextEditingController? qtyCtrl,
    String? unit,
    this.linkedItemId,
    this.linkedGroupId,
  })  : nameCtrl = nameCtrl ?? TextEditingController(),
        qtyCtrl = qtyCtrl ?? TextEditingController(text: '1'),
        unit = unit ?? 'Stück';

  void dispose() {
    nameCtrl.dispose();
    qtyCtrl.dispose();
  }
}

class _NutrField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  const _NutrField({required this.controller, required this.label});

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
        ],
      );
}
