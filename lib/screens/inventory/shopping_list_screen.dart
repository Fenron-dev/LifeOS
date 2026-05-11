import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../db/database.dart';
import '../../providers/groups_provider.dart';
import '../../providers/items_provider.dart';
import '../../providers/shops_provider.dart';
import '../../providers/vault_provider.dart';
import '../items/item_detail_screen.dart';

class ShoppingListScreen extends ConsumerWidget {
  /// When true, omits the Scaffold/AppBar — used when embedded in a TabBarView.
  final bool embedded;
  const ShoppingListScreen({super.key, this.embedded = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sectionsAsync = ref.watch(shoppingByShopProvider);

    final appBarActions = [
      IconButton(
        icon: const Icon(Icons.add),
        tooltip: 'Eintrag hinzufügen',
        onPressed: () => _showAddDialog(context, ref),
      ),
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
      builder: (_) => _AddCustomItemDialog(
        preselectedShopId: preselectedShopId,
      ),
    );
  }
}

// ── Shop section ──────────────────────────────────────────────────────────────

class _ShopSection extends StatelessWidget {
  final ShoppingSection section;
  final VoidCallback onAddCustom;
  const _ShopSection({required this.section, required this.onAddCustom});

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
                size: 16,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  shopName,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
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
        ...section.needs.map((need) => _NeedCard(need: need)),
        ...section.customItems
            .map((item) => _CustomItemTile(item: item)),
        const SizedBox(height: 4),
      ],
    );
  }
}

// ── Custom item tile ──────────────────────────────────────────────────────────

class _CustomItemTile extends ConsumerWidget {
  final CustomShoppingItem item;
  const _CustomItemTile({required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.read(databaseProvider);
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        dense: true,
        leading: Checkbox(
          value: item.checked,
          onChanged: (v) async {
            await db?.toggleCustomShoppingItem(item.id, v ?? false);
            // If linked to an inventory item and just checked, open add-stock.
            if ((v ?? false) && item.itemId != null && context.mounted) {
              final linkedItem = await db?.itemById(item.itemId!);
              if (linkedItem != null && context.mounted) {
                showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  useSafeArea: true,
                  builder: (_) => AddStockSheet(item: linkedItem),
                );
              }
            }
          },
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
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (item.quantity != null)
              Text(
                '${_fmt(item.quantity!)} ${item.unit ?? ''}',
                style: const TextStyle(fontSize: 12),
              ),
            if (item.itemId != null)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.inventory_2_outlined,
                      size: 11,
                      color: theme.colorScheme.secondary),
                  const SizedBox(width: 3),
                  Text('Verlinkt',
                      style: TextStyle(
                          fontSize: 11,
                          color: theme.colorScheme.secondary)),
                ],
              ),
          ],
        ),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline, size: 18),
          onPressed: () => db?.deleteCustomShoppingItem(item.id),
          tooltip: 'Entfernen',
        ),
      ),
    );
  }

  String _fmt(double q) =>
      q == q.truncateToDouble() ? q.toInt().toString() : q.toStringAsFixed(1);
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
  const _NeedCard({required this.need});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final unit = need.unit;
    final minQty = need.group?.minStockQuantity ?? need.item?.minStockQuantity ?? 0;
    final isItemNeed = need.group == null;

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
                  label: const Text('Überspringen'),
                  style: TextButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.outline,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _showBuyFlow(context, ref, need),
                    icon: const Icon(Icons.add_shopping_cart, size: 18),
                    label: Text(
                      '+${_fmt(need.neededQty)} $unit einkaufen',
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
  }

  String _fmt(double q) =>
      q == q.truncateToDouble() ? q.toInt().toString() : q.toStringAsFixed(1);

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

// ── Add custom item dialog ────────────────────────────────────────────────────

class _AddCustomItemDialog extends ConsumerStatefulWidget {
  final String? preselectedShopId;
  const _AddCustomItemDialog({this.preselectedShopId});

  @override
  ConsumerState<_AddCustomItemDialog> createState() =>
      _AddCustomItemDialogState();
}

class _AddCustomItemDialogState extends ConsumerState<_AddCustomItemDialog> {
  static const _uuid = Uuid();
  final _nameCtrl = TextEditingController();
  final _qtyCtrl = TextEditingController();
  String? _unit;
  String? _shopId;
  String? _linkedItemId;
  String? _linkedItemName;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _shopId = widget.preselectedShopId;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _qtyCtrl.dispose();
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
      final qty = double.tryParse(_qtyCtrl.text.replaceAll(',', '.'));
      await db.insertCustomShoppingItem(CustomShoppingItemsCompanion.insert(
        id: _uuid.v4(),
        name: _nameCtrl.text.trim(),
        quantity: Value(qty),
        unit: Value(_unit),
        shopId: Value(_shopId),
        itemId: Value(_linkedItemId),
      ));
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
          Text('Eintrag hinzufügen',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          TextField(
            controller: _nameCtrl,
            autofocus: true,
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
                  onChanged: (v) =>
                      setState(() => _unit = v.trim().isEmpty ? null : v.trim()),
                  decoration: const InputDecoration(labelText: 'Einheit'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Optional inventory item link
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              Icons.inventory_2_outlined,
              color: _linkedItemId != null
                  ? Theme.of(context).colorScheme.secondary
                  : null,
            ),
            title: Text(
              _linkedItemName ?? 'Artikel verlinken (optional)',
              style: _linkedItemId != null
                  ? TextStyle(
                      color: Theme.of(context).colorScheme.secondary,
                      fontWeight: FontWeight.w500)
                  : null,
            ),
            subtitle: _linkedItemId != null
                ? const Text('Beim Abhaken wird Einlagerung geöffnet',
                    style: TextStyle(fontSize: 11))
                : null,
            trailing: _linkedItemId != null
                ? IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => setState(
                        () { _linkedItemId = null; _linkedItemName = null; }),
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
                    : const Text('Hinzufügen'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
