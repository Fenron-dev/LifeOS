import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../db/database.dart';
import 'vault_provider.dart';

// ---------------------------------------------------------------------------
// InventoryEntries for a specific item
// ---------------------------------------------------------------------------

final inventoryForItemProvider =
    StreamProvider.family<List<InventoryEntry>, String>((ref, itemId) {
  final db = ref.watch(databaseProvider);
  if (db == null) return const Stream.empty();
  return db.watchInventoryForItem(itemId);
});

// ---------------------------------------------------------------------------
// ItemStates for a specific item
// ---------------------------------------------------------------------------

final itemStatesForItemProvider =
    StreamProvider.family<List<ItemState>, String>((ref, itemId) {
  final db = ref.watch(databaseProvider);
  if (db == null) return const Stream.empty();
  return db.watchStatesForItem(itemId);
});

// ---------------------------------------------------------------------------
// Inventory operations: purchase, consume, stocktake
// ---------------------------------------------------------------------------

final inventoryOpsProvider =
    AsyncNotifierProvider<InventoryOpsNotifier, void>(InventoryOpsNotifier.new);

class InventoryOpsNotifier extends AsyncNotifier<void> {
  static const _uuid = Uuid();

  @override
  Future<void> build() async {}

  AppDatabase get _db => ref.read(databaseProvider)!;

  Future<String> _deviceId() async {
    final id = await ref.read(deviceIdProvider.future);
    return id;
  }

  /// Record a purchase: create/update InventoryEntry + insert event + upsert state.
  Future<void> purchase({
    required String itemId,
    required double quantity,
    required String unit,
    String? locationId,
    DateTime? expiryDate,
    double? price,
    String? store,
    String? notes,
  }) async {
    final entryId = _uuid.v4();
    final now = DateTime.now();
    final deviceId = await _deviceId();

    // Insert inventory entry
    await _db.insertInventoryEntry(InventoryEntriesCompanion.insert(
      id: entryId,
      itemId: itemId,
      locationId: Value(locationId),
      quantity: quantity,
      unit: unit,
      expiryDate: Value(expiryDate),
    ));

    // Insert event
    await _db.insertItemEvent(ItemEventsCompanion.insert(
      id: _uuid.v4(),
      type: 'purchase',
      itemId: itemId,
      inventoryEntryId: Value(entryId),
      quantity: Value(quantity),
      unit: Value(unit),
      price: Value(price),
      store: Value(store),
      deviceId: deviceId,
      notes: Value(notes),
    ));

    // Upsert state
    await _db.upsertItemState(ItemStatesCompanion.insert(
      itemId: itemId,
      inventoryEntryId: entryId,
      currentQuantity: quantity,
      unit: unit,
      locationId: Value(locationId),
      state: 'fresh',
      expiryDate: Value(expiryDate),
      lastEventAt: now,
    ));
  }

  /// Record consumption: update InventoryEntry quantity + insert event + upsert/delete state.
  Future<void> consume({
    required String itemId,
    required String inventoryEntryId,
    required double quantity,
    required String unit,
    required double remainingQuantity,
    String? notes,
  }) async {
    final now = DateTime.now();
    final deviceId = await _deviceId();

    // Insert event
    await _db.insertItemEvent(ItemEventsCompanion.insert(
      id: _uuid.v4(),
      type: 'consumption',
      itemId: itemId,
      inventoryEntryId: Value(inventoryEntryId),
      quantity: Value(quantity),
      unit: Value(unit),
      deviceId: deviceId,
      notes: Value(notes),
    ));

    if (remainingQuantity <= 0) {
      // Delete inventory entry and state
      await _db.deleteInventoryEntry(inventoryEntryId);
      await _db.deleteItemState(inventoryEntryId);
    } else {
      // Update entry + state
      await _db.updateInventoryEntry(InventoryEntriesCompanion(
        id: Value(inventoryEntryId),
        quantity: Value(remainingQuantity),
        updatedAt: Value(now),
      ));
      await _db.upsertItemState(ItemStatesCompanion(
        inventoryEntryId: Value(inventoryEntryId),
        currentQuantity: Value(remainingQuantity),
        lastEventAt: Value(now),
        updatedAt: Value(now),
      ));
    }
  }

  /// Record a stocktake (manual quantity correction).
  Future<void> stocktake({
    required String itemId,
    required String inventoryEntryId,
    required double newQuantity,
    required String unit,
    String? notes,
  }) async {
    final now = DateTime.now();
    final deviceId = await _deviceId();

    await _db.insertItemEvent(ItemEventsCompanion.insert(
      id: _uuid.v4(),
      type: 'stocktake',
      itemId: itemId,
      inventoryEntryId: Value(inventoryEntryId),
      quantity: Value(newQuantity),
      unit: Value(unit),
      deviceId: deviceId,
      notes: Value(notes),
    ));

    if (newQuantity <= 0) {
      await _db.deleteInventoryEntry(inventoryEntryId);
      await _db.deleteItemState(inventoryEntryId);
    } else {
      await _db.updateInventoryEntry(InventoryEntriesCompanion(
        id: Value(inventoryEntryId),
        quantity: Value(newQuantity),
        updatedAt: Value(now),
      ));
      await _db.upsertItemState(ItemStatesCompanion(
        inventoryEntryId: Value(inventoryEntryId),
        currentQuantity: Value(newQuantity),
        lastEventAt: Value(now),
        updatedAt: Value(now),
      ));
    }
  }
}
