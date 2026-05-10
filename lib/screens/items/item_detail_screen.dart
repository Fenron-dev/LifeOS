import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/product_types.dart';
import '../../db/database.dart';
import '../../health/widgets/diary_entry_sheet.dart';
import '../../health/widgets/food_search_sheet.dart';
import '../../providers/items_provider.dart';
import '../../providers/inventory_provider.dart';
import '../../providers/events_provider.dart';
import '../../providers/locations_provider.dart';
import '../../providers/shops_provider.dart';
import '../../providers/unit_conversions_provider.dart';
import '../../providers/units_provider.dart';
import '../../providers/vault_provider.dart';
import '../../providers/tags_provider.dart';
import '../../providers/relations_provider.dart';
import '../../providers/templates_provider.dart';

class ItemDetailScreen extends ConsumerWidget {
  final String itemId;
  const ItemDetailScreen({super.key, required this.itemId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemAsync = ref.watch(itemByIdProvider(itemId));

    return itemAsync.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(body: Center(child: Text('Fehler: $e'))),
      data: (item) {
        if (item == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: Text('Artikel nicht gefunden')),
          );
        }
        return _ItemDetailBody(item: item);
      },
    );
  }
}

class _ItemDetailBody extends ConsumerWidget {
  final Item item;
  const _ItemDetailBody({required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entriesAsync = ref.watch(inventoryForItemProvider(item.id));
    final statesAsync = ref.watch(itemStatesForItemProvider(item.id));

    Future<void> logConsumption() async {
      final product = FoodSearchResult(
        productName: item.name,
        brand: item.brand,
        ean: item.ean,
        itemId: item.id,
        caloriesPer100g: item.caloriesPer100g,
        proteinPer100g: item.proteinPer100g,
        carbsPer100g: item.carbsPer100g,
        fatPer100g: item.fatPer100g,
        fiberPer100g: item.fiberPer100g,
        servingSizeG: item.servingSizeG,
        source: 'local',
      );
      // DiaryEntrySheet shows InventoryDeductSheet internally after save.
      await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        builder: (_) => DiaryEntrySheet(initialProduct: product),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(item.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Bearbeiten',
            onPressed: () => context.push('/haushalt/item/${item.id}/edit'),
          ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'delete') await _confirmDelete(context, ref);
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'delete',
                child: Row(children: [
                  Icon(Icons.delete_outline, color: Colors.red),
                  SizedBox(width: 8),
                  Text('Artikel löschen', style: TextStyle(color: Colors.red)),
                ]),
              ),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          _ItemInfoCard(item: item),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: logConsumption,
            icon: const Icon(Icons.restaurant_outlined),
            label: const Text('Im Tagebuch erfassen'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(40),
            ),
          ),
          if (_hasNutrition(item)) ...[
            const SizedBox(height: 12),
            _NutritionCard(item: item),
          ],
          const SizedBox(height: 12),
          _TagsSection(item: item),
          if (item.templateId != null) ...[
            const SizedBox(height: 12),
            _PropertiesSection(item: item),
          ],
          const SizedBox(height: 12),
          _StockSection(
            item: item,
            entriesAsync: entriesAsync,
            statesAsync: statesAsync,
          ),
          const SizedBox(height: 12),
          _EventsSection(itemId: item.id),
          const SizedBox(height: 12),
          _RelationsSection(item: item),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddStockDialog(context, ref, item),
        icon: const Icon(Icons.add_shopping_cart),
        label: const Text('Einlagern'),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Artikel löschen?'),
        content: Text('„${item.name}" wird dauerhaft gelöscht.'),
        actions: [
          TextButton(
            onPressed: () => ctx.pop(false),
            child: const Text('Abbrechen'),
          ),
          TextButton(
            onPressed: () => ctx.pop(true),
            child: const Text('Löschen', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await ref.read(itemsNotifierProvider.notifier).deleteItem(item.id);
      if (context.mounted) context.pop();
    }
  }
}

void _showAddStockDialog(BuildContext context, WidgetRef ref, Item item) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => AddStockSheet(item: item),
  );
}

bool _hasNutrition(Item item) =>
    item.caloriesPer100g != null ||
    item.proteinPer100g != null ||
    item.carbsPer100g != null ||
    item.fatPer100g != null ||
    item.fiberPer100g != null ||
    item.sugarsPer100g != null ||
    item.saturatedFatPer100g != null ||
    item.saltPer100g != null ||
    item.nutriscore != null ||
    item.novaGroup != null ||
    item.ingredientsText != null;

// ── Item info card ──────────────────────────────────────────────────────────

class _ItemInfoCard extends ConsumerWidget {
  final Item item;
  const _ItemInfoCard({required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final statsAsync = ref.watch(_itemStatsProvider(item.id));
    final stats = statsAsync.valueOrNull;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _ProductTypeChip(type: item.productType),
                const Spacer(),
                if (item.ean != null)
                  Flexible(
                    child: Chip(
                      avatar: const Icon(Icons.barcode_reader, size: 16),
                      label: Text(
                        item.ean!,
                        style: theme.textTheme.bodySmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
              ],
            ),
            if (item.brand != null) ...[
              const SizedBox(height: 4),
              Text(item.brand!, style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
              )),
            ],
            if (item.notes != null) ...[
              const SizedBox(height: 8),
              Text(item.notes!, style: theme.textTheme.bodySmall),
            ],
            const SizedBox(height: 12),
            // ── Ratings row ────────────────────────────────────────────
            Row(
              children: [
                // 5-star rating
                ...List.generate(5, (i) {
                  final filled = (item.starRating ?? 0) > i;
                  return GestureDetector(
                    onTap: () {
                      final newRating = (item.starRating == i + 1) ? null : i + 1;
                      ref.read(databaseProvider)?.setItemRating(
                        item.id,
                        starRating: newRating,
                        isFavorite: item.isFavorite,
                        isTrashed: item.isTrashed,
                      );
                    },
                    child: Icon(
                      filled ? Icons.star : Icons.star_border,
                      color: Colors.amber,
                      size: 22,
                    ),
                  );
                }),
                const SizedBox(width: 8),
                // Favorite toggle
                GestureDetector(
                  onTap: () => ref.read(databaseProvider)?.setItemRating(
                    item.id,
                    starRating: item.starRating,
                    isFavorite: !item.isFavorite,
                    isTrashed: item.isTrashed,
                  ),
                  child: Icon(
                    item.isFavorite ? Icons.favorite : Icons.favorite_border,
                    color: item.isFavorite ? Colors.red : cs.onSurfaceVariant,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 8),
                // Trash/dislike toggle
                GestureDetector(
                  onTap: () => ref.read(databaseProvider)?.setItemRating(
                    item.id,
                    starRating: item.starRating,
                    isFavorite: item.isFavorite,
                    isTrashed: !item.isTrashed,
                  ),
                  child: Icon(
                    item.isTrashed ? Icons.delete : Icons.delete_outline,
                    color: item.isTrashed ? cs.error : cs.onSurfaceVariant,
                    size: 22,
                  ),
                ),
                const Spacer(),
                // Thumbs up/down counts
                if (stats != null) ...[
                  Icon(Icons.thumb_up_outlined, size: 14, color: cs.primary),
                  const SizedBox(width: 3),
                  Text('${stats.up}', style: TextStyle(fontSize: 12, color: cs.primary)),
                  const SizedBox(width: 8),
                  Icon(Icons.thumb_down_outlined, size: 14, color: cs.error),
                  const SizedBox(width: 3),
                  Text('${stats.down}', style: TextStyle(fontSize: 12, color: cs.error)),
                  const SizedBox(width: 6),
                  Text('${stats.total}×', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                ],
              ],
            ),
            // Avg purchase price
            Builder(builder: (_) {
              final avg = ref.watch(_avgPriceProvider(item.id)).valueOrNull;
              if (avg == null) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  children: [
                    Icon(Icons.euro, size: 14, color: cs.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Text('Ø ${avg.toStringAsFixed(2)} €',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: cs.onSurfaceVariant)),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

// Provider for item consumption stats (total logs, thumbs up/down)
final _itemStatsProvider = FutureProvider.family<({int up, int down, int total}), String>(
  (ref, itemId) async {
    final db = ref.watch(databaseProvider);
    if (db == null) return (up: 0, down: 0, total: 0);
    return db.getNutritionLogStats(itemId);
  },
);

final _avgPriceProvider = StreamProvider.family<double?, String>(
  (ref, itemId) {
    final db = ref.watch(databaseProvider);
    if (db == null) return const Stream.empty();
    return db.watchAvgPrice(itemId);
  },
);

class _ProductTypeChip extends StatelessWidget {
  final String type;
  const _ProductTypeChip({required this.type});

  @override
  Widget build(BuildContext context) {
    final label = ProductType.labelDe(type);
    final icon = ProductType.iconFor(type);
    final color = ProductType.colorFor(type);
    return Chip(
      avatar: Icon(icon, size: 16, color: color),
      label: Text(label),
      visualDensity: VisualDensity.compact,
    );
  }
}

// ── Nutrition card ──────────────────────────────────────────────────────────

class _NutritionCard extends ConsumerStatefulWidget {
  final Item item;
  const _NutritionCard({required this.item});

  @override
  ConsumerState<_NutritionCard> createState() => _NutritionCardState();
}

class _NutritionCardState extends ConsumerState<_NutritionCard> {
  // null = per 100g; otherwise the unit name from a conversion
  String? _servingUnit;

  String _fmt(double v) =>
      v == v.truncateToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final theme = Theme.of(context);

    // Build list of (label, gramsPerServing) from item conversions where toUnit='g'
    final itemConvs =
        ref.watch(itemConversionsProvider(item.id)).valueOrNull ?? [];
    final globalConvs = ref.watch(globalConversionsProvider).valueOrNull ?? [];
    final allConvs = [...itemConvs, ...globalConvs];
    final refUnit = item.nutritionRefUnit; // 'g' or 'ml'
    final ref100Label = '100 $refUnit';
    final servings = <(String, double)>[
      (ref100Label, 100.0),
      if (item.servingSizeG != null)
        ('Portion (${_fmt(item.servingSizeG!)} $refUnit)', item.servingSizeG!),
      ...allConvs
          .where((c) => c.toUnit == 'g' && c.scopeId != null)
          .map((c) => ('1 ${c.fromUnit}', c.factor)),
    ];
    // Deduplicate by label
    final seen = <String>{};
    final uniqueServings =
        servings.where((s) => seen.add(s.$1)).toList();

    final currentLabel = _servingUnit ?? ref100Label;
    final gramsPerServing =
        uniqueServings.firstWhere((s) => s.$1 == currentLabel,
            orElse: () => (ref100Label, 100.0)).$2;
    final scale = gramsPerServing / 100.0;

    String nutrVal(double? per100g, String unit) {
      if (per100g == null) return '';
      return '${_fmt(per100g * scale)} $unit';
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: title + badges
            Row(
              children: [
                Text('Nährwerte', style: theme.textTheme.titleSmall),
                const Spacer(),
                if (item.nutriscore != null)
                  _NutriscoreBadge(score: item.nutriscore!),
                if (item.novaGroup != null) ...[
                  const SizedBox(width: 6),
                  _NovaBadge(group: item.novaGroup!),
                ],
              ],
            ),
            // Serving picker
            if (uniqueServings.length > 1) ...[
              const SizedBox(height: 8),
              InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Portion',
                  isDense: true,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                ),
                child: DropdownButton<String>(
                  value: currentLabel,
                  isExpanded: true,
                  underline: const SizedBox.shrink(),
                  isDense: true,
                  items: uniqueServings
                      .map((s) =>
                          DropdownMenuItem(value: s.$1, child: Text(s.$1)))
                      .toList(),
                  onChanged: (v) =>
                      setState(() => _servingUnit = v),
                ),
              ),
            ],
            const SizedBox(height: 12),
            // Macro table (scaled)
            if (item.caloriesPer100g != null)
              _NutrRow(label: 'Energie',
                  value: nutrVal(item.caloriesPer100g, 'kcal'), bold: true),
            if (item.proteinPer100g != null)
              _NutrRow(label: 'Eiweiß',
                  value: nutrVal(item.proteinPer100g, 'g')),
            if (item.carbsPer100g != null)
              _NutrRow(label: 'Kohlenhydrate',
                  value: nutrVal(item.carbsPer100g, 'g')),
            if (item.sugarsPer100g != null)
              _NutrRow(label: '  davon Zucker',
                  value: nutrVal(item.sugarsPer100g, 'g'), indent: true),
            if (item.fatPer100g != null)
              _NutrRow(label: 'Fett', value: nutrVal(item.fatPer100g, 'g')),
            if (item.saturatedFatPer100g != null)
              _NutrRow(label: '  davon gesättigte Fettsäuren',
                  value: nutrVal(item.saturatedFatPer100g, 'g'), indent: true),
            if (item.fiberPer100g != null)
              _NutrRow(label: 'Ballaststoffe',
                  value: nutrVal(item.fiberPer100g, 'g')),
            if (item.saltPer100g != null)
              _NutrRow(label: 'Salz', value: nutrVal(item.saltPer100g, 'g')),
            if (item.ingredientsText != null) ...[
              const Divider(height: 20),
              Text('Zutaten',
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: theme.colorScheme.outline)),
              const SizedBox(height: 4),
              Text(item.ingredientsText!, style: theme.textTheme.bodySmall),
            ],
          ],
        ),
      ),
    );
  }
}

class _NutrRow extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;
  final bool indent;
  const _NutrRow(
      {required this.label,
      required this.value,
      this.bold = false,
      this.indent = false});

  @override
  Widget build(BuildContext context) {
    final style = indent
        ? Theme.of(context)
            .textTheme
            .bodySmall
            ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)
        : bold
            ? Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(fontWeight: FontWeight.bold)
            : Theme.of(context).textTheme.bodyMedium;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(value, style: style),
        ],
      ),
    );
  }
}

class _NutriscoreBadge extends StatelessWidget {
  final String score;
  const _NutriscoreBadge({required this.score});

  static const _colors = {
    'a': Color(0xFF1A7F37),
    'b': Color(0xFF6FBE44),
    'c': Color(0xFFF5C400),
    'd': Color(0xFFEE8100),
    'e': Color(0xFFE63312),
  };

  @override
  Widget build(BuildContext context) {
    final color = _colors[score.toLowerCase()] ?? Colors.grey;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        'Nutri-Score ${score.toUpperCase()}',
        style: const TextStyle(
            color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
      ),
    );
  }
}

class _NovaBadge extends StatelessWidget {
  final int group;
  const _NovaBadge({required this.group});

  static const _colors = {
    1: Color(0xFF1A7F37),
    2: Color(0xFFF5C400),
    3: Color(0xFFEE8100),
    4: Color(0xFFE63312),
  };

  @override
  Widget build(BuildContext context) {
    final color = _colors[group] ?? Colors.grey;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        'NOVA $group',
        style: const TextStyle(
            color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
      ),
    );
  }
}

// ── Stock section ───────────────────────────────────────────────────────────

class _StockSection extends ConsumerWidget {
  final Item item;
  final AsyncValue<List<InventoryEntry>> entriesAsync;
  final AsyncValue<List<ItemState>> statesAsync;

  const _StockSection({
    required this.item,
    required this.entriesAsync,
    required this.statesAsync,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Bestand', style: theme.textTheme.titleMedium),
            const Spacer(),
          ],
        ),
        const SizedBox(height: 8),
        entriesAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Text('Fehler: $e'),
          data: (entries) {
            if (entries.isEmpty) {
              return _EmptyStock(onAdd: () => _showAddStockDialog(context, ref, item));
            }
            return Column(
              children: entries
                  .map((e) => _StockEntryCard(entry: e, item: item))
                  .toList(),
            );
          },
        ),
      ],
    );
  }
}

class _EmptyStock extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyStock({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(Icons.inventory_2_outlined,
                size: 48, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 8),
            const Text('Kein Bestand vorhanden'),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: const Text('Einlagern'),
            ),
          ],
        ),
      ),
    );
  }
}

class _StockEntryCard extends ConsumerWidget {
  final InventoryEntry entry;
  final Item item;
  const _StockEntryCard({required this.entry, required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final expiresIn = entry.expiryDate?.difference(DateTime.now()).inDays;
    final isExpiringSoon = expiresIn != null && expiresIn <= 3;
    final isExpired = expiresIn != null && expiresIn < 0;
    final locations = ref.watch(allLocationsProvider).valueOrNull ?? [];
    final location = entry.locationId != null
        ? locations.where((l) => l.id == entry.locationId).firstOrNull
        : null;

    Color? cardColor;
    if (isExpired) cardColor = theme.colorScheme.errorContainer;
    if (isExpiringSoon && !isExpired) {
      cardColor = Colors.orange.withValues(alpha: 0.15);
    }

    return Card(
      color: cardColor,
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${_formatQty(entry.quantity)} ${entry.unit}',
                    style: theme.textTheme.titleMedium,
                  ),
                  if (entry.expiryDate != null)
                    Text(
                      _expiryLabel(entry.expiryDate!, expiresIn!),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: isExpired
                            ? theme.colorScheme.error
                            : isExpiringSoon
                                ? Colors.orange.shade700
                                : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  _StateChip(state: entry.state),
                  if (entry.frozenAt != null) ...[
                    const SizedBox(height: 2),
                    Row(children: [
                      Icon(Icons.ac_unit, size: 12, color: Colors.blue.shade400),
                      const SizedBox(width: 3),
                      Text(
                        'Eingefroren ${DateFormat('dd.MM.yy').format(entry.frozenAt!)}',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: Colors.blue.shade400),
                      ),
                    ]),
                  ],
                  if (entry.thawedAt != null) ...[
                    const SizedBox(height: 2),
                    Row(children: [
                      Icon(Icons.water_drop_outlined,
                          size: 12, color: Colors.cyan.shade600),
                      const SizedBox(width: 3),
                      Text(
                        'Aufgetaut ${DateFormat('dd.MM.yy').format(entry.thawedAt!)}',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: Colors.cyan.shade600),
                      ),
                    ]),
                  ],
                  if (entry.price != null) ...[
                    const SizedBox(height: 2),
                    Row(children: [
                      Icon(Icons.euro,
                          size: 12, color: theme.colorScheme.outline),
                      const SizedBox(width: 3),
                      Text(
                        '${entry.price!.toStringAsFixed(2)} €',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.outline),
                      ),
                    ]),
                  ],
                  if (location != null) ...[
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(Icons.place_outlined,
                            size: 12,
                            color: theme.colorScheme.outline),
                        const SizedBox(width: 3),
                        Text(location.name,
                            style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.outline)),
                      ],
                    ),
                  ],
                  if (entry.openedAt != null) ...[
                    const SizedBox(height: 4),
                    Row(children: [
                      Icon(Icons.lock_open_outlined,
                          size: 12, color: Colors.blue.shade600),
                      const SizedBox(width: 3),
                      Text(
                        'Geöffnet ${DateFormat('dd.MM.yy').format(entry.openedAt!)}',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: Colors.blue.shade600),
                      ),
                    ]),
                  ],
                ],
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  tooltip: 'Buchung bearbeiten',
                  onPressed: () => _showEditDialog(context, ref),
                ),
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline, size: 20),
                  tooltip: 'Verbrauchen',
                  onPressed: () => _showConsumeDialog(context, ref),
                ),
                IconButton(
                  icon: const Icon(Icons.sync_alt, size: 20),
                  tooltip: 'Zustand ändern',
                  onPressed: () => _showStateChangeSheet(context),
                ),
                IconButton(
                  icon: const Icon(Icons.move_down_outlined, size: 20),
                  tooltip: 'Umbuchen',
                  onPressed: () => _showRelocateSheet(context, ref, locations),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatQty(double q) =>
      q == q.truncateToDouble() ? q.toInt().toString() : q.toString();

  String _expiryLabel(DateTime date, int days) {
    if (days < 0) return 'Abgelaufen ${DateFormat('dd.MM.yy').format(date)}';
    if (days == 0) return 'Läuft heute ab';
    if (days == 1) return 'Läuft morgen ab';
    if (days <= 7) return 'Läuft in $days Tagen ab';
    return 'MHD ${DateFormat('dd.MM.yy').format(date)}';
  }

  void _showEditDialog(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _EditEntrySheet(entry: entry),
    );
  }

  void _showConsumeDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (_) => ConsumeDialog(entry: entry, item: item),
    );
  }

  void _showStateChangeSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _StateChangeSheet(entry: entry),
    );
  }

  void _showRelocateSheet(
      BuildContext context, WidgetRef ref, List<Location> locations) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _RelocateSheet(entry: entry, locations: locations),
    );
  }
}

// ── Edit inventory entry sheet ──────────────────────────────────────────────

class _EditEntrySheet extends ConsumerStatefulWidget {
  final InventoryEntry entry;
  const _EditEntrySheet({required this.entry});

  @override
  ConsumerState<_EditEntrySheet> createState() => _EditEntrySheetState();
}

class _EditEntrySheetState extends ConsumerState<_EditEntrySheet> {
  late final TextEditingController _qtyCtrl;
  late final TextEditingController _priceCtrl;
  DateTime? _expiryDate;
  String? _locationId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.entry;
    _qtyCtrl = TextEditingController(text: _fmt(e.quantity));
    _priceCtrl = TextEditingController(
        text: e.price != null ? e.price!.toStringAsFixed(2) : '');
    _expiryDate = e.expiryDate;
    _locationId = e.locationId;
  }

  @override
  void dispose() {
    _qtyCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  String _fmt(double q) =>
      q == q.truncateToDouble() ? q.toInt().toString() : q.toString();

  Future<void> _save() async {
    final qty = double.tryParse(_qtyCtrl.text.replaceAll(',', '.'));
    if (qty == null || qty <= 0) return;
    final price = _priceCtrl.text.trim().isEmpty
        ? null
        : double.tryParse(_priceCtrl.text.replaceAll(',', '.'));
    setState(() => _saving = true);
    try {
      final db = ref.read(databaseProvider)!;
      await db.updateInventoryEntry(InventoryEntriesCompanion(
        id: Value(widget.entry.id),
        quantity: Value(qty),
        price: Value(price),
        locationId: Value(_locationId),
        expiryDate: Value(_expiryDate),
        updatedAt: Value(DateTime.now()),
      ));
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Buchung löschen?'),
        content: const Text('Diese Einlagerung wird dauerhaft entfernt.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Abbrechen')),
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Löschen',
                  style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final db = ref.read(databaseProvider)!;
    await db.deleteInventoryEntry(widget.entry.id);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final locations = ref.watch(allLocationsProvider).valueOrNull ?? [];

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text('Buchung bearbeiten',
                    style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  tooltip: 'Buchung löschen',
                  onPressed: _delete,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller: _qtyCtrl,
                    decoration: InputDecoration(
                        labelText: 'Menge (${widget.entry.unit})'),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 3,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.calendar_today, size: 20),
                    title: Text(_expiryDate == null
                        ? 'Kein MHD'
                        : DateFormat('dd.MM.yyyy').format(_expiryDate!),
                        style: Theme.of(context).textTheme.bodyMedium),
                    trailing: _expiryDate != null
                        ? IconButton(
                            icon: const Icon(Icons.close, size: 16),
                            onPressed: () =>
                                setState(() => _expiryDate = null))
                        : null,
                    onTap: () async {
                      final d = await showDatePicker(
                        context: context,
                        initialDate: _expiryDate ??
                            DateTime.now().add(const Duration(days: 7)),
                        firstDate: DateTime.now()
                            .subtract(const Duration(days: 30)),
                        lastDate:
                            DateTime.now().add(const Duration(days: 3650)),
                      );
                      if (d != null) setState(() => _expiryDate = d);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _priceCtrl,
              decoration: const InputDecoration(
                labelText: 'Preis (€)',
                prefixIcon: Icon(Icons.euro),
              ),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
            ),
            if (locations.isNotEmpty) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                // ignore: deprecated_member_use
                value: _locationId,
                decoration: const InputDecoration(
                  labelText: 'Lagerort',
                  prefixIcon: Icon(Icons.place_outlined),
                ),
                items: [
                  const DropdownMenuItem(
                      value: null, child: Text('— keiner —')),
                  ...locations.map((l) =>
                      DropdownMenuItem(value: l.id, child: Text(l.name))),
                ],
                onChanged: (v) => setState(() => _locationId = v),
              ),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Speichern'),
            ),
          ],
        ),
      ),
    );
  }
}

class _StateChip extends StatelessWidget {
  final String state;
  const _StateChip({required this.state});

  @override
  Widget build(BuildContext context) {
    if (state == 'fresh') return const SizedBox.shrink();
    final label = switch (state) {
      'frozen' => 'Tiefgefroren',
      'thawed' => 'Aufgetaut',
      _ => state,
    };
    return Chip(
      label: Text(label),
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
    );
  }
}

// ── Events section ──────────────────────────────────────────────────────────

class _EventsSection extends ConsumerWidget {
  final String itemId;
  const _EventsSection({required this.itemId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventsAsync = ref.watch(eventsForItemProvider(itemId));
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Verlauf', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        eventsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Text('Fehler: $e'),
          data: (events) {
            if (events.isEmpty) {
              return const Text('Noch keine Ereignisse',
                  style: TextStyle(color: Colors.grey));
            }
            return Column(
              children: events.take(20).map((e) => _EventTile(event: e)).toList(),
            );
          },
        ),
      ],
    );
  }
}

class _EventTile extends ConsumerWidget {
  final ItemEvent event;
  const _EventTile({required this.event});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final (icon, color, label) = _eventMeta(event.type);
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        radius: 16,
        backgroundColor: color.withValues(alpha: 0.15),
        child: Icon(icon, size: 16, color: color),
      ),
      title: Text(label),
      subtitle: event.quantity != null
          ? Text('${_formatQty(event.quantity!)} ${event.unit ?? ''}')
          : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            DateFormat('dd.MM.yy HH:mm').format(event.createdAt),
            style: theme.textTheme.bodySmall,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 16, color: Colors.red),
            tooltip: 'Ereignis löschen',
            onPressed: () => _confirmDelete(context, ref),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ereignis löschen?'),
        content: const Text(
            'Diesen Verlaufseintrag wirklich entfernen? Der Bestand wird nicht angepasst.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Abbrechen')),
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Löschen',
                  style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(databaseProvider)?.deleteItemEvent(event.id);
    }
  }

  (IconData, Color, String) _eventMeta(String type) => switch (type) {
    'purchase' => (Icons.add_shopping_cart, Colors.green, 'Gekauft'),
    'consumption' => (Icons.restaurant, Colors.orange, 'Verbraucht'),
    'stocktake' => (Icons.inventory, Colors.blue, 'Inventur'),
    'relocation' => (Icons.move_down, Colors.purple, 'Umgelagert'),
    'state_change' => (Icons.ac_unit, Colors.cyan, 'Zustand geändert'),
    'opened' => (Icons.open_in_new, Colors.brown, 'Geöffnet'),
    _ => (Icons.event, Colors.grey, type),
  };

  String _formatQty(double q) =>
      q == q.truncateToDouble() ? q.toInt().toString() : q.toString();
}

// ── Add stock bottom sheet ──────────────────────────────────────────────────

class AddStockSheet extends ConsumerStatefulWidget {
  final Item item;
  const AddStockSheet({super.key, required this.item});

  @override
  ConsumerState<AddStockSheet> createState() => _AddStockSheetState();
}

class _AddStockSheetState extends ConsumerState<AddStockSheet> {
  final _formKey = GlobalKey<FormState>();
  final _qtyCtrl = TextEditingController(text: '1');
  final _priceCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  late String _unit;
  String? _locationId;
  String? _shopName;
  DateTime? _expiryDate;
  bool _saving = false;
  String _state = 'fresh';
  DateTime? _frozenAt;
  DateTime? _thawedAt;
  String? _containerId;

  @override
  void initState() {
    super.initState();
    // Pre-select item's stockUnit; fall back to 'Stück'
    _unit = widget.item.stockUnit ?? 'Stück';
    // Pre-select most recent location for this item
    _initLocation();
  }

  Future<void> _initLocation() async {
    // 1. Use item's default location if set
    if (widget.item.defaultLocationId != null) {
      setState(() => _locationId = widget.item.defaultLocationId);
      return;
    }
    // 2. Fall back to most recent stock entry location
    final db = ref.read(databaseProvider);
    if (db == null) return;
    final entries = await db.watchInventoryForItem(widget.item.id).first;
    if (entries.isNotEmpty && mounted) {
      setState(() => _locationId = entries.first.locationId);
    }
  }

  String _fmtQty(double q) =>
      q == q.truncateToDouble() ? q.toInt().toString() : q.toStringAsFixed(1);

  Future<void> _pickContainer(BuildContext context, List<Item> containers) async {
    final result = await showModalBottomSheet<String?>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _ContainerPickerSheet(
        containers: containers,
        selectedId: _containerId,
      ),
    );
    if (result != null && mounted) {
      setState(() => _containerId = result.isEmpty ? null : result);
    }
  }

  @override
  void dispose() {
    _qtyCtrl.dispose();
    _priceCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await ref.read(inventoryOpsProvider.notifier).purchase(
        itemId: widget.item.id,
        quantity: double.parse(_qtyCtrl.text.replaceAll(',', '.')),
        unit: _unit,
        locationId: _locationId,
        expiryDate: _expiryDate,
        price: _priceCtrl.text.trim().isEmpty
            ? null
            : double.tryParse(_priceCtrl.text.replaceAll(',', '.')),
        store: _shopName?.trim().isEmpty == true ? null : _shopName?.trim(),
        notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        state: _state,
        frozenAt: _frozenAt,
        thawedAt: _thawedAt,
        containerId: _containerId,
      );
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16, right: 16, top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Einlagern: ${widget.item.name}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller: _qtyCtrl,
                    decoration: const InputDecoration(labelText: 'Menge *'),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Pflichtfeld';
                      final d = double.tryParse(v.replaceAll(',', '.'));
                      if (d == null || d <= 0) return 'Ungültig';
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 3,
                  child: Consumer(builder: (context, ref, _) {
                    final unitNames = ref.watch(unitNamesProvider);
                    // Ensure current unit is in list
                    if (!unitNames.contains(_unit) && unitNames.isNotEmpty) {
                      WidgetsBinding.instance.addPostFrameCallback(
                          (_) => setState(() => _unit = unitNames.first));
                    }
                    return InputDecorator(
                      decoration: const InputDecoration(labelText: 'Einheit'),
                      child: DropdownButton<String>(
                        value: unitNames.contains(_unit) ? _unit : null,
                        isExpanded: true,
                        underline: const SizedBox.shrink(),
                        items: unitNames
                            .map((u) => DropdownMenuItem(value: u, child: Text(u)))
                            .toList(),
                        onChanged: (v) => setState(() => _unit = v ?? _unit),
                      ),
                    );
                  }),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // ── State picker ─────────────────────────────────────────
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('Frisch'),
                  selected: _state == 'fresh',
                  onSelected: (v) {
                    if (v) setState(() { _state = 'fresh'; _frozenAt = null; _thawedAt = null; });
                  },
                ),
                ChoiceChip(
                  avatar: const Icon(Icons.ac_unit, size: 14),
                  label: const Text('Tiefgefroren'),
                  selected: _state == 'frozen',
                  onSelected: (v) {
                    if (v) setState(() { _state = 'frozen'; _frozenAt ??= DateTime.now(); _thawedAt = null; });
                  },
                ),
                ChoiceChip(
                  label: const Text('Aufgetaut'),
                  selected: _state == 'thawed',
                  onSelected: (v) {
                    if (v) setState(() { _state = 'thawed'; _thawedAt ??= DateTime.now(); });
                  },
                ),
              ],
            ),
            if (_state == 'frozen' || _state == 'thawed') ...[
              const SizedBox(height: 4),
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: const Icon(Icons.ac_unit, size: 20, color: Colors.blue),
                title: Text(_frozenAt == null
                    ? 'Eingefroren am (optional)'
                    : 'Eingefroren: ${DateFormat('dd.MM.yyyy').format(_frozenAt!)}'),
                trailing: _frozenAt != null
                    ? IconButton(
                        icon: const Icon(Icons.close, size: 16),
                        onPressed: () => setState(() => _frozenAt = null))
                    : null,
                onTap: () async {
                  final d = await showDatePicker(
                    context: context,
                    initialDate: _frozenAt ?? DateTime.now(),
                    firstDate: DateTime.now().subtract(const Duration(days: 365)),
                    lastDate: DateTime.now(),
                  );
                  if (d != null) setState(() => _frozenAt = d);
                },
              ),
            ],
            if (_state == 'thawed') ...[
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: const Icon(Icons.water_drop_outlined, size: 20, color: Colors.cyan),
                title: Text(_thawedAt == null
                    ? 'Aufgetaut am (optional)'
                    : 'Aufgetaut: ${DateFormat('dd.MM.yyyy').format(_thawedAt!)}'),
                trailing: _thawedAt != null
                    ? IconButton(
                        icon: const Icon(Icons.close, size: 16),
                        onPressed: () => setState(() => _thawedAt = null))
                    : null,
                onTap: () async {
                  final d = await showDatePicker(
                    context: context,
                    initialDate: _thawedAt ?? DateTime.now(),
                    firstDate: DateTime.now().subtract(const Duration(days: 365)),
                    lastDate: DateTime.now(),
                  );
                  if (d != null) setState(() => _thawedAt = d);
                },
              ),
            ],
            const SizedBox(height: 12),
            // Location picker
            Consumer(builder: (context, ref, _) {
              final locations = ref.watch(allLocationsProvider).valueOrNull ?? [];
              if (locations.isEmpty) return const SizedBox.shrink();
              return DropdownButtonFormField<String?>(
                // ignore: deprecated_member_use
                value: _locationId,
                decoration: const InputDecoration(
                  labelText: 'Lagerort',
                  prefixIcon: Icon(Icons.place_outlined),
                ),
                items: [
                  const DropdownMenuItem(value: null, child: Text('— keiner —')),
                  ...locations.map((l) =>
                      DropdownMenuItem(value: l.id, child: Text(l.name))),
                ],
                onChanged: (v) => setState(() => _locationId = v),
              );
            }),
            // ── Container picker ─────────────────────────────────────
            Consumer(builder: (context, ref, _) {
              final allItems = ref.watch(allItemsProvider).valueOrNull ?? [];
              final containers = allItems.where((i) => i.taraWeightG != null).toList();
              if (containers.isEmpty) return const SizedBox.shrink();
              final selected = containers.where((i) => i.id == _containerId).firstOrNull;
              final qty = double.tryParse(_qtyCtrl.text.replaceAll(',', '.')) ?? 0;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 12),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: const Icon(Icons.kitchen_outlined, size: 20),
                    title: Text(selected == null
                        ? 'Behälter (optional)'
                        : 'Behälter: ${selected.name}'),
                    subtitle: selected != null
                        ? Text('Tara: ${_fmtQty(selected.taraWeightG!)} g'
                            ' – Netto: ~${_fmtQty((qty - selected.taraWeightG!).clamp(0, double.infinity))} g')
                        : null,
                    trailing: _containerId != null
                        ? IconButton(
                            icon: const Icon(Icons.close, size: 16),
                            onPressed: () => setState(() => _containerId = null))
                        : const Icon(Icons.chevron_right, size: 16),
                    onTap: () => _pickContainer(context, containers),
                  ),
                ],
              );
            }),
            const SizedBox(height: 12),
            // Expiry date picker
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.calendar_today),
              title: Text(_expiryDate == null
                  ? 'MHD (optional)'
                  : 'MHD: ${DateFormat('dd.MM.yyyy').format(_expiryDate!)}'),
              trailing: _expiryDate != null
                  ? IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => setState(() => _expiryDate = null),
                    )
                  : null,
              onTap: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: DateTime.now().add(const Duration(days: 7)),
                  firstDate: DateTime.now().subtract(const Duration(days: 30)),
                  lastDate: DateTime.now().add(const Duration(days: 3650)),
                );
                if (d != null) setState(() => _expiryDate = d);
              },
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _priceCtrl,
              decoration: const InputDecoration(
                labelText: 'Preis (€)',
                prefixIcon: Icon(Icons.euro),
              ),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 12),
            // Shop picker with autocomplete + quick-save
            Consumer(builder: (context, ref, _) {
              final shops =
                  ref.watch(allShopsProvider).valueOrNull ?? [];
              final names = shops.map((s) => s.name).toList();
              return Row(
                children: [
                  Expanded(
                    child: Autocomplete<String>(
                      initialValue:
                          TextEditingValue(text: _shopName ?? ''),
                      optionsBuilder: (v) => v.text.isEmpty
                          ? names
                          : names.where((n) => n
                              .toLowerCase()
                              .contains(v.text.toLowerCase())),
                      onSelected: (v) =>
                          setState(() => _shopName = v),
                      fieldViewBuilder:
                          (context, ctrl, focusNode, onSubmit) {
                        ctrl.addListener(() => setState(
                            () => _shopName = ctrl.text.isEmpty
                                ? null
                                : ctrl.text));
                        return TextField(
                          controller: ctrl,
                          focusNode: focusNode,
                          decoration: const InputDecoration(
                            labelText: 'Geschäft (optional)',
                            prefixIcon: Icon(Icons.store_outlined),
                          ),
                        );
                      },
                    ),
                  ),
                  // Quick-save if name is new
                  if (_shopName != null &&
                      _shopName!.trim().isNotEmpty &&
                      !names.contains(_shopName!.trim()))
                    IconButton(
                      icon: const Icon(Icons.bookmark_add_outlined),
                      tooltip: 'Als Geschäft speichern',
                      onPressed: () async {
                        final name = _shopName!.trim();
                        final messenger =
                            ScaffoldMessenger.of(context);
                        await ref
                            .read(shopsNotifierProvider.notifier)
                            .create(name);
                        messenger.showSnackBar(
                          SnackBar(
                              content: Text('„$name" gespeichert')),
                        );
                      },
                    ),
                ],
              );
            }),
            const SizedBox(height: 12),
            TextFormField(
              controller: _notesCtrl,
              decoration: const InputDecoration(labelText: 'Notiz'),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Einlagern'),
            ),
          ],
          ),
        ),
      ),
    );
  }
}

// ── Consume dialog ──────────────────────────────────────────────────────────

class ConsumeDialog extends ConsumerStatefulWidget {
  final InventoryEntry entry;
  final Item item;
  const ConsumeDialog({super.key, required this.entry, required this.item});

  @override
  ConsumerState<ConsumeDialog> createState() => _ConsumeDialogState();
}

class _ConsumeDialogState extends ConsumerState<ConsumeDialog> {
  late final TextEditingController _qtyCtrl;
  late String _selectedUnit;
  String _consumptionReason = 'consumed';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _selectedUnit = widget.entry.unit;
    _qtyCtrl = TextEditingController(text: _formatQty(widget.entry.quantity));
  }

  @override
  void dispose() {
    _qtyCtrl.dispose();
    super.dispose();
  }

  String _formatQty(double q) =>
      q == q.truncateToDouble() ? q.toInt().toString() : q.toString();

  /// Convert [qty] in [_selectedUnit] to the entry's native unit using item conversions.
  /// Returns null if no conversion is found (falls back to native unit in caller).
  double? _toNativeUnit(double qty, List<UnitConversion> convs) {
    if (_selectedUnit == widget.entry.unit) return qty;
    // Find a conversion: selectedUnit → entry.unit
    final conv = convs.where((c) =>
        c.fromUnit == _selectedUnit && c.toUnit == widget.entry.unit).firstOrNull;
    if (conv != null) return qty * conv.factor;
    // Try reverse
    final rev = convs.where((c) =>
        c.fromUnit == widget.entry.unit && c.toUnit == _selectedUnit).firstOrNull;
    if (rev != null) return qty / rev.factor;
    return null;
  }

  Future<void> _consume(List<UnitConversion> convs) async {
    final qty = double.tryParse(_qtyCtrl.text.replaceAll(',', '.'));
    if (qty == null || qty <= 0) return;
    final nativeQty = _toNativeUnit(qty, convs) ?? qty;
    setState(() => _saving = true);
    try {
      final remaining = (widget.entry.quantity - nativeQty).clamp(0.0, double.infinity);
      await ref.read(inventoryOpsProvider.notifier).consume(
        itemId: widget.item.id,
        inventoryEntryId: widget.entry.id,
        quantity: nativeQty,
        unit: widget.entry.unit,
        remainingQuantity: remaining,
        consumptionReason: _consumptionReason,
      );
      await _maybeAutoOpen();
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _consumeAll() async {
    setState(() => _saving = true);
    try {
      await ref.read(inventoryOpsProvider.notifier).consume(
        itemId: widget.item.id,
        inventoryEntryId: widget.entry.id,
        quantity: widget.entry.quantity,
        unit: widget.entry.unit,
        remainingQuantity: 0,
        consumptionReason: _consumptionReason,
      );
      await _maybeAutoOpen();
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _maybeAutoOpen() async {
    if (widget.item.daysAfterOpening == null) return;
    if (widget.entry.openedAt != null) return;
    final db = ref.read(databaseProvider);
    if (db == null) return;
    await db.openEntry(widget.entry.id, widget.item.id);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${widget.item.name} als geöffnet markiert'),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final itemConvsAsync = ref.watch(itemConversionsProvider(widget.item.id));
    final globalConvsAsync = ref.watch(globalConversionsProvider);
    final convs = <UnitConversion>[
      ...itemConvsAsync.valueOrNull ?? const <UnitConversion>[],
      ...globalConvsAsync.valueOrNull ?? const <UnitConversion>[],
    ];

    // Build unit list: entry unit + all units that can convert to it
    final availableUnits = {widget.entry.unit};
    for (final c in convs) {
      if (c.toUnit == widget.entry.unit) availableUnits.add(c.fromUnit);
      if (c.fromUnit == widget.entry.unit) availableUnits.add(c.toUnit);
    }
    // Also add item stockUnit and servingSizeG-based unit names
    if (widget.item.stockUnit != null) availableUnits.add(widget.item.stockUnit!);

    final unitList = availableUnits.toList();
    if (!unitList.contains(_selectedUnit)) _selectedUnit = widget.entry.unit;

    return AlertDialog(
      title: const Text('Verbrauchen'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Bestand: ${_formatQty(widget.entry.quantity)} ${widget.entry.unit}'),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _qtyCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Menge',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  autofocus: true,
                ),
              ),
              if (unitList.length > 1) ...[
                const SizedBox(width: 8),
                SizedBox(
                  width: 110,
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    ),
                    child: DropdownButton<String>(
                      value: _selectedUnit,
                      isExpanded: true,
                      underline: const SizedBox.shrink(),
                      isDense: true,
                      items: unitList
                          .map((u) => DropdownMenuItem(value: u, child: Text(u)))
                          .toList(),
                      onChanged: (v) => setState(() => _selectedUnit = v ?? _selectedUnit),
                    ),
                  ),
                ),
              ] else
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Text(widget.entry.unit,
                      style: Theme.of(context).textTheme.bodyMedium),
                ),
            ],
          ),
          if (_selectedUnit != widget.entry.unit) ...[
            const SizedBox(height: 6),
            Builder(builder: (context) {
              final qty = double.tryParse(_qtyCtrl.text.replaceAll(',', '.'));
              if (qty == null) return const SizedBox.shrink();
              final native = _toNativeUnit(qty, convs);
              if (native == null) return const SizedBox.shrink();
              return Text(
                '= ${_formatQty(native)} ${widget.entry.unit}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.outline),
              );
            }),
          ],
          const SizedBox(height: 12),
          // Consumption reason
          DropdownButtonFormField<String>(
            initialValue: _consumptionReason,
            decoration: const InputDecoration(
              labelText: 'Grund',
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              isDense: true,
            ),
            items: const [
              DropdownMenuItem(value: 'consumed', child: Text('Konsumiert')),
              DropdownMenuItem(value: 'expired', child: Text('Abgelaufen')),
              DropdownMenuItem(value: 'discarded', child: Text('Weggeworfen')),
              DropdownMenuItem(value: 'gifted', child: Text('Verschenkt')),
            ],
            onChanged: (v) => setState(() => _consumptionReason = v ?? _consumptionReason),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        TextButton(
          onPressed: _saving ? null : _consumeAll,
          child: const Text('Alles verbraucht'),
        ),
        FilledButton(
          onPressed: _saving ? null : () => _consume(convs),
          child: _saving
              ? const SizedBox(
                  width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Verbrauchen'),
        ),
      ],
    );
  }
}

// ── Properties section ───────────────────────────────────────────────────────

class _PropertiesSection extends ConsumerWidget {
  final Item item;
  const _PropertiesSection({required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fieldsAsync =
        ref.watch(templateFieldsProvider(item.templateId!));
    final propsAsync = ref.watch(itemPropertiesProvider(item.id));
    final theme = Theme.of(context);

    final fields = fieldsAsync.valueOrNull ?? [];
    final props = propsAsync.valueOrNull ?? [];
    final propMap = {for (final p in props) p.fieldKey: p};

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.description_outlined,
                    size: 16, color: theme.colorScheme.primary),
                const SizedBox(width: 6),
                Text('Eigenschaften',
                    style: theme.textTheme.labelLarge
                        ?.copyWith(color: theme.colorScheme.primary)),
                const Spacer(),
                TextButton.icon(
                  onPressed: () =>
                      _showPropertyEditor(context, ref, fields, propMap),
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  label: const Text('Bearbeiten'),
                  style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      textStyle: const TextStyle(fontSize: 12)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (fields.isEmpty)
              Text('Keine Felder definiert.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.outline))
            else
              ...fields.map((field) {
                final prop = propMap[field.fieldName];
                final value = prop?.value ?? '';
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 120,
                        child: Text(
                          field.fieldName,
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ),
                      Expanded(
                        child: _PropertyValueWidget(
                            field: field, value: value, item: item),
                      ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  void _showPropertyEditor(
    BuildContext context,
    WidgetRef ref,
    List<TemplateField> fields,
    Map<String, ItemPropertyValue> propMap,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _PropertyEditorSheet(
          item: item, fields: fields, propMap: propMap),
    );
  }
}

class _PropertyValueWidget extends StatelessWidget {
  final TemplateField field;
  final String value;
  final Item item;
  const _PropertyValueWidget(
      {required this.field, required this.value, required this.item});

  @override
  Widget build(BuildContext context) {
    if (value.isEmpty) {
      return Text('–',
          style: TextStyle(
              color: Theme.of(context).colorScheme.outlineVariant));
    }
    switch (field.fieldType) {
      case 'boolean':
        return Text(value == 'true' ? 'Ja' : 'Nein');
      case 'link':
        try {
          final decoded = value; // raw URL or item id stored as plain text
          if (decoded.startsWith('http')) {
            return Text(decoded,
                style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    decoration: TextDecoration.underline));
          } else {
            return Row(
              children: [
                Icon(Icons.inventory_2_outlined,
                    size: 14,
                    color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 4),
                Text(decoded,
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.primary)),
              ],
            );
          }
        } catch (_) {
          return Text(value);
        }
      case 'liste':
        final lines = value.split('\n').where((l) => l.isNotEmpty).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: lines
              .map((l) => Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('• ', style: TextStyle(fontSize: 12)),
                      Expanded(child: Text(l)),
                    ],
                  ))
              .toList(),
        );
      default:
        return Text(value);
    }
  }
}

class _PropertyEditorSheet extends ConsumerStatefulWidget {
  final Item item;
  final List<TemplateField> fields;
  final Map<String, ItemPropertyValue> propMap;
  const _PropertyEditorSheet(
      {required this.item, required this.fields, required this.propMap});

  @override
  ConsumerState<_PropertyEditorSheet> createState() =>
      _PropertyEditorSheetState();
}

class _PropertyEditorSheetState extends ConsumerState<_PropertyEditorSheet> {
  late final Map<String, TextEditingController> _ctrls;
  late final Map<String, bool> _boolValues;

  @override
  void initState() {
    super.initState();
    _ctrls = {};
    _boolValues = {};
    for (final field in widget.fields) {
      final existing = widget.propMap[field.fieldName]?.value ?? '';
      if (field.fieldType == 'boolean') {
        _boolValues[field.fieldName] = existing == 'true';
      } else {
        _ctrls[field.fieldName] = TextEditingController(text: existing);
      }
    }
  }

  @override
  void dispose() {
    for (final ctrl in _ctrls.values) {
      ctrl.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (_, scrollCtrl) => Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text('Eigenschaften bearbeiten',
                  style: Theme.of(context).textTheme.titleMedium),
            ),
            Expanded(
              child: ListView(
                controller: scrollCtrl,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: widget.fields.map((field) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _buildFieldEditor(field),
                  );
                }).toList(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Abbrechen'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _save,
                      child: const Text('Speichern'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFieldEditor(TemplateField field) {
    switch (field.fieldType) {
      case 'boolean':
        return SwitchListTile(
          title: Text(field.fieldName),
          value: _boolValues[field.fieldName] ?? false,
          onChanged: (v) => setState(() => _boolValues[field.fieldName] = v),
          contentPadding: EdgeInsets.zero,
        );
      case 'date':
        return TextField(
          controller: _ctrls[field.fieldName],
          decoration: InputDecoration(
            labelText: field.fieldName,
            hintText: 'TT.MM.JJJJ',
            suffixIcon: IconButton(
              icon: const Icon(Icons.calendar_today_outlined),
              onPressed: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: DateTime.now(),
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2100),
                );
                if (picked != null) {
                  _ctrls[field.fieldName]?.text =
                      '${picked.day.toString().padLeft(2, '0')}.${picked.month.toString().padLeft(2, '0')}.${picked.year}';
                }
              },
            ),
          ),
        );
      case 'number':
        return TextField(
          controller: _ctrls[field.fieldName],
          keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: field.fieldName),
        );
      case 'liste':
        return TextField(
          controller: _ctrls[field.fieldName],
          maxLines: 4,
          decoration: InputDecoration(
            labelText: field.fieldName,
            hintText: 'Einen Eintrag pro Zeile',
          ),
        );
      default:
        return TextField(
          controller: _ctrls[field.fieldName],
          decoration: InputDecoration(labelText: field.fieldName),
        );
    }
  }

  Future<void> _save() async {
    final notifier = ref.read(propertiesNotifierProvider.notifier);
    for (final field in widget.fields) {
      String value;
      if (field.fieldType == 'boolean') {
        value = (_boolValues[field.fieldName] ?? false).toString();
      } else {
        value = _ctrls[field.fieldName]?.text.trim() ?? '';
      }
      if (value.isEmpty && widget.propMap[field.fieldName] == null) continue;
      await notifier.upsert(
        itemId: widget.item.id,
        fieldKey: field.fieldName,
        fieldType: field.fieldType,
        value: value,
        existingId: widget.propMap[field.fieldName]?.id,
      );
    }
    if (mounted) Navigator.of(context).pop();
  }
}

// ── Tags section ─────────────────────────────────────────────────────────────

class _TagsSection extends ConsumerWidget {
  final Item item;
  const _TagsSection({required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tagsAsync = ref.watch(tagsForItemProvider(item.id));
    final tags = tagsAsync.valueOrNull ?? [];
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.label_outline,
                    size: 16, color: theme.colorScheme.primary),
                const SizedBox(width: 6),
                Text('Tags',
                    style: theme.textTheme.labelLarge
                        ?.copyWith(color: theme.colorScheme.primary)),
                const Spacer(),
                TextButton.icon(
                  onPressed: () =>
                      _showTagPicker(context, ref, tags),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Hinzufügen'),
                  style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      textStyle: const TextStyle(fontSize: 12)),
                ),
              ],
            ),
            if (tags.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: tags.map((tag) {
                  Color color;
                  try {
                    color = Color(
                        int.parse(tag.color.replaceFirst('#', ''), radix: 16) |
                            0xFF000000);
                  } catch (_) {
                    color = theme.colorScheme.secondary;
                  }
                  return InputChip(
                    label: Text(tag.name,
                        style: const TextStyle(fontSize: 12)),
                    avatar: tag.icon != null
                        ? Icon(
                            IconData(int.parse(tag.icon!),
                                fontFamily: 'MaterialIcons'),
                            size: 14,
                            color: color)
                        : null,
                    backgroundColor:
                        color.withValues(alpha: 0.12),
                    side: BorderSide(
                        color: color.withValues(alpha: 0.4)),
                    visualDensity: VisualDensity.compact,
                    onDeleted: () => ref
                        .read(tagsNotifierProvider.notifier)
                        .removeTagFromItem(
                            item.id, item.categoryId, tag.name),
                  );
                }).toList(),
              ),
            ] else
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('Noch keine Tags.',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.outline)),
              ),
          ],
        ),
      ),
    );
  }

  void _showTagPicker(
      BuildContext context, WidgetRef ref, List<TagDefinition> current) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _TagPickerSheet(
        item: item,
        currentTags: current,
      ),
    );
  }
}

class _TagPickerSheet extends ConsumerStatefulWidget {
  final Item item;
  final List<TagDefinition> currentTags;
  const _TagPickerSheet({required this.item, required this.currentTags});

  @override
  ConsumerState<_TagPickerSheet> createState() => _TagPickerSheetState();
}

class _TagPickerSheetState extends ConsumerState<_TagPickerSheet> {
  final _ctrl = TextEditingController();
  late List<String> _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.currentTags.map((t) => t.name).toList();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final allAsync =
        ref.watch(tagDefinitionsForCategoryProvider(widget.item.categoryId));
    final all = allAsync.valueOrNull ?? [];
    final query = _ctrl.text.trim().toLowerCase();
    final filtered = query.isEmpty
        ? all
        : all
            .where((t) => t.name.toLowerCase().contains(query))
            .toList();
    final showCreate =
        query.isNotEmpty && !all.any((t) => t.name.toLowerCase() == query);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      builder: (_, scrollCtrl) => Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: TextField(
                controller: _ctrl,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Tag suchen oder neu erstellen…',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            Expanded(
              child: ListView(
                controller: scrollCtrl,
                children: [
                  if (showCreate)
                    ListTile(
                      leading: const Icon(Icons.add),
                      title: Text('Neu erstellen: "${_ctrl.text.trim()}"'),
                      onTap: () {
                        final name = _ctrl.text.trim();
                        if (!_selected.contains(name)) {
                          setState(() => _selected.add(name));
                        }
                        _ctrl.clear();
                        setState(() {});
                      },
                    ),
                  ...filtered.map((tag) {
                    final checked = _selected.contains(tag.name);
                    return CheckboxListTile(
                      title: Text(tag.name),
                      value: checked,
                      onChanged: (v) => setState(() {
                        if (v == true) {
                          _selected.add(tag.name);
                        } else {
                          _selected.remove(tag.name);
                        }
                      }),
                    );
                  }),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Abbrechen'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () async {
                        await ref
                            .read(tagsNotifierProvider.notifier)
                            .setTagsForItem(widget.item.id,
                                widget.item.categoryId, _selected);
                        if (context.mounted) Navigator.of(context).pop();
                      },
                      child: const Text('Speichern'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Relations section ─────────────────────────────────────────────────────────

class _RelationsSection extends ConsumerWidget {
  final Item item;
  const _RelationsSection({required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final relAsync = ref.watch(relationsForItemProvider(item.id));
    final relations = relAsync.valueOrNull ?? [];
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.link,
                    size: 16, color: theme.colorScheme.primary),
                const SizedBox(width: 6),
                Text('Verwandte Artikel',
                    style: theme.textTheme.labelLarge
                        ?.copyWith(color: theme.colorScheme.primary)),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => _showRelationPicker(context, ref),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Verlinken'),
                  style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      textStyle: const TextStyle(fontSize: 12)),
                ),
              ],
            ),
            if (relations.isNotEmpty) ...[
              const SizedBox(height: 8),
              ...relations.map((r) => _RelationTile(
                    sourceItemId: item.id,
                    relation: r.relation,
                    peer: r.peer,
                  )),
            ] else
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('Noch keine Verlinkungen.',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.outline)),
              ),
          ],
        ),
      ),
    );
  }

  void _showRelationPicker(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _RelationPickerSheet(sourceItem: item),
    );
  }
}

class _RelationTile extends ConsumerWidget {
  final String sourceItemId;
  final ItemRelation relation;
  final Item peer;
  const _RelationTile({
    required this.sourceItemId,
    required this.relation,
    required this.peer,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(Icons.arrow_forward,
          size: 16, color: theme.colorScheme.primary),
      title: Text(peer.name),
      subtitle: relation.notes != null
          ? Text(relation.notes!,
              style: const TextStyle(fontSize: 11))
          : null,
      onTap: () => context.push('/haushalt/item/${peer.id}'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 16),
            tooltip: 'Notiz bearbeiten',
            onPressed: () =>
                _editNotes(context, ref),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 16),
            tooltip: 'Verlinkung entfernen',
            onPressed: () => ref
                .read(relationsNotifierProvider.notifier)
                .delete(relation.id,
                    fromId: relation.fromItemId,
                    toId: relation.toItemId),
          ),
        ],
      ),
    );
  }

  Future<void> _editNotes(BuildContext context, WidgetRef ref) async {
    final ctrl = TextEditingController(text: relation.notes ?? '');
    final result = await showDialog<String?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Notiz bearbeiten'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Notiz (optional)'),
        ),
        actions: [
          TextButton(
              onPressed: () => ctx.pop(null),
              child: const Text('Abbrechen')),
          FilledButton(
              onPressed: () => ctx.pop(ctrl.text.trim()),
              child: const Text('Speichern')),
        ],
      ),
    );
    ctrl.dispose();
    if (result != null) {
      await ref.read(relationsNotifierProvider.notifier).updateNotes(
            relation.id,
            result.isEmpty ? null : result,
            fromId: relation.fromItemId,
            toId: relation.toItemId,
          );
    }
  }
}

class _RelationPickerSheet extends ConsumerStatefulWidget {
  final Item sourceItem;
  const _RelationPickerSheet({required this.sourceItem});

  @override
  ConsumerState<_RelationPickerSheet> createState() =>
      _RelationPickerSheetState();
}

class _RelationPickerSheetState extends ConsumerState<_RelationPickerSheet> {
  final _searchCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  Item? _selected;

  @override
  void dispose() {
    _searchCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final allItemsAsync = ref.watch(filteredItemsProvider);
    final allItems = (allItemsAsync.valueOrNull ?? [])
        .where((i) => i.id != widget.sourceItem.id)
        .toList();
    final query = _searchCtrl.text.trim().toLowerCase();
    final filtered = query.isEmpty
        ? allItems
        : allItems
            .where((i) => i.name.toLowerCase().contains(query))
            .toList();

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (_, scrollCtrl) => Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text('Artikel verlinken',
                  style: Theme.of(context).textTheme.titleMedium),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                controller: _searchCtrl,
                autofocus: _selected == null,
                decoration: const InputDecoration(
                  hintText: 'Artikel suchen…',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            if (_selected != null) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: TextField(
                  controller: _notesCtrl,
                  decoration: InputDecoration(
                    hintText: 'Notiz (optional)',
                    labelText: 'Verlinkung mit: ${_selected!.name}',
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => setState(() => _selected = null),
                        child: const Text('Anderen wählen'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: () async {
                          final notes = _notesCtrl.text.trim();
                          await ref
                              .read(relationsNotifierProvider.notifier)
                              .add(widget.sourceItem.id, _selected!.id,
                                  notes: notes.isEmpty ? null : notes);
                          if (context.mounted) Navigator.of(context).pop();
                        },
                        child: const Text('Verlinken'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            Expanded(
              child: ListView.builder(
                controller: scrollCtrl,
                itemCount: filtered.length,
                itemBuilder: (_, i) {
                  final itm = filtered[i];
                  return ListTile(
                    leading: const Icon(Icons.inventory_2_outlined),
                    title: Text(itm.name),
                    subtitle: itm.brand != null ? Text(itm.brand!) : null,
                    onTap: () => setState(() {
                      _selected = itm;
                      _searchCtrl.clear();
                    }),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── State change sheet ────────────────────────────────────────────────────────

// ── Relocate entry sheet ─────────────────────────────────────────────────────

class _RelocateSheet extends ConsumerStatefulWidget {
  final InventoryEntry entry;
  final List<Location> locations;
  const _RelocateSheet({required this.entry, required this.locations});

  @override
  ConsumerState<_RelocateSheet> createState() => _RelocateSheetState();
}

class _RelocateSheetState extends ConsumerState<_RelocateSheet> {
  late String? _locationId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _locationId = widget.entry.locationId;
  }

  Future<void> _save() async {
    if (_locationId == widget.entry.locationId) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(databaseProvider)?.updateEntryLocation(
            widget.entry.id,
            _locationId,
          );
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 12, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Umbuchen', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            '${_formatQty(widget.entry.quantity)} ${widget.entry.unit}',
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String?>(
            value: _locationId,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Neuer Lagerort',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.place_outlined),
            ),
            items: [
              const DropdownMenuItem(value: null, child: Text('— kein Ort —')),
              ...widget.locations.map(
                  (l) => DropdownMenuItem(value: l.id, child: Text(l.name))),
            ],
            onChanged: (v) => setState(() => _locationId = v),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Umbuchen'),
          ),
        ],
      ),
    );
  }

  String _formatQty(double q) =>
      q == q.truncateToDouble() ? q.toInt().toString() : q.toString();
}

// ── State change sheet ───────────────────────────────────────────────────────

class _StateChangeSheet extends ConsumerStatefulWidget {
  final InventoryEntry entry;
  const _StateChangeSheet({required this.entry});

  @override
  ConsumerState<_StateChangeSheet> createState() => _StateChangeSheetState();
}

class _StateChangeSheetState extends ConsumerState<_StateChangeSheet> {
  late String _newState;
  DateTime? _frozenAt;
  DateTime? _thawedAt;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _newState = widget.entry.state;
    _frozenAt = widget.entry.frozenAt;
    _thawedAt = widget.entry.thawedAt;
  }

  Future<void> _save() async {
    if (_newState == widget.entry.state &&
        _frozenAt == widget.entry.frozenAt &&
        _thawedAt == widget.entry.thawedAt) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(databaseProvider)!.updateEntryState(
        widget.entry.id,
        widget.entry.itemId,
        fromState: widget.entry.state,
        newState: _newState,
        frozenAt: _frozenAt,
        thawedAt: _thawedAt,
      );
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Zustand ändern',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: const Text('Frisch'),
                selected: _newState == 'fresh',
                onSelected: (v) {
                  if (v) setState(() => _newState = 'fresh');
                },
              ),
              ChoiceChip(
                avatar: const Icon(Icons.ac_unit, size: 14),
                label: const Text('Tiefgefroren'),
                selected: _newState == 'frozen',
                onSelected: (v) {
                  if (v) {
                    setState(() {
                      _newState = 'frozen';
                      _frozenAt ??= DateTime.now();
                    });
                  }
                },
              ),
              ChoiceChip(
                label: const Text('Aufgetaut'),
                selected: _newState == 'thawed',
                onSelected: (v) {
                  if (v) {
                    setState(() {
                      _newState = 'thawed';
                      _thawedAt ??= DateTime.now();
                    });
                  }
                },
              ),
            ],
          ),
          if (_newState == 'frozen' || _newState == 'thawed') ...[
            const SizedBox(height: 4),
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: const Icon(Icons.ac_unit, size: 20, color: Colors.blue),
              title: Text(_frozenAt == null
                  ? 'Eingefroren am (optional)'
                  : 'Eingefroren: ${DateFormat('dd.MM.yyyy').format(_frozenAt!)}'),
              trailing: _frozenAt != null
                  ? IconButton(
                      icon: const Icon(Icons.close, size: 16),
                      onPressed: () => setState(() => _frozenAt = null))
                  : null,
              onTap: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: _frozenAt ?? DateTime.now(),
                  firstDate: DateTime.now().subtract(const Duration(days: 365)),
                  lastDate: DateTime.now(),
                );
                if (d != null) setState(() => _frozenAt = d);
              },
            ),
          ],
          if (_newState == 'thawed') ...[
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: const Icon(Icons.water_drop_outlined,
                  size: 20, color: Colors.cyan),
              title: Text(_thawedAt == null
                  ? 'Aufgetaut am (optional)'
                  : 'Aufgetaut: ${DateFormat('dd.MM.yyyy').format(_thawedAt!)}'),
              trailing: _thawedAt != null
                  ? IconButton(
                      icon: const Icon(Icons.close, size: 16),
                      onPressed: () => setState(() => _thawedAt = null))
                  : null,
              onTap: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: _thawedAt ?? DateTime.now(),
                  firstDate: DateTime.now().subtract(const Duration(days: 365)),
                  lastDate: DateTime.now(),
                );
                if (d != null) setState(() => _thawedAt = d);
              },
            ),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Speichern'),
          ),
        ],
      ),
    );
  }
}

// ── Container picker sheet ────────────────────────────────────────────────────

class _ContainerPickerSheet extends StatefulWidget {
  final List<Item> containers;
  final String? selectedId;
  const _ContainerPickerSheet(
      {required this.containers, required this.selectedId});

  @override
  State<_ContainerPickerSheet> createState() => _ContainerPickerSheetState();
}

class _ContainerPickerSheetState extends State<_ContainerPickerSheet> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  String _fmtNum(double v) =>
      v == v.truncateToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final query = _ctrl.text.trim().toLowerCase();
    final filtered = query.isEmpty
        ? widget.containers
        : widget.containers
            .where((i) => i.name.toLowerCase().contains(query))
            .toList();

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.8,
      builder: (_, scrollCtrl) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TextField(
              controller: _ctrl,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Behälter suchen…',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.close),
            title: const Text('Kein Behälter'),
            selected: widget.selectedId == null,
            onTap: () => Navigator.of(context).pop(''),
          ),
          Expanded(
            child: ListView.builder(
              controller: scrollCtrl,
              itemCount: filtered.length,
              itemBuilder: (_, i) {
                final item = filtered[i];
                return ListTile(
                  leading: const Icon(Icons.kitchen_outlined),
                  title: Text(item.name),
                  subtitle: Text('Tara: ${_fmtNum(item.taraWeightG!)} g'),
                  selected: item.id == widget.selectedId,
                  onTap: () => Navigator.of(context).pop(item.id),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
