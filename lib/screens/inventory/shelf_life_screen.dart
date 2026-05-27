import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../db/database.dart';
import '../../providers/locations_provider.dart';
import '../../providers/vault_provider.dart';

final _shelfLifeProvider =
    StreamProvider<List<({InventoryEntry entry, Item item})>>((ref) {
  final db = ref.watch(databaseProvider);
  if (db == null) return const Stream.empty();
  return db.watchShelfLife();
});

DateTime? _effectiveExpiry(InventoryEntry entry, Item item) {
  DateTime? expiry = entry.expiryDate;
  if (entry.openedAt != null && item.daysAfterOpening != null) {
    final openedExpiry =
        entry.openedAt!.add(Duration(days: item.daysAfterOpening!));
    if (expiry == null || openedExpiry.isBefore(expiry)) {
      expiry = openedExpiry;
    }
  }
  return expiry;
}

class ShelfLifeScreen extends ConsumerStatefulWidget {
  const ShelfLifeScreen({super.key});

  @override
  ConsumerState<ShelfLifeScreen> createState() => _ShelfLifeScreenState();
}

class _ShelfLifeScreenState extends ConsumerState<ShelfLifeScreen> {
  final Set<String> _selected = {};

  bool get _selectMode => _selected.isNotEmpty;

  void _toggleSelect(String id) {
    setState(() {
      if (_selected.contains(id)) {
        _selected.remove(id);
      } else {
        _selected.add(id);
      }
    });
  }

  void _clearSelection() => setState(() => _selected.clear());

  Future<void> _batchSetExpiry(
      BuildContext context, List<({InventoryEntry entry, Item item})> rows) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
      helpText: 'MHD für ${_selected.length} Einträge',
      locale: const Locale('de', 'DE'),
    );
    if (picked == null || !context.mounted) return;
    final db = ref.read(databaseProvider);
    if (db == null) return;
    await db.batchSetExpiryDate(_selected.toList(), picked);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                'MHD auf ${DateFormat.yMMMd('de_DE').format(picked)} gesetzt')),
      );
      _clearSelection();
    }
  }

  Future<void> _batchChangeState(
      BuildContext context, List<({InventoryEntry entry, Item item})> rows) async {
    final states = const ['open', 'closed', 'frozen', 'thawed'];
    final labels = const {
      'open': 'Geöffnet',
      'closed': 'Geschlossen',
      'frozen': 'Eingefroren',
      'thawed': 'Aufgetaut',
    };
    final picked = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                'Zustand für ${_selected.length} Einträge',
                style: Theme.of(ctx).textTheme.titleSmall,
              ),
            ),
            for (final s in states)
              ListTile(
                title: Text(labels[s]!),
                onTap: () => Navigator.of(ctx).pop(s),
              ),
          ],
        ),
      ),
    );
    if (picked == null || !context.mounted) return;
    final db = ref.read(databaseProvider);
    if (db == null) return;
    for (final id in _selected.toList()) {
      final row = rows.where((r) => r.entry.id == id).firstOrNull;
      if (row == null) continue;
      await db.updateEntryState(
        id,
        row.entry.itemId,
        fromState: row.entry.state,
        newState: picked,
      );
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Zustand auf ${labels[picked]} gesetzt')),
      );
      _clearSelection();
    }
  }

  Future<void> _batchDelete(BuildContext context) async {
    final count = _selected.length;
    final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Einträge löschen?'),
            content: Text('$count ${count == 1 ? 'Eintrag' : 'Einträge'} '
                'werden unwiderruflich gelöscht.'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('Abbrechen')),
              FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor: Theme.of(ctx).colorScheme.error),
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Löschen'),
              ),
            ],
          ),
        ) ??
        false;
    if (!ok || !context.mounted) return;
    final db = ref.read(databaseProvider);
    if (db == null) return;
    await db.batchDeleteEntries(_selected.toList());
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text('$count ${count == 1 ? 'Eintrag' : 'Einträge'} gelöscht')),
      );
      _clearSelection();
    }
  }

  @override
  Widget build(BuildContext context) {
    final listAsync = ref.watch(_shelfLifeProvider);
    final locationsAsync = ref.watch(allLocationsProvider);

    return Scaffold(
      appBar: AppBar(
        title: _selectMode
            ? Text('${_selected.length} ausgewählt')
            : const Text('Haltbarkeit'),
        leading: _selectMode
            ? IconButton(
                icon: const Icon(Icons.close),
                tooltip: 'Auswahl aufheben',
                onPressed: _clearSelection,
              )
            : null,
        actions: _selectMode
            ? []
            : [
                IconButton(
                  icon: const Icon(Icons.checklist_outlined),
                  tooltip: 'Mehrere auswählen',
                  onPressed: () {}, // tap any tile to enter select mode
                ),
              ],
      ),
      body: listAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Fehler: $e')),
        data: (rows) {
          final relevant = rows
              .where((r) =>
                  r.entry.expiryDate != null || r.item.daysAfterOpening != null)
              .toList();

          if (relevant.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.inventory_2_outlined, size: 64),
                    SizedBox(height: 16),
                    Text(
                      'Keine Haltbarkeitsdaten vorhanden.',
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Füge Ablaufdaten beim Einlagern hinzu oder '
                      'hinterlege "Haltbar nach Öffnen" beim Artikel.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              ),
            );
          }

          relevant.sort((a, b) {
            final ea = _effectiveExpiry(a.entry, a.item);
            final eb = _effectiveExpiry(b.entry, b.item);
            if (ea == null && eb == null) return 0;
            if (ea == null) return 1;
            if (eb == null) return -1;
            return ea.compareTo(eb);
          });

          final locationMap = locationsAsync.valueOrNull != null
              ? {for (final l in locationsAsync.value!) l.id: l.name}
              : <String, String>{};

          final countPerItem = <String, int>{};
          final indexPerEntry = <String, int>{};
          for (final row in relevant) {
            final idx = (countPerItem[row.item.id] ?? 0) + 1;
            countPerItem[row.item.id] = idx;
            indexPerEntry[row.entry.id] = idx;
          }

          return Column(
            children: [
              Expanded(
                child: ListView.builder(
                  padding: EdgeInsets.fromLTRB(
                      8, 8, 8, _selectMode ? 80 : 8),
                  itemCount: relevant.length,
                  itemBuilder: (context, i) {
                    final row = relevant[i];
                    final totalForItem = countPerItem[row.item.id] ?? 1;
                    final entryIndex = indexPerEntry[row.entry.id] ?? 1;
                    final isSelected = _selected.contains(row.entry.id);
                    return _ShelfLifeTile(
                      entry: row.entry,
                      item: row.item,
                      locationName: row.entry.locationId != null
                          ? locationMap[row.entry.locationId]
                          : null,
                      entryLabel: totalForItem > 1
                          ? 'Packung $entryIndex von $totalForItem'
                          : null,
                      selectMode: _selectMode,
                      isSelected: isSelected,
                      onSelect: () => _toggleSelect(row.entry.id),
                      onLongPress: () => _toggleSelect(row.entry.id),
                    );
                  },
                ),
              ),
              if (_selectMode)
                _BatchActionBar(
                  selectedCount: _selected.length,
                  onSetExpiry: () => _batchSetExpiry(context, relevant),
                  onChangeState: () => _batchChangeState(context, relevant),
                  onDelete: () => _batchDelete(context),
                  onSelectAll: () => setState(() {
                    _selected
                      ..clear()
                      ..addAll(relevant.map((r) => r.entry.id));
                  }),
                ),
            ],
          );
        },
      ),
    );
  }
}

// ── Batch action bar ─────────────────────────────────────────────────────────

class _BatchActionBar extends StatelessWidget {
  final int selectedCount;
  final VoidCallback onSetExpiry;
  final VoidCallback onChangeState;
  final VoidCallback onDelete;
  final VoidCallback onSelectAll;

  const _BatchActionBar({
    required this.selectedCount,
    required this.onSetExpiry,
    required this.onChangeState,
    required this.onDelete,
    required this.onSelectAll,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        border: Border(top: BorderSide(color: cs.outlineVariant)),
      ),
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
      child: Row(
        children: [
          TextButton.icon(
            onPressed: onSelectAll,
            icon: const Icon(Icons.select_all, size: 16),
            label: const Text('Alle'),
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
          ),
          const Spacer(),
          IconButton.filledTonal(
            icon: const Icon(Icons.calendar_month_outlined),
            tooltip: 'MHD ändern',
            onPressed: onSetExpiry,
          ),
          const SizedBox(width: 8),
          IconButton.filledTonal(
            icon: const Icon(Icons.swap_horiz_outlined),
            tooltip: 'Zustand ändern',
            onPressed: onChangeState,
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Löschen',
            style: IconButton.styleFrom(
              backgroundColor: cs.error,
              foregroundColor: cs.onError,
            ),
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}

// ── Shelf-life tile ──────────────────────────────────────────────────────────

class _ShelfLifeTile extends ConsumerWidget {
  final InventoryEntry entry;
  final Item item;
  final String? locationName;
  final String? entryLabel;
  final bool selectMode;
  final bool isSelected;
  final VoidCallback onSelect;
  final VoidCallback onLongPress;

  const _ShelfLifeTile({
    required this.entry,
    required this.item,
    this.locationName,
    this.entryLabel,
    required this.selectMode,
    required this.isSelected,
    required this.onSelect,
    required this.onLongPress,
  });

  Color _urgencyColor(BuildContext context, DateTime? expiry) {
    if (expiry == null) return Colors.transparent;
    final cs = Theme.of(context).colorScheme;
    final diff = expiry.difference(DateTime.now()).inDays;
    if (diff < 0) return cs.error;
    if (diff == 0) return cs.error;
    if (diff <= 3) return Colors.orange;
    if (diff <= 7) return Colors.amber;
    return cs.primary;
  }

  String _expiryLabel(DateTime? expiry) {
    if (expiry == null) return '';
    final now = DateTime.now();
    final diff =
        expiry.difference(DateTime(now.year, now.month, now.day)).inDays;
    final dateStr = DateFormat.yMMMd('de_DE').format(expiry);
    if (diff < 0) return '$dateStr (abgelaufen seit ${-diff} T.)';
    if (diff == 0) return '$dateStr (heute)';
    if (diff == 1) return '$dateStr (morgen)';
    return '$dateStr (noch $diff T.)';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final effectiveExpiry = _effectiveExpiry(entry, item);
    final urgencyColor = _urgencyColor(context, effectiveExpiry);
    final isExpired = effectiveExpiry != null &&
        effectiveExpiry.isBefore(DateTime.now());
    final isOpened = entry.openedAt != null;

    final qty = entry.quantity % 1 == 0
        ? entry.quantity.toStringAsFixed(0)
        : entry.quantity.toStringAsFixed(1);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      color: isSelected ? cs.primaryContainer.withValues(alpha: 0.5) : null,
      child: ListTile(
        onTap: selectMode
            ? onSelect
            : () => context.push('/haushalt/item/${item.id}'),
        onLongPress: onLongPress,
        leading: selectMode
            ? Checkbox(
                value: isSelected,
                onChanged: (_) => onSelect(),
              )
            : Container(
                width: 4,
                height: 48,
                decoration: BoxDecoration(
                  color: urgencyColor,
                  borderRadius: const BorderRadius.all(Radius.circular(2)),
                ),
              ),
        title: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    style: TextStyle(
                      decoration:
                          isExpired ? TextDecoration.lineThrough : null,
                      color: isExpired ? cs.onSurfaceVariant : null,
                    ),
                  ),
                  if (entryLabel != null)
                    Text(
                      entryLabel!,
                      style:
                          TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                    ),
                ],
              ),
            ),
            if (isOpened)
              Chip(
                label: Text(
                  'Geöffnet',
                  style: TextStyle(
                      fontSize: 11, color: cs.onSecondaryContainer),
                ),
                backgroundColor: cs.secondaryContainer,
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$qty ${entry.unit}'
              '${locationName != null ? ' · $locationName' : ''}',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
            ),
            if (entry.expiryDate != null && !isOpened)
              Text(
                _expiryLabel(entry.expiryDate),
                style: TextStyle(
                  color: urgencyColor == Colors.transparent
                      ? cs.onSurfaceVariant
                      : urgencyColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            if (isOpened) ...[
              if (entry.openedAt != null)
                Text(
                  'Geöffnet: ${DateFormat.yMMMd('de_DE').format(entry.openedAt!)}',
                  style: TextStyle(
                      color: cs.onSurfaceVariant, fontSize: 12),
                ),
              if (effectiveExpiry != null)
                Text(
                  _expiryLabel(effectiveExpiry),
                  style: TextStyle(
                    color: urgencyColor == Colors.transparent
                        ? cs.onSurfaceVariant
                        : urgencyColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
            ],
          ],
        ),
        isThreeLine: true,
        trailing: selectMode
            ? null
            : IconButton(
                icon: Icon(
                  isOpened ? Icons.lock_open : Icons.lock_outline,
                  color: isOpened ? cs.primary : cs.onSurfaceVariant,
                ),
                tooltip: isOpened
                    ? 'Als ungeöffnet markieren'
                    : 'Als geöffnet markieren',
                onPressed: () async {
                  final db = ref.read(databaseProvider);
                  if (db == null) return;
                  if (isOpened) {
                    await db.setInventoryOpenedAt(entry.id, null);
                  } else {
                    await db.openEntry(entry.id, item.id);
                  }
                },
              ),
      ),
    );
  }
}
