import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../db/database.dart';
import '../../providers/inventory_provider.dart';
import '../../providers/items_provider.dart';
import '../../providers/unit_conversions_provider.dart';
import '../../providers/settings_provider.dart';
import '../../widgets/adaptive_shell.dart';

class InventoryScreen extends ConsumerWidget {
  const InventoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemsAsync = ref.watch(filteredItemsProvider);
    final query = ref.watch(itemSearchQueryProvider);
    final quickActions = ref.watch(settingsProvider).valueOrNull?.quickActions
        ?? AppSettingsData.defaultQuickActions;
    final hasScanAction = quickActions.contains(QuickAction.scanBarcode);
    final hasAddAction = quickActions.contains(QuickAction.addInventory);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Inventar'),
        actions: [
          IconButton(
            icon: const Icon(Icons.shopping_cart_outlined),
            tooltip: 'Einkaufsliste',
            onPressed: () => context.push('/inventory/shopping'),
          ),
          ...shellMenuActions(context),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: SearchBar(
              hintText: 'Artikel suchen…',
              leading: const Icon(Icons.search),
              trailing: query.isNotEmpty
                  ? [
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => ref
                            .read(itemSearchQueryProvider.notifier)
                            .state = '',
                      ),
                    ]
                  : null,
              onChanged: (v) =>
                  ref.read(itemSearchQueryProvider.notifier).state = v,
            ),
          ),
        ),
      ),
      body: itemsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Fehler: $e')),
        data: (items) => items.isEmpty
            ? _EmptyState(hasQuery: query.isNotEmpty)
            : _ItemsList(items: items),
      ),
      floatingActionButton: (hasScanAction && hasAddAction) ? null : Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!hasScanAction)
            FloatingActionButton.small(
              heroTag: 'scan',
              onPressed: () => _scanBarcode(context, ref),
              tooltip: 'Barcode scannen',
              child: const Icon(Icons.qr_code_scanner),
            ),
          if (!hasScanAction && !hasAddAction) const SizedBox(height: 8),
          if (!hasAddAction)
            FloatingActionButton(
              heroTag: 'add',
              onPressed: () => context.push('/inventory/item/new'),
              tooltip: 'Artikel hinzufügen',
              child: const Icon(Icons.add),
            ),
        ],
      ),
    );
  }

  Future<void> _scanBarcode(BuildContext context, WidgetRef ref) async {
    final ean = await context.push<String>('/scan');
    if (ean == null || !context.mounted) return;

    // Check if item with this EAN already exists
    final dao = ref.read(itemsDaoProvider);
    final existing = await dao?.itemByEan(ean);
    if (!context.mounted) return;

    if (existing != null) {
      // Navigate to item detail
      context.push('/inventory/item/${existing.id}');
    } else {
      // Create new item with pre-filled EAN
      context.push('/inventory/item/new', extra: ean);
    }
  }
}

class _ItemsList extends ConsumerWidget {
  final List<Item> items;
  const _ItemsList({required this.items});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stockMap = ref.watch(itemStockMapProvider).valueOrNull ?? {};
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      itemCount: items.length,
      itemBuilder: (context, i) =>
          _ItemCard(item: items[i], states: stockMap[items[i].id] ?? []),
    );
  }
}

class _ItemCard extends StatelessWidget {
  final Item item;
  final List<ItemState> states;
  const _ItemCard({required this.item, required this.states});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: _ProductTypeIcon(type: item.productType),
        title: Text(
          item.name,
          style: theme.textTheme.titleSmall,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (item.brand != null)
              Text(
                item.brand!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            Row(
              children: [
                if (item.ean != null) ...[
                  Icon(Icons.barcode_reader, size: 12,
                      color: theme.colorScheme.outline),
                  const SizedBox(width: 4),
                ],
                _StockBadge(item: item, states: states),
              ],
            ),
          ],
        ),
        trailing: const Icon(Icons.chevron_right),
        isThreeLine: item.brand != null,
        onTap: () => context.push('/inventory/item/${item.id}'),
      ),
    );
  }
}

class _StockBadge extends ConsumerWidget {
  final Item item;
  final List<ItemState> states;
  const _StockBadge({required this.item, required this.states});

  String _fmt(double v) =>
      v == v.truncateToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (states.isEmpty) return const SizedBox.shrink();

    String label;
    final stockUnit = item.stockUnit;

    if (stockUnit != null) {
      // Try to convert all quantities to stockUnit via item conversions
      final convs = ref
          .watch(itemConversionsProvider(item.id))
          .valueOrNull ?? [];
      final globalConvs = ref
          .watch(globalConversionsProvider)
          .valueOrNull ?? [];
      final allConvs = [...convs, ...globalConvs];

      double total = 0;
      bool allConverted = true;
      for (final s in states) {
        if (s.unit == stockUnit) {
          total += s.currentQuantity;
        } else {
          // Look for conversion s.unit → stockUnit
          final conv = allConvs.where((c) =>
              c.fromUnit == s.unit && c.toUnit == stockUnit).firstOrNull;
          if (conv != null) {
            total += s.currentQuantity * conv.factor;
          } else {
            allConverted = false;
            total += s.currentQuantity; // fallback: add raw
          }
        }
      }
      label = allConverted
          ? '${_fmt(total)} $stockUnit'
          : '${_fmt(total)} $stockUnit*'; // * = conversion incomplete
    } else {
      // No stockUnit: group by unit and sum
      final Map<String, double> byUnit = {};
      for (final s in states) {
        byUnit[s.unit] = (byUnit[s.unit] ?? 0) + s.currentQuantity;
      }
      label = byUnit.entries
          .map((e) => '${_fmt(e.value)} ${e.key}')
          .join(' + ');
    }

    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Chip(
        label: Text(label, style: const TextStyle(fontSize: 11)),
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        side: BorderSide.none,
        backgroundColor:
            Theme.of(context).colorScheme.secondaryContainer,
      ),
    );
  }
}

class _ProductTypeIcon extends StatelessWidget {
  final String type;
  const _ProductTypeIcon({required this.type});

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (type) {
      'readyToEat' => (Icons.lunch_dining, Colors.orange),
      'ingredient' => (Icons.spa, Colors.green),
      _ => (Icons.kitchen, Theme.of(context).colorScheme.primary),
    };
    return CircleAvatar(
      backgroundColor: color.withValues(alpha: 0.15),
      child: Icon(icon, color: color, size: 20),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final bool hasQuery;
  const _EmptyState({required this.hasQuery});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.inventory_2_outlined,
              size: 64, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 16),
          Text(
            hasQuery ? 'Keine Treffer' : 'Noch keine Artikel',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (!hasQuery) ...[
            const SizedBox(height: 8),
            const Text('Tippe + um einen Artikel hinzuzufügen\noder scanne einen Barcode.'),
          ],
        ],
      ),
    );
  }
}
