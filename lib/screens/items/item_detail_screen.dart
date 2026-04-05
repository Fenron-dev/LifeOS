import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../db/database.dart';
import '../../providers/items_provider.dart';
import '../../providers/inventory_provider.dart';
import '../../providers/events_provider.dart';
import '../../providers/locations_provider.dart';
import '../../providers/shops_provider.dart';

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

    return Scaffold(
      appBar: AppBar(
        title: Text(item.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Bearbeiten',
            onPressed: () => context.push('/inventory/item/${item.id}/edit'),
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
        padding: const EdgeInsets.all(16),
        children: [
          _ItemInfoCard(item: item),
          if (_hasNutrition(item)) ...[
            const SizedBox(height: 12),
            _NutritionCard(item: item),
          ],
          const SizedBox(height: 12),
          _StockSection(
            item: item,
            entriesAsync: entriesAsync,
            statesAsync: statesAsync,
          ),
          const SizedBox(height: 12),
          _EventsSection(itemId: item.id),
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

class _ItemInfoCard extends StatelessWidget {
  final Item item;
  const _ItemInfoCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
                color: theme.colorScheme.onSurfaceVariant,
              )),
            ],
            if (item.notes != null) ...[
              const SizedBox(height: 8),
              Text(item.notes!, style: theme.textTheme.bodySmall),
            ],
          ],
        ),
      ),
    );
  }
}

class _ProductTypeChip extends StatelessWidget {
  final String type;
  const _ProductTypeChip({required this.type});

  @override
  Widget build(BuildContext context) {
    final (label, icon, color) = switch (type) {
      'readyToEat' => ('Fertiggericht', Icons.lunch_dining, Colors.orange),
      'ingredient' => ('Zutat', Icons.spa, Colors.green),
      _ => ('Zuzubereiten', Icons.kitchen, Theme.of(context).colorScheme.primary),
    };
    return Chip(
      avatar: Icon(icon, size: 16, color: color),
      label: Text(label),
      visualDensity: VisualDensity.compact,
    );
  }
}

// ── Nutrition card ──────────────────────────────────────────────────────────

class _NutritionCard extends StatelessWidget {
  final Item item;
  const _NutritionCard({required this.item});

  String _fmt(double v) =>
      v == v.truncateToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row with Nutri-Score / NOVA badges
            Row(
              children: [
                Text('Nährwerte pro 100g',
                    style: theme.textTheme.titleSmall),
                const Spacer(),
                if (item.nutriscore != null)
                  _NutriscoreBadge(score: item.nutriscore!),
                if (item.novaGroup != null) ...[
                  const SizedBox(width: 6),
                  _NovaBadge(group: item.novaGroup!),
                ],
              ],
            ),
            const SizedBox(height: 12),
            // Macro table
            if (item.caloriesPer100g != null)
              _NutrRow(
                label: 'Energie',
                value: '${_fmt(item.caloriesPer100g!)} kcal',
                bold: true,
              ),
            if (item.proteinPer100g != null)
              _NutrRow(
                  label: 'Eiweiß', value: '${_fmt(item.proteinPer100g!)} g'),
            if (item.carbsPer100g != null)
              _NutrRow(
                  label: 'Kohlenhydrate',
                  value: '${_fmt(item.carbsPer100g!)} g'),
            if (item.sugarsPer100g != null)
              _NutrRow(
                  label: '  davon Zucker',
                  value: '${_fmt(item.sugarsPer100g!)} g',
                  indent: true),
            if (item.fatPer100g != null)
              _NutrRow(label: 'Fett', value: '${_fmt(item.fatPer100g!)} g'),
            if (item.saturatedFatPer100g != null)
              _NutrRow(
                  label: '  davon gesättigte Fettsäuren',
                  value: '${_fmt(item.saturatedFatPer100g!)} g',
                  indent: true),
            if (item.fiberPer100g != null)
              _NutrRow(
                  label: 'Ballaststoffe',
                  value: '${_fmt(item.fiberPer100g!)} g'),
            if (item.saltPer100g != null)
              _NutrRow(
                  label: 'Salz', value: '${_fmt(item.saltPer100g!)} g'),
            if (item.servingSizeG != null) ...[
              const SizedBox(height: 4),
              Text(
                'Portionsgröße: ${_fmt(item.servingSizeG!)} g',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
            ],
            if (item.ingredientsText != null) ...[
              const Divider(height: 20),
              Text('Zutaten', style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.outline,
              )),
              const SizedBox(height: 4),
              Text(item.ingredientsText!,
                  style: theme.textTheme.bodySmall),
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
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.remove_circle_outline),
              tooltip: 'Verbrauchen',
              onPressed: () => _showConsumeDialog(context, ref),
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

  void _showConsumeDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (_) => ConsumeDialog(entry: entry, item: item),
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

class _EventTile extends StatelessWidget {
  final ItemEvent event;
  const _EventTile({required this.event});

  @override
  Widget build(BuildContext context) {
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
      trailing: Text(
        DateFormat('dd.MM.yy HH:mm').format(event.createdAt),
        style: theme.textTheme.bodySmall,
      ),
    );
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
  String _unit = 'Stück';
  String? _locationId;
  String? _shopName;
  DateTime? _expiryDate;
  bool _saving = false;

  static const _units = [
    'Stück', 'g', 'kg', 'ml', 'l', 'Packung', 'Dose', 'Flasche', 'Tüte',
  ];

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
                  child: DropdownButtonFormField<String>(
                    // ignore: deprecated_member_use
                    value: _unit,
                    decoration: const InputDecoration(labelText: 'Einheit'),
                    items: _units
                        .map((u) => DropdownMenuItem(value: u, child: Text(u)))
                        .toList(),
                    onChanged: (v) => setState(() => _unit = v!),
                  ),
                ),
              ],
            ),
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
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _qtyCtrl = TextEditingController(text: _formatQty(widget.entry.quantity));
  }

  @override
  void dispose() {
    _qtyCtrl.dispose();
    super.dispose();
  }

  String _formatQty(double q) =>
      q == q.truncateToDouble() ? q.toInt().toString() : q.toString();

  Future<void> _consume() async {
    final qty = double.tryParse(_qtyCtrl.text.replaceAll(',', '.'));
    if (qty == null || qty <= 0) return;
    setState(() => _saving = true);
    try {
      final remaining = (widget.entry.quantity - qty).clamp(0, double.infinity);
      await ref.read(inventoryOpsProvider.notifier).consume(
        itemId: widget.item.id,
        inventoryEntryId: widget.entry.id,
        quantity: qty,
        unit: widget.entry.unit,
        remainingQuantity: remaining.toDouble(),
      );
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
      );
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Verbrauchen'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Bestand: ${_formatQty(widget.entry.quantity)} ${widget.entry.unit}'),
          const SizedBox(height: 16),
          TextField(
            controller: _qtyCtrl,
            decoration: InputDecoration(
              labelText: 'Verbrauchte Menge (${widget.entry.unit})',
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            autofocus: true,
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
          onPressed: _saving ? null : _consume,
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
