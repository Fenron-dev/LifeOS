import 'package:flutter/material.dart';

import '../../services/open_food_facts_service.dart';

/// Shows a dialog that lets the user pick which OFF fields to import.
/// Returns the set of selected [OFFField]s, or null if cancelled.
Future<Set<OFFField>?> showOffImportDialog(
  BuildContext context,
  OFFProduct product,
) {
  return showDialog<Set<OFFField>>(
    context: context,
    builder: (_) => _OffImportDialog(product: product),
  );
}

class _OffImportDialog extends StatefulWidget {
  final OFFProduct product;
  const _OffImportDialog({required this.product});

  @override
  State<_OffImportDialog> createState() => _OffImportDialogState();
}

class _OffImportDialogState extends State<_OffImportDialog> {
  late final Set<OFFField> _selected;

  @override
  void initState() {
    super.initState();
    // Pre-select all available fields
    _selected = OFFField.values
        .where((f) => widget.product.hasField(f))
        .toSet();
  }

  void _toggle(OFFField field, bool? checked) {
    setState(() {
      if (checked == true) {
        _selected.add(field);
      } else {
        _selected.remove(field);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    return AlertDialog(
      title: const Text('OpenFoodFacts – Daten übernehmen'),
      contentPadding: const EdgeInsets.fromLTRB(8, 16, 8, 0),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(
          shrinkWrap: true,
          children: [
            // ── Basic info ────────────────────────────────────────────────
            _SectionHeader('Produktinfo'),
            _FieldTile(
              field: OFFField.name,
              label: 'Name',
              value: p.name,
              product: p,
              selected: _selected,
              onChanged: _toggle,
            ),
            _FieldTile(
              field: OFFField.brand,
              label: 'Marke',
              value: p.brand,
              product: p,
              selected: _selected,
              onChanged: _toggle,
            ),
            _FieldTile(
              field: OFFField.nutriscore,
              label: 'Nutri-Score',
              value: p.nutriscore?.toUpperCase(),
              product: p,
              selected: _selected,
              onChanged: _toggle,
            ),
            _FieldTile(
              field: OFFField.novaGroup,
              label: 'NOVA-Gruppe',
              value: p.novaGroup != null ? '${p.novaGroup}' : null,
              product: p,
              selected: _selected,
              onChanged: _toggle,
            ),
            _FieldTile(
              field: OFFField.servingSize,
              label: 'Portionsgröße',
              value: p.servingSizeG != null ? '${_fmt(p.servingSizeG!)} g' : null,
              product: p,
              selected: _selected,
              onChanged: _toggle,
            ),
            _FieldTile(
              field: OFFField.ingredientsText,
              label: 'Zutaten',
              value: p.ingredientsText != null
                  ? _truncate(p.ingredientsText!, 80)
                  : null,
              product: p,
              selected: _selected,
              onChanged: _toggle,
            ),

            // ── Nutrition ─────────────────────────────────────────────────
            _SectionHeader('Nährwerte pro 100g'),
            _FieldTile(
              field: OFFField.calories,
              label: 'Kalorien (kcal)',
              value: p.calories != null ? '${_fmt(p.calories!)} kcal' : null,
              product: p,
              selected: _selected,
              onChanged: _toggle,
            ),
            _FieldTile(
              field: OFFField.protein,
              label: 'Eiweiß (g)',
              value: p.protein != null ? '${_fmt(p.protein!)} g' : null,
              product: p,
              selected: _selected,
              onChanged: _toggle,
            ),
            _FieldTile(
              field: OFFField.carbs,
              label: 'Kohlenhydrate (g)',
              value: p.carbs != null ? '${_fmt(p.carbs!)} g' : null,
              product: p,
              selected: _selected,
              onChanged: _toggle,
            ),
            _FieldTile(
              field: OFFField.sugars,
              label: 'davon Zucker (g)',
              value: p.sugars != null ? '${_fmt(p.sugars!)} g' : null,
              product: p,
              selected: _selected,
              onChanged: _toggle,
            ),
            _FieldTile(
              field: OFFField.fat,
              label: 'Fett (g)',
              value: p.fat != null ? '${_fmt(p.fat!)} g' : null,
              product: p,
              selected: _selected,
              onChanged: _toggle,
            ),
            _FieldTile(
              field: OFFField.saturatedFat,
              label: 'davon gesättigte Fettsäuren (g)',
              value: p.saturatedFat != null ? '${_fmt(p.saturatedFat!)} g' : null,
              product: p,
              selected: _selected,
              onChanged: _toggle,
            ),
            _FieldTile(
              field: OFFField.fiber,
              label: 'Ballaststoffe (g)',
              value: p.fiber != null ? '${_fmt(p.fiber!)} g' : null,
              product: p,
              selected: _selected,
              onChanged: _toggle,
            ),
            _FieldTile(
              field: OFFField.salt,
              label: 'Salz (g)',
              value: p.salt != null ? '${_fmt(p.salt!)} g' : null,
              product: p,
              selected: _selected,
              onChanged: _toggle,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: _selected.isEmpty
              ? null
              : () => Navigator.of(context).pop(_selected),
          child: const Text('Übernehmen'),
        ),
      ],
    );
  }

  String _fmt(double v) =>
      v == v.truncateToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

  String _truncate(String s, int max) =>
      s.length <= max ? s : '${s.substring(0, max)}…';
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.8,
            ),
      ),
    );
  }
}

class _FieldTile extends StatelessWidget {
  final OFFField field;
  final String label;
  final String? value;
  final OFFProduct product;
  final Set<OFFField> selected;
  final void Function(OFFField, bool?) onChanged;

  const _FieldTile({
    required this.field,
    required this.label,
    required this.value,
    required this.product,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final available = product.hasField(field);
    return CheckboxListTile(
      dense: true,
      enabled: available,
      title: Text(label,
          style: TextStyle(
              color: available ? null : Theme.of(context).disabledColor)),
      subtitle: available
          ? Text(value ?? '',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ))
          : Text('nicht verfügbar',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).disabledColor,
                    fontStyle: FontStyle.italic,
                  )),
      value: available ? selected.contains(field) : false,
      onChanged: available ? (v) => onChanged(field, v) : null,
    );
  }
}
