import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeos/core/item_categories.dart';
import 'package:lifeos/db/database.dart';

/// Smoke tests that exercise the end-to-end schema on a fresh in-memory DB.
/// These catch:
///   - invalid column types or typos in table definitions
///   - broken `CREATE INDEX` statements (`_createIndexes`)
///   - missing FK targets
///   - seed helpers that throw on an empty database
///   - migration-order bugs that crash `createAll` via the onCreate hook
///
/// Equivalent to drift's `verifySelf` for the current schema version — the
/// test that would have caught Bug #1 on a clean checkout.
void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  test('fresh database opens and exposes schemaVersion 10', () async {
    // Triggers onCreate → createAll + seeds + _createIndexes
    await db.customSelect('SELECT 1').get();
    expect(db.schemaVersion, 10);
  });

  test('every declared table is reachable', () async {
    // If any table was dropped from @DriftDatabase but still referenced
    // internally (or vice versa), createAll would have failed above.
    // Touch a representative set here so future schema changes keep the
    // smoke test honest.
    await db.select(db.items).get();
    await db.select(db.inventoryEntries).get();
    await db.select(db.itemEvents).get();
    await db.select(db.itemStates).get();
    await db.select(db.recipes).get();
    await db.select(db.recipeIngredients).get();
    await db.select(db.recipeSteps).get();
    await db.select(db.recipeTags).get();
    await db.select(db.tagDefinitions).get();
    await db.select(db.itemTags).get();
    await db.select(db.locations).get();
    await db.select(db.units).get();
    await db.select(db.unitConversions).get();
    await db.select(db.mealTypes).get();
    await db.select(db.bodyWeightLogs).get();
  });

  test('default units and meal types are seeded on create', () async {
    final units = await db.select(db.units).get();
    final mealTypes = await db.select(db.mealTypes).get();
    expect(units, isNotEmpty, reason: 'onCreate must seed default units');
    expect(mealTypes, isNotEmpty, reason: 'onCreate must seed meal types');
  });

  test('hot-path indexes exist', () async {
    final rows = await db.customSelect(
      "SELECT name FROM sqlite_master WHERE type='index' AND name LIKE 'idx_%'",
    ).get();
    final names = rows.map((r) => r.read<String>('name')).toSet();
    // A representative subset of indexes created by _createIndexes — if any
    // of these disappear, either the helper or the onCreate wiring is broken.
    expect(names, containsAll(<String>{
      'idx_items_ean',
      'idx_items_category',
      'idx_inv_item',
      'idx_inv_expiry',
      'idx_events_item',
      'idx_states_item',
      'idx_tags_item',
    }));
  });

  test('FK cascade deletes inventory entries when item is deleted', () async {
    await db.into(db.items).insert(ItemsCompanion.insert(
          id: 'itm_1',
          name: 'Milk',
          categoryId: ItemCategory.food,
        ));
    await db.into(db.inventoryEntries).insert(
          InventoryEntriesCompanion.insert(
            id: 'inv_1',
            itemId: 'itm_1',
            quantity: 1,
            unit: 'l',
          ),
        );
    expect(
      (await db.select(db.inventoryEntries).get()).length,
      1,
    );
    await (db.delete(db.items)..where((i) => i.id.equals('itm_1'))).go();
    expect(
      (await db.select(db.inventoryEntries).get()).length,
      0,
      reason: 'item → inventory_entries FK must CASCADE',
    );
  });

  test('recipe tag round-trip via normalized junction', () async {
    await db.into(db.recipes).insert(RecipesCompanion.insert(
          id: 'r_1',
          name: 'Pancakes',
        ));
    await db.setTagsForRecipe('r_1', ['breakfast', 'sweet', 'Breakfast']);
    final tags = await db.tagsForRecipe('r_1');
    // Case-insensitive dedup: 'breakfast' and 'Breakfast' collapse.
    expect(tags.length, 2);
    expect(tags.map((t) => t.toLowerCase()).toSet(),
        equals({'breakfast', 'sweet'}));

    // Replacing should remove old tags not in the new set.
    await db.setTagsForRecipe('r_1', ['sweet']);
    final after = await db.tagsForRecipe('r_1');
    expect(after, ['sweet']);
  });

  test('sqlite_master tables match every @DriftDatabase-declared table',
      () async {
    // Poor man's schema self-verification: every table registered with the
    // database must exist as a real SQLite table. Divergence between the
    // Dart declarations and the materialized schema (typos, missed
    // `createTable` in onUpgrade, etc.) shows up here.
    final rows = await db.customSelect(
      "SELECT name FROM sqlite_master WHERE type='table' "
      "AND name NOT LIKE 'sqlite_%' AND name NOT LIKE 'android_%'",
    ).get();
    final realTables = rows.map((r) => r.read<String>('name')).toSet();
    final declared =
        db.allTables.map((t) => t.actualTableName).toSet();
    expect(realTables, containsAll(declared));
  });
}
