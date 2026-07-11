import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../db/database.dart';
import '../../providers/inventory_provider.dart';
import '../../providers/vault_provider.dart';

/// One scanned position in the current purchase session.
class _SessionRow {
  final String ean;
  Item? item; // null = unknown EAN
  double qty;
  String unit;
  DateTime? expiryDate;
  String? locationId;
  double? price;

  _SessionRow({
    required this.ean,
    this.item,
    this.unit = 'Stück',
    this.expiryDate,
    this.locationId,
  })  : qty = 1,
        price = null;
}

/// Kassenbon-Modus: scanner stays open, every scan adds/increments a session
/// row with smart defaults. One "Alle einbuchen" books everything at the end.
class PurchaseSessionScreen extends ConsumerStatefulWidget {
  const PurchaseSessionScreen({super.key});

  @override
  ConsumerState<PurchaseSessionScreen> createState() =>
      _PurchaseSessionScreenState();
}

class _PurchaseSessionScreenState
    extends ConsumerState<PurchaseSessionScreen> {
  final MobileScannerController _ctrl = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  final List<_SessionRow> _rows = [];
  final Map<String, DateTime> _lastScan = {}; // ean → time (re-scan cooldown)
  bool _saving = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    final ean = capture.barcodes
        .map((b) => b.rawValue)
        .firstWhere((v) => v != null && v.isNotEmpty, orElse: () => null);
    if (ean == null || _saving) return;

    // Cooldown: the same code within 2 s is the same physical scan.
    final now = DateTime.now();
    final last = _lastScan[ean];
    if (last != null && now.difference(last).inMilliseconds < 2000) return;
    _lastScan[ean] = now;

    HapticFeedback.mediumImpact();
    SystemSound.play(SystemSoundType.click);

    // Same article again → increment quantity.
    final existing = _rows.where((r) => r.ean == ean).firstOrNull;
    if (existing != null) {
      setState(() => existing.qty += 1);
      return;
    }

    final db = ref.read(databaseProvider);
    final item = await db?.itemByEan(ean);
    if (!mounted) return;
    if (item == null) {
      setState(() => _rows.add(_SessionRow(ean: ean)));
      return;
    }
    setState(() => _rows.add(_SessionRow(
          ean: ean,
          item: item,
          unit: item.purchaseUnit ?? item.stockUnit ?? 'Stück',
          expiryDate: (item.expiryType == 'daysAfterPurchase' &&
                  item.shelfLifeDays != null)
              ? DateTime.now().add(Duration(days: item.shelfLifeDays!))
              : null,
          locationId: item.defaultLocationId,
        )));
  }

  Future<void> _createUnknownItem(_SessionRow row) async {
    await context.push('/haushalt/item/new', extra: row.ean);
    // Back from the form: re-check whether the item exists now.
    final db = ref.read(databaseProvider);
    final item = await db?.itemByEan(row.ean);
    if (!mounted || item == null) return;
    setState(() {
      row.item = item;
      row.unit = item.purchaseUnit ?? item.stockUnit ?? 'Stück';
      row.locationId = item.defaultLocationId;
      if (item.expiryType == 'daysAfterPurchase' &&
          item.shelfLifeDays != null) {
        row.expiryDate =
            DateTime.now().add(Duration(days: item.shelfLifeDays!));
      }
    });
  }

  Future<void> _editRow(_SessionRow row) async {
    final priceCtrl = TextEditingController(
        text: row.price != null ? row.price!.toStringAsFixed(2) : '');
    var expiry = row.expiryDate;
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: Text(row.item?.name ?? row.ean,
              maxLines: 1, overflow: TextOverflow.ellipsis),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: priceCtrl,
                decoration: const InputDecoration(
                  labelText: 'Preis (€, gesamt)',
                  prefixIcon: Icon(Icons.euro),
                ),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
              ),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event_outlined),
                title: Text(expiry != null
                    ? 'MHD: ${DateFormat('dd.MM.yyyy').format(expiry!)}'
                    : 'Kein MHD'),
                trailing: expiry != null
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () => setDlg(() => expiry = null),
                      )
                    : null,
                onTap: () async {
                  final d = await showDatePicker(
                    context: ctx,
                    initialDate: expiry ?? DateTime.now(),
                    firstDate: DateTime.now()
                        .subtract(const Duration(days: 30)),
                    lastDate:
                        DateTime.now().add(const Duration(days: 3650)),
                  );
                  if (d != null) setDlg(() => expiry = d);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Abbrechen')),
            FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Übernehmen')),
          ],
        ),
      ),
    );
    if (saved == true && mounted) {
      setState(() {
        row.price =
            double.tryParse(priceCtrl.text.trim().replaceAll(',', '.'));
        row.expiryDate = expiry;
      });
    }
    priceCtrl.dispose();
  }

  Future<void> _bookAll() async {
    final bookable = _rows.where((r) => r.item != null).toList();
    if (bookable.isEmpty) return;
    setState(() => _saving = true);
    final ops = ref.read(inventoryOpsProvider.notifier);
    final db = ref.read(databaseProvider);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final entryIds = <String>[];
      for (final row in bookable) {
        entryIds.add(await ops.purchase(
          itemId: row.item!.id,
          quantity: row.qty,
          unit: row.unit,
          locationId: row.locationId,
          expiryDate: row.expiryDate,
          price: row.price,
        ));
      }
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        content: Text('${bookable.length} Positionen eingebucht'),
        duration: const Duration(seconds: 6),
        action: SnackBarAction(
          label: 'Rückgängig',
          onPressed: () => db?.undoPurchases(entryIds),
        ),
      ));
      Navigator.of(context).pop(bookable.length);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  static String _fmtQty(double v) =>
      v % 1 == 0 ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bookableCount = _rows.where((r) => r.item != null).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Einkauf erfassen'),
        actions: [
          ValueListenableBuilder(
            valueListenable: _ctrl,
            builder: (_, state, _) => IconButton(
              icon: Icon(state.torchState == TorchState.on
                  ? Icons.flash_on
                  : Icons.flash_off),
              tooltip: 'Licht',
              onPressed: () => _ctrl.toggleTorch(),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Scanner (stays open the whole session) ─────────────────────
          SizedBox(
            height: 220,
            child: Stack(
              fit: StackFit.expand,
              children: [
                MobileScanner(controller: _ctrl, onDetect: _onDetect),
                Center(
                  child: Container(
                    width: 200,
                    height: 120,
                    decoration: BoxDecoration(
                      border: Border.all(color: cs.primary, width: 2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // ── Session list ────────────────────────────────────────────────
          Expanded(
            child: _rows.isEmpty
                ? Center(
                    child: Text(
                      'Scanne die Artikel deines Einkaufs.\n'
                      'Gleicher Artikel mehrfach = Menge zählt hoch.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: cs.onSurfaceVariant),
                    ),
                  )
                : ListView.builder(
                    itemCount: _rows.length,
                    itemBuilder: (context, i) {
                      final row = _rows[_rows.length - 1 - i]; // newest first
                      if (row.item == null) {
                        return ListTile(
                          leading: Icon(Icons.help_outline, color: cs.error),
                          title: Text('Unbekannt: ${row.ean}'),
                          subtitle:
                              const Text('Artikel ist noch nicht angelegt'),
                          trailing: FilledButton.tonal(
                            onPressed: () => _createUnknownItem(row),
                            child: const Text('Anlegen'),
                          ),
                        );
                      }
                      return ListTile(
                        onTap: () => _editRow(row),
                        leading: IconButton(
                          icon: const Icon(Icons.remove_circle_outline),
                          onPressed: () => setState(() {
                            if (row.qty > 1) {
                              row.qty -= 1;
                            } else {
                              _rows.remove(row);
                            }
                          }),
                        ),
                        title: Text(row.item!.name,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text([
                          '${_fmtQty(row.qty)} ${row.unit}',
                          if (row.expiryDate != null)
                            'MHD ${DateFormat('dd.MM.').format(row.expiryDate!)}',
                          if (row.price != null)
                            '${row.price!.toStringAsFixed(2)} €',
                        ].join(' · ')),
                        trailing: IconButton(
                          icon: const Icon(Icons.add_circle_outline),
                          onPressed: () => setState(() => row.qty += 1),
                        ),
                      );
                    },
                  ),
          ),
          // ── Footer ──────────────────────────────────────────────────────
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  icon: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.done_all),
                  label: Text(bookableCount == 0
                      ? 'Noch nichts gescannt'
                      : '$bookableCount Positionen einbuchen'),
                  onPressed:
                      (bookableCount == 0 || _saving) ? null : _bookAll,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
