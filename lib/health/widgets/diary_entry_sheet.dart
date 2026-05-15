import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../db/database.dart';
import '../../providers/inventory_provider.dart';
import '../../providers/units_provider.dart';
import '../../providers/vault_provider.dart';
import '../../utils/unit_deduct_utils.dart';
import '../providers/nutrition_provider.dart';
import 'food_search_sheet.dart';
import 'inventory_deduct_sheet.dart';

/// Bottom sheet for adding / editing one food diary entry.
///
/// Pass [editLog] to open in edit mode.
/// Pass [initialProduct] to pre-fill the food picker (e.g. from item detail).
/// Pops with `true` on successful save, `null` on cancel.
class DiaryEntrySheet extends ConsumerStatefulWidget {
  final String? initialMealTypeId;
  final DateTime? initialLoggedAt;
  final NutritionLog? editLog;
  final FoodSearchResult? initialProduct;
  /// When true the inventory was already deducted externally (e.g. via the
  /// quick-action Ausbuchen flow). Pre-unchecks the "Vom Bestand abbuchen"
  /// toggle so the user doesn't accidentally double-deduct.
  final bool deductAlreadyDone;

  const DiaryEntrySheet({
    super.key,
    this.initialMealTypeId,
    this.initialLoggedAt,
    this.editLog,
    this.initialProduct,
    this.deductAlreadyDone = false,
  });

  @override
  ConsumerState<DiaryEntrySheet> createState() => _DiaryEntrySheetState();
}

class _DiaryEntrySheetState extends ConsumerState<DiaryEntrySheet> {
  final _qtyController = TextEditingController();
  final _notesController = TextEditingController();
  final _kcalManual = TextEditingController();
  final _proteinManual = TextEditingController();
  final _carbsManual = TextEditingController();
  final _fatManual = TextEditingController();

  FoodSearchResult? _product;
  String? _mealTypeId;
  DateTime _loggedAt = DateTime.now();
  bool _saving = false;
  String _unit = 'g';

  // Inventory deduction context (loaded when a local item is selected)
  List<UnitDeductOption> _deductOpts = [];
  List<UnitConversion> _convs = [];
  List<InventoryEntry> _inventoryEntries = [];
  bool _hasInventory = false;
  late bool _doDeduct;
  String _consumptionReason = 'consumed';

  bool get _isEditMode => widget.editLog != null;

  bool get _hasPerHundredData => _product?.caloriesPer100g != null;

  /// Recipe/meal: always prefer qty × total over per-100g math (avoids
  /// rounding errors when some ingredients lack nutrition data).
  bool get _hasRecipeTotals =>
      _product != null &&
      _product!.isRecipe &&
      _product!.recipeKcalTotal != null;

  /// True when the current unit is a weight/volume unit (g, ml, kg, l, …).
  /// Used to switch recipe entries between serving-count and gram-based math.
  bool get _recipeUsesWeightUnit =>
      _product != null && _product!.isRecipe && _isWeightVolUnit(_unit);

  bool get _showManualMacros =>
      _product != null && !_hasPerHundredData && !_hasRecipeTotals;

  static bool _isWeightVolUnit(String unit) {
    final u = unit.toLowerCase().trim();
    return u == 'g' || u == 'gr' || u == 'gramm' ||
        u == 'kg' || u == 'kilogramm' ||
        u == 'ml' || u == 'milliliter' ||
        u == 'cl' || u == 'dl' ||
        u == 'l' || u == 'liter';
  }

  @override
  void initState() {
    super.initState();
    _doDeduct = !widget.deductAlreadyDone;
    _mealTypeId = widget.initialMealTypeId;
    _loggedAt = widget.initialLoggedAt ?? DateTime.now();

    final log = widget.editLog;
    if (log != null) {
      _mealTypeId = log.mealTypeId;
      _loggedAt = log.loggedAt;
      _unit = log.displayUnit;
      _qtyController.text = _fmtQty(log.quantityG);
      _notesController.text = log.notes ?? '';

      if (log.source == 'meal' || log.source == 'recipe') {
        if (_isWeightVolUnit(log.displayUnit) &&
            log.quantityG > 0 &&
            log.kcal != null) {
          // g/ml unit: quantityG = grams. Derive per-100g so qty editing scales.
          _product = FoodSearchResult(
            productName: log.productName,
            brand: log.brand,
            ean: log.ean,
            itemId: log.itemId,
            source: log.source,
            isRecipe: true,
            servingUnit: log.displayUnit,
            caloriesPer100g: log.kcal! / log.quantityG * 100,
            proteinPer100g: log.proteinG != null
                ? log.proteinG! / log.quantityG * 100
                : null,
            carbsPer100g: log.carbsG != null
                ? log.carbsG! / log.quantityG * 100
                : null,
            fatPer100g: log.fatG != null
                ? log.fatG! / log.quantityG * 100
                : null,
          );
        } else {
          // Portion/Stück: quantityG stores serving count.
          // Reconstruct per-serving totals so changing qty re-multiplies correctly.
          final servings = log.quantityG > 0 ? log.quantityG : 1.0;
          _product = FoodSearchResult(
            productName: log.productName,
            brand: log.brand,
            ean: log.ean,
            itemId: log.itemId,
            source: log.source,
            isRecipe: true,
            recipeKcalTotal:
                log.kcal != null ? log.kcal! / servings : null,
            recipeProteinTotal:
                log.proteinG != null ? log.proteinG! / servings : null,
            recipeCarbsTotal:
                log.carbsG != null ? log.carbsG! / servings : null,
            recipeFatTotal:
                log.fatG != null ? log.fatG! / servings : null,
          );
        }
      } else {
        // Start with a stub product; _reloadItemData replaces it with current
        // item nutrition so corrected values are immediately reflected.
        _product = FoodSearchResult(
          productName: log.productName,
          brand: log.brand,
          ean: log.ean,
          itemId: log.itemId,
          source: log.source,
        );
        if (log.kcal != null) _kcalManual.text = log.kcal!.toStringAsFixed(0);
        if (log.proteinG != null) {
          _proteinManual.text = log.proteinG!.toStringAsFixed(1);
        }
        if (log.carbsG != null) {
          _carbsManual.text = log.carbsG!.toStringAsFixed(1);
        }
        if (log.fatG != null) _fatManual.text = log.fatG!.toStringAsFixed(1);
        if (log.itemId != null) {
          WidgetsBinding.instance
              .addPostFrameCallback((_) => _reloadItemData(log));
        }
      }
    } else if (widget.initialProduct != null) {
      _product = widget.initialProduct;
      final p = _product!;
      if (p.isRecipe) {
        final su = p.servingUnit;
        _unit = su;
        if (_isWeightVolUnit(su)) {
          // Weight/volume unit: pre-fill with the gram serving size
          _qtyController.text = _fmtQty(p.servingSizeG ?? 1);
        } else {
          // Portion, Stück, etc.: pre-fill with 1
          _qtyController.text = '1';
        }
      } else if (p.servingSizeG != null) {
        // Regular food item with a known serving: pre-fill in grams
        _qtyController.text = _fmtQty(p.servingSizeG!);
        _unit = 'g';
      } else if (p.nutritionRefUnit == 'ml') {
        _unit = 'ml';
      }
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadItemContext());
    }
  }

  @override
  void dispose() {
    _qtyController.dispose();
    _notesController.dispose();
    _kcalManual.dispose();
    _proteinManual.dispose();
    _carbsManual.dispose();
    _fatManual.dispose();
    super.dispose();
  }

  String _fmtQty(double v) =>
      v % 1 == 0 ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  /// Loads inventory context for the currently selected local item.
  /// Builds unit options, filters the unit dropdown, and pre-selects consumeUnit.
  Future<void> _loadItemContext() async {
    final itemId = _product?.itemId;
    if (itemId == null || _isEditMode) {
      if (mounted) setState(() { _deductOpts = []; _hasInventory = false; _convs = []; _inventoryEntries = []; });
      return;
    }
    final db = ref.read(databaseProvider);
    if (db == null) return;

    final item = await db.itemById(itemId);
    final entries = await db.inventoryEntriesForItem(itemId);
    final itemConvs = await db.watchConversionsForItem(itemId).first;
    final globalConvs = await db.watchConversionsGlobal().first;
    final allConvs = [...itemConvs, ...globalConvs];
    if (!mounted) return;

    final invUnit = entries.isNotEmpty ? entries.first.unit : 'g';
    final opts = buildDeductUnitOptions(
      inventoryUnit: invUnit,
      conversions: allConvs,
      consumeQty: item?.consumeQty,
      consumeUnit: item?.consumeUnit,
      fallbackQty: 1.0,
    );

    // Switch to consumeUnit if set and available in options
    final cu = item?.consumeUnit?.toLowerCase().trim();
    String newUnit = _unit;
    double? newQty;
    if (cu != null && opts.any((o) => o.unit.toLowerCase().trim() == cu)) {
      final opt = opts.firstWhere((o) => o.unit.toLowerCase().trim() == cu);
      newUnit = opt.unit;
      if (item?.consumeQty != null) newQty = item!.consumeQty;
    }

    setState(() {
      _deductOpts = opts;
      _convs = allConvs;
      _inventoryEntries = entries;
      _hasInventory = entries.isNotEmpty;
      _unit = newUnit;
      if (newQty != null && _qtyController.text.trim().isEmpty) {
        _qtyController.text = _fmtQty(newQty);
      }
    });
  }

  /// Grams equivalent of 1 [_unit], derived from item conversions.
  /// Returns null if no conversion to grams is known.
  double? get _currentUnitGrams => unitToGrams(_unit, _convs);

  /// Convert entered quantity to grams using the selected unit.
  double _toGrams(double qty) {
    // Check item-specific conversions first
    final cug = _currentUnitGrams;
    if (cug != null) return qty * cug;

    final lower = _unit.toLowerCase().trim();
    return switch (lower) {
      'g' || 'gr' || 'gramm' || 'mg' => qty,
      'kg' || 'kilogramm' => qty * 1000,
      'ml' || 'milliliter' => qty,
      'cl' => qty * 10,
      'dl' => qty * 100,
      'l' || 'liter' => qty * 1000,
      'el' || 'esslöffel' || 'esslöffel (us)' || 'tbsp' => qty * 15,
      'tl' || 'teelöffel' || 'teelöffel (us)' || 'tsp' => qty * 5,
      'tasse' => qty * 240,
      'cup' => qty * 237,
      'oz' || 'unze' => qty * 28.35,
      'lb' || 'pfund' => qty * 453.6,
      _ =>
        _product?.servingSizeG != null ? qty * _product!.servingSizeG! : qty,
    };
  }

  double? _calcMacro(double? per100, double qtyG) {
    if (per100 == null) return null;
    return per100 * qtyG / 100;
  }

  double? _manualVal(TextEditingController c) {
    final v = c.text.trim().replaceAll(',', '.');
    if (v.isEmpty) return null;
    return double.tryParse(v);
  }

  /// Refreshes nutrition on the stub product from the item's current DB row.
  /// Called post-frame when opening an existing log entry for editing, so that
  /// any nutrition corrections made in the item form are picked up immediately.
  Future<void> _reloadItemData(NutritionLog log) async {
    final db = ref.read(databaseProvider);
    if (db == null || !mounted) return;
    final item = await db.itemById(log.itemId!);
    if (item == null || !mounted) return;
    setState(() {
      _product = FoodSearchResult(
        productName: log.productName,
        brand: log.brand,
        ean: log.ean,
        itemId: item.id,
        caloriesPer100g: item.caloriesPer100g,
        proteinPer100g: item.proteinPer100g,
        carbsPer100g: item.carbsPer100g,
        fatPer100g: item.fatPer100g,
        fiberPer100g: item.fiberPer100g,
        servingSizeG: item.servingSizeG,
        nutritionRefUnit: item.nutritionRefUnit,
        source: log.source,
      );
      // If item has per-100g data, the live preview takes over — clear stale
      // manual fields so they don't conflict with the computed values on save.
      if (item.caloriesPer100g != null) {
        _kcalManual.clear();
        _proteinManual.clear();
        _carbsManual.clear();
        _fatManual.clear();
      }
    });
  }

  Future<void> _openSearch() async {
    final result = await showModalBottomSheet<FoodSearchResult?>(
      context: context,
      isScrollControlled: true,
      builder: (_) => FoodSearchSheet(mealTypeId: _mealTypeId),
    );
    if (result == null) return;
    setState(() {
      _product = result;
      if (_qtyController.text.trim().isEmpty) {
        if (result.isRecipe) {
          final su = result.servingUnit;
          _unit = su;
          if (_isWeightVolUnit(su)) {
            _qtyController.text = _fmtQty(result.servingSizeG ?? 1);
          } else {
            _qtyController.text = '1';
          }
        } else if (result.servingSizeG != null) {
          _qtyController.text = _fmtQty(result.servingSizeG!);
          _unit = 'g';
        }
      }
      if (result.caloriesPer100g != null) {
        _kcalManual.clear();
        _proteinManual.clear();
        _carbsManual.clear();
        _fatManual.clear();
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadItemContext());
  }

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _loggedAt,
      firstDate: DateTime.now().subtract(const Duration(days: 365 * 2)),
      lastDate: DateTime.now(),
      locale: const Locale('de'),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_loggedAt),
    );
    if (time == null) return;
    setState(() {
      _loggedAt =
          DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  Future<void> _save() async {
    if (_product == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bitte zuerst ein Lebensmittel wählen.')),
      );
      return;
    }
    final qty = double.tryParse(
        _qtyController.text.trim().replaceAll(',', '.'));
    if (qty == null || qty <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bitte eine gültige Menge eingeben.')),
      );
      return;
    }

    final qtyG = _toGrams(qty);
    // Determine effective serving count for recipe entries:
    // - weight/volume unit (g/ml/…): servings = grams / gramWeightPerServing
    // - Portion/Stück/other: servings = entered qty directly
    final servingSizeG = _product?.servingSizeG;
    final servings = (_hasRecipeTotals && _recipeUsesWeightUnit &&
            servingSizeG != null &&
            servingSizeG > 0)
        ? qtyG / servingSizeG
        : qty;
    // storedQty: grams for weight/volume units, entered count for everything
    // else (Stück, Portion, …) so the diary shows "1 Stück" not "18 Stück".
    // kcal is always calculated from qtyG (gram-equivalent) above.
    final storedQty = _hasRecipeTotals
        ? (_recipeUsesWeightUnit ? qtyG : qty)
        : (_isWeightVolUnit(_unit) ? qtyG : qty);
    late double? kcal, protein, carbs, fat, fiber;
    if (_hasRecipeTotals) {
      kcal = servings * _product!.recipeKcalTotal!;
      protein = _product!.recipeProteinTotal != null
          ? servings * _product!.recipeProteinTotal!
          : null;
      carbs = _product!.recipeCarbsTotal != null
          ? servings * _product!.recipeCarbsTotal!
          : null;
      fat = _product!.recipeFatTotal != null
          ? servings * _product!.recipeFatTotal!
          : null;
      fiber = null;
    } else if (_hasPerHundredData) {
      kcal = _calcMacro(_product!.caloriesPer100g, qtyG);
      protein = _calcMacro(_product!.proteinPer100g, qtyG);
      carbs = _calcMacro(_product!.carbsPer100g, qtyG);
      fat = _calcMacro(_product!.fatPer100g, qtyG);
      fiber = _calcMacro(_product!.fiberPer100g, qtyG);
    } else {
      kcal = _manualVal(_kcalManual);
      protein = _manualVal(_proteinManual);
      carbs = _manualVal(_carbsManual);
      fat = _manualVal(_fatManual);
      fiber = null;
    }
    final notes = _notesController.text.trim().isEmpty
        ? null
        : _notesController.text.trim();

    setState(() => _saving = true);
    try {
      if (_isEditMode) {
        await ref.read(nutritionOpsProvider.notifier).updateLog(
              NutritionLogsCompanion(
                id: Value(widget.editLog!.id),
                loggedAt: Value(_loggedAt),
                productName: Value(_product!.productName),
                brand: Value(_product!.brand),
                mealTypeId: Value(_mealTypeId),
                itemId: Value(_product!.itemId),
                ean: Value(_product!.ean),
                quantityG: Value(storedQty),
                displayUnit: Value(_unit),
                kcal: Value(kcal),
                proteinG: Value(protein),
                carbsG: Value(carbs),
                fatG: Value(fat),
                fiberG: Value(fiber),
                notes: Value(notes),
              ),
            );
      } else {
        final src = _product!.source;
        final savedId = await ref.read(nutritionOpsProvider.notifier).logFood(
              loggedAt: _loggedAt,
              productName: _product!.productName,
              brand: _product!.brand,
              mealTypeId: _mealTypeId,
              itemId: _product!.itemId,
              ean: _product!.ean,
              quantityG: storedQty,
              displayUnit: _unit,
              kcal: kcal,
              proteinG: protein,
              carbsG: carbs,
              fatG: fat,
              fiberG: fiber,
              source: src,
              notes: notes,
            );
        // Deduct from inventory.
        // Local items: inline deduction using the unit already selected in
        // this sheet (no second dialog).
        // Meals / recipes: multi-ingredient deduction via separate sheet.
        final hasDeductable = _product!.itemId != null &&
            (src == 'local' || src == 'meal' || src == 'recipe');
        if (hasDeductable && mounted) {
          if (src == 'local' &&
              _doDeduct &&
              _hasInventory &&
              _deductOpts.isNotEmpty &&
              _inventoryEntries.isNotEmpty) {
            final opt = _deductOpts.firstWhere(
              (o) => o.unit.toLowerCase().trim() == _unit.toLowerCase().trim(),
              orElse: () => _deductOpts.first,
            );
            final entry = _inventoryEntries.first;
            final deductAmount = qty * opt.factor;
            final remaining =
                (entry.quantity - deductAmount).clamp(0.0, double.infinity);
            await ref.read(inventoryOpsProvider.notifier).consume(
                  itemId: _product!.itemId!,
                  inventoryEntryId: entry.id,
                  quantity: deductAmount,
                  unit: entry.unit,
                  remainingQuantity: remaining,
                  consumptionReason: _consumptionReason,
                );
            await ref
                .read(nutritionOpsProvider.notifier)
                .setInventoryDeducted(savedId, true);
          } else if (src == 'meal' || src == 'recipe') {
            final logForDeduct = NutritionLog(
              id: savedId,
              loggedAt: _loggedAt,
              productName: _product!.productName,
              brand: _product!.brand,
              mealTypeId: _mealTypeId,
              itemId: _product!.itemId,
              ean: _product!.ean,
              quantityG: storedQty,
              displayUnit: _unit,
              kcal: kcal,
              proteinG: protein,
              carbsG: carbs,
              fatG: fat,
              fiberG: fiber,
              source: src,
              notes: notes,
              thumbRating: null,
              inventoryDeducted: false,
              createdAt: DateTime.now(),
            );
            await showModalBottomSheet<bool>(
              context: context,
              isScrollControlled: true,
              builder: (_) => InventoryDeductSheet(log: logForDeduct),
            );
          }
        }
      }
      if (mounted) Navigator.of(context).pop(true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eintrag löschen?'),
        content: Text('„${widget.editLog!.productName}" wird entfernt.'),
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
    if (ok == true && mounted) {
      await ref
          .read(nutritionOpsProvider.notifier)
          .deleteLog(widget.editLog!.id);
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.of(context).viewInsets.bottom;
    final cs = Theme.of(context).colorScheme;
    final mealTypes = ref.watch(mealTypesProvider).valueOrNull ?? [];
    final allUnits = ref.watch(unitNamesProvider);
    final baseUnits =
        allUnits.isEmpty ? ['g', 'ml', 'Stück', 'Portion'] : allUnits;
    // For local items with known unit conversions, filter to meaningful units only.
    final units = (_deductOpts.isNotEmpty && _product?.source == 'local')
        ? _deductOpts.map((o) => o.unit).toList()
        : baseUnits;
    // If current unit not in list, fall back to first.
    final safeUnit = units.contains(_unit) ? _unit : units.first;

    return Padding(
      padding: EdgeInsets.only(
          left: 16, right: 16, top: 8, bottom: 16 + inset),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Handle ─────────────────────────────────────────────────────
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Theme.of(context).dividerColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _isEditMode ? 'Eintrag bearbeiten' : 'Eintrag hinzufügen',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                if (_isEditMode)
                  IconButton(
                    icon: Icon(Icons.delete_outline, color: cs.error),
                    tooltip: 'Eintrag löschen',
                    onPressed: _confirmDelete,
                  ),
              ],
            ),
            const SizedBox(height: 16),

            // ── Product picker ──────────────────────────────────────────────
            OutlinedButton.icon(
              onPressed: _openSearch,
              icon: const Icon(Icons.search),
              label: Text(
                _product == null
                    ? 'Lebensmittel wählen …'
                    : _product!.productName,
                overflow: TextOverflow.ellipsis,
              ),
              style: OutlinedButton.styleFrom(
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 14),
              ),
            ),
            if (_product?.brand != null)
              Padding(
                padding: const EdgeInsets.only(top: 4, left: 4),
                child: Text(
                  _product!.brand!,
                  style:
                      TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                ),
              ),
            const SizedBox(height: 12),

            // ── Live nutrition preview ──────────────────────────────────────
            // Recipes/meals: always show total × servings (not per-100g math).
            if (_hasRecipeTotals)
              _RecipeTotalsPreview(
                  product: _product!,
                  qty: _qtyController.text)
            else if (_hasPerHundredData)
              _NutritionPreview(
                  product: _product!,
                  qty: _qtyController.text,
                  unit: safeUnit,
                  servingSizeG: _currentUnitGrams ?? _product!.servingSizeG),

            // ── Quantity + unit ─────────────────────────────────────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: TextFormField(
                    controller: _qtyController,
                    autofocus: _product != null,
                    decoration: const InputDecoration(
                      labelText: 'Menge *',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.scale_outlined),
                    ),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                    ],
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Einheit',
                      border: OutlineInputBorder(),
                      contentPadding:
                          EdgeInsets.fromLTRB(12, 16, 8, 16),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: safeUnit,
                        isDense: true,
                        isExpanded: true,
                        items: units
                            .map((u) => DropdownMenuItem(
                                  value: u,
                                  child: Text(u,
                                      overflow: TextOverflow.ellipsis),
                                ))
                            .toList(),
                        onChanged: (v) =>
                            setState(() => _unit = v ?? 'g'),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // ── Inventory deduction toggle (local items only) ───────────────
            if (_hasInventory && !_isEditMode && _product?.source == 'local') ...[
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Bestand ausbuchen'),
                value: _doDeduct,
                onChanged: (v) => setState(() => _doDeduct = v),
              ),
              if (_doDeduct) ...[
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                        value: 'consumed',
                        label: Text('Verbraucht'),
                        icon: Icon(Icons.restaurant, size: 14)),
                    ButtonSegment(
                        value: 'expired',
                        label: Text('Abgelaufen'),
                        icon: Icon(Icons.event_busy, size: 14)),
                    ButtonSegment(
                        value: 'discarded',
                        label: Text('Entsorgt'),
                        icon: Icon(Icons.delete_outline, size: 14)),
                    ButtonSegment(
                        value: 'gifted',
                        label: Text('Verschenkt'),
                        icon: Icon(Icons.card_giftcard, size: 14)),
                  ],
                  selected: {_consumptionReason},
                  onSelectionChanged: (s) =>
                      setState(() => _consumptionReason = s.first),
                  style: const ButtonStyle(
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ],

            // ── Manual macro fields ─────────────────────────────────────────
            if (_showManualMacros) ...[
              Text('Nährwerte (optional)',
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _MacroField(
                        controller: _kcalManual,
                        label: 'kcal',
                        onChanged: () => setState(() {})),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _MacroField(
                        controller: _proteinManual,
                        label: 'Protein (g)',
                        onChanged: () => setState(() {})),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _MacroField(
                        controller: _carbsManual,
                        label: 'Kohlenhydrate (g)',
                        onChanged: () => setState(() {})),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _MacroField(
                        controller: _fatManual,
                        label: 'Fett (g)',
                        onChanged: () => setState(() {})),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],

            // ── Meal type ───────────────────────────────────────────────────
            if (mealTypes.isNotEmpty) ...[
              InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Mahlzeit',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.restaurant_outlined),
                  contentPadding: EdgeInsets.fromLTRB(12, 16, 8, 16),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String?>(
                    value: _mealTypeId,
                    isDense: true,
                    isExpanded: true,
                    items: [
                      const DropdownMenuItem(
                          value: null, child: Text('Keine Angabe')),
                      ...mealTypes.map((mt) => DropdownMenuItem(
                            value: mt.id,
                            child: Text(mt.name),
                          )),
                    ],
                    onChanged: (v) => setState(() => _mealTypeId = v),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],

            // ── Date/time ───────────────────────────────────────────────────
            InkWell(
              onTap: _pickDateTime,
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Zeitpunkt',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.schedule),
                ),
                child: Text(
                  DateFormat.yMMMMd('de_DE').add_Hm().format(_loggedAt),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // ── Notes ───────────────────────────────────────────────────────
            TextField(
              controller: _notesController,
              decoration: const InputDecoration(
                labelText: 'Notiz (optional)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.note_outlined),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 16),

            // ── Actions ─────────────────────────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed:
                        _saving ? null : () => Navigator.of(context).pop(),
                    child: const Text('Abbrechen'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Speichern'),
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

// ── Live nutrition preview ────────────────────────────────────────────────────

class _NutritionPreview extends StatelessWidget {
  final FoodSearchResult product;
  final String qty;
  final String unit;
  final double? servingSizeG;

  const _NutritionPreview({
    required this.product,
    required this.qty,
    required this.unit,
    this.servingSizeG,
  });

  double _toGrams(double raw) {
    final lower = unit.toLowerCase().trim();
    return switch (lower) {
      'g' || 'gr' || 'gramm' || 'mg' => raw,
      'kg' || 'kilogramm' => raw * 1000,
      'ml' || 'milliliter' => raw,
      'cl' => raw * 10,
      'dl' => raw * 100,
      'l' || 'liter' => raw * 1000,
      'el' || 'esslöffel' || 'tbsp' => raw * 15,
      'tl' || 'teelöffel' || 'tsp' => raw * 5,
      'tasse' || 'cup' => raw * 237,
      'oz' || 'unze' => raw * 28.35,
      'lb' || 'pfund' => raw * 453.6,
      _ => servingSizeG != null ? raw * servingSizeG! : raw,
    };
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final raw = double.tryParse(qty.replaceAll(',', '.')) ?? 0;
    final g = _toGrams(raw);
    final fmt =
        NumberFormat.decimalPattern('de_DE')..maximumFractionDigits = 1;

    String calc(double? per100) {
      if (per100 == null || g <= 0) return '—';
      return fmt.format(per100 * g / 100);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _MacroCell(
              label: 'kcal',
              value: calc(product.caloriesPer100g),
              cs: cs,
              highlight: true),
          _MacroCell(
              label: 'Protein',
              value: '${calc(product.proteinPer100g)} g',
              cs: cs),
          _MacroCell(
              label: 'KH',
              value: '${calc(product.carbsPer100g)} g',
              cs: cs),
          _MacroCell(
              label: 'Fett',
              value: '${calc(product.fatPer100g)} g',
              cs: cs),
        ],
      ),
    );
  }
}

class _MacroCell extends StatelessWidget {
  final String label;
  final String value;
  final ColorScheme cs;
  final bool highlight;

  const _MacroCell(
      {required this.label,
      required this.value,
      required this.cs,
      this.highlight = false});

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: highlight ? 18 : 14,
                color: highlight ? cs.primary : cs.onSurface),
          ),
          Text(label,
              style:
                  TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
        ],
      );
}

/// Preview shown when a recipe has stored per-serving totals but no per-100g data.
class _RecipeTotalsPreview extends StatelessWidget {
  final FoodSearchResult product;
  final String qty;

  const _RecipeTotalsPreview({required this.product, required this.qty});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final portions = double.tryParse(qty.replaceAll(',', '.')) ?? 0;
    final fmt = NumberFormat.decimalPattern('de_DE')..maximumFractionDigits = 1;

    String calc(double? perServing) {
      if (perServing == null || portions <= 0) return '—';
      return fmt.format(perServing * portions);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _MacroCell(
              label: 'kcal',
              value: calc(product.recipeKcalTotal),
              cs: cs,
              highlight: true),
          _MacroCell(
              label: 'Protein',
              value: '${calc(product.recipeProteinTotal)} g',
              cs: cs),
          _MacroCell(
              label: 'KH',
              value: '${calc(product.recipeCarbsTotal)} g',
              cs: cs),
          _MacroCell(
              label: 'Fett',
              value: '${calc(product.recipeFatTotal)} g',
              cs: cs),
        ],
      ),
    );
  }
}

class _MacroField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final VoidCallback onChanged;

  const _MacroField(
      {required this.controller,
      required this.label,
      required this.onChanged});

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        keyboardType:
            const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
        ],
        onChanged: (_) => onChanged(),
      );
}
