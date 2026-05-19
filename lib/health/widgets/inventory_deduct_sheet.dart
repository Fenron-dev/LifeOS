import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../db/database.dart';
import '../../providers/inventory_provider.dart';
import '../../providers/vault_provider.dart';
import '../../utils/unit_deduct_utils.dart';
import '../providers/nutrition_provider.dart';

typedef _UnitOption = UnitDeductOption;

// ── Row data model ────────────────────────────────────────────────────────────

class _DeductRow {
  final String label;
  final String? brand;
  final String? itemId;
  final double requestedQty;
  final String requestedUnit;
  List<InventoryEntry> inventoryEntries;
  InventoryEntry? selectedEntry;
  bool skip;

  /// Holds qty in the LOGICAL unit (what the user thinks in).
  final TextEditingController qtyController;

  final List<_UnitOption> unitOptions;
  _UnitOption selectedUnit;

  _DeductRow({
    required this.label,
    this.brand,
    required this.itemId,
    required this.requestedQty,
    required this.requestedUnit,
    this.inventoryEntries = const [],
    this.selectedEntry,
    this.skip = false,
    required this.unitOptions,
    required this.selectedUnit,
  }) : qtyController =
            TextEditingController(text: _fmt(selectedUnit.defaultQty));

  static String _fmt(double v) =>
      v % 1 == 0 ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  double get logicalQty =>
      double.tryParse(qtyController.text.replaceAll(',', '.')) ?? 0;

  /// Physical quantity to subtract from the inventory entry (in inventory unit).
  double get deductQty => logicalQty * selectedUnit.factor;

  /// Always the inventory entry's native unit – used by _confirm().
  String get deductUnit => selectedEntry?.unit ?? requestedUnit;

  void dispose() => qtyController.dispose();
}

// ── Main sheet ────────────────────────────────────────────────────────────────

/// Bottom sheet shown after a diary entry is saved. Lets the user confirm
/// (or skip) deducting the logged quantities from inventory.
///
/// [log] — the diary entry just saved.
/// Returns true if any deductions were performed.
class InventoryDeductSheet extends ConsumerStatefulWidget {
  final NutritionLog log;

  const InventoryDeductSheet({super.key, required this.log});

  @override
  ConsumerState<InventoryDeductSheet> createState() =>
      _InventoryDeductSheetState();
}

class _InventoryDeductSheetState
    extends ConsumerState<InventoryDeductSheet> {
  List<_DeductRow> _rows = [];
  bool _loading = true;
  bool _saving = false;
  String _consumptionReason = 'consumed';

  @override
  void initState() {
    super.initState();
    _loadRows();
  }

  @override
  void dispose() {
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  // ── Servings calculation for meal/recipe deduction ───────────────────────────

  /// Computes how many servings of a meal/recipe were consumed.
  ///
  /// - Non-weight units (Portion, Stück, etc.): [quantityG] stores the count directly.
  /// - Weight/volume units (g, ml, …): derive servings from the logged grams
  ///   relative to the total ingredient weight per serving.
  static double _computeServings({
    required double quantityG,
    required String displayUnit,
    required List<({double qty, String unit})> ingredientQuantities,
    int? recipeServings,
  }) {
    if (quantityG <= 0) return 1.0;
    if (!isWeightVolUnit(displayUnit)) {
      // Portion/Stück/etc.: quantityG is the consumed serving count.
      return quantityG;
    }
    // Weight-based logging: compute total ingredient weight per recipe serving.
    double totalGPerRecipe = 0;
    for (final ing in ingredientQuantities) {
      final g = convertWeightVol(ing.qty, ing.unit, 'g');
      if (g != null) totalGPerRecipe += g;
    }
    if (totalGPerRecipe <= 0) return quantityG;
    final servingSizeG = recipeServings != null && recipeServings > 0
        ? totalGPerRecipe / recipeServings
        : totalGPerRecipe;
    return (quantityG / servingSizeG).clamp(0.01, 999.0);
  }

  // ── Heuristic fallback (when no consumeUnit conversion applies) ─────────────

  static double _heuristicQty({
    required double quantityG,
    required String inventoryUnit,
    required double? servingSizeG,
  }) {
    if (isWeightVolUnit(inventoryUnit)) {
      return convertWeightVol(quantityG, 'g', inventoryUnit) ?? quantityG;
    }
    if (servingSizeG != null && servingSizeG > 0) {
      return quantityG / servingSizeG;
    }
    return 1.0;
  }

  // ── Load rows ───────────────────────────────────────────────────────────────

  Future<void> _loadRows() async {
    final db = ref.read(databaseProvider);
    if (db == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    final log = widget.log;
    final rows = <_DeductRow>[];

    Future<List<UnitConversion>> loadConvs(String? itemId) async {
      if (itemId == null) return [];
      final item = await db.watchConversionsForItem(itemId).first;
      final global = await db.watchConversionsGlobal().first;
      return [...item, ...global];
    }

    Future<_DeductRow> makeRow({
      required String label,
      String? brand,
      required String? itemId,
      required double qty,
      required String unit,
      required List<InventoryEntry> entries,
      required Item? item,
    }) async {
      final inventoryUnit = entries.isNotEmpty ? entries.first.unit : unit;
      final convs = await loadConvs(itemId);

      final fallback = _heuristicQty(
        quantityG: qty,
        inventoryUnit: inventoryUnit,
        servingSizeG: item?.servingSizeG,
      );

      final unitOptions = buildDeductUnitOptions(
        inventoryUnit: inventoryUnit,
        conversions: convs,
        consumeQty: item?.consumeQty,
        consumeUnit: item?.consumeUnit,
        fallbackQty: fallback,
        diaryMode: true,
      );

      // Pre-select the option matching item.consumeUnit (if it exists)
      final cu = item?.consumeUnit?.toLowerCase().trim();
      final selected = cu != null
          ? unitOptions.firstWhere(
              (o) => o.unit.toLowerCase().trim() == cu,
              orElse: () => unitOptions.first,
            )
          : unitOptions.first;

      return _DeductRow(
        label: label,
        brand: brand,
        itemId: itemId,
        requestedQty: qty,
        requestedUnit: unit,
        inventoryEntries: entries,
        selectedEntry: entries.isNotEmpty ? entries.first : null,
        skip: entries.isEmpty,
        unitOptions: unitOptions,
        selectedUnit: selected,
      );
    }

    if (log.source == 'meal' && log.itemId != null) {
      final ings = await db.ingredientsForMeal(log.itemId!);
      final servings = _computeServings(
        quantityG: log.quantityG,
        displayUnit: log.displayUnit,
        ingredientQuantities: ings
            .map((i) => (qty: i.quantity, unit: i.unit))
            .toList(),
      );
      for (final ing in ings) {
        if (ing.itemId == null) continue;
        final entries = await db.inventoryEntriesForItem(ing.itemId!);
        final item = await db.itemById(ing.itemId!);
        rows.add(await makeRow(
          label: ing.name,
          itemId: ing.itemId,
          qty: ing.quantity * servings,
          unit: ing.unit,
          entries: entries,
          item: item,
        ));
      }
    } else if (log.source == 'recipe' && log.itemId != null) {
      final ings = await db.ingredientsForRecipe(log.itemId!);
      final recipe = await db.recipeById(log.itemId!);
      // Recipe ingredient quantities are stored as TOTAL for all recipe servings.
      // Divide by recipe.servings to get per-serving amount, then multiply by
      // how many servings the user consumed.
      final recipeServings = (recipe?.servings ?? 1).toDouble();
      final servings = _computeServings(
        quantityG: log.quantityG,
        displayUnit: log.displayUnit,
        ingredientQuantities: ings
            .map((i) => (qty: i.quantity, unit: i.unit))
            .toList(),
        recipeServings: recipe?.servings,
      );
      for (final ing in ings) {
        if (ing.itemId == null) continue;
        final entries = await db.inventoryEntriesForItem(ing.itemId!);
        final item = await db.itemById(ing.itemId!);
        rows.add(await makeRow(
          label: ing.name,
          itemId: ing.itemId,
          qty: (ing.quantity / recipeServings) * servings,
          unit: ing.unit,
          entries: entries,
          item: item,
        ));
      }
    } else if (log.itemId != null) {
      final item = await db.itemById(log.itemId!);
      final entries = await db.inventoryEntriesForItem(log.itemId!);
      if (item != null) {
        rows.add(await makeRow(
          label: item.name,
          brand: item.brand,
          itemId: item.id,
          qty: log.quantityG,
          unit: log.displayUnit,
          entries: entries,
          item: item,
        ));
      }
    }

    if (mounted) {
      setState(() {
        _rows = rows;
        _loading = false;
      });
    }
  }

  // ── Confirm ─────────────────────────────────────────────────────────────────

  Future<void> _confirm() async {
    final db = ref.read(databaseProvider);
    if (db == null) return;

    setState(() => _saving = true);
    try {
      for (final row in _rows) {
        if (row.skip || row.selectedEntry == null) continue;
        final entry = row.selectedEntry!;
        // row.deductQty is already in entry.unit (logical * factor)
        final native = row.deductQty;
        if (native <= 0) continue;

        final remaining =
            (entry.quantity - native).clamp(0.0, double.infinity);
        await ref.read(inventoryOpsProvider.notifier).consume(
              itemId: row.itemId!,
              inventoryEntryId: entry.id,
              quantity: native,
              unit: entry.unit,
              remainingQuantity: remaining,
              consumptionReason: _consumptionReason,
            );
      }
      if (widget.log.id.isNotEmpty) {
        await ref
            .read(nutritionOpsProvider.notifier)
            .setInventoryDeducted(widget.log.id, true);
      }
      if (mounted) Navigator.of(context).pop(true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            16, 12, 16, MediaQuery.of(context).viewInsets.bottom + 16),
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
              'Bestand reduzieren?',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Einheit wählen, Menge anpassen, dann „Ausbuchen" tippen.',
              style:
                  TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 10),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                    value: 'consumed',
                    label: Text('Konsumiert'),
                    icon: Icon(Icons.restaurant, size: 14)),
                ButtonSegment(
                    value: 'expired',
                    label: Text('Abgelaufen'),
                    icon: Icon(Icons.event_busy, size: 14)),
                ButtonSegment(
                    value: 'discarded',
                    label: Text('Weggeworfen'),
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
            const SizedBox(height: 12),
            if (_loading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_rows.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  (widget.log.source == 'meal' ||
                          widget.log.source == 'recipe')
                      ? 'Keine verknüpften Lagerbestände. Verknüpfe die Zutaten in den Gericht-/Rezepteinstellungen mit Artikeln.'
                      : 'Keine Lagerbestände für diesen Eintrag gefunden.',
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 320),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _rows.length,
                  itemBuilder: (context, i) => _RowTile(
                    row: _rows[i],
                    onChanged: () => setState(() {}),
                  ),
                ),
              ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _saving
                      ? null
                      : () => Navigator.of(context).pop(false),
                  child: const Text('Überspringen'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: (_saving ||
                          _loading ||
                          _rows.isEmpty ||
                          _rows.every((r) => r.skip || r.deductQty <= 0))
                      ? null
                      : _confirm,
                  child: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white))
                      : const Text('Ausbuchen'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Row tile ──────────────────────────────────────────────────────────────────

class _RowTile extends StatefulWidget {
  final _DeductRow row;
  final VoidCallback onChanged;

  const _RowTile({required this.row, required this.onChanged});

  @override
  State<_RowTile> createState() => _RowTileState();
}

class _RowTileState extends State<_RowTile> {
  _DeductRow get row => widget.row;

  static String _fmtQty(double v) =>
      v % 1 == 0 ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  @override
  void initState() {
    super.initState();
    row.qtyController.addListener(_onQtyChanged);
  }

  @override
  void dispose() {
    row.qtyController.removeListener(_onQtyChanged);
    super.dispose();
  }

  void _onQtyChanged() => widget.onChanged();

  void _selectUnit(_UnitOption opt) {
    setState(() {
      row.selectedUnit = opt;
      row.qtyController.text = _fmtQty(opt.defaultQty);
    });
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasStock = row.inventoryEntries.isNotEmpty;
    final entry = row.selectedEntry;
    final inventoryUnit = entry?.unit ?? row.requestedUnit;

    final currentQty = entry?.quantity ?? 0.0;
    final deductPhysical = row.deductQty; // in inventoryUnit
    final remaining = (currentQty - deductPhysical).clamp(0.0, double.infinity);

    final multiUnit = row.unitOptions.length > 1;
    final isRawUnit =
        row.selectedUnit.unit.toLowerCase() == inventoryUnit.toLowerCase();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CheckboxListTile(
          value: !row.skip,
          onChanged: hasStock
              ? (v) {
                  row.skip = !(v ?? false);
                  widget.onChanged();
                }
              : null,
          title: Row(
            children: [
              Expanded(
                child: Text(
                  row.brand != null
                      ? '${row.label} · ${row.brand}'
                      : row.label,
                  style: TextStyle(
                    color: row.skip || !hasStock
                        ? cs.onSurfaceVariant
                        : null,
                    decoration:
                        !hasStock ? TextDecoration.lineThrough : null,
                  ),
                ),
              ),
            ],
          ),
          subtitle: !hasStock
              ? Text('Kein Bestand vorhanden',
                  style: TextStyle(
                      fontSize: 12, color: cs.onSurfaceVariant))
              : Text(
                  'Tagebuch: ${_fmtQty(row.requestedQty)} ${row.requestedUnit}'
                  '  ·  Bestand: ${_fmtQty(currentQty)} $inventoryUnit',
                  style: TextStyle(
                      fontSize: 12, color: cs.onSurfaceVariant),
                ),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
          dense: true,
        ),

        if (hasStock && !row.skip) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(40, 0, 0, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Unit chips (only when multiple units available)
                if (multiUnit) ...[
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: row.unitOptions.map((opt) {
                      final sel = opt == row.selectedUnit;
                      return ChoiceChip(
                        label: Text(opt.unit,
                            style: const TextStyle(fontSize: 12)),
                        selected: sel,
                        onSelected: (_) => _selectUnit(opt),
                        visualDensity: VisualDensity.compact,
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 6),
                ],

                // Qty field + unit label + remaining preview
                Row(
                  children: [
                    SizedBox(
                      width: 80,
                      child: TextFormField(
                        controller: row.qtyController,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                              RegExp(r'[\d.,]')),
                        ],
                        decoration: InputDecoration(
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 6),
                          border: const OutlineInputBorder(),
                          filled: true,
                          fillColor: cs.surfaceContainerHighest
                              .withValues(alpha: 0.5),
                        ),
                        style: const TextStyle(fontSize: 14),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      row.selectedUnit.unit,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w500),
                    ),
                    // Conversion hint when not in native inventory unit
                    if (!isRawUnit) ...[
                      const SizedBox(width: 6),
                      Text(
                        '= ${_fmtQty(deductPhysical)} $inventoryUnit',
                        style: TextStyle(
                            fontSize: 12,
                            color: cs.primary,
                            fontStyle: FontStyle.italic),
                      ),
                    ],
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        '→ ${_fmtQty(remaining)} $inventoryUnit',
                        style: TextStyle(
                          fontSize: 12,
                          color: remaining <= 0
                              ? cs.error
                              : cs.onSurfaceVariant,
                          fontStyle: FontStyle.italic,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),

                // Entry selector when multiple inventory entries exist
                if (row.inventoryEntries.length > 1)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Wrap(
                      spacing: 8,
                      children: row.inventoryEntries.map((e) {
                        final selected = row.selectedEntry?.id == e.id;
                        final label =
                            '${_fmtQty(e.quantity)} ${e.unit}'
                            '${e.expiryDate != null ? ' (MHD ${e.expiryDate!.day}.${e.expiryDate!.month}.)' : ''}';
                        return ChoiceChip(
                          label: Text(label,
                              style: const TextStyle(fontSize: 11)),
                          selected: selected,
                          onSelected: (_) {
                            setState(() => row.selectedEntry = e);
                            widget.onChanged();
                          },
                          visualDensity: VisualDensity.compact,
                        );
                      }).toList(),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
