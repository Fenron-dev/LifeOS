import 'package:drift/drift.dart' show Value;
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

  test('fresh database opens and exposes schemaVersion 36', () async {
    // Triggers onCreate → createAll + seeds + _createIndexes
    await db.customSelect('SELECT 1').get();
    expect(db.schemaVersion, 36);
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
    await db.select(db.bodyMeasurements).get();
    await db.select(db.userProfile).get();
    await db.select(db.nutritionLogs).get();
    await db.select(db.waterLogs).get();
    await db.select(db.mealPlanEntries).get();
    await db.select(db.categoryDefinitions).get();
    await db.select(db.bodyPhotos).get();
    await db.select(db.exercises).get();
    await db.select(db.workouts).get();
    await db.select(db.workoutSets).get();
    await db.select(db.workoutPlans).get();
    await db.select(db.workoutPlanExercises).get();
    await db.select(db.customShoppingItems).get();
    await db.select(db.itemRelations).get();
    await db.select(db.itemTemplates).get();
    await db.select(db.templateFields).get();
    await db.select(db.itemPropertyValues).get();
    await db.select(db.productTypeDefinitions).get();
    await db.select(db.preparedDishes).get();
    await db.select(db.mealRelations).get();
    await db.select(db.entityPhotos).get();
  });

  test('weight log persists full body composition payload', () async {
    await db.insertWeightLog(BodyWeightLogsCompanion.insert(
      id: 'w1',
      loggedAt: DateTime(2026, 5, 1, 8, 0),
      weightKg: 78.4,
      bodyFatPct: const Value(22.1),
      muscleMassPct: const Value(38.5),
      visceralFat: const Value(8.0),
      waterPct: const Value(55.2),
      boneMassKg: const Value(3.1),
      source: const Value('scale'),
    ));
    final log = (await db.latestWeightLog())!;
    expect(log.weightKg, 78.4);
    expect(log.bodyFatPct, 22.1);
    expect(log.muscleMassPct, 38.5);
    expect(log.visceralFat, 8.0);
    expect(log.waterPct, 55.2);
    expect(log.boneMassKg, 3.1);
    expect(log.source, 'scale');
  });

  test('user profile is a true singleton (id always 1)', () async {
    await db.upsertUserProfile(UserProfileCompanion(
      heightCm: const Value(180),
      sex: const Value('male'),
      birthDate: Value(DateTime(1990, 1, 1)),
    ));
    // Even if a caller passes a wrong id, the upsert pins id=1.
    await db.upsertUserProfile(UserProfileCompanion(
      id: const Value(99),
      heightCm: const Value(181),
    ));
    final all = await db.select(db.userProfile).get();
    expect(all, hasLength(1));
    expect(all.single.id, 1);
    expect(all.single.heightCm, 181);
    // Sex from the first call survives — second upsert only patched height.
    expect(all.single.sex, 'male');
  });

  test('weightLogDaysSince counts distinct days', () async {
    // Anchor on a fixed noon so "+ 4 hours" stays on the same calendar day
    // regardless of when the suite runs.
    final now = DateTime.now();
    final today =
        DateTime(now.year, now.month, now.day, 12, 0).toUtc();
    Future<void> add(String id, DateTime at) =>
        db.insertWeightLog(BodyWeightLogsCompanion.insert(
          id: id,
          loggedAt: at,
          weightKg: 80,
        ));
    await add('a', today);
    // Same calendar day, different time — must collapse to one bucket.
    await add('b', today.add(const Duration(hours: 4)));
    await add('c', today.subtract(const Duration(days: 2)));
    await add('d', today.subtract(const Duration(days: 30)));

    final last7 = await db
        .weightLogDaysSince(today.subtract(const Duration(days: 7)));
    expect(last7, 2); // today + day-2 (day-30 is outside)
  });

  test('default units, meal types and exercises are seeded on create',
      () async {
    final units = await db.select(db.units).get();
    final mealTypes = await db.select(db.mealTypes).get();
    final exs = await db.select(db.exercises).get();
    expect(units, isNotEmpty, reason: 'onCreate must seed default units');
    expect(mealTypes, isNotEmpty, reason: 'onCreate must seed meal types');
    expect(exs.length, greaterThanOrEqualTo(40),
        reason: 'onCreate must seed default exercises');
  });

  test('product type definitions and built-in templates are seeded on create',
      () async {
    final types = await db.select(db.productTypeDefinitions).get();
    final templates = await db.select(db.itemTemplates).get();
    final fields = await db.select(db.templateFields).get();
    expect(types.length, 7,
        reason: 'onCreate must seed 7 built-in product types');
    expect(templates, isNotEmpty,
        reason: 'onCreate must seed built-in templates');
    expect(fields, isNotEmpty,
        reason: 'built-in templates must have fields');
    // All seeded types are built-in
    expect(types.every((t) => t.isBuiltIn), isTrue);
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
