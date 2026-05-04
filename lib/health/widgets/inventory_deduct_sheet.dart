import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../db/database.dart';
import '../../providers/inventory_provider.dart';
import '../../providers/vault_provider.dart';
import '../providers/nutrition_provider.dart';

/// Data for one ingredient/food that may be deducted from inventory.
class _DeductRow {
  final String label;
  final String? brand;
  final String? itemId;
  final double requestedQty;  // amount the diary logged (grams or count)
  final String requestedUnit; // unit shown in diary (g, Stück, Packung…)
  List<InventoryEntry> inventoryEntries;
  InventoryEntry? selectedEntry;
  bool skip;

  // The TextEditingController holds what the user will actually deduct,
  // expressed in the inventory entry's native unit.
  final TextEditingController qtyController;

  _DeductRow({
    required this.label,
    this.brand,
    required this.itemId,
    required this.requestedQty,
    required this.requestedUnit,
    this.inventoryEntries = const [],
    this.selectedEntry,
    this.skip = false,
    required double initialDeductQty,
  }) : qtyController =
            TextEditingController(text: _fmt(initialDeductQty));

  static String _fmt(double v) =>
      v % 1 == 0 ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  double get deductQty =>
      double.tryParse(qtyController.text.replaceAll(',', '.')) ?? 0;

  String get deductUnit => selectedEntry?.unit ?? requestedUnit;

  void dispose() => qtyController.dispose();
}

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

  static bool _isWeightVolUnit(String unit) {
    switch (unit.toLowerCase().trim()) {
      case 'g':
      case 'gr':
      case 'gramm':
      case 'mg':
      case 'kg':
      case 'kilogramm':
      case 'ml':
      case 'milliliter':
      case 'cl':
      case 'dl':
      case 'l':
      case 'liter':
        return true;
      default:
        return false;
    }
  }

  /// Converts [qty] from [from] to [to] for weight/volume units.
  /// Returns null when units differ and no conversion rule exists.
  static double? _convertWeightVol(double qty, String from, String to) {
    final f = from.toLowerCase().trim();
    final t = to.toLowerCase().trim();
    if (f == t) return qty;
    if (f == 'g' && (t == 'kg' || t == 'kilogramm')) return qty / 1000;
    if ((f == 'kg' || f == 'kilogramm') && t == 'g') return qty * 1000;
    if (f == 'ml' && (t == 'l' || t == 'liter')) return qty / 1000;
    if ((f == 'l' || f == 'liter') && t == 'ml') return qty * 1000;
    if (f == 'cl' && t == 'ml') return qty * 10;
    if (f == 'ml' && t == 'cl') return qty / 10;
    if (f == 'dl' && t == 'ml') return qty * 100;
    if (f == 'ml' && t == 'dl') return qty / 100;
    return null;
  }

  /// Best-guess deduction quantity in [inventoryUnit] given the diary log
  /// [quantityG] (always grams, or raw count when no servingSizeG) and the
  /// item's explicit [consumeQty]/[consumeUnit] override or [servingSizeG].
  ///
  /// Rules (highest priority first):
  ///  • item has consumeQty + consumeUnit and units match inventory → use that
  ///  • inventory in weight/vol  → use quantityG, convert g→inventoryUnit
  ///  • inventory in count unit  → quantityG / servingSizeG  (if known)
  ///  • no servingSizeG          → fall back to 1 (one inventory unit)
  static double _defaultDeductQty({
    required double quantityG,
    required String inventoryUnit,
    required double? servingSizeG,
    double? consumeQty,
    String? consumeUnit,
  }) {
    // Explicit per-item override takes precedence when the unit matches
    if (consumeQty != null &&
        consumeQty > 0 &&
        consumeUnit != null &&
        consumeUnit.toLowerCase().trim() ==
            inventoryUnit.toLowerCase().trim()) {
      return consumeQty;
    }
    if (_isWeightVolUnit(inventoryUnit)) {
      // Convert grams to the inventory's weight unit
      return _convertWeightVol(quantityG, 'g', inventoryUnit) ?? quantityG;
    }
    // Counting unit: reverse the diary's g-per-serving multiplication
    if (servingSizeG != null && servingSizeG > 0) {
      return quantityG / servingSizeG;
    }
    // No serving size info — default to 1 (one inventory unit)
    return 1.0;
  }

  Future<void> _loadRows() async {
    final db = ref.read(databaseProvider);
    if (db == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    final log = widget.log;
    final rows = <_DeductRow>[];

    if (log.source == 'meal' && log.itemId != null) {
      // Standard meal → deduct each ingredient
      final ings = await db.ingredientsForMeal(log.itemId!);
      final servings = log.quantityG > 0 ? log.quantityG : 1.0;
      for (final ing in ings) {
        if (ing.itemId == null) continue;
        final entries = await db.inventoryEntriesForItem(ing.itemId!);
        final item = await db.itemById(ing.itemId!);
        final qty = ing.quantity * servings;
        final inventoryUnit =
            entries.isNotEmpty ? entries.first.unit : ing.unit;
        final initial = _defaultDeductQty(
          quantityG: qty,
          inventoryUnit: inventoryUnit,
          servingSizeG: item?.servingSizeG,
          consumeQty: item?.consumeQty,
          consumeUnit: item?.consumeUnit,
        );
        rows.add(_DeductRow(
          label: ing.name,
          itemId: ing.itemId,
          requestedQty: qty,
          requestedUnit: ing.unit,
          inventoryEntries: entries,
          selectedEntry: entries.isNotEmpty ? entries.first : null,
          skip: entries.isEmpty,
          initialDeductQty: initial,
        ));
      }
    } else if (log.source == 'recipe' && log.itemId != null) {
      // Recipe → deduct each ingredient
      final ings = await db.ingredientsForRecipe(log.itemId!);
      final servings = log.quantityG > 0 ? log.quantityG : 1.0;
      for (final ing in ings) {
        if (ing.itemId == null) continue;
        final entries = await db.inventoryEntriesForItem(ing.itemId!);
        final item = await db.itemById(ing.itemId!);
        final qty = ing.quantity * servings;
        final inventoryUnit =
            entries.isNotEmpty ? entries.first.unit : ing.unit;
        final initial = _defaultDeductQty(
          quantityG: qty,
          inventoryUnit: inventoryUnit,
          servingSizeG: item?.servingSizeG,
          consumeQty: item?.consumeQty,
          consumeUnit: item?.consumeUnit,
        );
        rows.add(_DeductRow(
          label: ing.name,
          itemId: ing.itemId,
          requestedQty: qty,
          requestedUnit: ing.unit,
          inventoryEntries: entries,
          selectedEntry: entries.isNotEmpty ? entries.first : null,
          skip: entries.isEmpty,
          initialDeductQty: initial,
        ));
      }
    } else if (log.itemId != null) {
      // Single local item
      final item = await db.itemById(log.itemId!);
      final entries = await db.inventoryEntriesForItem(log.itemId!);
      if (item != null) {
        final inventoryUnit =
            entries.isNotEmpty ? entries.first.unit : log.displayUnit;
        final initial = _defaultDeductQty(
          quantityG: log.quantityG,
          inventoryUnit: inventoryUnit,
          servingSizeG: item.servingSizeG,
          consumeQty: item.consumeQty,
          consumeUnit: item.consumeUnit,
        );
        rows.add(_DeductRow(
          label: item.name,
          brand: item.brand,
          itemId: item.id,
          requestedQty: log.quantityG,
          requestedUnit: log.displayUnit,
          inventoryEntries: entries,
          selectedEntry: entries.isNotEmpty ? entries.first : null,
          skip: entries.isEmpty,
          initialDeductQty: initial,
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

  Future<void> _confirm() async {
    final db = ref.read(databaseProvider);
    if (db == null) return;

    setState(() => _saving = true);
    try {
      for (final row in _rows) {
        if (row.skip || row.selectedEntry == null) continue;
        final entry = row.selectedEntry!;
        final deductQty = row.deductQty;
        if (deductQty <= 0) continue;

        // deductQty is already in the inventory entry's native unit
        // (the user edited the field in that unit directly).
        // Convert only for well-known weight/vol pairs where both sides differ.
        final native =
            _convertWeightVol(deductQty, row.deductUnit, entry.unit) ??
                deductQty;

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
              'Menge anpassen falls nötig, dann „Ausbuchen" tippen.',
              style:
                  TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 10),
            // Consumption reason
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
                  'Keine Lagerbestände für diesen Eintrag gefunden.',
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

  void _onQtyChanged() {
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasStock = row.inventoryEntries.isNotEmpty;
    final entry = row.selectedEntry;
    final inventoryUnit = entry?.unit ?? row.requestedUnit;

    // Show remaining after deduction for live feedback
    final currentQty = entry?.quantity ?? 0.0;
    final deductQty = row.deductQty;
    final remaining = (currentQty - deductQty).clamp(0.0, double.infinity);

    // Whether units differ (informational hint)
    final unitsDiffer = row.requestedUnit.toLowerCase().trim() !=
        inventoryUnit.toLowerCase().trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Checkbox + label
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
                  // Logged amount as hint (reference)
                  'Tagebuch: ${_fmtQty(row.requestedQty)} ${row.requestedUnit}'
                  '${unitsDiffer ? '  ·  Bestand in $inventoryUnit' : ''}',
                  style: TextStyle(
                      fontSize: 12, color: cs.onSurfaceVariant),
                ),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
          dense: true,
        ),

        // Editable deduction field + remaining preview
        if (hasStock && !row.skip) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(40, 0, 0, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Amount row: editable qty + unit label
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
                          fillColor:
                              cs.surfaceContainerHighest.withValues(
                                  alpha: 0.5),
                        ),
                        style: const TextStyle(fontSize: 14),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      inventoryUnit,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(width: 12),
                    // Live remaining preview
                    Text(
                      '→ verbleibend: ${_fmtQty(remaining)} $inventoryUnit',
                      style: TextStyle(
                        fontSize: 12,
                        color: remaining <= 0
                            ? cs.error
                            : cs.onSurfaceVariant,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
                // Inventory entry selector if multiple entries
                if (row.inventoryEntries.length > 1)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Wrap(
                      spacing: 8,
                      children: row.inventoryEntries.map((e) {
                        final selected =
                            row.selectedEntry?.id == e.id;
                        final label =
                            '${_fmtQty(e.quantity)} ${e.unit}'
                            '${e.expiryDate != null ? ' (MHD ${e.expiryDate!.day}.${e.expiryDate!.month}.)' : ''}';
                        return ChoiceChip(
                          label: Text(label,
                              style: const TextStyle(fontSize: 11)),
                          selected: selected,
                          onSelected: (_) {
                            row.selectedEntry = e;
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
