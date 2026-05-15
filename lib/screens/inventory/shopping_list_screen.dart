import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../db/database.dart';
import '../../providers/groups_provider.dart';
import '../../providers/inventory_provider.dart';
import '../../providers/items_provider.dart';
import '../../providers/shops_provider.dart';
import '../../providers/vault_provider.dart';
import '../items/item_detail_screen.dart';

/// Tracks whether the simplified "Einkaufsmodus" is active.
/// Scoped to the app session — resets on hot restart but not hot reload.
final _shoppingModeProvider = StateProvider<bool>((ref) => false);

class ShoppingListScreen extends ConsumerWidget {
  /// When true, omits the Scaffold/AppBar — used when embedded in a TabBarView.
  final bool embedded;
  const ShoppingListScreen({super.key, this.embedded = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sectionsAsync = ref.watch(shoppingByShopProvider);
    final shoppingMode = ref.watch(_shoppingModeProvider);

    final appBarActions = [
      IconButton(
        icon: Icon(shoppingMode ? Icons.shopping_cart : Icons.shopping_cart_outlined),
        tooltip: shoppingMode ? 'Einkaufsmodus beenden' : 'Einkaufsmodus',
        color: shoppingMode ? Theme.of(context).colorScheme.primary : null,
        onPressed: () =>
            ref.read(_shoppingModeProvider.notifier).state = !shoppingMode,
      ),
      if (!shoppingMode)
        IconButton(
          icon: const Icon(Icons.qr_code_scanner),
          tooltip: 'Scan zum Hinzufügen',
          onPressed: () => _scanToAdd(context, ref),
        ),
      if (!shoppingMode)
        IconButton(
          icon: const Icon(Icons.add),
          tooltip: 'Eintrag hinzufügen',
          onPressed: () => _showAddDialog(context, ref),
        ),
      if (!shoppingMode)
        PopupMenuButton<String>(
        tooltip: 'Weitere Optionen',
        onSelected: (v) {
          switch (v) {
            case 'groups':
              context.push('/haushalt/groups');
            case 'shops':
              context.push('/settings/shops');
            case 'reset_snoozed':
              ref.read(snoozedShoppingNeedsProvider.notifier).state = {};
          }
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'groups', child: Text('Gruppen verwalten')),
          PopupMenuItem(value: 'shops', child: Text('Geschäfte verwalten')),
          PopupMenuItem(
              value: 'reset_snoozed',
              child: Text('Übersprungene zurücksetzen')),
        ],
      ),
    ];

    final snoozedCount = ref.watch(snoozedShoppingNeedsProvider).length;

    final body = sectionsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Fehler: $e')),
      data: (sections) {
        final allNeeds = sections.expand((s) => s.needs).toList();
        final allCustom = sections.expand((s) => s.customItems).toList();

        if (allNeeds.isEmpty && allCustom.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle_outline,
                    size: 64,
                    color: Theme.of(context).colorScheme.primary),
                const SizedBox(height: 16),
                const Text('Einkaufsliste ist leer!'),
                const SizedBox(height: 8),
                const Text(
                  'Tippe + um Einträge hinzuzufügen,\noder definiere Mindestbestände.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
                if (snoozedCount > 0) ...[
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: () =>
                        ref.read(snoozedShoppingNeedsProvider.notifier).state =
                            {},
                    icon: const Icon(Icons.refresh, size: 16),
                    label: Text('$snoozedCount übersprungen – zurücksetzen'),
                  ),
                ],
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () => _showAddDialog(context, ref),
                  icon: const Icon(Icons.add),
                  label: const Text('Eintrag hinzufügen'),
                ),
              ],
            ),
          );
        }

        final checkedCount =
            allCustom.where((c) => c.checked).length;

        return Column(
          children: [
            if (shoppingMode)
              MaterialBanner(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                content: Text(
                  'Einkaufsmodus aktiv – tippe Artikel zum Abhaken',
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.onPrimaryContainer),
                ),
                backgroundColor:
                    Theme.of(context).colorScheme.primaryContainer,
                actions: [
                  TextButton(
                    onPressed: () => ref
                        .read(_shoppingModeProvider.notifier)
                        .state = false,
                    child: const Text('Beenden'),
                  ),
                ],
              ),
            if (!shoppingMode)
              Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  Icon(Icons.info_outline,
                      size: 16,
                      color: Theme.of(context).colorScheme.outline),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      [
                        if (allNeeds.isNotEmpty)
                          '${allNeeds.length} unter Mindestbestand',
                        if (allCustom.isNotEmpty)
                          '${allCustom.length} manuell',
                        if (snoozedCount > 0)
                          '$snoozedCount übersprungen',
                      ].join(' · '),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  if (checkedCount > 0)
                    TextButton.icon(
                      onPressed: () =>
                          ref.read(databaseProvider)?.deleteCheckedCustomShoppingItems(),
                      icon: const Icon(Icons.delete_sweep_outlined, size: 16),
                      label: Text('$checkedCount erledigt löschen'),
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        textStyle: const TextStyle(fontSize: 12),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                itemCount: sections.length,
                itemBuilder: (context, si) {
                  final section = sections[si];
                  return _ShopSection(
                    section: section,
                    shoppingMode: shoppingMode,
                    onAddCustom: () => _showAddDialog(context, ref,
                        preselectedShopId: section.shop?.id),
                  );
                },
              ),
            ),
          ],
        );
      },
    );

    if (embedded) {
      return Stack(
        children: [
          body,
          if (!shoppingMode)
            Positioned(
              right: 16,
              bottom: 136,
              child: FloatingActionButton.small(
                heroTag: 'scan_shopping',
                onPressed: () => _scanToAdd(context, ref),
                tooltip: 'Scan zum Hinzufügen',
                child: const Icon(Icons.qr_code_scanner),
              ),
            ),
          Positioned(
            right: 16,
            bottom: 80,
            child: FloatingActionButton.small(
              heroTag: 'shopping_mode_toggle',
              onPressed: () =>
                  ref.read(_shoppingModeProvider.notifier).state = !shoppingMode,
              tooltip:
                  shoppingMode ? 'Einkaufsmodus beenden' : 'Einkaufsmodus',
              backgroundColor: shoppingMode
                  ? Theme.of(context).colorScheme.primary
                  : null,
              foregroundColor: shoppingMode
                  ? Theme.of(context).colorScheme.onPrimary
                  : null,
              child: Icon(shoppingMode
                  ? Icons.shopping_cart
                  : Icons.shopping_cart_outlined),
            ),
          ),
          Positioned(
            right: 16,
            bottom: 16,
            child: FloatingActionButton(
              heroTag: 'add_shopping',
              onPressed: () => _showAddDialog(context, ref),
              tooltip: 'Eintrag hinzufügen',
              child: const Icon(Icons.add),
            ),
          ),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Einkaufsliste'),
        actions: appBarActions,
      ),
      body: body,
    );
  }

  void _showAddDialog(BuildContext context, WidgetRef ref,
      {String? preselectedShopId}) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _AddCustomItemSheet(
        preselectedShopId: preselectedShopId,
      ),
    );
  }

  Future<void> _scanToAdd(BuildContext context, WidgetRef ref) async {
    final ean = await context.push<String>('/scan');
    if (ean == null || !context.mounted) return;
    final db = ref.read(databaseProvider);
    if (db == null) return;
    final item = await db.itemByEan(ean);
    if (!context.mounted) return;
    if (item == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Artikel nicht gefunden'),
          action: SnackBarAction(
            label: 'Anlegen',
            onPressed: () => context.push('/haushalt/item/new', extra: ean),
          ),
        ),
      );
      return;
    }
    await db.insertCustomShoppingItem(CustomShoppingItemsCompanion.insert(
      id: const Uuid().v4(),
      name: item.name,
      itemId: Value(item.id),
      shopId: Value(item.preferredShopId),
    ));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${item.name} zur Einkaufsliste hinzugefügt')),
      );
    }
  }
}

// ── Shop section ──────────────────────────────────────────────────────────────

class _ShopSection extends StatelessWidget {
  final ShoppingSection section;
  final VoidCallback onAddCustom;
  final bool shoppingMode;
  const _ShopSection(
      {required this.section,
      required this.onAddCustom,
      this.shoppingMode = false});

  @override
  Widget build(BuildContext context) {
    final shopName = section.shop?.name ?? 'Kein Geschäft';
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 8, 0, 4),
          child: Row(
            children: [
              Icon(
                section.shop != null
                    ? Icons.store_outlined
                    : Icons.store_mall_directory_outlined,
                size: shoppingMode ? 20 : 16,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  shopName,
                  style: (shoppingMode
                          ? theme.textTheme.titleMedium
                          : theme.textTheme.labelLarge)
                      ?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (!shoppingMode)
                InkWell(
                  onTap: onAddCustom,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(Icons.add, size: 16,
                        color: theme.colorScheme.primary),
                  ),
                ),
            ],
          ),
        ),
        ...section.needs.map((need) =>
            _NeedCard(need: need, shoppingMode: shoppingMode)),
        ...section.customItems.map((item) => item.itemId != null
            ? _LinkedItemCard(customItem: item, shoppingMode: shoppingMode)
            : _CustomItemTile(item: item, shoppingMode: shoppingMode)),
        const SizedBox(height: 4),
      ],
    );
  }
}

// ── Custom item tile (no item link) ──────────────────────────────────────────

class _CustomItemTile extends ConsumerWidget {
  final CustomShoppingItem item;
  final bool shoppingMode;
  const _CustomItemTile({required this.item, this.shoppingMode = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.read(databaseProvider);
    final theme = Theme.of(context);

    if (shoppingMode) {
      return InkWell(
        onTap: () => db?.toggleCustomShoppingItem(item.id, !item.checked),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Transform.scale(
                scale: 1.4,
                child: Checkbox(
                  value: item.checked,
                  onChanged: (v) =>
                      db?.toggleCustomShoppingItem(item.id, v ?? false),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      style: theme.textTheme.titleMedium?.copyWith(
                        decoration:
                            item.checked ? TextDecoration.lineThrough : null,
                        color: item.checked ? theme.colorScheme.outline : null,
                      ),
                    ),
                    if (item.quantity != null)
                      Text('${_fmt(item.quantity!)} ${item.unit ?? ''}',
                          style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        dense: true,
        leading: Checkbox(
          value: item.checked,
          onChanged: (v) =>
              db?.toggleCustomShoppingItem(item.id, v ?? false),
        ),
        title: Text(
          item.name,
          style: item.checked
              ? TextStyle(
                  decoration: TextDecoration.lineThrough,
                  color: theme.colorScheme.outline,
                )
              : null,
        ),
        subtitle: item.quantity != null
            ? Text(
                '${_fmt(item.quantity!)} ${item.unit ?? ''}',
                style: const TextStyle(fontSize: 12),
              )
            : null,
        trailing: PopupMenuButton<String>(
          onSelected: (v) async {
            if (v == 'edit') {
              showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                useSafeArea: true,
                builder: (_) => _AddCustomItemSheet(existing: item),
              );
            } else if (v == 'delete') {
              db?.deleteCustomShoppingItem(item.id);
            } else if (v == 'link') {
              final allItems = ref.read(allItemsProvider).valueOrNull ?? [];
              if (allItems.isEmpty || !context.mounted) return;
              final picked = await showModalBottomSheet<Item>(
                context: context,
                isScrollControlled: true,
                useSafeArea: true,
                builder: (ctx) => _ItemSearchSheet(items: allItems),
              );
              if (picked != null && context.mounted) {
                await db?.updateCustomShoppingItem(CustomShoppingItemsCompanion(
                  id: Value(item.id),
                  itemId: Value(picked.id),
                ));
              }
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(
              value: 'edit',
              child: Row(children: [
                Icon(Icons.edit_outlined),
                SizedBox(width: 8),
                Text('Bearbeiten'),
              ]),
            ),
            const PopupMenuItem(
              value: 'link',
              child: Row(children: [
                Icon(Icons.link),
                SizedBox(width: 8),
                Text('Mit Artikel verknüpfen'),
              ]),
            ),
            const PopupMenuItem(
              value: 'delete',
              child: Row(children: [
                Icon(Icons.delete_outline, color: Colors.red),
                SizedBox(width: 8),
                Text('Löschen', style: TextStyle(color: Colors.red)),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  String _fmt(double q) =>
      q == q.truncateToDouble() ? q.toInt().toString() : q.toStringAsFixed(1);
}

// ── Linked item card (mirrors _NeedCard, shows current stock) ─────────────────

class _LinkedItemCard extends ConsumerWidget {
  final CustomShoppingItem customItem;
  final bool shoppingMode;
  const _LinkedItemCard(
      {required this.customItem, this.shoppingMode = false});

  String _fmt(double q) =>
      q == q.truncateToDouble() ? q.toInt().toString() : q.toStringAsFixed(1);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemAsync = ref.watch(itemByIdProvider(customItem.itemId!));
    final statesAsync =
        ref.watch(itemStatesForItemProvider(customItem.itemId!));
    final db = ref.read(databaseProvider);
    final theme = Theme.of(context);

    return itemAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (e, _) => _CustomItemTile(item: customItem, shoppingMode: shoppingMode),
      data: (item) {
        if (item == null) {
          return _CustomItemTile(item: customItem, shoppingMode: shoppingMode);
        }

        final states = statesAsync.valueOrNull ?? [];
        final unit =
            customItem.unit ?? item.minStockUnit ?? item.stockUnit ?? '';
        double currentQty = 0;
        for (final s in states) {
          if (unit.isEmpty || s.unit == unit) {
            currentQty += s.currentQuantity;
          }
        }
        final neededQty = customItem.quantity ?? item.minStockQuantity ?? 0;

        if (shoppingMode) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Transform.scale(
                  scale: 1.4,
                  child: Checkbox(
                    value: customItem.checked,
                    onChanged: (v) => db?.toggleCustomShoppingItem(
                        customItem.id, v ?? false),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.name,
                        style: theme.textTheme.titleMedium?.copyWith(
                          decoration: customItem.checked
                              ? TextDecoration.lineThrough
                              : null,
                          color: customItem.checked
                              ? theme.colorScheme.outline
                              : null,
                        ),
                      ),
                      if (neededQty > 0)
                        Text(
                          '+${_fmt(neededQty)} $unit benötigt',
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.error),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }

        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Icon(Icons.inventory_2_outlined,
                          size: 16,
                          color: theme.colorScheme.onSurfaceVariant),
                    ),
                    Expanded(
                      child: Text(item.name,
                          style: theme.textTheme.titleMedium),
                    ),
                    if (neededQty > 0)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '${_fmt(currentQty)} / ${_fmt(neededQty)} $unit',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.error,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text('vorhanden / Ziel',
                              style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.outline)),
                        ],
                      ),
                  ],
                ),
                if (neededQty > 0) ...[
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: (currentQty / neededQty).clamp(0.0, 1.0),
                      minHeight: 6,
                      backgroundColor: theme.colorScheme.errorContainer,
                      valueColor: AlwaysStoppedAnimation(
                          theme.colorScheme.error),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    // Edit
                    TextButton.icon(
                      onPressed: () => showModalBottomSheet<void>(
                        context: context,
                        isScrollControlled: true,
                        useSafeArea: true,
                        builder: (_) =>
                            _AddCustomItemSheet(existing: customItem),
                      ),
                      icon: const Icon(Icons.edit_outlined, size: 16),
                      label: const Text('Bearbeiten'),
                      style: TextButton.styleFrom(
                        foregroundColor: theme.colorScheme.outline,
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                    // Delete
                    TextButton.icon(
                      onPressed: () =>
                          db?.deleteCustomShoppingItem(customItem.id),
                      icon: const Icon(Icons.close, size: 16),
                      label: const Text('Entfernen'),
                      style: TextButton.styleFrom(
                        foregroundColor: theme.colorScheme.outline,
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                    const Spacer(),
                    // Buy button → opens AddStockSheet, auto-removes on success
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final booked = await showModalBottomSheet<bool>(
                            context: context,
                            isScrollControlled: true,
                            useSafeArea: true,
                            builder: (_) => AddStockSheet(item: item),
                          );
                          if (booked == true && context.mounted) {
                            await db?.deleteCustomShoppingItem(customItem.id);
                          }
                        },
                        icon: const Icon(Icons.add_shopping_cart, size: 18),
                        label: Text(
                          neededQty > 0
                              ? '+${_fmt(neededQty)} $unit einkaufen'
                              : 'Einlagern',
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ── Item search sheet for linking ─────────────────────────────────────────────

class _ItemSearchSheet extends StatefulWidget {
  final List<Item> items;
  const _ItemSearchSheet({required this.items});

  @override
  State<_ItemSearchSheet> createState() => _ItemSearchSheetState();
}

class _ItemSearchSheetState extends State<_ItemSearchSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final filtered = _query.isEmpty
        ? widget.items
        : widget.items
            .where((i) =>
                i.name.toLowerCase().contains(_query.toLowerCase()) ||
                (i.brand?.toLowerCase().contains(_query.toLowerCase()) ??
                    false))
            .toList();

    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TextField(
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Artikel suchen…',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: filtered.length,
              itemBuilder: (ctx, i) {
                final item = filtered[i];
                return ListTile(
                  leading: const Icon(Icons.inventory_2_outlined),
                  title: Text(item.name),
                  subtitle: item.brand != null ? Text(item.brand!) : null,
                  onTap: () => Navigator.of(ctx).pop(item),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ── Need card ─────────────────────────────────────────────────────────────────

class _NeedCard extends ConsumerWidget {
  final ShoppingNeed need;
  final bool shoppingMode;
  const _NeedCard({required this.need, this.shoppingMode = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final unit = need.unit;
    final minQty = need.group?.minStockQuantity ?? need.item?.minStockQuantity ?? 0;
    final isItemNeed = need.group == null;

    if (shoppingMode) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Transform.scale(
              scale: 1.4,
              child: Checkbox(
                value: false,
                onChanged: (_) => _showBuyFlow(context, ref, need),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(need.name, style: theme.textTheme.titleMedium),
                  Text(
                    '+${_fmt(need.neededQty)} $unit benötigt',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.error),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (isItemNeed)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Icon(Icons.inventory_2_outlined,
                        size: 16, color: theme.colorScheme.onSurfaceVariant),
                  ),
                Expanded(
                  child: Text(need.name, style: theme.textTheme.titleMedium),
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
                value: minQty > 0
                    ? (need.currentQty / minQty).clamp(0.0, 1.0)
                    : 0.0,
                minHeight: 6,
                backgroundColor: theme.colorScheme.errorContainer,
                valueColor:
                    AlwaysStoppedAnimation(theme.colorScheme.error),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton.icon(
                  onPressed: () {
                    final id = need.group?.id ?? need.item?.id;
                    if (id != null) {
                      ref
                          .read(snoozedShoppingNeedsProvider.notifier)
                          .update((s) => {...s, id});
                    }
                  },
                  icon: const Icon(Icons.close, size: 16),
                  label: const Text('Skip'),
                  style: TextButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                Expanded(
                  child: Builder(builder: (context) {
                    final pUnit = need.item?.purchaseUnit;
                    final pQty = need.item?.purchaseQty;
                    final packCount = (pUnit != null && pQty != null && pQty > 0)
                        ? (need.neededQty / pQty).ceil()
                        : null;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () => _showBuyFlow(context, ref, need),
                          icon: const Icon(Icons.add_shopping_cart, size: 18),
                          label: Text(
                            packCount != null
                                ? '+$packCount $pUnit einkaufen'
                                : '+${_fmt(need.neededQty)} $unit einkaufen',
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                        if (packCount != null)
                          Text(
                            '= ${_fmt(need.neededQty)} $unit',
                            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: Theme.of(context).colorScheme.outline),
                            textAlign: TextAlign.center,
                          ),
                      ],
                    );
                  }),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _fmt(double q) => q.ceil().toString();

  Future<void> _showBuyFlow(
      BuildContext context, WidgetRef ref, ShoppingNeed need) async {
    final db = ref.read(databaseProvider);
    if (db == null) return;

    Item? selectedItem;

    if (need.item != null) {
      selectedItem = need.item;
    } else {
      final members = await db.membersForGroup(need.group!.id);
      if (members.isEmpty || !context.mounted) return;

      if (members.length == 1) {
        selectedItem = await db.itemById(members.first.itemId);
      } else {
        final items = await Future.wait(
            members.map((m) => db.itemById(m.itemId)));
        final available = items.whereType<Item>().toList();
        if (!context.mounted) return;
        selectedItem = await showDialog<Item>(
          context: context,
          builder: (ctx) => SimpleDialog(
            title: const Text('Welchen Artikel einlagern?'),
            children: available
                .map((item) => SimpleDialogOption(
                      onPressed: () => Navigator.of(ctx).pop(item),
                      child: ListTile(
                        dense: true,
                        leading: const Icon(Icons.inventory_2_outlined),
                        title: Text(item.name),
                        subtitle:
                            item.brand != null ? Text(item.brand!) : null,
                      ),
                    ))
                .toList(),
          ),
        );
      }
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

// ── Add / edit custom item sheet ──────────────────────────────────────────────

class _AddCustomItemSheet extends ConsumerStatefulWidget {
  final String? preselectedShopId;
  final CustomShoppingItem? existing;
  const _AddCustomItemSheet({this.preselectedShopId, this.existing});

  @override
  ConsumerState<_AddCustomItemSheet> createState() =>
      _AddCustomItemSheetState();
}

class _AddCustomItemSheetState extends ConsumerState<_AddCustomItemSheet> {
  static const _uuid = Uuid();
  final _nameCtrl = TextEditingController();
  final _qtyCtrl = TextEditingController();
  final _unitCtrl = TextEditingController();
  String? _shopId;
  String? _linkedItemId;
  String? _linkedItemName;
  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _nameCtrl.text = e.name;
      if (e.quantity != null) {
        _qtyCtrl.text = e.quantity!.toStringAsFixed(
            e.quantity! == e.quantity!.truncateToDouble() ? 0 : 1);
      }
      _unitCtrl.text = e.unit ?? '';
      _shopId = e.shopId;
      _linkedItemId = e.itemId;
    } else {
      _shopId = widget.preselectedShopId;
    }
    // If editing a linked item, load the name asynchronously
    if (_linkedItemId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final db = ref.read(databaseProvider);
        if (db == null) return;
        final item = await db.itemById(_linkedItemId!);
        if (mounted && item != null) {
          setState(() => _linkedItemName = item.name);
        }
      });
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _qtyCtrl.dispose();
    _unitCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickItem() async {
    final allItems = ref.read(allItemsProvider).valueOrNull ?? [];
    if (allItems.isEmpty) return;
    final picked = await showModalBottomSheet<Item>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _ItemSearchSheet(items: allItems),
    );
    if (picked == null) return;
    setState(() {
      _linkedItemId = picked.id;
      _linkedItemName = picked.name;
      if (_nameCtrl.text.trim().isEmpty) _nameCtrl.text = picked.name;
    });
  }

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty) return;
    final db = ref.read(databaseProvider);
    if (db == null) return;
    setState(() => _saving = true);
    try {
      final qty =
          double.tryParse(_qtyCtrl.text.replaceAll(',', '.'));
      final unit =
          _unitCtrl.text.trim().isEmpty ? null : _unitCtrl.text.trim();

      if (_isEdit) {
        await db.updateCustomShoppingItem(CustomShoppingItemsCompanion(
          id: Value(widget.existing!.id),
          name: Value(_nameCtrl.text.trim()),
          quantity: Value(qty),
          unit: Value(unit),
          shopId: Value(_shopId),
          itemId: Value(_linkedItemId),
        ));
      } else {
        await db.insertCustomShoppingItem(CustomShoppingItemsCompanion.insert(
          id: _uuid.v4(),
          name: _nameCtrl.text.trim(),
          quantity: Value(qty),
          unit: Value(unit),
          shopId: Value(_shopId),
          itemId: Value(_linkedItemId),
        ));
      }
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final shopsAsync = ref.watch(allShopsProvider);
    final shops = shopsAsync.valueOrNull ?? [];
    final bottom = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 20, 16, bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _isEdit ? 'Eintrag bearbeiten' : 'Eintrag hinzufügen',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _nameCtrl,
            autofocus: !_isEdit,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Bezeichnung *'),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _qtyCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Menge'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _unitCtrl,
                  decoration: const InputDecoration(labelText: 'Einheit'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              Icons.inventory_2_outlined,
              color: _linkedItemId != null
                  ? Theme.of(context).colorScheme.secondary
                  : null,
            ),
            title: Text(
              _linkedItemName ??
                  (_linkedItemId != null ? '…' : 'Artikel verlinken (optional)'),
              style: _linkedItemId != null
                  ? TextStyle(
                      color: Theme.of(context).colorScheme.secondary,
                      fontWeight: FontWeight.w500)
                  : null,
            ),
            subtitle: _linkedItemId != null
                ? const Text('Lagerbestand + Einlagern-Flow verfügbar',
                    style: TextStyle(fontSize: 11))
                : null,
            trailing: _linkedItemId != null
                ? IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => setState(() {
                      _linkedItemId = null;
                      _linkedItemName = null;
                    }),
                  )
                : const Icon(Icons.chevron_right, size: 18),
            onTap: _pickItem,
          ),
          if (shops.isNotEmpty) ...[
            const SizedBox(height: 4),
            InputDecorator(
              decoration: const InputDecoration(labelText: 'Geschäft'),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String?>(
                  value: _shopId,
                  isDense: true,
                  isExpanded: true,
                  items: [
                    const DropdownMenuItem(
                        value: null, child: Text('Kein Geschäft')),
                    ...shops.map((s) =>
                        DropdownMenuItem(value: s.id, child: Text(s.name))),
                  ],
                  onChanged: (v) => setState(() => _shopId = v),
                ),
              ),
            ),
          ],
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Abbrechen'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(_isEdit ? 'Speichern' : 'Hinzufügen'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
