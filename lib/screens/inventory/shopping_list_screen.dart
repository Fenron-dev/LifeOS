import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../db/database.dart';
import '../../providers/groups_provider.dart';
import '../../providers/vault_provider.dart';
import '../items/item_detail_screen.dart';

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
                      _showBuyFlow(context, ref, need),
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

  Future<void> _showBuyFlow(
      BuildContext context, WidgetRef ref, ShoppingNeed need) async {
    final db = ref.read(databaseProvider);
    if (db == null) return;

    final members = await db.membersForGroup(need.group.id);
    if (members.isEmpty || !context.mounted) return;

    Item? selectedItem;

    if (members.length == 1) {
      // Only one article — load it directly
      selectedItem = await db.itemById(members.first.itemId);
    } else {
      // Let user pick which article to stock
      final items = await Future.wait(
          members.map((m) => db.itemById(m.itemId)));
      final available = items.whereType<Item>().toList();
      if (!context.mounted) return;
      selectedItem = await showDialog<Item>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: const Text('Welchen Artikel einlagern?'),
          children: available.map((item) => SimpleDialogOption(
            onPressed: () => Navigator.of(ctx).pop(item),
            child: ListTile(
              dense: true,
              leading: const Icon(Icons.inventory_2_outlined),
              title: Text(item.name),
              subtitle: item.brand != null ? Text(item.brand!) : null,
            ),
          )).toList(),
        ),
      );
    }

    if (selectedItem == null || !context.mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => AddStockSheet(item: selectedItem!),
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

