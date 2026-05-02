import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../db/database.dart';
import '../../providers/units_provider.dart';
import '../providers/nutrition_provider.dart';
import 'food_search_sheet.dart';

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

  const DiaryEntrySheet({
    super.key,
    this.initialMealTypeId,
    this.initialLoggedAt,
    this.editLog,
    this.initialProduct,
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

  bool get _isEditMode => widget.editLog != null;

  bool get _hasPerHundredData => _product?.caloriesPer100g != null;

  /// Recipe selected without linked ingredients, but has stored per-serving totals.
  bool get _hasRecipeTotals =>
      _product != null &&
      _product!.isRecipe &&
      !_hasPerHundredData &&
      _product!.recipeKcalTotal != null;

  bool get _showManualMacros =>
      _product != null && !_hasPerHundredData && !_hasRecipeTotals;

  @override
  void initState() {
    super.initState();
    _mealTypeId = widget.initialMealTypeId;
    _loggedAt = widget.initialLoggedAt ?? DateTime.now();

    final log = widget.editLog;
    if (log != null) {
      _mealTypeId = log.mealTypeId;
      _loggedAt = log.loggedAt;
      _unit = log.displayUnit;
      _qtyController.text = _fmtQty(log.quantityG);
      _notesController.text = log.notes ?? '';
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
      if (log.carbsG != null) _carbsManual.text = log.carbsG!.toStringAsFixed(1);
      if (log.fatG != null) _fatManual.text = log.fatG!.toStringAsFixed(1);
    } else if (widget.initialProduct != null) {
      _product = widget.initialProduct;
      final p = _product!;
      if (p.isRecipe) {
        // Recipes & meals: qty = number of servings (1 Portion = servingSizeG grams)
        _qtyController.text = '1';
        _unit = 'Portion';
      } else if (p.servingSizeG != null) {
        // Regular food item with a known serving: pre-fill in grams
        _qtyController.text = _fmtQty(p.servingSizeG!);
        _unit = 'g';
      } else if (p.nutritionRefUnit == 'ml') {
        _unit = 'ml';
      }
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

  /// Convert entered quantity to grams using the selected unit.
  double _toGrams(double qty) {
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

  Future<void> _openSearch() async {
    final result = await showModalBottomSheet<FoodSearchResult?>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const FoodSearchSheet(),
    );
    if (result == null) return;
    setState(() {
      _product = result;
      if (_qtyController.text.trim().isEmpty) {
        if (result.isRecipe) {
          _qtyController.text = '1';
          _unit = 'Portion';
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
    late double? kcal, protein, carbs, fat, fiber;
    if (_hasRecipeTotals) {
      // qty = number of servings; multiply stored per-serving totals
      kcal = qty * _product!.recipeKcalTotal!;
      protein = _product!.recipeProteinTotal != null
          ? qty * _product!.recipeProteinTotal!
          : null;
      carbs = _product!.recipeCarbsTotal != null
          ? qty * _product!.recipeCarbsTotal!
          : null;
      fat = _product!.recipeFatTotal != null
          ? qty * _product!.recipeFatTotal!
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
                quantityG: Value(qtyG),
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
        await ref.read(nutritionOpsProvider.notifier).logFood(
              loggedAt: _loggedAt,
              productName: _product!.productName,
              brand: _product!.brand,
              mealTypeId: _mealTypeId,
              itemId: _product!.itemId,
              ean: _product!.ean,
              quantityG: qtyG,
              displayUnit: _unit,
              kcal: kcal,
              proteinG: protein,
              carbsG: carbs,
              fatG: fat,
              fiberG: fiber,
              source: _product!.source,
              notes: notes,
            );
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
    // Ensure 'g' is always available as fallback.
    final units = allUnits.isEmpty ? ['g', 'ml', 'Stück', 'Portion'] : allUnits;
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
            if (_hasPerHundredData)
              _NutritionPreview(
                  product: _product!,
                  qty: _qtyController.text,
                  unit: safeUnit,
                  servingSizeG: _product!.servingSizeG)
            else if (_hasRecipeTotals)
              _RecipeTotalsPreview(
                  product: _product!,
                  qty: _qtyController.text),

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
