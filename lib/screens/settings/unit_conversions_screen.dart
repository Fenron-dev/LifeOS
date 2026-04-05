import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../db/database.dart';
import '../../providers/unit_conversions_provider.dart';

/// Full screen for managing global unit conversions.
class UnitConversionsScreen extends ConsumerWidget {
  const UnitConversionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conversionsAsync = ref.watch(globalConversionsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Einheiten-Umrechnung')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                Icon(Icons.info_outline,
                    size: 16, color: Theme.of(context).colorScheme.outline),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Globale Regeln gelten für alle Artikel und Gruppen. '
                    'Gruppen- und Artikel-spezifische Regeln haben Vorrang.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: conversionsAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Fehler: $e')),
              data: (conversions) {
                if (conversions.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.swap_horiz,
                            size: 64,
                            color: Theme.of(context).colorScheme.outline),
                        const SizedBox(height: 16),
                        const Text('Keine globalen Umrechnungen'),
                        const SizedBox(height: 4),
                        const Text(
                          'z. B. 1 kg = 1000 g',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                  itemCount: conversions.length,
                  itemBuilder: (context, i) =>
                      ConversionTile(conversion: conversions[i]),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => showAddConversionDialog(
          context,
          onSave: (from, to, factor) => ref
              .read(conversionsNotifierProvider.notifier)
              .addGlobal(fromUnit: from, toUnit: to, factor: factor),
        ),
        tooltip: 'Umrechnung hinzufügen',
        child: const Icon(Icons.add),
      ),
    );
  }
}

// ── Reusable tile ──────────────────────────────────────────────────────────

class ConversionTile extends ConsumerWidget {
  final UnitConversion conversion;
  const ConversionTile({super.key, required this.conversion});

  String _fmt(double v) =>
      v == v.truncateToDouble() ? v.toInt().toString() : v.toStringAsFixed(3);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        dense: true,
        leading: const Icon(Icons.swap_horiz),
        title: Text(
          '1 ${conversion.fromUnit} = ${_fmt(conversion.factor)} ${conversion.toUnit}',
        ),
        subtitle: conversion.notes != null ? Text(conversion.notes!) : null,
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline, color: Colors.red),
          tooltip: 'Löschen',
          onPressed: () =>
              ref.read(conversionsNotifierProvider.notifier).delete(conversion.id),
        ),
      ),
    );
  }
}

// ── Reusable inline section (for GroupsScreen and ItemFormScreen) ──────────

/// A compact list of conversions with an add-button, for embedding in cards.
class ConversionsList extends ConsumerWidget {
  final List<UnitConversion> conversions;
  final VoidCallback onAdd;
  final String addTooltip;

  const ConversionsList({
    super.key,
    required this.conversions,
    required this.onAdd,
    this.addTooltip = 'Umrechnung hinzufügen',
  });

  String _fmt(double v) =>
      v == v.truncateToDouble() ? v.toInt().toString() : v.toStringAsFixed(3);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Einheiten-Umrechnung',
                style: Theme.of(context).textTheme.labelMedium),
            const Spacer(),
            TextButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Hinzufügen'),
            ),
          ],
        ),
        if (conversions.isEmpty)
          Text(
            'Noch keine Umrechnungen definiert.',
            style: TextStyle(
                color: Theme.of(context).colorScheme.outline,
                fontSize: 12),
          )
        else
          ...conversions.map((c) => Row(
                children: [
                  Expanded(
                    child: Text(
                      '1 ${c.fromUnit} = ${_fmt(c.factor)} ${c.toUnit}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline,
                        size: 18, color: Colors.red),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => ref
                        .read(conversionsNotifierProvider.notifier)
                        .delete(c.id),
                  ),
                ],
              )),
      ],
    );
  }
}

// ── Add conversion dialog ──────────────────────────────────────────────────

Future<void> showAddConversionDialog(
  BuildContext context, {
  required Future<void> Function(String from, String to, double factor) onSave,
}) {
  return showDialog(
    context: context,
    builder: (_) => _AddConversionDialog(onSave: onSave),
  );
}

class _AddConversionDialog extends StatefulWidget {
  final Future<void> Function(String from, String to, double factor) onSave;
  const _AddConversionDialog({required this.onSave});

  @override
  State<_AddConversionDialog> createState() => _AddConversionDialogState();
}

class _AddConversionDialogState extends State<_AddConversionDialog> {
  final _fromCtrl = TextEditingController();
  final _toCtrl = TextEditingController();
  final _factorCtrl = TextEditingController();
  bool _saving = false;

  static const _commonUnits = [
    'g', 'kg', 'ml', 'l', 'Stück', 'Packung', 'Dose', 'Flasche',
    'Tüte', 'EL', 'TL', 'Tasse', 'Scheibe', 'Portion',
  ];

  @override
  void dispose() {
    _fromCtrl.dispose();
    _toCtrl.dispose();
    _factorCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final from = _fromCtrl.text.trim();
    final to = _toCtrl.text.trim();
    final factor = double.tryParse(_factorCtrl.text.replaceAll(',', '.'));
    if (from.isEmpty || to.isEmpty || factor == null || factor <= 0) return;
    setState(() => _saving = true);
    try {
      await widget.onSave(from, to, factor);
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _unitField(TextEditingController ctrl, String label) {
    return Autocomplete<String>(
      optionsBuilder: (v) => v.text.isEmpty
          ? _commonUnits
          : _commonUnits
              .where((u) => u.toLowerCase().contains(v.text.toLowerCase())),
      onSelected: (v) => ctrl.text = v,
      fieldViewBuilder: (context, textCtrl, focusNode, onSubmit) {
        // Sync external controller with internal autocomplete controller
        if (textCtrl.text != ctrl.text) textCtrl.text = ctrl.text;
        textCtrl.addListener(() => ctrl.text = textCtrl.text);
        return TextField(
          controller: textCtrl,
          focusNode: focusNode,
          decoration: InputDecoration(labelText: label),
          textCapitalization: TextCapitalization.sentences,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Umrechnung hinzufügen'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            '1 [Von-Einheit] = Faktor × [Zu-Einheit]',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _unitField(_fromCtrl, 'Von-Einheit')),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _factorCtrl,
                  decoration: const InputDecoration(labelText: 'Faktor'),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(child: _unitField(_toCtrl, 'Zu-Einheit')),
            ],
          ),
          const SizedBox(height: 8),
          ListenableBuilder(
            listenable:
                Listenable.merge([_fromCtrl, _toCtrl, _factorCtrl]),
            builder: (context, _) {
              final f = _fromCtrl.text.isEmpty ? '?' : _fromCtrl.text;
              final t = _toCtrl.text.isEmpty ? '?' : _toCtrl.text;
              final v =
                  _factorCtrl.text.isEmpty ? '?' : _factorCtrl.text;
              return Text(
                'Vorschau: 1 $f = $v $t',
                style: const TextStyle(
                    fontSize: 12, fontStyle: FontStyle.italic),
              );
            },
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Hinzufügen'),
        ),
      ],
    );
  }
}
