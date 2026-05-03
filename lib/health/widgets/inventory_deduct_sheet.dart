import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../db/database.dart';
import '../../providers/inventory_provider.dart';
import '../../providers/vault_provider.dart';
import '../providers/nutrition_provider.dart';

/// Data for one ingredient/food that may be deducted from inventory.
class _DeductRow {
  final String label; // ingredient or item name
  final String? brand;
  final String? itemId; // items table ID (null if group only / manual)
  final double requestedQty; // amount from the diary entry or ingredient
  final String requestedUnit; // unit from the diary entry or ingredient
  // Resolved: matching inventory entries for selection
  List<InventoryEntry> inventoryEntries;
  // Which inventory entry to deduct from (null = skip this row)
  InventoryEntry? selectedEntry;
  // Amount to actually deduct (may differ from requestedQty after unit conversion)
  double deductQty;
  String deductUnit;
  bool skip;

  _DeductRow({
    required this.label,
    this.brand,
    required this.itemId,
    required this.requestedQty,
    required this.requestedUnit,
    this.inventoryEntries = const [],
    this.selectedEntry,
    required this.deductQty,
    required this.deductUnit,
    this.skip = false,
  });
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

  Future<void> _loadRows() async {
    final db = ref.read(databaseProvider);
    if (db == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    final log = widget.log;
    final rows = <_DeductRow>[];

    if (log.source == 'meal' && log.itemId != null) {
      // Meal: load all ingredients
      final ings = await db.ingredientsForMeal(log.itemId!);
      final servings = log.quantityG > 0 ? log.quantityG : 1.0;
      for (final ing in ings) {
        if (ing.itemId == null) continue; // skip group-only or manual ingredients
        final entries = await db.inventoryEntriesForItem(ing.itemId!);
        final qty = ing.quantity * servings;
        rows.add(_DeductRow(
          label: ing.name,
          itemId: ing.itemId,
          requestedQty: qty,
          requestedUnit: ing.unit,
          inventoryEntries: entries,
          selectedEntry: entries.isNotEmpty ? entries.first : null,
          deductQty: qty,
          deductUnit: ing.unit,
          skip: entries.isEmpty,
        ));
      }
    } else if (log.source == 'recipe' && log.itemId != null) {
      // Recipe: load all ingredients
      final ings = await db.ingredientsForRecipe(log.itemId!);
      final servings = log.quantityG > 0 ? log.quantityG : 1.0;
      for (final ing in ings) {
        if (ing.itemId == null) continue;
        final entries = await db.inventoryEntriesForItem(ing.itemId!);
        final qty = ing.quantity * servings;
        rows.add(_DeductRow(
          label: ing.name,
          itemId: ing.itemId,
          requestedQty: qty,
          requestedUnit: ing.unit,
          inventoryEntries: entries,
          selectedEntry: entries.isNotEmpty ? entries.first : null,
          deductQty: qty,
          deductUnit: ing.unit,
          skip: entries.isEmpty,
        ));
      }
    } else if (log.itemId != null) {
      // Single local item
      final item = await db.itemById(log.itemId!);
      final entries = await db.inventoryEntriesForItem(log.itemId!);
      if (item != null) {
        // displayUnit could be g, ml, Portion, Stück…
        // Use the stored quantity and unit from the log as-is
        rows.add(_DeductRow(
          label: item.name,
          brand: item.brand,
          itemId: item.id,
          requestedQty: log.quantityG,
          requestedUnit: log.displayUnit,
          inventoryEntries: entries,
          selectedEntry: entries.isNotEmpty ? entries.first : null,
          deductQty: log.quantityG,
          deductUnit: log.displayUnit,
          skip: entries.isEmpty,
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
        // Determine how many units to remove in the inventory entry's native unit.
        // Simple case: if units match, deduct directly.
        // Otherwise we pass the requested unit to consume() and let it record the event.
        final deductNative = _convertToUnit(
          row.deductQty,
          row.deductUnit,
          entry.unit,
        ) ?? row.deductQty;

        final remaining =
            (entry.quantity - deductNative).clamp(0.0, double.infinity);
        await ref.read(inventoryOpsProvider.notifier).consume(
          itemId: row.itemId!,
          inventoryEntryId: entry.id,
          quantity: deductNative,
          unit: entry.unit,
          remainingQuantity: remaining,
          consumptionReason: _consumptionReason,
        );
      }
      // Mark the diary log as deducted if it has a real ID
      if (widget.log.id.isNotEmpty) {
        await ref.read(nutritionOpsProvider.notifier)
            .setInventoryDeducted(widget.log.id, true);
      }
      if (mounted) Navigator.of(context).pop(true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Best-effort unit conversion for deduction. Returns null if conversion
  /// is unknown — caller falls back to raw value.
  double? _convertToUnit(double qty, String from, String to) {
    final f = from.toLowerCase().trim();
    final t = to.toLowerCase().trim();
    if (f == t) return qty;
    // g ↔ kg
    if (f == 'g' && (t == 'kg' || t == 'kilogramm')) return qty / 1000;
    if ((f == 'kg' || f == 'kilogramm') && t == 'g') return qty * 1000;
    // ml ↔ l
    if (f == 'ml' && (t == 'l' || t == 'liter')) return qty / 1000;
    if ((f == 'l' || f == 'liter') && t == 'ml') return qty * 1000;
    // cl/dl ↔ ml
    if (f == 'cl' && t == 'ml') return qty * 10;
    if (f == 'ml' && t == 'cl') return qty / 10;
    if (f == 'dl' && t == 'ml') return qty * 100;
    if (f == 'ml' && t == 'dl') return qty / 100;
    return null;
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

            Text(
              'Bestand reduzieren?',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Sollen die verbrauchten Mengen aus deinem Inventar ausgebucht werden?',
              style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 10),
            // Consumption reason selector
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'consumed', label: Text('Konsumiert'), icon: Icon(Icons.restaurant, size: 14)),
                ButtonSegment(value: 'expired', label: Text('Abgelaufen'), icon: Icon(Icons.event_busy, size: 14)),
                ButtonSegment(value: 'discarded', label: Text('Weggeworfen'), icon: Icon(Icons.delete_outline, size: 14)),
                ButtonSegment(value: 'gifted', label: Text('Verschenkt'), icon: Icon(Icons.card_giftcard, size: 14)),
              ],
              selected: {_consumptionReason},
              onSelectionChanged: (s) => setState(() => _consumptionReason = s.first),
              style: ButtonStyle(
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
              ))
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
                          _rows.every((r) => r.skip))
                      ? null
                      : _confirm,
                  child: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
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

class _RowTile extends StatelessWidget {
  final _DeductRow row;
  final VoidCallback onChanged;

  const _RowTile({required this.row, required this.onChanged});

  String _fmtQty(double v) =>
      v % 1 == 0 ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasStock = row.inventoryEntries.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CheckboxListTile(
          value: !row.skip,
          onChanged: hasStock
              ? (v) {
                  row.skip = !(v ?? false);
                  onChanged();
                }
              : null,
          title: Text(
            row.label,
            style: TextStyle(
              color: row.skip || !hasStock ? cs.onSurfaceVariant : null,
              decoration:
                  !hasStock ? TextDecoration.lineThrough : null,
            ),
          ),
          subtitle: Text(
            hasStock
                ? '${_fmtQty(row.deductQty)} ${row.deductUnit} — '
                    'Bestand: ${_fmtQty(row.selectedEntry?.quantity ?? 0)} '
                    '${row.selectedEntry?.unit ?? ''}'
                : 'Kein Bestand vorhanden',
            style: TextStyle(
                fontSize: 12, color: cs.onSurfaceVariant),
          ),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
          dense: true,
        ),
        // If multiple inventory entries, show radio selector
        if (!row.skip && row.inventoryEntries.length > 1)
          Padding(
            padding: const EdgeInsets.only(left: 40, bottom: 4),
            child: Wrap(
              spacing: 8,
              children: row.inventoryEntries.map((e) {
                final selected = row.selectedEntry?.id == e.id;
                final label =
                    '${_fmtQty(e.quantity)} ${e.unit}'
                    '${e.expiryDate != null ? ' (MHD ${e.expiryDate!.day}.${e.expiryDate!.month}.)' : ''}';
                return ChoiceChip(
                  label: Text(label, style: const TextStyle(fontSize: 11)),
                  selected: selected,
                  onSelected: (_) {
                    row.selectedEntry = e;
                    onChanged();
                  },
                  visualDensity: VisualDensity.compact,
                );
              }).toList(),
            ),
          ),
      ],
    );
  }
}
