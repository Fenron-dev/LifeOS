import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeos/db/database.dart';

/// Sync foundation (Phase S): append-only event insert, projection rebuild
/// and applying foreign events to the inventory.
void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> insertItem(String id) => db.into(db.items).insert(
        ItemsCompanion.insert(
          id: id,
          name: 'Item $id',
          categoryId: 'food',
          productType: const Value('ingredient'),
        ),
      );

  ItemEventsCompanion purchaseEvent({
    required String id,
    required String itemId,
    required String entryId,
    double qty = 5,
    DateTime? at,
  }) =>
      ItemEventsCompanion.insert(
        id: id,
        type: 'purchase',
        itemId: itemId,
        inventoryEntryId: Value(entryId),
        quantity: Value(qty),
        unit: const Value('Stück'),
        deviceId: 'remote-device',
        createdAt: Value(at ?? DateTime(2026, 7, 1)),
      );

  test('insertSyncedEvents ignoriert vorhandene IDs (append-only, S5)',
      () async {
    await insertItem('i1');
    final e = purchaseEvent(id: 'e1', itemId: 'i1', entryId: 'entry1');
    expect(await db.ingestForeignEvents([e]), 1);

    // Second insert with same id but different quantity must NOT overwrite.
    final tampered = purchaseEvent(
        id: 'e1', itemId: 'i1', entryId: 'entry1', qty: 999);
    expect(await db.ingestForeignEvents([tampered]), 0);
    final stored = await (db.select(db.itemEvents)
          ..where((x) => x.id.equals('e1')))
        .getSingle();
    expect(stored.quantity, 5);
  });

  test('markEventsSynced setzt syncStatus + syncedAt (F1)', () async {
    await insertItem('i1');
    await db.ingestForeignEvents(
        [purchaseEvent(id: 'e1', itemId: 'i1', entryId: 'n1')]);
    await db.markEventsSynced(['e1']);
    final stored = await (db.select(db.itemEvents)
          ..where((x) => x.id.equals('e1')))
        .getSingle();
    expect(stored.syncStatus, 'synced');
    expect(stored.syncedAt, isNotNull);
  });

  test('applyForeignEvents materialisiert purchase + consumption (F2)',
      () async {
    await insertItem('i1');
    final purchase = purchaseEvent(
        id: 'e1', itemId: 'i1', entryId: 'entry1', qty: 5,
        at: DateTime(2026, 7, 1));
    final consumption = ItemEventsCompanion.insert(
      id: 'e2',
      type: 'consumption',
      itemId: 'i1',
      inventoryEntryId: const Value('entry1'),
      quantity: const Value(2),
      unit: const Value('Stück'),
      deviceId: 'remote-device',
      createdAt: Value(DateTime(2026, 7, 2)),
    );

    expect(await db.ingestForeignEvents([purchase, consumption]), 2);

    final entry = await (db.select(db.inventoryEntries)
          ..where((x) => x.id.equals('entry1')))
        .getSingle();
    expect(entry.quantity, 3); // 5 gekauft − 2 verbraucht

    final states = await (db.select(db.itemStates)
          ..where((s) => s.itemId.equals('i1')))
        .get();
    expect(states, hasLength(1));
    expect(states.first.currentQuantity, 3);
  });

  test('applyForeignEvents löscht Entry+State bei Verbrauch auf 0', () async {
    await insertItem('i1');
    await db.ingestForeignEvents([
      purchaseEvent(id: 'e1', itemId: 'i1', entryId: 'entry1', qty: 2,
          at: DateTime(2026, 7, 1)),
      ItemEventsCompanion.insert(
        id: 'e2',
        type: 'consumption',
        itemId: 'i1',
        inventoryEntryId: const Value('entry1'),
        quantity: const Value(2),
        deviceId: 'remote-device',
        createdAt: Value(DateTime(2026, 7, 2)),
      ),
    ]);

    expect(
        await (db.select(db.inventoryEntries)
              ..where((x) => x.id.equals('entry1')))
            .getSingleOrNull(),
        isNull);
    expect(
        await (db.select(db.itemStates)
              ..where((s) => s.itemId.equals('i1')))
            .get(),
        isEmpty);
  });

  test('applyForeignEvents überspringt Events für unbekannte Items', () async {
    // Must not throw and must not create anything (item unknown → dropped).
    expect(
        await db.ingestForeignEvents(
            [purchaseEvent(id: 'e1', itemId: 'ghost', entryId: 'entry1')]),
        0);
    expect(
        await (db.select(db.inventoryEntries)
              ..where((x) => x.id.equals('entry1')))
            .getSingleOrNull(),
        isNull);
  });

  test('rebuildItemStates stellt Projektion aus Entries wieder her (F4)',
      () async {
    await insertItem('i1');
    await db.into(db.inventoryEntries).insert(
        InventoryEntriesCompanion.insert(
            id: 'entry1', itemId: 'i1', quantity: 7, unit: 'g'));
    // Kaputte Projektion: falsche Menge + Waisen-State.
    await db.into(db.itemStates).insert(ItemStatesCompanion.insert(
        itemId: 'i1',
        inventoryEntryId: 'entry1',
        currentQuantity: 999,
        unit: 'g',
        state: 'fresh',
        lastEventAt: DateTime(2026)));

    await db.rebuildItemStates();

    final states = await (db.select(db.itemStates)
          ..where((s) => s.itemId.equals('i1')))
        .get();
    expect(states, hasLength(1));
    expect(states.first.currentQuantity, 7);
  });

  test('applyMasterData: LWW für Items, insert-or-ignore für Shops',
      () async {
    await insertItem('i1');
    final local = await db.itemById('i1');
    final newer = local!
        .copyWith(
          name: 'Umbenannt vom Peer',
          updatedAt: local.updatedAt.add(const Duration(days: 1)),
        )
        .toJson();
    final older = local
        .copyWith(
          name: 'Veraltet',
          updatedAt: local.updatedAt.subtract(const Duration(days: 1)),
        )
        .toJson();

    await db.applyMasterData({'items': [older]});
    expect((await db.itemById('i1'))!.name, 'Item i1'); // LWW: lokal gewinnt

    await db.applyMasterData({'items': [newer]});
    expect((await db.itemById('i1'))!.name, 'Umbenannt vom Peer');
  });
}
