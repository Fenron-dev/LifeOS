import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/item_categories.dart';
import '../../providers/inventory_provider.dart';
import '../../providers/items_provider.dart';
import '../../providers/locations_provider.dart';
import '../../providers/vault_provider.dart';

/// Provider that computes a summary of the current inventory:
/// total item count, entry count, value estimate, by-category, by-location.
final _inventoryValueProvider =
    FutureProvider<_InvStats>((ref) async {
  final db = ref.watch(databaseProvider);
  if (db == null) return const _InvStats();

  final stockMap =
      await ref.watch(itemStockMapProvider.future);
  final allItems =
      await ref.watch(allItemsProvider.future);
  final allLocations =
      await ref.watch(allLocationsProvider.future);

  final itemById = {for (final i in allItems) i.id: i};
  final locById = {for (final l in allLocations) l.id: l};

  int totalEntries = 0;
  double totalValue = 0;
  final byCat = <String, _CatStat>{};
  final byLoc = <String, int>{};

  for (final entry in stockMap.entries) {
    final item = itemById[entry.key];
    if (item == null) continue;
    final states = entry.value;
    totalEntries += states.length;

    // Category
    final catId = item.categoryId;
    final catLabel = ItemCategory.allItemCategories.contains(catId)
        ? ItemCategory.labelDe(catId)
        : catId;
    final cat = byCat.putIfAbsent(catId, () => _CatStat(catLabel));
    cat.itemCount++;

    // Location
    for (final s in states) {
      if (s.locationId != null) {
        final locName = locById[s.locationId]?.name ?? s.locationId!;
        byLoc[locName] = (byLoc[locName] ?? 0) + 1;
      }
    }

    // Price estimate: avg purchase price × total current qty
    final price = await db.watchAvgPrice(item.id).first;
    if (price != null) {
      double qty = 0;
      for (final s in states) {
        qty += s.currentQuantity;
      }
      final value = price * qty;
      totalValue += value;
      cat.value += value;
      cat.hasPrice = true;
    }
  }

  return _InvStats(
    totalItems: itemById.values
        .where((i) => stockMap.containsKey(i.id))
        .length,
    totalEntries: totalEntries,
    totalValue: totalValue,
    hasValue: totalValue > 0,
    byCat: byCat.values.toList()
      ..sort((a, b) => b.itemCount.compareTo(a.itemCount)),
    byLoc: (byLoc.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value)))
        .take(10)
        .toList(),
  );
});

class _InvStats {
  final int totalItems;
  final int totalEntries;
  final double totalValue;
  final bool hasValue;
  final List<_CatStat> byCat;
  final List<MapEntry<String, int>> byLoc;

  const _InvStats({
    this.totalItems = 0,
    this.totalEntries = 0,
    this.totalValue = 0,
    this.hasValue = false,
    this.byCat = const [],
    this.byLoc = const [],
  });
}

class _CatStat {
  final String label;
  int itemCount = 0;
  double value = 0;
  bool hasPrice = false;
  _CatStat(this.label);
}

// ── Sheet ─────────────────────────────────────────────────────────────────────

class InventoryValueSheet extends ConsumerWidget {
  const InventoryValueSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(_inventoryValueProvider);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 20, 16, MediaQuery.viewInsetsOf(context).bottom + 24),
      child: statsAsync.when(
        loading: () =>
            const SizedBox(height: 200, child: Center(child: CircularProgressIndicator())),
        error: (e, _) => Text('Fehler: $e'),
        data: (stats) => SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(Icons.inventory_2_outlined, color: cs.primary),
                  const SizedBox(width: 8),
                  Text('Lagerübersicht', style: theme.textTheme.titleLarge),
                ],
              ),
              const SizedBox(height: 16),

              // Summary cards
              Row(
                children: [
                  _SummaryCard(
                    icon: Icons.category_outlined,
                    label: 'Artikel',
                    value: '${stats.totalItems}',
                    color: cs.primary,
                  ),
                  const SizedBox(width: 8),
                  _SummaryCard(
                    icon: Icons.storage_outlined,
                    label: 'Einträge',
                    value: '${stats.totalEntries}',
                    color: Colors.teal,
                  ),
                  if (stats.hasValue) ...[
                    const SizedBox(width: 8),
                    _SummaryCard(
                      icon: Icons.euro_outlined,
                      label: 'Lagerwert',
                      value: '~${stats.totalValue.toStringAsFixed(2)} €',
                      color: Colors.green.shade600,
                    ),
                  ],
                ],
              ),
              if (stats.hasValue)
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 8),
                  child: Text(
                    '* Schätzung basierend auf Durchschnittseinkaufspreis',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ),

              const SizedBox(height: 16),

              // By category
              if (stats.byCat.isNotEmpty) ...[
                Text('Nach Kategorie', style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                ...stats.byCat.map((c) => _StatRow(
                      label: c.label,
                      count: c.itemCount,
                      value: c.hasPrice ? c.value : null,
                      total: stats.totalItems,
                      theme: theme,
                    )),
              ],

              const SizedBox(height: 16),

              // By location
              if (stats.byLoc.isNotEmpty) ...[
                Text('Nach Lagerort (Top 10)',
                    style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                ...stats.byLoc.map((e) => _StatRow(
                      label: e.key,
                      count: e.value,
                      value: null,
                      total: stats.totalEntries,
                      theme: theme,
                    )),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  const _SummaryCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border:
              Border.all(color: color.withValues(alpha: 0.3), width: 0.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(height: 4),
            Text(value,
                style: theme.textTheme.titleSmall
                    ?.copyWith(color: color, fontWeight: FontWeight.bold)),
            Text(label,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: color.withValues(alpha: 0.8))),
          ],
        ),
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  final String label;
  final int count;
  final double? value;
  final int total;
  final ThemeData theme;
  const _StatRow({
    required this.label,
    required this.count,
    required this.value,
    required this.total,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final fraction = total > 0 ? count / total : 0.0;
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(label, style: theme.textTheme.bodyMedium),
              ),
              Text('$count Artikel',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: cs.onSurfaceVariant)),
              if (value != null) ...[
                const SizedBox(width: 8),
                Text(
                  '~${value!.toStringAsFixed(2)} €',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.green.shade700,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: fraction.clamp(0.0, 1.0),
              minHeight: 4,
              backgroundColor: cs.surfaceContainerHighest,
              valueColor:
                  AlwaysStoppedAnimation(cs.primary.withValues(alpha: 0.6)),
            ),
          ),
        ],
      ),
    );
  }
}
