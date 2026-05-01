import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeos/core/item_categories.dart';
import 'package:lifeos/db/database.dart';
import 'package:lifeos/providers/items_provider.dart';
import 'package:lifeos/providers/vault_provider.dart';

/// CRUD tests for ItemsNotifier against a fresh in-memory Drift database.
/// We override databaseProvider with a memory-backed AppDatabase so the
/// notifier exercises real Drift code paths without touching the filesystem.
void main() {
  late AppDatabase db;
  late ProviderContainer container;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
    ]);
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  test('createItem persists item and returns its id', () async {
    final notifier = container.read(itemsNotifierProvider.notifier);

    final id = await notifier.createItem(
      name: 'Milch',
      categoryId: ItemCategory.food,
      brand: 'Bio-Hof',
      caloriesPer100g: 64,
    );

    expect(id, isNotEmpty);
    final item = await db.itemById(id);
    expect(item, isNotNull);
    expect(item!.name, 'Milch');
    expect(item.brand, 'Bio-Hof');
    expect(item.caloriesPer100g, 64);
  });

  test('updateItem persists field changes', () async {
    final notifier = container.read(itemsNotifierProvider.notifier);
    final id = await notifier.createItem(
      name: 'Apfel',
      categoryId: ItemCategory.food,
    );
    final original = (await db.itemById(id))!;

    await notifier.updateItem(original.copyWith(name: 'Apfel rot'));
    final updated = (await db.itemById(id))!;
    expect(updated.name, 'Apfel rot');
  });

  test('deleteItem removes the item', () async {
    final notifier = container.read(itemsNotifierProvider.notifier);
    final id = await notifier.createItem(
      name: 'Brot',
      categoryId: ItemCategory.food,
    );
    expect(await db.itemById(id), isNotNull);

    await notifier.deleteItem(id);
    expect(await db.itemById(id), isNull);
  });

  test('createItem stores nutrition fields exactly as provided', () async {
    final notifier = container.read(itemsNotifierProvider.notifier);
    final id = await notifier.createItem(
      name: 'Haferflocken',
      categoryId: ItemCategory.food,
      caloriesPer100g: 380,
      proteinPer100g: 13.5,
      carbsPer100g: 58.7,
      fatPer100g: 7.0,
      fiberPer100g: 10.0,
    );

    final item = (await db.itemById(id))!;
    expect(item.caloriesPer100g, 380);
    expect(item.proteinPer100g, 13.5);
    expect(item.carbsPer100g, 58.7);
    expect(item.fatPer100g, 7.0);
    expect(item.fiberPer100g, 10.0);
  });
}
