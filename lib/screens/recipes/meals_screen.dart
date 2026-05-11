import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../db/database.dart';
import '../../health/providers/nutrition_provider.dart';
import '../../health/widgets/inventory_deduct_sheet.dart';
import '../../providers/groups_provider.dart';
import '../../providers/items_provider.dart';
import '../../providers/locations_provider.dart';
import '../../providers/recipe_suggestions_provider.dart';
import '../../providers/recipes_provider.dart';
import '../../providers/units_provider.dart';
import '../../providers/entity_photos_provider.dart';
import '../../providers/vault_provider.dart';
import '../../widgets/entity_photo_section.dart';
import '../../widgets/thumbnail_image.dart';

class MealsScreen extends ConsumerStatefulWidget {
  final bool filterExpiring;
  const MealsScreen({super.key, this.filterExpiring = false});

  @override
  ConsumerState<MealsScreen> createState() => _MealsScreenState();
}

class _MealsScreenState extends ConsumerState<MealsScreen> {
  late bool _filterExpiring;
  bool _isGridView = false;

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
        actions: [
          IconButton(
            icon: Icon(
                _isGridView ? Icons.view_list_outlined : Icons.grid_view),
            tooltip: _isGridView ? 'Listenansicht' : 'Rasteransicht',
            onPressed: () => setState(() => _isGridView = !_isGridView),
          ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Gericht hinzufügen',
            onPressed: () => _showMealDialog(context, ref),
          ),
        ],
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
          final allMeals = meals;

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

          if (filtered.isEmpty && allMeals.isEmpty) return _EmptyState();

          if (_isGridView) {
            return CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                    child: _PreparedDishSection(allMeals: allMeals)),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
                  sliver: SliverGrid.builder(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                      childAspectRatio: 0.85,
                    ),
                    itemCount: filtered.length,
                    itemBuilder: (context, i) => _MealGridCard(
                      meal: filtered[i],
                      onTap: () => showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        useSafeArea: true,
                        builder: (_) =>
                            _MealConsumeSheet(meal: filtered[i]),
                      ),
                    ),
                  ),
                ),
              ],
            );
          }

          return CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: _PreparedDishSection(allMeals: allMeals),
                ),
                if (filtered.isEmpty)
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: Text('Keine passenden Gerichte')),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                    sliver: SliverList.builder(
                      itemCount: filtered.length,
                      itemBuilder: (context, i) => _MealCard(
                        meal: filtered[i],
                        expiringItemIds: expiringIds,
                      ),
                    ),
                  ),
              ],
            );
        },
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
// Meal grid card
// ---------------------------------------------------------------------------

class _MealGridCard extends ConsumerWidget {
  final StandardMeal meal;
  final VoidCallback onTap;
  const _MealGridCard({required this.meal, required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final photosAsync = ref.watch(entityPhotosProvider(meal.id));
    final firstPhoto = photosAsync.valueOrNull?.firstOrNull;
    final vaultPath = ref.watch(vaultPathProvider);

    Widget photoWidget;
    if (firstPhoto != null && vaultPath != null) {
      final fullPath = p.join(vaultPath, firstPhoto.photoPath);
      photoWidget = ThumbnailImage(
        sourcePath: fullPath,
        width: double.infinity,
        height: double.infinity,
        fit: BoxFit.cover,
      );
    } else {
      photoWidget = Container(
        color: cs.surfaceContainerHighest,
        child: Center(
          child: Icon(Icons.restaurant_menu,
              size: 40,
              color: cs.onSurfaceVariant.withValues(alpha: 0.4)),
        ),
      );
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: photoWidget),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
              child: Text(
                meal.name,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
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
        // Title and subtitle use full available width — trailing is only 2 items.
        title: Text(meal.name, softWrap: true),
        subtitle: ingsAsync.when(
          loading: () => const Text('…'),
          error: (err, st) => const SizedBox.shrink(),
          data: (ings) {
            final expiringCount = ings
                .where((i) =>
                    i.itemId != null &&
                    expiringItemIds.contains(i.itemId))
                .length;
            return Wrap(
              spacing: 6,
              children: [
                Text(
                  '${ings.length} Zutat${ings.length == 1 ? '' : 'en'}',
                  style: const TextStyle(fontSize: 12),
                ),
                if (expiringCount > 0)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
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
                  ),
              ],
            );
          },
        ),
        // Only 2 items in trailing: play + popup menu (freeze/edit/delete)
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.play_circle_outline, size: 22),
              tooltip: 'Verbrauchen',
              onPressed: () => showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                useSafeArea: true,
                builder: (_) => _MealConsumeSheet(meal: meal),
              ),
            ),
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'freeze') {
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    useSafeArea: true,
                    builder: (_) => _FreezeDishSheet(meal: meal),
                  );
                } else if (v == 'photos') {
                  showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    builder: (ctx) => Padding(
                      padding: EdgeInsets.fromLTRB(
                          16, 20, 16,
                          MediaQuery.viewInsetsOf(ctx).bottom + 24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(meal.name,
                              style:
                                  Theme.of(ctx).textTheme.titleMedium),
                          const SizedBox(height: 12),
                          EntityPhotoSection(
                              entityId: meal.id,
                              entityType: 'meal'),
                        ],
                      ),
                    ),
                  );
                } else if (v == 'edit') {
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    builder: (ctx) => _MealForm(meal: meal),
                  );
                } else if (v == 'delete') {
                  _confirmDelete(context, ref);
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'freeze',
                  child: Row(children: [
                    Icon(Icons.ac_unit_outlined),
                    SizedBox(width: 8),
                    Text('Einfrieren'),
                  ]),
                ),
                const PopupMenuItem(
                  value: 'photos',
                  child: Row(children: [
                    Icon(Icons.photo_library_outlined),
                    SizedBox(width: 8),
                    Text('Fotos'),
                  ]),
                ),
                const PopupMenuItem(
                  value: 'edit',
                  child: Row(children: [
                    Icon(Icons.edit_outlined),
                    SizedBox(width: 8),
                    Text('Bearbeiten'),
                  ]),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Row(children: [
                    Icon(Icons.delete_outline, color: Colors.red),
                    SizedBox(width: 8),
                    Text('Löschen',
                        style: TextStyle(color: Colors.red)),
                  ]),
                ),
              ],
            ),
          ],
        ),
        children: [
          ingsAsync.when(
            loading: () => const Padding(
                padding: EdgeInsets.all(8),
                child: CircularProgressIndicator()),
            error: (e, _) => Text('Fehler: $e'),
            data: (ings) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (ings.isEmpty)
                    const ListTile(title: Text('Keine Zutaten'), dense: true)
                  else
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
                  _MealRelationsSection(meal: meal),
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
  final _frozenShelfCtrl = TextEditingController();
  final _thawedShelfCtrl = TextEditingController();
  String _servingUnit = 'Portion';
  String? _freezeLocationId;
  bool _freezeEnabled = false;
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
      if (m.frozenShelfMonths != null || m.thawedShelfDays != null || m.defaultFreezeLocationId != null) {
        _freezeEnabled = true;
        if (m.frozenShelfMonths != null) _frozenShelfCtrl.text = m.frozenShelfMonths!.toString();
        if (m.thawedShelfDays != null) _thawedShelfCtrl.text = m.thawedShelfDays!.toString();
        _freezeLocationId = m.defaultFreezeLocationId;
      }
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
    _frozenShelfCtrl.dispose();
    _thawedShelfCtrl.dispose();
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
    final locationsAsync = ref.watch(allLocationsProvider);
    final allItems = itemsAsync.valueOrNull ?? [];
    final allGroups = groupsAsync.valueOrNull ?? [];
    final allLocations = locationsAsync.valueOrNull ?? [];
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

                  // ── Freeze settings ───────────────────────────────────────
                  SwitchListTile(
                    value: _freezeEnabled,
                    onChanged: (v) => setState(() {
                      _freezeEnabled = v;
                      if (!v) {
                        _frozenShelfCtrl.clear();
                        _thawedShelfCtrl.clear();
                        _freezeLocationId = null;
                      }
                    }),
                    title: const Text('Einfrieren aktivieren'),
                    subtitle: const Text('Portionen dieses Gerichts können eingefroren werden.'),
                    contentPadding: EdgeInsets.zero,
                  ),
                  if (_freezeEnabled) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _frozenShelfCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Haltbarkeit gefroren (Monate)',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            keyboardType: TextInputType.number,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _thawedShelfCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Haltbarkeit aufgetaut (Tage)',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            keyboardType: TextInputType.number,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Standard-Einfrierlagerort (optional)',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      child: DropdownButton<String?>(
                        value: _freezeLocationId,
                        isExpanded: true,
                        underline: const SizedBox.shrink(),
                        isDense: true,
                        items: [
                          const DropdownMenuItem(value: null, child: Text('— kein Standard —')),
                          ...allLocations.map((l) => DropdownMenuItem(
                                value: l.id,
                                child: Text(l.name),
                              )),
                        ],
                        onChanged: (v) => setState(() => _freezeLocationId = v),
                      ),
                    ),
                  ],

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
    final frozenMonths = _freezeEnabled ? int.tryParse(_frozenShelfCtrl.text) : null;
    final thawedDays = _freezeEnabled ? int.tryParse(_thawedShelfCtrl.text) : null;
    final freezeLocId = _freezeEnabled ? _freezeLocationId : null;

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
        frozenShelfMonths: frozenMonths,
        thawedShelfDays: thawedDays,
        defaultFreezeLocationId: freezeLocId,
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
        frozenShelfMonths: frozenMonths,
        thawedShelfDays: thawedDays,
        defaultFreezeLocationId: freezeLocId,
        clearFreezeSettings: !_freezeEnabled,
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

// ---------------------------------------------------------------------------
// Consume sheet
// ---------------------------------------------------------------------------

class _MealConsumeSheet extends ConsumerStatefulWidget {
  final StandardMeal meal;
  const _MealConsumeSheet({required this.meal});

  @override
  ConsumerState<_MealConsumeSheet> createState() => _MealConsumeSheetState();
}

class _MealConsumeSheetState extends ConsumerState<_MealConsumeSheet> {
  double _servings = 1.0;
  bool _saving = false;

  static const _servingOptions = [0.5, 1.0, 1.5, 2.0, 3.0];

  Future<void> _log({required bool withDeduction}) async {
    setState(() => _saving = true);
    try {
      final db = ref.read(databaseProvider);
      if (db == null) return;

      final nutr = await db.computeMealNutrition(widget.meal.id);
      final kcal = nutr?.kcal ?? widget.meal.kcalTotal;
      final protein = nutr?.proteinG ?? widget.meal.proteinG;
      final carbs = nutr?.carbsG ?? widget.meal.carbsG;
      final fat = nutr?.fatG ?? widget.meal.fatG;

      final logId = await ref.read(nutritionOpsProvider.notifier).logFood(
            productName: widget.meal.name,
            loggedAt: DateTime.now(),
            itemId: widget.meal.id,
            quantityG: _servings,
            displayUnit: widget.meal.servingUnit,
            kcal: kcal != null ? kcal * _servings : null,
            proteinG: protein != null ? protein * _servings : null,
            carbsG: carbs != null ? carbs * _servings : null,
            fatG: fat != null ? fat * _servings : null,
            source: 'meal',
          );

      if (withDeduction && mounted) {
        final log = await db.getNutritionLogById(logId);
        if (log != null && mounted) {
          Navigator.of(context).pop();
          await showModalBottomSheet<bool>(
            context: context,
            isScrollControlled: true,
            builder: (_) => InventoryDeductSheet(log: log),
          );
          return;
        }
      }

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('«${widget.meal.name}» ins Tagebuch eingetragen'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ingsAsync = ref.watch(mealIngredientsProvider(widget.meal.id));
    final nutrAsync = ref.watch(mealNutritionProvider(widget.meal.id));

    final nutr = nutrAsync.valueOrNull;
    final kcal = nutr?.kcal ?? widget.meal.kcalTotal;
    final protein = nutr?.proteinG ?? widget.meal.proteinG;
    final carbs = nutr?.carbsG ?? widget.meal.carbsG;
    final fat = nutr?.fatG ?? widget.meal.fatG;

    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 12, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
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
            Text(widget.meal.name,
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),

            // Servings
            Text('Portionen', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              children: _servingOptions.map((s) {
                final label = s == s.truncateToDouble()
                    ? s.toInt().toString()
                    : s.toString();
                return ChoiceChip(
                  label: Text(label),
                  selected: _servings == s,
                  onSelected: (v) {
                    if (v) setState(() => _servings = s);
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 16),

            // Ingredients
            ingsAsync.when(
              loading: () => const SizedBox.shrink(),
              error: (e, _) => const SizedBox.shrink(),
              data: (ings) {
                if (ings.isEmpty) return const SizedBox.shrink();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Zutaten',
                        style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 6),
                    ...ings.map((ing) {
                      final qty = ing.quantity * _servings;
                      final qtyStr = qty == qty.truncateToDouble()
                          ? qty.toInt().toString()
                          : qty.toStringAsFixed(1);
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Row(
                          children: [
                            Icon(
                              ing.itemId != null
                                  ? Icons.inventory_2_outlined
                                  : Icons.fiber_manual_record,
                              size: ing.itemId != null ? 14 : 8,
                              color: cs.onSurfaceVariant,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text('$qtyStr ${ing.unit}  ${ing.name}'),
                            ),
                          ],
                        ),
                      );
                    }),
                    const SizedBox(height: 12),
                  ],
                );
              },
            ),

            // Nutrition summary
            if (kcal != null) ...[
              Card(
                color: cs.surfaceContainerHighest,
                elevation: 0,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _ConsumeNutrCell(
                          label: 'kcal',
                          value: (kcal * _servings).round().toString(),
                          color: cs.primary),
                      if (protein != null)
                        _ConsumeNutrCell(
                            label: 'Protein',
                            value:
                                '${(protein * _servings).toStringAsFixed(1)}g'),
                      if (carbs != null)
                        _ConsumeNutrCell(
                            label: 'Kohlenhydrate',
                            value:
                                '${(carbs * _servings).toStringAsFixed(1)}g'),
                      if (fat != null)
                        _ConsumeNutrCell(
                            label: 'Fett',
                            value:
                                '${(fat * _servings).toStringAsFixed(1)}g'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],

            // Action buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed:
                        _saving ? null : () => _log(withDeduction: false),
                    icon: const Icon(Icons.book_outlined, size: 18),
                    label: const Text('Ins Tagebuch'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed:
                        _saving ? null : () => _log(withDeduction: true),
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.remove_shopping_cart_outlined,
                            size: 18),
                    label: const Text('Verbrauchen'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ConsumeNutrCell extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  const _ConsumeNutrCell(
      {required this.label, required this.value, this.color});

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.bold,
                ),
          ),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
          ),
        ],
      );
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

// ---------------------------------------------------------------------------
// Freeze dish sheet
// ---------------------------------------------------------------------------

class _FreezeDishSheet extends ConsumerStatefulWidget {
  final StandardMeal meal;
  const _FreezeDishSheet({required this.meal});

  @override
  ConsumerState<_FreezeDishSheet> createState() => _FreezeDishSheetState();
}

class _FreezeDishSheetState extends ConsumerState<_FreezeDishSheet> {
  final _portionsCtrl = TextEditingController(text: '1');
  final _notesCtrl = TextEditingController();
  String? _locationId;
  DateTime _frozenAt = DateTime.now();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _locationId = widget.meal.defaultFreezeLocationId;
  }

  @override
  void dispose() {
    _portionsCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  DateTime? get _expiresAt {
    final months = widget.meal.frozenShelfMonths;
    if (months == null) return null;
    return DateTime(_frozenAt.year, _frozenAt.month + months, _frozenAt.day);
  }

  Future<void> _save() async {
    final portions = int.tryParse(_portionsCtrl.text) ?? 1;
    if (portions <= 0) return;
    setState(() => _saving = true);
    try {
      final db = ref.read(databaseProvider);
      if (db == null) return;
      await db.insertPreparedDishe(PreparedDishesCompanion.insert(
        id: const Uuid().v4(),
        mealId: Value(widget.meal.id),
        name: widget.meal.name,
        portions: Value(portions),
        locationId: Value(_locationId),
        frozenAt: Value(_frozenAt),
        expiresAt: Value(_expiresAt),
        notes: Value(_notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim()),
      ));
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final locationsAsync = ref.watch(allLocationsProvider);
    final allLocations = locationsAsync.valueOrNull ?? [];
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.ac_unit),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Einfrieren: ${widget.meal.name}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _portionsCtrl,
              decoration: const InputDecoration(
                labelText: 'Portionen',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Eingefroren am'),
              subtitle: Text(DateFormat('dd.MM.yyyy').format(_frozenAt)),
              trailing: const Icon(Icons.calendar_today_outlined, size: 18),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _frozenAt,
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now().add(const Duration(days: 1)),
                );
                if (picked != null) setState(() => _frozenAt = picked);
              },
            ),
            if (_expiresAt != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'Haltbar bis ca. ${DateFormat('dd.MM.yyyy').format(_expiresAt!)}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Lagerort (optional)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              child: DropdownButton<String?>(
                value: _locationId,
                isExpanded: true,
                underline: const SizedBox.shrink(),
                isDense: true,
                items: [
                  const DropdownMenuItem(value: null, child: Text('— kein Lagerort —')),
                  ...allLocations.map((l) => DropdownMenuItem(
                        value: l.id,
                        child: Text(l.name),
                      )),
                ],
                onChanged: (v) => setState(() => _locationId = v),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notesCtrl,
              decoration: const InputDecoration(
                labelText: 'Notizen (optional)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.save_outlined),
              label: const Text('Einfrieren'),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Prepared dishes section (shown above meal list)
// ---------------------------------------------------------------------------

class _PreparedDishSection extends ConsumerWidget {
  final List<StandardMeal> allMeals;
  const _PreparedDishSection({required this.allMeals});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dishesAsync = ref.watch(preparedDishesProvider);
    final locationsAsync = ref.watch(allLocationsProvider);
    final locations = {for (final l in locationsAsync.valueOrNull ?? <Location>[]) l.id: l};
    final mealNames = {for (final m in allMeals) m.id: m.name};

    return dishesAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (e, st) => const SizedBox.shrink(),
      data: (dishes) {
        if (dishes.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Eingefrorene Gerichte',
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 6),
              ...dishes.map((d) => _PreparedDishCard(
                    dish: d,
                    mealName: d.mealId != null ? mealNames[d.mealId] : null,
                    location: d.locationId != null ? locations[d.locationId] : null,
                  )),
              const Divider(height: 24),
            ],
          ),
        );
      },
    );
  }
}

class _PreparedDishCard extends ConsumerWidget {
  final PreparedDishe dish;
  final String? mealName;
  final Location? location;
  const _PreparedDishCard({required this.dish, this.mealName, this.location});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isExpired = dish.expiresAt != null && dish.expiresAt!.isBefore(DateTime.now());
    final expiringSoon = dish.expiresAt != null &&
        !isExpired &&
        dish.expiresAt!.isBefore(DateTime.now().add(const Duration(days: 7)));

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      color: isExpired
          ? Theme.of(context).colorScheme.errorContainer
          : expiringSoon
              ? Theme.of(context).colorScheme.tertiaryContainer
              : null,
      child: ListTile(
        dense: true,
        leading: Icon(
          dish.state == 'thawed' ? Icons.water_drop_outlined : Icons.ac_unit,
          color: dish.state == 'thawed'
              ? Theme.of(context).colorScheme.primary
              : Colors.lightBlue,
          size: 22,
        ),
        title: Text(dish.name),
        subtitle: Text([
          '${dish.portions} Portion${dish.portions == 1 ? '' : 'en'}',
          if (location != null) location!.name,
          if (dish.expiresAt != null)
            isExpired
                ? 'ABGELAUFEN'
                : 'bis ${DateFormat('dd.MM.yy').format(dish.expiresAt!)}',
        ].join(' · ')),
        trailing: PopupMenuButton<String>(
          onSelected: (v) => _onAction(context, ref, v),
          itemBuilder: (ctx) => [
            if (dish.state == 'frozen')
              const PopupMenuItem(value: 'thaw', child: Row(children: [
                Icon(Icons.water_drop_outlined, size: 18),
                SizedBox(width: 8),
                Text('Auftauen'),
              ])),
            const PopupMenuItem(value: 'consume', child: Row(children: [
              Icon(Icons.restaurant_outlined, size: 18),
              SizedBox(width: 8),
              Text('Verbraucht'),
            ])),
            const PopupMenuItem(value: 'delete', child: Row(children: [
              Icon(Icons.delete_outline, size: 18),
              SizedBox(width: 8),
              Text('Löschen'),
            ])),
          ],
        ),
      ),
    );
  }

  Future<void> _onAction(BuildContext context, WidgetRef ref, String action) async {
    final db = ref.read(databaseProvider);
    if (db == null) return;
    if (action == 'thaw') {
      await db.updatePreparedDishe(PreparedDishesCompanion(
        id: Value(dish.id),
        state: const Value('thawed'),
        thawedAt: Value(DateTime.now()),
      ));
    } else if (action == 'consume') {
      await db.updatePreparedDishe(PreparedDishesCompanion(
        id: Value(dish.id),
        state: const Value('consumed'),
      ));
      await db.deletePreparedDishe(dish.id);
    } else if (action == 'delete') {
      await db.deletePreparedDishe(dish.id);
    }
  }
}

// ---------------------------------------------------------------------------
// Meal relations ("Passt gut zu")
// ---------------------------------------------------------------------------

class _MealRelationsSection extends ConsumerWidget {
  final StandardMeal meal;
  const _MealRelationsSection({required this.meal});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final relationsAsync = ref.watch(mealRelationsProvider(meal.id));
    final allMealsAsync = ref.watch(allMealsProvider);
    final allMeals = allMealsAsync.valueOrNull ?? [];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Passt gut zu',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: Theme.of(context).colorScheme.outline,
                      )),
              const Spacer(),
              TextButton.icon(
                onPressed: () => _addRelation(context, ref, allMeals),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Verknüpfen'),
              ),
            ],
          ),
          relationsAsync.when(
            loading: () => const SizedBox.shrink(),
            error: (e, st) => const SizedBox.shrink(),
            data: (relations) {
              if (relations.isEmpty) {
                return Text(
                  'Noch keine Verknüpfungen.',
                  style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.outline),
                );
              }
              return Wrap(
                spacing: 6,
                runSpacing: 4,
                children: relations.map((r) {
                  final name = allMeals
                      .where((m) => m.id == r.toId)
                      .firstOrNull
                      ?.name ?? r.toId;
                  return Chip(
                    label: Text(name, style: const TextStyle(fontSize: 12)),
                    deleteIcon: const Icon(Icons.close, size: 14),
                    onDeleted: () => ref.read(databaseProvider)
                        ?.removeMealRelation(r.id),
                    padding: EdgeInsets.zero,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _addRelation(
      BuildContext context, WidgetRef ref, List<StandardMeal> allMeals) async {
    final others = allMeals.where((m) => m.id != meal.id).toList();
    if (others.isEmpty) return;
    final picked = await showDialog<String>(
      context: context,
      builder: (ctx) => _PickMealDialog(meals: others, title: 'Gericht verknüpfen'),
    );
    if (picked == null) return;
    final db = ref.read(databaseProvider);
    if (db == null) return;
    await db.addMealRelation(MealRelationsCompanion.insert(
      id: const Uuid().v4(),
      fromId: meal.id,
      fromType: 'meal',
      toId: picked,
      toType: 'meal',
    ));
  }
}

class _PickMealDialog extends StatelessWidget {
  final List<StandardMeal> meals;
  final String title;
  const _PickMealDialog({required this.meals, required this.title});

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: meals.length,
            itemBuilder: (ctx, i) => ListTile(
              title: Text(meals[i].name),
              onTap: () => Navigator.of(ctx).pop(meals[i].id),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Abbrechen'),
          ),
        ],
      );
}
