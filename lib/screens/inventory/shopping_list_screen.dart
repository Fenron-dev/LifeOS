import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/groups_provider.dart';
import '../../providers/inventory_provider.dart';
import '../../providers/vault_provider.dart';

class ShoppingListScreen extends ConsumerWidget {
  const ShoppingListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final needsAsync = ref.watch(shoppingNeedsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Einkaufsliste'),
        actions: [
          IconButton(
            icon: const Icon(Icons.category_outlined),
            tooltip: 'Produktgruppen verwalten',
            onPressed: () => context.push('/inventory/groups'),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Aktualisieren',
            onPressed: () => ref.invalidate(shoppingNeedsProvider),
          ),
        ],
      ),
      body: needsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Fehler: $e')),
        data: (needs) {
          if (needs.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle_outline,
                      size: 64,
                      color: Theme.of(context).colorScheme.primary),
                  const SizedBox(height: 16),
                  const Text('Alles ausreichend vorhanden!'),
                  const SizedBox(height: 8),
                  const Text(
                    'Definiere Produktgruppen mit Mindestbestand,\num automatisch zu sehen was fehlt.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: () => context.push('/inventory/groups'),
                    icon: const Icon(Icons.category_outlined),
                    label: const Text('Produktgruppen'),
                  ),
                ],
              ),
            );
          }

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Row(
                  children: [
                    Icon(Icons.info_outline,
                        size: 16,
                        color: Theme.of(context).colorScheme.outline),
                    const SizedBox(width: 8),
                    Text(
                      '${needs.length} Artikel unter Mindestbestand',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  itemCount: needs.length,
                  itemBuilder: (context, i) =>
                      _NeedCard(need: needs[i]),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ── Need card ─────────────────────────────────────────────────────────────────

class _NeedCard extends ConsumerWidget {
  final ShoppingNeed need;
  const _NeedCard({required this.need});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final unit = need.group.minStockUnit ?? '';
    final minQty = need.group.minStockQuantity!;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(need.group.name,
                      style: theme.textTheme.titleMedium),
                ),
                _StockIndicator(
                    current: need.currentQty,
                    min: minQty,
                    unit: unit),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: (need.currentQty / minQty).clamp(0.0, 1.0),
                minHeight: 6,
                backgroundColor:
                    theme.colorScheme.errorContainer,
                valueColor: AlwaysStoppedAnimation(
                    theme.colorScheme.error),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton.icon(
                  onPressed: () =>
                      _showBuyDialog(context, ref, need),
                  icon: const Icon(Icons.add_shopping_cart, size: 18),
                  label: Text(
                      'Einkaufen (+${_fmt(need.neededQty)} $unit)'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _fmt(double q) =>
      q == q.truncateToDouble() ? q.toInt().toString() : q.toStringAsFixed(1);

  void _showBuyDialog(
      BuildContext context, WidgetRef ref, ShoppingNeed need) {
    showDialog(
      context: context,
      builder: (_) => _QuickBuyDialog(need: need),
    );
  }
}

class _StockIndicator extends StatelessWidget {
  final double current;
  final double min;
  final String unit;
  const _StockIndicator(
      {required this.current, required this.min, required this.unit});

  String _fmt(double q) =>
      q == q.truncateToDouble() ? q.toInt().toString() : q.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          '${_fmt(current)} / ${_fmt(min)} $unit',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.error,
                fontWeight: FontWeight.bold,
              ),
        ),
        Text('vorhanden / Minimum',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.outline)),
      ],
    );
  }
}

// ── Quick buy dialog ──────────────────────────────────────────────────────────

class _QuickBuyDialog extends ConsumerStatefulWidget {
  final ShoppingNeed need;
  const _QuickBuyDialog({required this.need});

  @override
  ConsumerState<_QuickBuyDialog> createState() => _QuickBuyDialogState();
}

class _QuickBuyDialogState extends ConsumerState<_QuickBuyDialog> {
  late final TextEditingController _qtyCtrl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final needed = widget.need.neededQty;
    final q = needed == needed.truncateToDouble()
        ? needed.toInt().toString()
        : needed.toStringAsFixed(1);
    _qtyCtrl = TextEditingController(text: q);
  }

  @override
  void dispose() {
    _qtyCtrl.dispose();
    super.dispose();
  }

  Future<void> _buy() async {
    final qty =
        double.tryParse(_qtyCtrl.text.replaceAll(',', '.'));
    if (qty == null || qty <= 0) return;
    setState(() => _saving = true);

    // Get first member item of the group to record purchase against
    final db = ref.read(databaseProvider);
    if (db == null) return;
    final members = await db.membersForGroup(widget.need.group.id);
    if (members.isEmpty || !mounted) {
      setState(() => _saving = false);
      return;
    }

    try {
      await ref.read(inventoryOpsProvider.notifier).purchase(
            itemId: members.first.itemId,
            quantity: qty,
            unit: widget.need.group.minStockUnit ?? 'Stück',
          );
      if (mounted) {
        Navigator.of(context).pop();
        ref.invalidate(shoppingNeedsProvider);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final unit = widget.need.group.minStockUnit ?? 'Stück';
    return AlertDialog(
      title: Text('Einkaufen: ${widget.need.group.name}'),
      content: TextField(
        controller: _qtyCtrl,
        decoration: InputDecoration(
          labelText: 'Eingekaufte Menge ($unit)',
        ),
        keyboardType:
            const TextInputType.numberWithOptions(decimal: true),
        autofocus: true,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: _saving ? null : _buy,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child:
                      CircularProgressIndicator(strokeWidth: 2))
              : const Text('Einlagern'),
        ),
      ],
    );
  }
}
