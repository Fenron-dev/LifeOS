import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/item_categories.dart';
import '../../core/product_types.dart';
import '../../providers/tags_provider.dart';
import '../../db/database.dart';
import '../../providers/categories_provider.dart';
import '../../providers/inventory_provider.dart';
import '../../providers/items_provider.dart';
import '../../providers/unit_conversions_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/vault_provider.dart';
import '../../widgets/adaptive_shell.dart';
import '../../widgets/search_filter_bar.dart';
import 'inventory_value_screen.dart';

class InventoryScreen extends ConsumerStatefulWidget {
  const InventoryScreen({super.key});

  @override
  ConsumerState<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends ConsumerState<InventoryScreen> {
  late final TextEditingController _searchCtrl;

  @override
  void initState() {
    super.initState();
    _searchCtrl = TextEditingController(
        text: ref.read(itemSearchQueryProvider));
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _clearSearch() {
    _searchCtrl.clear();
    ref.read(itemSearchQueryProvider.notifier).state = '';
  }

  void _showFilterSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _InventoryFilterSheet(),
    );
  }

  Future<void> _scanBarcode(BuildContext context) async {
    final ean = await context.push<String>('/scan');
    if (ean == null || !context.mounted) return;
    final db = ref.read(databaseProvider);
    if (db == null) return;
    final item = await db.itemByEan(ean);
    if (!context.mounted) return;
    if (item == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Kein Artikel mit diesem Barcode gefunden'),
          action: SnackBarAction(
            label: 'Anlegen',
            onPressed: () =>
                context.push('/haushalt/item/new', extra: ean),
          ),
        ),
      );
      return;
    }
    context.push('/haushalt/item/${item.id}');
  }

  @override
  Widget build(BuildContext context) {
    final itemsAsync = ref.watch(filteredItemsProvider);
    final query = ref.watch(itemSearchQueryProvider);
    final quickActions = ref.watch(settingsProvider).valueOrNull?.quickActions
        ?? AppSettingsData.defaultQuickActions;
    final hasAddAction = quickActions.contains(QuickAction.addInventory);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Inventar'),
        actions: [
          IconButton(
            icon: const Icon(Icons.event_available_outlined),
            tooltip: 'Haltbarkeit',
            onPressed: () => context.push('/haushalt/shelf-life'),
          ),
          IconButton(
            icon: const Icon(Icons.shopping_cart_outlined),
            tooltip: 'Einkaufsliste',
            onPressed: () => context.push('/aufgaben'),
          ),
          IconButton(
            icon: const Icon(Icons.euro_outlined),
            tooltip: 'Lagerwert',
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              useSafeArea: true,
              builder: (_) => const InventoryValueSheet(),
            ),
          ),
          ...shellMenuActions(context),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: _InventorySearchBar(
            searchCtrl: _searchCtrl,
            query: query,
            onClear: _clearSearch,
            onScan: () => _scanBarcode(context),
            onFilter: () => _showFilterSheet(context),
          ),
        ),
      ),
      body: Column(
        children: [
          _ActiveInventoryFilters(),
          Expanded(
            child: itemsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Fehler: $e')),
              data: (items) => items.isEmpty
                  ? _EmptyState(hasQuery: query.isNotEmpty)
                  : _ItemsList(items: items),
            ),
          ),
        ],
      ),
      floatingActionButton: hasAddAction ? null : FloatingActionButton(
        heroTag: 'add',
        onPressed: () => context.push('/haushalt/item/new'),
        tooltip: 'Artikel hinzufügen',
        child: const Icon(Icons.add),
      ),
    );
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

  bool _hasFrozen() => states.any((s) => s.state == 'frozen' || s.state == 'thawed');

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
    final frozen = _hasFrozen();

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
                if (frozen) ...[
                  const SizedBox(width: 6),
                  _FrozenBadge(states: states),
                ],
              ],
            ),
          ],
        ),
        trailing: const Icon(Icons.chevron_right),
        isThreeLine: item.brand != null,
        onTap: () => context.push('/haushalt/item/${item.id}'),
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

class _FrozenBadge extends StatelessWidget {
  final List<ItemState> states;
  const _FrozenBadge({required this.states});

  @override
  Widget build(BuildContext context) {
    final hasThawed = states.any((s) => s.state == 'thawed');
    final color = hasThawed ? Colors.cyan.shade600 : Colors.blue.shade400;
    final label = hasThawed ? 'Aufgetaut' : 'Gefroren';
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
          Icon(Icons.ac_unit, size: 10, color: color),
          const SizedBox(width: 2),
          Text(label,
              style: TextStyle(
                  fontSize: 10, color: color, fontWeight: FontWeight.w600)),
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
    final icon = ProductType.iconFor(type);
    final color = ProductType.colorFor(type);
    return CircleAvatar(
      backgroundColor: color.withValues(alpha: 0.15),
      child: Icon(icon, color: color, size: 20),
    );
  }
}

// ── New search bar + filter standard ──────────────────────────────────────────

class _InventorySearchBar extends ConsumerWidget {
  final TextEditingController searchCtrl;
  final String query;
  final VoidCallback onClear;
  final VoidCallback onScan;
  final VoidCallback onFilter;
  const _InventorySearchBar({
    required this.searchCtrl,
    required this.query,
    required this.onClear,
    required this.onScan,
    required this.onFilter,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasFilter = ref.watch(itemCategoryFilterProvider) != null ||
        ref.watch(itemTagFilterProvider) != null ||
        ref.watch(itemFavoriteFilterProvider) ||
        ref.watch(itemMinRatingFilterProvider) != null ||
        ref.watch(itemTrashedFilterProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: SearchBar(
              controller: searchCtrl,
              hintText: 'Artikel suchen…',
              leading: const Icon(Icons.search),
              trailing: [
                if (query.isNotEmpty)
                  IconButton(
                      icon: const Icon(Icons.close), onPressed: onClear),
                IconButton(
                  icon: const Icon(Icons.qr_code_scanner),
                  tooltip: 'Barcode scannen',
                  onPressed: onScan,
                ),
              ],
              onChanged: (v) =>
                  ref.read(itemSearchQueryProvider.notifier).state = v,
            ),
          ),
          const SizedBox(width: 8),
          Badge(
            isLabelVisible: hasFilter,
            smallSize: 8,
            child: IconButton.filledTonal(
              icon: const Icon(Icons.tune),
              tooltip: 'Filtern',
              onPressed: onFilter,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActiveInventoryFilters extends ConsumerWidget {
  const _ActiveInventoryFilters();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cat = ref.watch(itemCategoryFilterProvider);
    final tagId = ref.watch(itemTagFilterProvider);
    final favOnly = ref.watch(itemFavoriteFilterProvider);
    final minRating = ref.watch(itemMinRatingFilterProvider);
    final trashedOnly = ref.watch(itemTrashedFilterProvider);

    final customCats =
        ref.watch(categoryDefinitionsProvider).valueOrNull ?? [];
    final catLabel = cat != null
        ? (customCats
                .where((c) => c.id == cat)
                .firstOrNull
                ?.name ??
            ItemCategory.labelDe(cat))
        : null;

    // Resolve tag name (always watch, but only use when tagId != null)
    final tagsForCat = ref
        .watch(tagDefinitionsForCategoryProvider(cat ?? ''))
        .valueOrNull ??
        [];
    final tagLabel = tagId != null
        ? tagsForCat.where((t) => t.id == tagId).firstOrNull?.name
        : null;

    final chips = <ActiveFilterChip>[
      if (catLabel != null)
        ActiveFilterChip(
          label: catLabel,
          onRemove: () {
            ref.read(itemCategoryFilterProvider.notifier).state = null;
            ref.read(itemTagFilterProvider.notifier).state = null;
          },
        ),
      if (tagLabel != null)
        ActiveFilterChip(
          label: tagLabel,
          onRemove: () =>
              ref.read(itemTagFilterProvider.notifier).state = null,
        ),
      if (favOnly)
        ActiveFilterChip(
          label: '❤️ Favoriten',
          onRemove: () =>
              ref.read(itemFavoriteFilterProvider.notifier).state = false,
        ),
      if (minRating != null)
        ActiveFilterChip(
          label: '${'★' * minRating}+',
          onRemove: () =>
              ref.read(itemMinRatingFilterProvider.notifier).state = null,
        ),
      if (trashedOnly)
        ActiveFilterChip(
          label: 'Abgelehnt',
          onRemove: () =>
              ref.read(itemTrashedFilterProvider.notifier).state = false,
        ),
    ];

    if (chips.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
        children: chips,
      ),
    );
  }
}

class _InventoryFilterSheet extends ConsumerWidget {
  const _InventoryFilterSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final selectedCat = ref.watch(itemCategoryFilterProvider);
    final selectedTag = ref.watch(itemTagFilterProvider);
    final favOnly = ref.watch(itemFavoriteFilterProvider);
    final minRating = ref.watch(itemMinRatingFilterProvider);
    final trashedOnly = ref.watch(itemTrashedFilterProvider);
    final customCats =
        ref.watch(categoryDefinitionsProvider).valueOrNull ?? [];
    final tags = selectedCat != null
        ? (ref
                .watch(tagDefinitionsForCategoryProvider(selectedCat))
                .valueOrNull ??
            [])
        : <TagDefinition>[];

    final catChips = <(String, String)>[
      for (final id in ItemCategory.allItemCategories)
        (id, ItemCategory.labelDe(id)),
      for (final cat in customCats) (cat.id, cat.name),
    ];

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollCtrl) => Column(
        children: [
          const SizedBox(height: 8),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: cs.onSurfaceVariant.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 4, 0),
            child: Row(
              children: [
                Text('Filter',
                    style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                TextButton(
                  onPressed: () {
                    ref.read(itemCategoryFilterProvider.notifier).state =
                        null;
                    ref.read(itemTagFilterProvider.notifier).state = null;
                    ref.read(itemFavoriteFilterProvider.notifier).state =
                        false;
                    ref.read(itemMinRatingFilterProvider.notifier).state =
                        null;
                    ref.read(itemTrashedFilterProvider.notifier).state =
                        false;
                  },
                  child: const Text('Zurücksetzen'),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              controller: scrollCtrl,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                _FSection('Kategorie'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (final chip in catChips)
                      FilterChip(
                        label: Text(chip.$2),
                        selected: selectedCat == chip.$1,
                        onSelected: (_) {
                          final next = selectedCat == chip.$1
                              ? null
                              : chip.$1;
                          ref
                              .read(itemCategoryFilterProvider.notifier)
                              .state = next;
                          if (next == null) {
                            ref
                                .read(itemTagFilterProvider.notifier)
                                .state = null;
                          }
                        },
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
                if (tags.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _FSection('Tags'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: tags
                        .map((tag) => FilterChip(
                              avatar: const Icon(
                                  Icons.label_outline,
                                  size: 12),
                              label: Text(tag.name,
                                  style:
                                      const TextStyle(fontSize: 12)),
                              selected: selectedTag == tag.id,
                              onSelected: (_) => ref
                                  .read(itemTagFilterProvider.notifier)
                                  .state = selectedTag == tag.id
                                      ? null
                                      : tag.id,
                              visualDensity: VisualDensity.compact,
                            ))
                        .toList(),
                  ),
                ],
                const SizedBox(height: 16),
                _FSection('Bewertung & Status'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    FilterChip(
                      avatar: Icon(Icons.favorite,
                          size: 13,
                          color: favOnly ? Colors.red.shade400 : null),
                      label: const Text('Favoriten'),
                      selected: favOnly,
                      onSelected: (_) => ref
                          .read(itemFavoriteFilterProvider.notifier)
                          .state = !favOnly,
                      visualDensity: VisualDensity.compact,
                    ),
                    for (final stars in [3, 4, 5])
                      FilterChip(
                        label: Text('${'★' * stars}+'),
                        selected: minRating == stars,
                        onSelected: (_) => ref
                            .read(itemMinRatingFilterProvider.notifier)
                            .state = minRating == stars ? null : stars,
                        visualDensity: VisualDensity.compact,
                      ),
                    FilterChip(
                      avatar: const Icon(Icons.thumb_down_outlined,
                          size: 13),
                      label: const Text('Abgelehnt'),
                      selected: trashedOnly,
                      onSelected: (_) => ref
                          .read(itemTrashedFilterProvider.notifier)
                          .state = !trashedOnly,
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FSection extends StatelessWidget {
  final String text;
  const _FSection(this.text);
  @override
  Widget build(BuildContext context) => Text(
        text,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
      );
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
