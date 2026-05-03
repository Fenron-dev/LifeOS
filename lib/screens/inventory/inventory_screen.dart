import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/item_categories.dart';
import '../../db/database.dart';
import '../../providers/categories_provider.dart';
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
            icon: const Icon(Icons.event_available_outlined),
            tooltip: 'Haltbarkeit',
            onPressed: () => context.push('/inventory/shelf-life'),
          ),
          IconButton(
            icon: const Icon(Icons.shopping_cart_outlined),
            tooltip: 'Einkaufsliste',
            onPressed: () => context.push('/inventory/shopping'),
          ),
          ...shellMenuActions(context),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(104),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
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
              _CategoryFilterRow(),
            ],
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

  // Returns (daysLeft, expiryDate) for the soonest expiring state, or null.
  (int, DateTime)? _soonestExpiry() {
    DateTime? soonest;
    for (final s in states) {
      if (s.expiryDate == null) continue;
      if (soonest == null || s.expiryDate!.isBefore(soonest)) {
        soonest = s.expiryDate;
      }
    }
    if (soonest == null) return null;
    final days = soonest.difference(DateTime.now()).inDays;
    return (days, soonest);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final expiry = _soonestExpiry();
    final showExpiry = expiry != null && expiry.$1 <= 7;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: _ProductTypeIcon(type: item.productType),
        title: Row(
          children: [
            Expanded(
              child: Text(
                item.name,
                style: theme.textTheme.titleSmall,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (item.isFavorite) ...[
              const SizedBox(width: 4),
              Icon(Icons.favorite, size: 14, color: Colors.red.shade400),
            ],
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (item.brand != null)
              Text(
                item.brand!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            Row(
              children: [
                if (item.ean != null) ...[
                  Icon(Icons.barcode_reader, size: 12, color: cs.outline),
                  const SizedBox(width: 4),
                ],
                _StockBadge(item: item, states: states),
                if (showExpiry) ...[
                  const SizedBox(width: 6),
                  _ExpiryBadge(daysLeft: expiry.$1),
                ],
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

class _ExpiryBadge extends StatelessWidget {
  final int daysLeft;
  const _ExpiryBadge({required this.daysLeft});

  @override
  Widget build(BuildContext context) {
    final Color color;
    final String label;
    if (daysLeft < 0) {
      color = Theme.of(context).colorScheme.error;
      label = 'Abgelaufen';
    } else if (daysLeft == 0) {
      color = Theme.of(context).colorScheme.error;
      label = 'Heute';
    } else if (daysLeft <= 3) {
      color = Colors.orange;
      label = '${daysLeft}T';
    } else {
      color = Colors.amber.shade700;
      label = '${daysLeft}T';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.5), width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.event_busy_outlined, size: 10, color: color),
          const SizedBox(width: 2),
          Text(label, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600)),
        ],
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

class _CategoryFilterRow extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(itemCategoryFilterProvider);
    final customCats =
        ref.watch(categoryDefinitionsProvider).valueOrNull ?? [];

    final chips = <(String, String)>[
      for (final id in ItemCategory.allItemCategories)
        (id, ItemCategory.labelDe(id)),
      for (final cat in customCats)
        (cat.id, cat.name),
    ];

    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: chips.length,
        separatorBuilder: (context, i) => const SizedBox(width: 6),
        itemBuilder: (context, i) {
          final (id, label) = chips[i];
          final isSelected = selected == id;
          return FilterChip(
            label: Text(label),
            selected: isSelected,
            onSelected: (_) => ref
                .read(itemCategoryFilterProvider.notifier)
                .state = isSelected ? null : id,
            visualDensity: VisualDensity.compact,
          );
        },
      ),
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
