import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../db/database.dart';
import '../../providers/settings_provider.dart';
import '../../providers/vault_provider.dart';
import '../../screens/scanner/barcode_scanner_screen.dart';
import '../../services/open_food_facts_service.dart';

/// The result of picking a product in [FoodSearchSheet].
class FoodSearchResult {
  final String productName;
  final String? brand;
  final String? ean;
  final String? itemId;
  final double? caloriesPer100g;
  final double? proteinPer100g;
  final double? carbsPer100g;
  final double? fatPer100g;
  final double? fiberPer100g;
  /// For items/recipes: the default serving size in grams (pre-fills quantity).
  final double? servingSizeG;
  /// For recipes: the total nutrition for the full recipe (1 serving).
  final double? recipeKcalTotal;
  final double? recipeProteinTotal;
  final double? recipeCarbsTotal;
  final double? recipeFatTotal;
  final bool isRecipe;
  /// For recipes/meals: how the user-facing serving unit is labelled
  /// ('Portion' | 'Stück' | 'g' | 'ml' | custom). Defaults to 'Portion'.
  final String servingUnit;
  final String? nutritionRefUnit; // 'g' | 'ml' for local items
  final String source; // 'local' | 'off' | 'recipe' | 'meal' | 'manual'

  const FoodSearchResult({
    required this.productName,
    this.brand,
    this.ean,
    this.itemId,
    this.caloriesPer100g,
    this.proteinPer100g,
    this.carbsPer100g,
    this.fatPer100g,
    this.fiberPer100g,
    this.servingSizeG,
    this.recipeKcalTotal,
    this.recipeProteinTotal,
    this.recipeCarbsTotal,
    this.recipeFatTotal,
    this.isRecipe = false,
    this.servingUnit = 'Portion',
    this.nutritionRefUnit,
    required this.source,
  });
}

/// Bottom sheet for searching food. Searches local items, recipes and the
/// OpenFoodFacts API in parallel. Also supports barcode scanning.
/// Pops with a [FoodSearchResult] or `null` on cancel.
///
/// [mealTypeId] filters the history tabs to the same meal slot.
/// [onMultiAdd] is called when the user selects multiple history entries to
/// add at once; the callback receives the list of selected [NutritionLog]s
/// and is responsible for saving them and closing this sheet.
class FoodSearchSheet extends ConsumerStatefulWidget {
  final String? mealTypeId;
  final Future<void> Function(List<NutritionLog>)? onMultiAdd;
  const FoodSearchSheet({super.key, this.mealTypeId, this.onMultiAdd});

  @override
  ConsumerState<FoodSearchSheet> createState() => _FoodSearchSheetState();
}

class _FoodSearchSheetState extends ConsumerState<FoodSearchSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;
  final _controller = TextEditingController();
  Timer? _debounce;

  bool _loading = false;
  List<_SearchItem> _results = [];
  String? _error;
  // null = all sources; 'local' | 'recipe' | 'off' = filtered
  String? _sourceFilter;

  // History tabs
  bool _historyLoading = true;
  List<NutritionLog> _recentLogs = [];
  List<NutritionLog> _frequentLogs = [];
  List<NutritionLog> _allMealsLogs = [];
  bool _allMealsExpanded = false;

  // Multi-select (history tabs)
  final Set<String> _selectedIds = {};
  // Quick lookup by log ID across all history lists
  final Map<String, NutritionLog> _logsById = {};

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    _loadHistory();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    final db = ref.read(databaseProvider);
    if (db == null) {
      if (mounted) setState(() => _historyLoading = false);
      return;
    }
    final settings = ref.read(settingsProvider).valueOrNull;
    final recentLimit = settings?.historyRecentCount ?? 20;
    final frequentLimit = settings?.historyFrequentCount ?? 20;
    final allMealsLimit = settings?.historyAllMealsCount ?? 10;

    final results = await Future.wait([
      db.recentlyLoggedFoods(mealTypeId: widget.mealTypeId, limit: recentLimit),
      db.mostFrequentlyLoggedFoods(mealTypeId: widget.mealTypeId, limit: frequentLimit),
      db.recentlyLoggedFoods(limit: allMealsLimit), // all meal types
    ]);
    if (mounted) {
      final recent = results[0];
      final frequent = results[1];
      final allMeals = results[2];
      // Build lookup map
      final byId = <String, NutritionLog>{};
      for (final l in [...recent, ...frequent, ...allMeals]) {
        byId[l.id] = l;
      }
      setState(() {
        _recentLogs = recent;
        _frequentLogs = frequent;
        _allMealsLogs = allMeals;
        _logsById.addAll(byId);
        _historyLoading = false;
      });
    }
  }

  void _onChanged(String query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(query));
  }

  Future<void> _search(String query) async {
    final q = query.trim();
    if (q.isEmpty) {
      setState(() { _results = []; _error = null; });
      return;
    }
    setState(() { _loading = true; _error = null; });

    try {
      final db = ref.read(databaseProvider);
      final results = await Future.wait([
        _searchLocal(db, q),
        _searchRecipes(db, q),
        _searchMeals(db, q),
        OpenFoodFactsService.searchByName(q, pageSize: 20),
      ]);

      final localItems = results[0] as List<_SearchItem>;
      final recipeItems = results[1] as List<_SearchItem>;
      final mealItems = results[2] as List<_SearchItem>;
      final offProducts = (results[3] as List<OFFProduct>)
          .map(_SearchItem.fromOff)
          .toList();

      final localNames =
          localItems.map((i) => i.name.toLowerCase().trim()).toSet();
      final localEans =
          localItems.map((i) => i.ean).whereType<String>().toSet();

      final seen = <String>{};
      final merged = <_SearchItem>[];
      for (final item
          in [...localItems, ...recipeItems, ...mealItems, ...offProducts]) {
        if (item.source == 'off') {
          if (item.ean != null && localEans.contains(item.ean)) continue;
          if (localNames.contains(item.name.toLowerCase().trim())) continue;
        }
        final key = item.ean ?? '${item.source}:${item.name}';
        if (seen.add(key)) merged.add(item);
      }

      setState(() { _results = merged; _loading = false; });
    } catch (_) {
      setState(() { _error = 'Suche fehlgeschlagen'; _loading = false; });
    }
  }

  Future<List<_SearchItem>> _searchLocal(AppDatabase? db, String q) async {
    if (db == null) return [];
    final rows = await db.searchItems(q).first;
    return rows.map(_SearchItem.fromItem).toList();
  }

  Future<List<_SearchItem>> _searchRecipes(AppDatabase? db, String q) async {
    if (db == null) return [];
    final lower = q.toLowerCase();
    final all = await db.select(db.recipes).get();
    final recipes = all
        .where((r) => r.name.toLowerCase().contains(lower))
        .toList();
    final items = <_SearchItem>[];
    for (final r in recipes) {
      final nutrition = await db.computeRecipeNutrition(r.id);
      items.add(_SearchItem.fromRecipe(r, nutrition));
    }
    return items;
  }

  Future<List<_SearchItem>> _searchMeals(AppDatabase? db, String q) async {
    if (db == null) return [];
    final lower = q.toLowerCase();
    final all = await db.watchAllMeals().first;
    final meals = all.where((m) => m.name.toLowerCase().contains(lower)).toList();
    final items = <_SearchItem>[];
    for (final m in meals) {
      final nutrition = await db.computeMealNutrition(m.id);
      items.add(_SearchItem.fromMeal(m, nutrition));
    }
    return items;
  }

  Future<void> _scanBarcode() async {
    final ean = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const BarcodeScannerScreen()),
    );
    if (ean == null || !mounted) return;
    _controller.text = ean;
    setState(() { _loading = true; _error = null; _results = []; });
    try {
      final db = ref.read(databaseProvider);
      final localItem = await db?.itemByEan(ean);
      if (localItem != null) {
        setState(() { _loading = false; });
        _pick(_SearchItem.fromItem(localItem));
        return;
      }
      final product = await OpenFoodFactsService.lookup(ean);
      if (!mounted) return;
      if (product != null) {
        setState(() { _loading = false; });
        _pick(_SearchItem.fromOff(product));
      } else {
        setState(() {
          _loading = false;
          _error = 'Produkt nicht gefunden — bitte manuell eingeben.';
        });
      }
    } catch (_) {
      if (mounted) setState(() { _loading = false; _error = 'Suche fehlgeschlagen'; });
    }
  }

  void _pick(_SearchItem item) {
    Navigator.of(context).pop(FoodSearchResult(
      productName: item.name,
      brand: item.brand,
      ean: item.ean,
      itemId: item.itemId,
      caloriesPer100g: item.caloriesPer100g,
      proteinPer100g: item.proteinPer100g,
      carbsPer100g: item.carbsPer100g,
      fatPer100g: item.fatPer100g,
      fiberPer100g: item.fiberPer100g,
      servingSizeG: item.servingSizeG,
      recipeKcalTotal: item.recipeKcalTotal,
      recipeProteinTotal: item.recipeProteinTotal,
      recipeCarbsTotal: item.recipeCarbsTotal,
      recipeFatTotal: item.recipeFatTotal,
      isRecipe: item.source == 'recipe' || item.source == 'meal',
      servingUnit: item.servingUnit,
      nutritionRefUnit: item.nutritionRefUnit,
      source: item.source,
    ));
  }

  void _pickManual() {
    final name = _controller.text.trim();
    Navigator.of(context).pop(FoodSearchResult(
      productName: name.isEmpty ? 'Manueller Eintrag' : name,
      source: 'manual',
    ));
  }

  /// Picks a food from a history log entry, loading full item data when
  /// available for accurate per-100g nutritional values.
  Future<void> _pickFromLog(NutritionLog log) async {
    final db = ref.read(databaseProvider);
    if (db == null) return;

    if (log.itemId != null) {
      switch (log.source) {
        case 'local':
          final item = await db.itemById(log.itemId!);
          if (item != null) { _pick(_SearchItem.fromItem(item)); return; }
        case 'recipe':
          final recipe = await db.recipeById(log.itemId!);
          if (recipe != null) {
            final nutrition = await db.computeRecipeNutrition(log.itemId!);
            _pick(_SearchItem.fromRecipe(recipe, nutrition));
            return;
          }
        case 'meal':
          final meals = await db.watchAllMeals().first;
          final meal = meals.where((m) => m.id == log.itemId).firstOrNull;
          if (meal != null) {
            final nutrition = await db.computeMealNutrition(log.itemId!);
            _pick(_SearchItem.fromMeal(meal, nutrition));
            return;
          }
      }
    }

    // Fallback: reconstruct from log data
    double? cal100;
    if (log.quantityG > 0 && log.kcal != null) {
      cal100 = log.kcal! * 100 / log.quantityG;
    }
    _pick(_SearchItem(
      name: log.productName,
      brand: log.brand,
      itemId: log.itemId,
      caloriesPer100g: cal100,
      proteinPer100g: (log.proteinG != null && log.quantityG > 0)
          ? log.proteinG! * 100 / log.quantityG
          : null,
      carbsPer100g: (log.carbsG != null && log.quantityG > 0)
          ? log.carbsG! * 100 / log.quantityG
          : null,
      fatPer100g: (log.fatG != null && log.quantityG > 0)
          ? log.fatG! * 100 / log.quantityG
          : null,
      servingSizeG: log.quantityG > 0 ? log.quantityG : null,
      servingUnit: log.displayUnit,
      source: log.source,
    ));
  }

  List<_SearchItem> get _filteredResults {
    if (_sourceFilter == null) return _results;
    return _results.where((r) => r.source == _sourceFilter).toList();
  }

  int _countBySource(String source) =>
      _results.where((r) => r.source == source).length;

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.of(context).viewInsets.bottom;
    final cs = Theme.of(context).colorScheme;

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.85,
      child: Padding(
        padding: EdgeInsets.only(bottom: inset),
        child: Column(
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                margin: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: Theme.of(context).dividerColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Row(
                children: [
                  Text('Lebensmittel',
                      style: Theme.of(context).textTheme.titleLarge),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(null),
                    child: const Text('Abbrechen'),
                  ),
                ],
              ),
            ),
            // ── Tab bar ───────────────────────────────────────────────────
            TabBar(
              controller: _tabCtrl,
              tabs: const [
                Tab(text: 'Suche'),
                Tab(text: 'Kürzlich'),
                Tab(text: 'Häufig'),
              ],
            ),
            // ── Search field (Suche tab only) ─────────────────────────────
            AnimatedBuilder(
              animation: _tabCtrl,
              builder: (_, child) => _tabCtrl.index == 0
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                      child: TextField(
                        controller: _controller,
                        autofocus: true,
                        decoration: InputDecoration(
                          hintText: 'Name oder EAN …',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_loading)
                                const Padding(
                                  padding: EdgeInsets.all(12),
                                  child: SizedBox(
                                    width: 20, height: 20,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  ),
                                ),
                              IconButton(
                                icon: const Icon(Icons.qr_code_scanner),
                                tooltip: 'Barcode scannen',
                                onPressed: _scanBarcode,
                              ),
                            ],
                          ),
                          border: const OutlineInputBorder(),
                        ),
                        onChanged: _onChanged,
                        onSubmitted: _search,
                        textInputAction: TextInputAction.search,
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Text(_error!, style: TextStyle(color: cs.error)),
              ),
            Expanded(
              child: TabBarView(
                controller: _tabCtrl,
                children: [
                  _buildSearchTab(cs),
                  _buildHistoryTabWithAllMeals(_recentLogs, cs),
                  _buildHistoryTabWithAllMeals(_frequentLogs, cs),
                ],
              ),
            ),
            // ── Multi-add button ──────────────────────────────────────────
            if (_selectedIds.isNotEmpty && widget.onMultiAdd != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: FilledButton.icon(
                  icon: const Icon(Icons.add),
                  label: Text('${_selectedIds.length} Einträge hinzufügen'),
                  onPressed: _confirmMultiAdd,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(44),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchTab(ColorScheme cs) {
    final filtered = _filteredResults;

    if (_results.isEmpty && !_loading) {
      return _EmptyHint(
        hasQuery: _controller.text.trim().isNotEmpty,
        onManual: _pickManual,
      );
    }

    return Column(
      children: [
        // ── Source filter chips ──────────────────────────────────────────
        if (_results.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _FilterChip(
                    label: 'Alle (${_results.length})',
                    selected: _sourceFilter == null,
                    onSelected: () => setState(() => _sourceFilter = null),
                    cs: cs,
                  ),
                  const SizedBox(width: 6),
                  if (_countBySource('local') > 0) ...[
                    _FilterChip(
                      label: 'Lokal (${_countBySource('local')})',
                      selected: _sourceFilter == 'local',
                      onSelected: () =>
                          setState(() => _sourceFilter = 'local'),
                      cs: cs,
                    ),
                    const SizedBox(width: 6),
                  ],
                  if (_countBySource('recipe') > 0) ...[
                    _FilterChip(
                      label: 'Rezepte (${_countBySource('recipe')})',
                      selected: _sourceFilter == 'recipe',
                      onSelected: () =>
                          setState(() => _sourceFilter = 'recipe'),
                      cs: cs,
                    ),
                    const SizedBox(width: 6),
                  ],
                  if (_countBySource('meal') > 0) ...[
                    _FilterChip(
                      label: 'Gerichte (${_countBySource('meal')})',
                      selected: _sourceFilter == 'meal',
                      onSelected: () =>
                          setState(() => _sourceFilter = 'meal'),
                      cs: cs,
                    ),
                    const SizedBox(width: 6),
                  ],
                  if (_countBySource('off') > 0)
                    _FilterChip(
                      label: 'Online (${_countBySource('off')})',
                      selected: _sourceFilter == 'off',
                      onSelected: () =>
                          setState(() => _sourceFilter = 'off'),
                      cs: cs,
                    ),
                ],
              ),
            ),
          ),
        Expanded(
          child: ListView.builder(
            itemCount: filtered.length + 1,
            itemBuilder: (ctx, i) {
              if (i == filtered.length) {
                return ListTile(
                  leading: const Icon(Icons.edit_outlined),
                  title: const Text('Manuell eingeben'),
                  onTap: _pickManual,
                );
              }
              final item = filtered[i];
              return _SearchItemTile(item: item, cs: cs, onTap: () => _pick(item));
            },
          ),
        ),
      ],
    );
  }

  Widget _buildHistoryTabWithAllMeals(List<NutritionLog> logs, ColorScheme cs) {
    if (_historyLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    // IDs already shown in the main list (to exclude from "Alle Mahlzeiten")
    final shownIds = logs.map((l) => l.id).toSet();

    return ListView(
      children: [
        if (logs.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.history, size: 48, color: cs.outline),
                  const SizedBox(height: 12),
                  Text(
                    'Noch keine Einträge vorhanden.',
                    style: TextStyle(color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          )
        else
          ...logs.map((log) => _HistoryLogTile(
                log: log,
                cs: cs,
                selected: _selectedIds.contains(log.id),
                onToggleSelect: widget.onMultiAdd != null
                    ? () => setState(() {
                          if (_selectedIds.contains(log.id)) {
                            _selectedIds.remove(log.id);
                          } else {
                            _selectedIds.add(log.id);
                          }
                        })
                    : null,
                onTap: () => _pickFromLog(log),
              )),
        // ── Alle Mahlzeiten (expandable) ────────────────────────────────
        const SizedBox(height: 8),
        _AllMealsSection(
          logs: _allMealsLogs.where((l) => !shownIds.contains(l.id)).toList(),
          cs: cs,
          expanded: _allMealsExpanded,
          onToggle: () =>
              setState(() => _allMealsExpanded = !_allMealsExpanded),
          selectedIds: _selectedIds,
          canSelect: widget.onMultiAdd != null,
          onToggleSelect: (id) => setState(() {
            if (_selectedIds.contains(id)) {
              _selectedIds.remove(id);
            } else {
              _selectedIds.add(id);
            }
          }),
          onPickLog: _pickFromLog,
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Future<void> _confirmMultiAdd() async {
    final selected = _selectedIds
        .map((id) => _logsById[id])
        .whereType<NutritionLog>()
        .toList();
    if (selected.isEmpty) return;
    await widget.onMultiAdd!(selected);
  }
}

// ─── History log tile (with optional checkbox) ────────────────────────────────

class _HistoryLogTile extends StatelessWidget {
  final NutritionLog log;
  final ColorScheme cs;
  final bool selected;
  final VoidCallback? onToggleSelect;
  final VoidCallback onTap;

  const _HistoryLogTile({
    required this.log,
    required this.cs,
    required this.selected,
    required this.onToggleSelect,
    required this.onTap,
  });

  static (Color, Color, IconData) _colors(String source, ColorScheme cs) =>
      switch (source) {
        'recipe' => (cs.tertiaryContainer, cs.onTertiaryContainer,
            Icons.menu_book_outlined),
        'meal' => (
            cs.tertiaryContainer,
            cs.onTertiaryContainer,
            Icons.dinner_dining
          ),
        'local' => (
            cs.primaryContainer,
            cs.onPrimaryContainer,
            Icons.inventory_2_outlined
          ),
        _ => (cs.secondaryContainer, cs.onSecondaryContainer, Icons.public),
      };

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat.decimalPattern('de_DE')..maximumFractionDigits = 1;
    final (bgColor, fgColor, icon) = _colors(log.source, cs);

    final portionStr = '${fmt.format(log.quantityG)} ${log.displayUnit}';
    final kcalStr = log.kcal != null
        ? '${log.kcal!.toStringAsFixed(0)} kcal'
        : null;
    final subtitle = [log.brand, portionStr, kcalStr]
        .whereType<String>()
        .join(' · ');

    return ListTile(
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (onToggleSelect != null)
            SizedBox(
              width: 24,
              child: Checkbox(
                value: selected,
                onChanged: (_) => onToggleSelect!(),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
            ),
          CircleAvatar(
            backgroundColor: selected ? cs.primary : bgColor,
            child: Icon(icon, size: 18,
                color: selected ? cs.onPrimary : fgColor),
          ),
        ],
      ),
      title: Text(log.productName),
      subtitle: Text(subtitle, style: TextStyle(color: cs.onSurfaceVariant)),
      onTap: onToggleSelect != null ? () => onToggleSelect!() : onTap,
      onLongPress: onToggleSelect != null ? onTap : null,
    );
  }
}

// ─── Alle Mahlzeiten expandable section ──────────────────────────────────────

class _AllMealsSection extends StatelessWidget {
  final List<NutritionLog> logs;
  final ColorScheme cs;
  final bool expanded;
  final VoidCallback onToggle;
  final Set<String> selectedIds;
  final bool canSelect;
  final void Function(String id) onToggleSelect;
  final void Function(NutritionLog) onPickLog;

  const _AllMealsSection({
    required this.logs,
    required this.cs,
    required this.expanded,
    required this.onToggle,
    required this.selectedIds,
    required this.canSelect,
    required this.onToggleSelect,
    required this.onPickLog,
  });

  @override
  Widget build(BuildContext context) {
    if (logs.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Icon(Icons.restaurant_menu,
                    size: 16, color: cs.onSurfaceVariant),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Alle Mahlzeiten (${logs.length})',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurfaceVariant),
                  ),
                ),
                Icon(expanded ? Icons.expand_less : Icons.expand_more,
                    size: 18, color: cs.onSurfaceVariant),
              ],
            ),
          ),
        ),
        if (expanded)
          ...logs.map((log) => _HistoryLogTile(
                log: log,
                cs: cs,
                selected: selectedIds.contains(log.id),
                onToggleSelect: canSelect ? () => onToggleSelect(log.id) : null,
                onTap: () => onPickLog(log),
              )),
      ],
    );
  }
}

// ─── Search result tile ───────────────────────────────────────────────────────

class _SearchItemTile extends StatelessWidget {
  final _SearchItem item;
  final ColorScheme cs;
  final VoidCallback onTap;

  const _SearchItemTile({
    required this.item,
    required this.cs,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final (bgColor, fgColor, icon) = switch (item.source) {
      'recipe' => (
          cs.tertiaryContainer,
          cs.onTertiaryContainer,
          Icons.menu_book_outlined
        ),
      'meal' => (
          cs.tertiaryContainer,
          cs.onTertiaryContainer,
          Icons.dinner_dining
        ),
      'local' => (
          cs.primaryContainer,
          cs.onPrimaryContainer,
          Icons.inventory_2_outlined
        ),
      _ => (cs.secondaryContainer, cs.onSecondaryContainer, Icons.public),
    };
    final refUnit = item.nutritionRefUnit ?? 'g';
    final subtitle = [
      if (item.brand != null) item.brand!,
      if (item.caloriesPer100g != null)
        '${item.caloriesPer100g!.toStringAsFixed(0)} kcal/100$refUnit'
      else if (item.recipeKcalTotal != null)
        '${item.recipeKcalTotal!.toStringAsFixed(0)} kcal gesamt',
    ].join(' · ');
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: bgColor,
        child: Icon(icon, size: 18, color: fgColor),
      ),
      title: Text(item.name),
      subtitle: subtitle.isNotEmpty
          ? Text(subtitle, style: TextStyle(color: cs.onSurfaceVariant))
          : null,
      onTap: onTap,
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onSelected;
  final ColorScheme cs;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onSelected,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) => FilterChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onSelected(),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        visualDensity: VisualDensity.compact,
      );
}

class _EmptyHint extends StatelessWidget {
  final bool hasQuery;
  final VoidCallback onManual;
  const _EmptyHint({required this.hasQuery, required this.onManual});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search, size: 48, color: cs.outline),
            const SizedBox(height: 12),
            Text(
              hasQuery
                  ? 'Keine Ergebnisse — Suche läuft oder manuell eingeben.'
                  : 'Produktname eintippen …',
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
            if (hasQuery) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: onManual,
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Manuell eingeben'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Internal search result ───────────────────────────────────────────────────

class _SearchItem {
  final String name;
  final String? brand;
  final String? ean;
  final String? itemId;
  final double? caloriesPer100g;
  final double? proteinPer100g;
  final double? carbsPer100g;
  final double? fatPer100g;
  final double? fiberPer100g;
  final double? servingSizeG;
  final double? recipeKcalTotal;
  final double? recipeProteinTotal;
  final double? recipeCarbsTotal;
  final double? recipeFatTotal;
  final String servingUnit;
  final String? nutritionRefUnit; // 'g' | 'ml' — from local items
  final String source;

  const _SearchItem({
    required this.name,
    this.brand,
    this.ean,
    this.itemId,
    this.caloriesPer100g,
    this.proteinPer100g,
    this.carbsPer100g,
    this.fatPer100g,
    this.fiberPer100g,
    this.servingSizeG,
    this.recipeKcalTotal,
    this.recipeProteinTotal,
    this.recipeCarbsTotal,
    this.recipeFatTotal,
    this.servingUnit = 'Portion',
    this.nutritionRefUnit,
    required this.source,
  });

  factory _SearchItem.fromItem(Item item) => _SearchItem(
        name: item.name,
        brand: item.brand,
        ean: item.ean,
        itemId: item.id,
        caloriesPer100g: item.caloriesPer100g,
        proteinPer100g: item.proteinPer100g,
        carbsPer100g: item.carbsPer100g,
        fatPer100g: item.fatPer100g,
        fiberPer100g: item.fiberPer100g,
        servingSizeG: item.servingSizeG,
        nutritionRefUnit: item.nutritionRefUnit,
        source: 'local',
      );

  factory _SearchItem.fromOff(OFFProduct p) => _SearchItem(
        name: p.name ?? p.ean,
        brand: p.brand,
        ean: p.ean,
        caloriesPer100g: p.calories,
        proteinPer100g: p.protein,
        carbsPer100g: p.carbs,
        fatPer100g: p.fat,
        fiberPer100g: p.fiber,
        servingSizeG: p.servingSizeG,
        source: 'off',
      );

  factory _SearchItem.fromRecipe(Recipe r, RecipeNutritionData? nutrition) {
    final servingSizeG = (nutrition != null &&
            nutrition.totalWeightG > 0 &&
            r.servings > 0)
        ? nutrition.totalWeightG / r.servings
        : null;
    return _SearchItem(
      name: r.name,
      itemId: r.id,
      caloriesPer100g: nutrition?.caloriesPer100g,
      proteinPer100g: nutrition?.proteinPer100g,
      carbsPer100g: nutrition?.carbsPer100g,
      fatPer100g: nutrition?.fatPer100g,
      fiberPer100g: nutrition?.fiberPer100g,
      servingSizeG: servingSizeG,
      recipeKcalTotal: nutrition?.kcal ?? r.caloriesPerServing,
      recipeProteinTotal: nutrition?.proteinG ?? r.proteinPerServing,
      recipeCarbsTotal: nutrition?.carbsG ?? r.carbsPerServing,
      recipeFatTotal: nutrition?.fatG ?? r.fatPerServing,
      servingUnit: r.servingUnit,
      source: 'recipe',
    );
  }

  factory _SearchItem.fromMeal(StandardMeal m, RecipeNutritionData? nutrition) {
    return _SearchItem(
      name: m.name,
      itemId: m.id,
      caloriesPer100g: nutrition?.caloriesPer100g,
      proteinPer100g: nutrition?.proteinPer100g,
      carbsPer100g: nutrition?.carbsPer100g,
      fatPer100g: nutrition?.fatPer100g,
      fiberPer100g: nutrition?.fiberPer100g,
      servingSizeG: nutrition?.totalWeightG,
      recipeKcalTotal: nutrition?.kcal ?? m.kcalTotal,
      recipeProteinTotal: nutrition?.proteinG ?? m.proteinG,
      recipeCarbsTotal: nutrition?.carbsG ?? m.carbsG,
      recipeFatTotal: nutrition?.fatG ?? m.fatG,
      servingUnit: m.servingUnit,
      source: 'meal',
    );
  }
}
