import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeos/db/database.dart';

/// Full vault sync (Phase S, rev. 2): every user table travels, LWW on
/// updated_at tables, insert-or-ignore otherwise, item_states rebuilt from
/// inventory_entries. Round-trips through JSON like the real transport.
void main() {
  late AppDatabase a;
  late AppDatabase b;

  setUp(() {
    a = AppDatabase.forTesting(NativeDatabase.memory());
    b = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await a.close();
    await b.close();
  });

  Future<void> seedItem(AppDatabase db, String id,
      {String name = 'Item', double? qty}) async {
    await db.into(db.items).insert(ItemsCompanion.insert(
          id: id,
          name: name,
          categoryId: 'food',
          productType: const Value('ingredient'),
        ));
    if (qty != null) {
      await db.into(db.inventoryEntries).insert(
          InventoryEntriesCompanion.insert(
              id: 'entry_$id', itemId: id, quantity: qty, unit: 'Stück'));
    }
  }

  /// Simulates the wire: export from [from], JSON round-trip, import into [to].
  Future<int> syncOneWay(AppDatabase from, AppDatabase to) async {
    final dump = await from.exportForSync();
    final wire = jsonDecode(jsonEncode(dump)) as Map<String, dynamic>;
    return to.importFromSync(wire);
  }

  test('kompletter Round-Trip: Produkte + Bestand + Aufgaben + Rezepte',
      () async {
    await seedItem(a, 'i1', name: 'Milch', qty: 3);
    await seedItem(a, 'i2', name: 'Eier', qty: 10);
    await a.into(a.tasks).insert(
        TasksCompanion.insert(id: 't1', title: 'Einkaufen'));
    await a.into(a.recipes).insert(
        RecipesCompanion.insert(id: 'r1', name: 'Rührei'));

    await syncOneWay(a, b);

    expect((await b.select(b.items).get()).length, 2);
    expect((await b.select(b.inventoryEntries).get()).length, 2);
    expect((await b.select(b.tasks).get()).length, 1);
    expect((await b.select(b.recipes).get()).length, 1);
  });

  test('Bestand erscheint auf der Gegenseite (item_states neu berechnet)',
      () async {
    await seedItem(a, 'i1', name: 'Milch', qty: 5);

    await syncOneWay(a, b);

    // Kernbeschwerde des Nutzers: „92 Produkte, 0 Inventar".
    final states = await (b.select(b.itemStates)
          ..where((s) => s.itemId.equals('i1')))
        .get();
    expect(states, hasLength(1));
    expect(states.first.currentQuantity, 5);
  });

  test('LWW: neueres Item gewinnt, älteres wird verworfen', () async {
    await seedItem(a, 'i1', name: 'Original');
    await seedItem(b, 'i1', name: 'Lokal neuer');
    final local = await b.itemById('i1');
    await (b.update(b.items)..where((i) => i.id.equals('i1'))).write(
        ItemsCompanion(
            updatedAt: Value(local!.updatedAt.add(const Duration(days: 1)))));

    await syncOneWay(a, b); // a ist älter → darf b nicht überschreiben
    expect((await b.itemById('i1'))!.name, 'Lokal neuer');

    await (a.update(a.items)..where((i) => i.id.equals('i1'))).write(
        ItemsCompanion(
            name: const Value('Ferngewinner'),
            updatedAt: Value(DateTime.now().add(const Duration(days: 2)))));
    await syncOneWay(a, b);
    expect((await b.itemById('i1'))!.name, 'Ferngewinner');
  });

  test('insert-or-ignore: bestehende Zeile ohne updated_at bleibt lokal',
      () async {
    await a.into(a.locations).insert(
        LocationsCompanion.insert(id: 'loc1', name: 'Küche A'));
    await b.into(b.locations).insert(
        LocationsCompanion.insert(id: 'loc1', name: 'Küche B (lokal)'));

    await syncOneWay(a, b);
    final loc = await (b.select(b.locations)..where((l) => l.id.equals('loc1')))
        .getSingle();
    expect(loc.name, 'Küche B (lokal)'); // kein Datenverlust
  });

  test('app_settings + item_states sind vom Sync ausgeschlossen', () async {
    await a.setSetting('sync_client_url', 'http://geheim:7070');
    await syncOneWay(a, b);
    expect(await b.getSetting('sync_client_url'), isNull);
    expect(SyncDao.syncTableNames.contains('app_settings'), isFalse);
    expect(SyncDao.syncTableNames.contains('item_states'), isFalse);
  });

  test('rebuildItemStates repariert kaputte Projektion', () async {
    await seedItem(a, 'i1', qty: 7);
    await a.into(a.itemStates).insert(ItemStatesCompanion.insert(
        itemId: 'i1',
        inventoryEntryId: 'entry_i1',
        currentQuantity: 999,
        unit: 'Stück',
        state: 'fresh',
        lastEventAt: DateTime(2026)));

    await a.rebuildItemStates();

    final s =
        await (a.select(a.itemStates)..where((x) => x.itemId.equals('i1')))
            .getSingle();
    expect(s.currentQuantity, 7);
  });
}
