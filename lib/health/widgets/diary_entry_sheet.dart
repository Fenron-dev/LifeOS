import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../providers/nutrition_provider.dart';
import 'food_search_sheet.dart';

/// Bottom sheet for adding one food diary entry. Flow:
///   1. Tap "Lebensmittel wählen" → opens [FoodSearchSheet]
///   2. Product fills in name/brand/macros
///   3. User enters quantity (g), optionally adjusts meal slot + time
///   4. Tap "Speichern"
class DiaryEntrySheet extends ConsumerStatefulWidget {
  /// Pre-selected meal-type id (e.g. 'mt_fruehstueck') — can be null.
  final String? initialMealTypeId;

  /// Pre-selected log time — defaults to now.
  final DateTime? initialLoggedAt;

  const DiaryEntrySheet({
    super.key,
    this.initialMealTypeId,
    this.initialLoggedAt,
  });

  @override
  ConsumerState<DiaryEntrySheet> createState() => _DiaryEntrySheetState();
}

class _DiaryEntrySheetState extends ConsumerState<DiaryEntrySheet> {
  final _qtyController = TextEditingController();
  final _notesController = TextEditingController();

  FoodSearchResult? _product;
  String? _mealTypeId;
  DateTime _loggedAt = DateTime.now();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _mealTypeId = widget.initialMealTypeId;
    _loggedAt = widget.initialLoggedAt ?? DateTime.now();
  }

  @override
  void dispose() {
    _qtyController.dispose();
    _notesController.dispose();
    super.dispose();
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
      // Pre-fill quantity with serving size if available
      if (result.servingSizeG != null && _qtyController.text.trim().isEmpty) {
        _qtyController.text =
            result.servingSizeG!.toStringAsFixed(0);
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

  double? _scale(double? per100, double qty) {
    if (per100 == null) return null;
    return per100 * qty / 100;
  }

  Future<void> _save() async {
    if (_product == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Bitte zuerst ein Lebensmittel wählen.')),
      );
      return;
    }
    final qtyText = _qtyController.text.trim().replaceAll(',', '.');
    final qty = double.tryParse(qtyText);
    if (qty == null || qty <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bitte eine gültige Menge eingeben.')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      await ref.read(nutritionOpsProvider.notifier).logFood(
            loggedAt: _loggedAt,
            productName: _product!.productName,
            brand: _product!.brand,
            mealTypeId: _mealTypeId,
            itemId: _product!.itemId,
            ean: _product!.ean,
            quantityG: qty,
            displayUnit: 'g',
            kcal: _scale(_product!.caloriesPer100g, qty),
            proteinG: _scale(_product!.proteinPer100g, qty),
            carbsG: _scale(_product!.carbsPer100g, qty),
            fatG: _scale(_product!.fatPer100g, qty),
            fiberG: _scale(_product!.fiberPer100g, qty),
            source: _product!.source,
            notes:
                _notesController.text.trim().isEmpty
                    ? null
                    : _notesController.text.trim(),
          );
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.of(context).viewInsets.bottom;
    final cs = Theme.of(context).colorScheme;
    final mealTypes = ref.watch(mealTypesProvider).valueOrNull ?? [];

    return Padding(
      padding: EdgeInsets.only(
          left: 16, right: 16, top: 8, bottom: 16 + inset),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Handle
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
            Text('Eintrag hinzufügen',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),

            // ── Product picker ─────────────────────────────────────────────
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
                child: Text(_product!.brand!,
                    style: TextStyle(
                        color: cs.onSurfaceVariant, fontSize: 12)),
              ),
            const SizedBox(height: 12),

            // ── Nutrition preview ─────────────────────────────────────────
            if (_product != null && _product!.caloriesPer100g != null)
              _NutritionPreview(
                  product: _product!, qty: _qtyController.text),

            // ── Quantity ──────────────────────────────────────────────────
            TextFormField(
              controller: _qtyController,
              autofocus: _product != null,
              decoration: const InputDecoration(
                labelText: 'Menge *',
                suffixText: 'g',
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
            const SizedBox(height: 12),

            // ── Meal type dropdown ────────────────────────────────────────
            if (mealTypes.isNotEmpty)
              DropdownButtonFormField<String?>(
                initialValue: _mealTypeId,
                decoration: const InputDecoration(
                  labelText: 'Mahlzeit',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.restaurant_outlined),
                ),
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
            const SizedBox(height: 12),

            // ── Date/time ─────────────────────────────────────────────────
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

            // ── Notes ─────────────────────────────────────────────────────
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

            // ── Actions ───────────────────────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _saving
                        ? null
                        : () => Navigator.of(context).pop(),
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
                            child: CircularProgressIndicator(
                                strokeWidth: 2))
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

// ── Live nutrition preview card ───────────────────────────────────────────────

class _NutritionPreview extends StatelessWidget {
  final FoodSearchResult product;
  final String qty;

  const _NutritionPreview({required this.product, required this.qty});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final g = double.tryParse(qty.replaceAll(',', '.')) ?? 0;
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
              label: 'Protein', value: '${calc(product.proteinPer100g)} g', cs: cs),
          _MacroCell(
              label: 'Kohlenhydrate', value: '${calc(product.carbsPer100g)} g', cs: cs),
          _MacroCell(
              label: 'Fett', value: '${calc(product.fatPer100g)} g', cs: cs),
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
          Text(value,
              style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: highlight ? 18 : 14,
                  color: highlight ? cs.primary : cs.onSurface)),
          Text(label,
              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
        ],
      );
}
