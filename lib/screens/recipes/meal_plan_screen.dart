import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../db/database.dart';
import '../../health/providers/nutrition_provider.dart';
import '../../providers/inventory_provider.dart';
import '../../providers/meal_plan_provider.dart';
import '../../providers/vault_provider.dart';
import '../../health/widgets/food_search_sheet.dart';

class MealPlanScreen extends ConsumerStatefulWidget {
  const MealPlanScreen({super.key});

  @override
  ConsumerState<MealPlanScreen> createState() => _MealPlanScreenState();
}

class _MealPlanScreenState extends ConsumerState<MealPlanScreen> {
  late DateTime _weekStart;

  @override
  void initState() {
    super.initState();
    _weekStart = _mondayOf(DateTime.now());
  }

  static DateTime _mondayOf(DateTime d) {
    final monday = d.subtract(Duration(days: d.weekday - 1));
    return DateTime(monday.year, monday.month, monday.day);
  }

  DateTime get _weekEnd => _weekStart.add(const Duration(days: 7));

  void _prevWeek() => setState(() => _weekStart = _weekStart.subtract(const Duration(days: 7)));
  void _nextWeek() => setState(() => _weekStart = _weekStart.add(const Duration(days: 7)));

  String get _weekLabel {
    final end = _weekStart.add(const Duration(days: 6));
    final fmt = DateFormat('dd.MM.', 'de_DE');
    return '${fmt.format(_weekStart)} – ${fmt.format(end)}';
  }

  @override
  Widget build(BuildContext context) {
    final entriesAsync = ref.watch(
        mealPlanEntriesProvider((_weekStart, _weekEnd)));
    final mealTypes = ref.watch(mealTypesProvider).valueOrNull ?? [];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mahlzeitenplan'),
        actions: [
          IconButton(
            icon: const Icon(Icons.shopping_cart_outlined),
            tooltip: 'Zutaten prüfen',
            onPressed: () => _showIngredientCheck(context),
          ),
        ],
      ),
      body: Column(
        children: [
          // Week navigation bar
          _WeekNavBar(
            label: _weekLabel,
            onPrev: _prevWeek,
            onNext: _nextWeek,
          ),
          Expanded(
            child: entriesAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Fehler: $e')),
              data: (entries) => _WeekBody(
                weekStart: _weekStart,
                entries: entries,
                mealTypes: mealTypes,
                onAddEntry: (date, mealTypeId) =>
                    _openAddSheet(context, date, mealTypeId),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openAddSheet(
      BuildContext context, DateTime date, String? mealTypeId) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _AddMealPlanEntrySheet(
        date: date,
        initialMealTypeId: mealTypeId,
      ),
    );
  }

  Future<void> _showIngredientCheck(BuildContext context) async {
    final db = ref.read(databaseProvider);
    if (db == null) return;
    final needs =
        await db.getPlanIngredientNeeds(_weekStart, _weekEnd);
    if (!context.mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _IngredientCheckSheet(
        needs: needs,
        weekLabel: _weekLabel,
      ),
    );
  }
}

// ── Week navigation bar ───────────────────────────────────────────────────────

class _WeekNavBar extends StatelessWidget {
  final String label;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  const _WeekNavBar(
      {required this.label, required this.onPrev, required this.onNext});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      color: cs.surfaceContainerLow,
      child: Row(
        children: [
          IconButton(
              icon: const Icon(Icons.chevron_left), onPressed: onPrev),
          Expanded(
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          IconButton(
              icon: const Icon(Icons.chevron_right), onPressed: onNext),
        ],
      ),
    );
  }
}

// ── Week body ─────────────────────────────────────────────────────────────────

class _WeekBody extends StatelessWidget {
  final DateTime weekStart;
  final List<MealPlanEntry> entries;
  final List<MealType> mealTypes;
  final void Function(DateTime, String?) onAddEntry;

  const _WeekBody({
    required this.weekStart,
    required this.entries,
    required this.mealTypes,
    required this.onAddEntry,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
      itemCount: 7,
      itemBuilder: (context, i) {
        final day = weekStart.add(Duration(days: i));
        final dayEnd = day.add(const Duration(days: 1));
        final dayEntries = entries
            .where((e) =>
                !e.date.isBefore(day) && e.date.isBefore(dayEnd))
            .toList();
        return _DayCard(
          day: day,
          entries: dayEntries,
          mealTypes: mealTypes,
          onAddEntry: onAddEntry,
        );
      },
    );
  }
}

// ── Day card ──────────────────────────────────────────────────────────────────

class _DayCard extends ConsumerWidget {
  final DateTime day;
  final List<MealPlanEntry> entries;
  final List<MealType> mealTypes;
  final void Function(DateTime, String?) onAddEntry;

  const _DayCard({
    required this.day,
    required this.entries,
    required this.mealTypes,
    required this.onAddEntry,
  });

  String _dayLabel(DateTime d) {
    final weekdayNames = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];
    final label = weekdayNames[d.weekday - 1];
    return '$label ${DateFormat('dd.MM.', 'de_DE').format(d)}';
  }

  bool get _isToday {
    final n = DateTime.now();
    return day.year == n.year && day.month == n.month && day.day == n.day;
  }

  double get _totalKcal => entries.fold(
      0,
      (sum, e) =>
          sum + ((e.kcalPerServing ?? 0) * e.servings));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final fmt0 = NumberFormat('##0', 'de_DE');

    // Group entries by mealTypeId
    final bySlot = <String?, List<MealPlanEntry>>{};
    for (final e in entries) {
      bySlot.putIfAbsent(e.mealTypeId, () => []).add(e);
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: _isToday ? cs.primaryContainer.withValues(alpha: 0.3) : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Day header
            Row(
              children: [
                Text(
                  _dayLabel(day),
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: _isToday ? cs.primary : null,
                        fontWeight: _isToday ? FontWeight.w700 : null,
                      ),
                ),
                const Spacer(),
                if (_totalKcal > 0)
                  Text(
                    '${fmt0.format(_totalKcal)} kcal',
                    style: TextStyle(
                        fontSize: 12, color: cs.onSurfaceVariant),
                  ),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline, size: 20),
                  tooltip: 'Hinzufügen',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => onAddEntry(day, null),
                ),
              ],
            ),
            // Meal slot sections
            if (entries.isNotEmpty) ...[
              const Divider(height: 8),
              // Entries with known meal type, in order
              for (final mt in mealTypes)
                if (bySlot[mt.id] != null)
                  _SlotSection(
                    label: mt.name,
                    entries: bySlot[mt.id]!,
                    onAdd: () => onAddEntry(day, mt.id),
                  ),
              // Entries with no slot
              if (bySlot[null] != null)
                _SlotSection(
                  label: 'Sonstiges',
                  entries: bySlot[null]!,
                  onAdd: () => onAddEntry(day, null),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Slot section ──────────────────────────────────────────────────────────────

class _SlotSection extends ConsumerWidget {
  final String label;
  final List<MealPlanEntry> entries;
  final VoidCallback onAdd;

  const _SlotSection(
      {required this.label, required this.entries, required this.onAdd});

  String _fmt(double v) =>
      v == v.truncateToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 2),
          child: Text(
            label,
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: cs.onSurfaceVariant),
          ),
        ),
        for (final e in entries)
          Dismissible(
            key: ValueKey(e.id),
            direction: DismissDirection.endToStart,
            background: Container(
              color: cs.error,
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Icon(Icons.delete, color: cs.onError, size: 18),
            ),
            onDismissed: (_) =>
                ref.read(mealPlanOpsProvider.notifier).deleteEntry(e.id),
            child: ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
              dense: true,
              leading: Icon(
                e.recipeId != null
                    ? Icons.menu_book_outlined
                    : e.dishId != null
                        ? Icons.restaurant_outlined
                        : Icons.fastfood_outlined,
                size: 18,
                color: cs.onSurfaceVariant,
              ),
              title: Text(e.entryName,
                  style: const TextStyle(fontSize: 13)),
              subtitle: Text(
                '${_fmt(e.servings)} Portion'
                '${e.kcalPerServing != null ? ' · ${NumberFormat("##0", "de_DE").format(e.kcalPerServing! * e.servings)} kcal' : ''}',
                style: TextStyle(
                    fontSize: 11, color: cs.onSurfaceVariant),
              ),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline, size: 16),
                visualDensity: VisualDensity.compact,
                onPressed: () =>
                    ref.read(mealPlanOpsProvider.notifier).deleteEntry(e.id),
              ),
            ),
          ),
      ],
    );
  }
}

// ── Add entry bottom sheet ────────────────────────────────────────────────────

class _AddMealPlanEntrySheet extends ConsumerStatefulWidget {
  final DateTime date;
  final String? initialMealTypeId;

  const _AddMealPlanEntrySheet(
      {required this.date, this.initialMealTypeId});

  @override
  ConsumerState<_AddMealPlanEntrySheet> createState() =>
      _AddMealPlanEntrySheetState();
}

class _AddMealPlanEntrySheetState
    extends ConsumerState<_AddMealPlanEntrySheet> {
  late DateTime _date;
  String? _mealTypeId;
  final _servingsCtrl = TextEditingController(text: '1');
  bool _saving = false;

  // Selected item from food search
  FoodSearchResult? _selected;

  @override
  void initState() {
    super.initState();
    _date = widget.date;
    _mealTypeId = widget.initialMealTypeId;
  }

  @override
  void dispose() {
    _servingsCtrl.dispose();
    super.dispose();
  }

  double? get _kcalPerServing {
    final sel = _selected;
    if (sel == null) return null;
    if (sel.recipeKcalTotal != null) return sel.recipeKcalTotal;
    if (sel.caloriesPer100g != null && sel.servingSizeG != null) {
      return sel.caloriesPer100g! * sel.servingSizeG! / 100;
    }
    return null;
  }

  Future<void> _save() async {
    final sel = _selected;
    if (sel == null) return;
    final servings =
        double.tryParse(_servingsCtrl.text.replaceAll(',', '.')) ?? 1.0;
    setState(() => _saving = true);
    try {
      await ref.read(mealPlanOpsProvider.notifier).addEntry(
            date: DateTime(_date.year, _date.month, _date.day),
            mealTypeId: _mealTypeId,
            recipeId: sel.source == 'recipe' ? sel.itemId : null,
            dishId: sel.source == 'meal' ? sel.itemId : null,
            itemId: (sel.source == 'local' || sel.source == 'off' ||
                    sel.source == 'barcode')
                ? sel.itemId
                : null,
            entryName: sel.productName,
            servings: servings,
            kcalPerServing: _kcalPerServing,
          );
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final mealTypes = ref.watch(mealTypesProvider).valueOrNull ?? [];

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 12, 16, bottom + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Handle
          Center(
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: cs.onSurfaceVariant.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text('Mahlzeit hinzufügen',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),

          // Date + meal type row
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.calendar_today, size: 16),
                  label: Text(DateFormat('dd.MM.yyyy', 'de_DE').format(_date)),
                  onPressed: () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: _date,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2030),
                    );
                    if (d != null) setState(() => _date = d);
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<String?>(
                  initialValue: _mealTypeId,
                  decoration: const InputDecoration(
                    labelText: 'Mahlzeit',
                    border: OutlineInputBorder(),
                    isDense: true,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  items: [
                    const DropdownMenuItem(
                        value: null, child: Text('— keine —')),
                    ...mealTypes.map((mt) =>
                        DropdownMenuItem(value: mt.id, child: Text(mt.name))),
                  ],
                  onChanged: (v) => setState(() => _mealTypeId = v),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Food picker
          OutlinedButton.icon(
            icon: Icon(
              _selected != null ? Icons.check_circle : Icons.search,
              size: 18,
            ),
            label: Text(
              _selected != null ? _selected!.productName : 'Lebensmittel / Rezept wählen…',
              overflow: TextOverflow.ellipsis,
            ),
            onPressed: () async {
              final result = await showModalBottomSheet<FoodSearchResult>(
                context: context,
                isScrollControlled: true,
                useSafeArea: true,
                builder: (_) => const _MealPlanFoodPicker(),
              );
              if (result != null) setState(() => _selected = result);
            },
          ),

          if (_selected != null) ...[
            const SizedBox(height: 8),
            // Servings
            TextFormField(
              controller: _servingsCtrl,
              decoration: const InputDecoration(
                labelText: 'Portionen',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
            ),
            if (_kcalPerServing != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '≈ ${NumberFormat("##0", "de_DE").format(_kcalPerServing! * (double.tryParse(_servingsCtrl.text) ?? 1))} kcal',
                  style: TextStyle(
                      fontSize: 12, color: cs.onSurfaceVariant),
                ),
              ),
          ],

          const SizedBox(height: 16),
          FilledButton(
            onPressed:
                (_selected == null || _saving) ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 16, height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Text('Hinzufügen'),
          ),
        ],
      ),
    );
  }
}

// ── Food picker (inline search inside plan sheet) ────────────────────────────

class _MealPlanFoodPicker extends ConsumerStatefulWidget {
  const _MealPlanFoodPicker();

  @override
  ConsumerState<_MealPlanFoodPicker> createState() =>
      _MealPlanFoodPickerState();
}

class _MealPlanFoodPickerState
    extends ConsumerState<_MealPlanFoodPicker> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollCtrl) {
        return Column(
          children: [
            // Handle + search
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Column(
                children: [
                  Center(
                    child: Container(
                      width: 40, height: 4,
                      decoration: BoxDecoration(
                        color: cs.onSurfaceVariant.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _searchCtrl,
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: 'Suchen…',
                      prefixIcon: const Icon(Icons.search),
                      border: const OutlineInputBorder(),
                      isDense: true,
                      suffixIcon: _query.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: () {
                                _searchCtrl.clear();
                                setState(() => _query = '');
                              },
                            )
                          : null,
                    ),
                    onChanged: (v) => setState(() => _query = v),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _MealPlanSearchResults(
                query: _query,
                scrollCtrl: scrollCtrl,
                onPick: (r) => Navigator.of(context).pop(r),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _MealPlanSearchResults extends ConsumerWidget {
  final String query;
  final ScrollController scrollCtrl;
  final void Function(FoodSearchResult) onPick;

  const _MealPlanSearchResults(
      {required this.query,
      required this.scrollCtrl,
      required this.onPick});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(databaseProvider);
    if (db == null) return const SizedBox.shrink();

    return FutureBuilder(
      future: _search(db, query),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final results = snap.data ?? [];
        if (results.isEmpty) {
          return Center(
            child: Text(
              query.isEmpty
                  ? 'Tippe um Rezepte, Gerichte oder Artikel zu suchen.'
                  : 'Keine Ergebnisse für „$query".',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          );
        }
        return ListView.builder(
          controller: scrollCtrl,
          itemCount: results.length,
          itemBuilder: (context, i) {
            final r = results[i];
            return ListTile(
              leading: CircleAvatar(
                radius: 16,
                backgroundColor:
                    r.source == 'recipe' || r.source == 'meal'
                        ? Theme.of(context).colorScheme.tertiaryContainer
                        : Theme.of(context).colorScheme.primaryContainer,
                child: Icon(
                  r.source == 'recipe'
                      ? Icons.menu_book_outlined
                      : r.source == 'meal'
                          ? Icons.restaurant_outlined
                          : Icons.fastfood_outlined,
                  size: 16,
                  color: r.source == 'recipe' || r.source == 'meal'
                      ? Theme.of(context).colorScheme.onTertiaryContainer
                      : Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              ),
              title: Text(r.productName),
              subtitle: Text(
                r.source == 'recipe'
                    ? 'Rezept'
                    : r.source == 'meal'
                        ? 'Gericht'
                        : r.brand ?? 'Lebensmittel',
                style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
              onTap: () => onPick(r),
            );
          },
        );
      },
    );
  }

  Future<List<FoodSearchResult>> _search(AppDatabase db, String q) async {
    final lower = q.toLowerCase().trim();
    final results = <FoodSearchResult>[];

    // Recipes
    final recipes = await db.searchRecipes(lower).first;
    for (final r in recipes) {
      results.add(FoodSearchResult(
        productName: r.name,
        itemId: r.id,
        source: 'recipe',
        recipeKcalTotal: r.caloriesPerServing,
        recipeProteinTotal: r.proteinPerServing,
        recipeCarbsTotal: r.carbsPerServing,
        recipeFatTotal: r.fatPerServing,
        servingUnit: r.servingUnit,
      ));
    }

    // Standard meals
    final meals = await db.searchMeals(lower);
    for (final m in meals) {
      results.add(FoodSearchResult(
        productName: m.name,
        itemId: m.id,
        source: 'meal',
        recipeKcalTotal: m.kcalTotal,
        recipeProteinTotal: m.proteinG,
        recipeCarbsTotal: m.carbsG,
        recipeFatTotal: m.fatG,
        servingUnit: m.servingUnit,
      ));
    }

    // Items (food)
    final items = await db.searchItems(lower).first;
    for (final item in items) {
      results.add(FoodSearchResult(
        productName: item.name,
        brand: item.brand,
        ean: item.ean,
        itemId: item.id,
        caloriesPer100g: item.caloriesPer100g,
        proteinPer100g: item.proteinPer100g,
        carbsPer100g: item.carbsPer100g,
        fatPer100g: item.fatPer100g,
        fiberPer100g: item.fiberPer100g,
        servingSizeG: item.servingSizeG,
        source: 'local',
      ));
    }

    return results;
  }
}

// ── Ingredient check sheet ────────────────────────────────────────────────────

class _IngredientCheckSheet extends ConsumerWidget {
  final List<({String? itemId, String name, double qty, String unit})> needs;
  final String weekLabel;

  const _IngredientCheckSheet(
      {required this.needs, required this.weekLabel});

  String _fmt(double v) =>
      v == v.truncateToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final stockMap = ref.watch(itemStockMapProvider).valueOrNull ?? {};

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      expand: false,
      builder: (ctx, scrollCtrl) {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40, height: 4,
                      decoration: BoxDecoration(
                        color: cs.onSurfaceVariant.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text('Zutaten KW $weekLabel',
                      style:
                          Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    'Benötigte Zutaten für die geplanten Mahlzeiten.',
                    style: TextStyle(
                        fontSize: 13, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: needs.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(
                          'Keine Zutaten für diese Woche geplant.',
                          style:
                              TextStyle(color: cs.onSurfaceVariant),
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: scrollCtrl,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: needs.length,
                      itemBuilder: (context, i) {
                        final need = needs[i];
                        final states =
                            need.itemId != null
                                ? (stockMap[need.itemId!] ?? [])
                                : <ItemState>[];
                        final inStock = states.fold(
                            0.0,
                            (sum, s) => sum + s.currentQuantity);
                        final hasStock = inStock > 0;

                        return ListTile(
                          leading: Icon(
                            hasStock
                                ? Icons.check_circle_outline
                                : Icons.radio_button_unchecked,
                            color: hasStock
                                ? cs.primary
                                : cs.onSurfaceVariant,
                            size: 20,
                          ),
                          title: Text(need.name),
                          subtitle: Text(
                            'Benötigt: ${_fmt(need.qty)} ${need.unit}'
                            '${hasStock ? ' · Im Bestand: ${_fmt(inStock)}' : ''}',
                            style: TextStyle(
                                fontSize: 12,
                                color: cs.onSurfaceVariant),
                          ),
                          trailing: !hasStock
                              ? Chip(
                                  label: Text(
                                    'Fehlt',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: cs.onErrorContainer),
                                  ),
                                  backgroundColor: cs.errorContainer,
                                  visualDensity: VisualDensity.compact,
                                  padding: EdgeInsets.zero,
                                )
                              : null,
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}
