import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeos/core/item_categories.dart';
import 'package:lifeos/db/database.dart';
import 'package:lifeos/providers/inventory_provider.dart';
import 'package:lifeos/providers/vault_provider.dart';

/// Tests the purchase / consume / stocktake event flow. These exercise the
/// event-sourcing core: every operation must (a) write an immutable event,
/// (b) keep inventory_entries / item_states consistent, (c) handle the
/// "fully consumed" branch by deleting the entry and its state row.
void main() {
  late AppDatabase db;
  late ProviderContainer container;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      // Skip SharedPreferences plugin path used by the real provider.
      deviceIdProvider.overrideWith((ref) async => 'test-device'),
    ]);

    await db.insertItem(ItemsCompanion.insert(
      id: 'itm-1',
      name: 'Milk',
      categoryId: ItemCategory.food,
    ));
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  test('purchase creates inventory entry, event and state', () async {
    final ops = container.read(inventoryOpsProvider.notifier);

    await ops.purchase(itemId: 'itm-1', quantity: 1, unit: 'l');

    final entries = await db.select(db.inventoryEntries).get();
    final events = await db.select(db.itemEvents).get();
    final states = await db.select(db.itemStates).get();
    expect(entries, hasLength(1));
    expect(events, hasLength(1));
    expect(events.single.type, 'purchase');
    expect(events.single.deviceId, 'test-device');
    expect(states, hasLength(1));
    expect(states.single.currentQuantity, 1);
  });

  test('consume with positive remainder updates entry, keeps state', () async {
    final ops = container.read(inventoryOpsProvider.notifier);
    await ops.purchase(itemId: 'itm-1', quantity: 1, unit: 'l');
    final entryId = (await db.select(db.inventoryEntries).get()).single.id;

    await ops.consume(
      itemId: 'itm-1',
      inventoryEntryId: entryId,
      quantity: 0.4,
      unit: 'l',
      remainingQuantity: 0.6,
    );

    final entries = await db.select(db.inventoryEntries).get();
    expect(entries.single.quantity, 0.6);

    final events = await db.select(db.itemEvents).get();
    expect(events.where((e) => e.type == 'consumption'), hasLength(1));
  });

  test('consume that empties the entry deletes entry and state', () async {
    final ops = container.read(inventoryOpsProvider.notifier);
    await ops.purchase(itemId: 'itm-1', quantity: 1, unit: 'l');
    final entryId = (await db.select(db.inventoryEntries).get()).single.id;

    await ops.consume(
      itemId: 'itm-1',
      inventoryEntryId: entryId,
      quantity: 1,
      unit: 'l',
      remainingQuantity: 0,
    );

    expect(await db.select(db.inventoryEntries).get(), isEmpty);
    expect(await db.select(db.itemStates).get(), isEmpty);
    // The event log is immutable — consumption record must remain.
    final events = await db.select(db.itemEvents).get();
    expect(events.map((e) => e.type), containsAll(['purchase', 'consumption']));
  });

  test('stocktake to zero deletes entry but keeps event log', () async {
    final ops = container.read(inventoryOpsProvider.notifier);
    await ops.purchase(itemId: 'itm-1', quantity: 2, unit: 'l');
    final entryId = (await db.select(db.inventoryEntries).get()).single.id;

    await ops.stocktake(
      itemId: 'itm-1',
      inventoryEntryId: entryId,
      newQuantity: 0,
      unit: 'l',
    );

    expect(await db.select(db.inventoryEntries).get(), isEmpty);
    final events = await db.select(db.itemEvents).get();
    expect(events.where((e) => e.type == 'stocktake'), hasLength(1));
  });
}
