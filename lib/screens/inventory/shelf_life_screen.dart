import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

/// Effective expiry for an inventory entry:
/// min(expiryDate, openedAt + daysAfterOpening) — whichever is sooner.
/// Returns null when neither applies.
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

class ShelfLifeScreen extends ConsumerWidget {
  const ShelfLifeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listAsync = ref.watch(_shelfLifeProvider);
    final locationsAsync = ref.watch(allLocationsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Haltbarkeit')),
      body: listAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Fehler: $e')),
        data: (rows) {
          // Only show entries that have expiry data or can become expiry-tracked
          // via opened state. Filter out entries with no expiry and no
          // daysAfterOpening defined.
          final relevant = rows.where((r) =>
              r.entry.expiryDate != null ||
              r.item.daysAfterOpening != null).toList();

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

          // Sort: entries with effective expiry first (soonest first),
          // then entries without effective expiry at bottom.
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

          // Count how many entries exist per item so we can number them
          final countPerItem = <String, int>{};
          final indexPerEntry = <String, int>{};
          for (final row in relevant) {
            final idx = (countPerItem[row.item.id] ?? 0) + 1;
            countPerItem[row.item.id] = idx;
            indexPerEntry[row.entry.id] = idx;
          }

          return ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: relevant.length,
            itemBuilder: (context, i) {
              final row = relevant[i];
              final totalForItem = countPerItem[row.item.id] ?? 1;
              final entryIndex = indexPerEntry[row.entry.id] ?? 1;
              return _ShelfLifeTile(
                entry: row.entry,
                item: row.item,
                locationName: row.entry.locationId != null
                    ? locationMap[row.entry.locationId]
                    : null,
                // Show "Packung 2 von 3" only when multiple entries exist
                entryLabel: totalForItem > 1
                    ? 'Packung $entryIndex von $totalForItem'
                    : null,
              );
            },
          );
        },
      ),
    );
  }
}

class _ShelfLifeTile extends ConsumerWidget {
  final InventoryEntry entry;
  final Item item;
  final String? locationName;
  final String? entryLabel; // e.g. "Packung 2 von 3"

  const _ShelfLifeTile({
    required this.entry,
    required this.item,
    this.locationName,
    this.entryLabel,
  });

  Color _urgencyColor(BuildContext context, DateTime? expiry) {
    if (expiry == null) return Colors.transparent;
    final cs = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final diff = expiry.difference(now).inDays;
    if (diff < 0) return cs.error;
    if (diff == 0) return cs.error;
    if (diff <= 3) return Colors.orange;
    if (diff <= 7) return Colors.amber;
    return cs.primary;
  }

  String _expiryLabel(DateTime? expiry) {
    if (expiry == null) return '';
    final now = DateTime.now();
    final diff = expiry.difference(DateTime(now.year, now.month, now.day)).inDays;
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
      child: ListTile(
        leading: Container(
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
                      style: TextStyle(
                          fontSize: 11, color: cs.onSurfaceVariant),
                    ),
                ],
              ),
            ),
            if (isOpened)
              Chip(
                label: Text(
                  'Geöffnet',
                  style: TextStyle(fontSize: 11, color: cs.onSecondaryContainer),
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
                  style:
                      TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
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
        trailing: IconButton(
          icon: Icon(
            isOpened ? Icons.lock_open : Icons.lock_outline,
            color: isOpened ? cs.primary : cs.onSurfaceVariant,
          ),
          tooltip: isOpened ? 'Als ungeöffnet markieren' : 'Als geöffnet markieren',
          onPressed: () async {
            final db = ref.read(databaseProvider);
            if (db == null) return;
            if (isOpened) {
              await db.setInventoryOpenedAt(entry.id, null);
            } else {
              await db.setInventoryOpenedAt(entry.id, DateTime.now());
            }
          },
        ),
      ),
    );
  }
}
