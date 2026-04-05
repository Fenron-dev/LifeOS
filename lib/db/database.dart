import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;

import 'tables/items_table.dart';
import 'tables/events_table.dart';
import 'tables/locations_table.dart';
import 'tables/shops_table.dart';
import 'tables/units_table.dart';
import 'tables/tags_table.dart';
import 'tables/recipes_table.dart';
import 'tables/tasks_table.dart';
import 'tables/automation_table.dart';
import 'tables/stats_table.dart';

part 'database.g.dart';

@DriftDatabase(tables: [
  // Core inventory
  Items,
  InventoryEntries,
  ItemGroups,
  ItemGroupMembers,
  // Events & state
  ItemEvents,
  ItemStates,
  // Locations
  Locations,
  // Tags & photos
  TagDefinitions,
  ItemTags,
  EntityPhotos,
  // Recipes
  Recipes,
  RecipeIngredients,
  RecipeSteps,
  StandardMeals,
  StandardMealIngredients,
  // Tasks & wish list
  Tasks,
  WishListEntries,
  // Shops, unit conversions & units
  Shops,
  UnitConversions,
  Units,
  // Automation & settings
  AutomationRules,
  AppSettings,
  // Stats
  BodyWeightLogs,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase(String vaultPath) : super(_openDb(vaultPath));

  @override
  int get schemaVersion => 6;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await _seedDefaultUnits();
          await _seedDefaultConversions();
        },
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.addColumn(items, items.caloriesPer100g);
            await m.addColumn(items, items.proteinPer100g);
            await m.addColumn(items, items.carbsPer100g);
            await m.addColumn(items, items.fatPer100g);
            await m.addColumn(items, items.fiberPer100g);
            await m.addColumn(items, items.sugarsPer100g);
            await m.addColumn(items, items.saturatedFatPer100g);
            await m.addColumn(items, items.saltPer100g);
            await m.addColumn(items, items.servingSizeG);
            await m.addColumn(items, items.nutriscore);
            await m.addColumn(items, items.novaGroup);
            await m.addColumn(items, items.ingredientsText);
          }
          if (from < 3) {
            await m.createTable(shops);
            await m.createTable(unitConversions);
          }
          if (from < 5) {
            await m.addColumn(locations, locations.locationType);
          }
          if (from < 6) {
            await m.createTable(bodyWeightLogs);
            await _seedDefaultConversions();
          }
          if (from < 4) {
            await m.createTable(units);
            await m.addColumn(items, items.stockUnit);
            await m.addColumn(recipes, recipes.sourceUrl);
            await m.addColumn(recipes, recipes.mealieSlug);
            await m.addColumn(recipes, recipes.imageUrl);
            await m.addColumn(recipes, recipes.tags);
            await m.addColumn(recipes, recipes.fiberPerServing);
            await m.addColumn(recipes, recipes.sodiumPerServing);
            // Seed default units
            await _seedDefaultUnits();
          }
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
          await customStatement('PRAGMA journal_mode = WAL');
        },
      );

  static QueryExecutor _openDb(String vaultPath) {
    final dbFile = File(p.join(vaultPath, 'lifeos.db'));
    return NativeDatabase.createInBackground(dbFile);
  }

  // ── Items ──────────────────────────────────────────────────────────────────

  Future<List<Item>> allItems() => select(items).get();

  Stream<List<Item>> watchAllItems() => select(items).watch();

  Stream<List<Item>> watchItemsByCategory(String categoryId) =>
      (select(items)..where((i) => i.categoryId.equals(categoryId))).watch();

  Future<Item?> itemById(String id) =>
      (select(items)..where((i) => i.id.equals(id))).getSingleOrNull();

  Future<Item?> itemByEan(String ean) =>
      (select(items)..where((i) => i.ean.equals(ean))).getSingleOrNull();

  Future<void> insertItem(ItemsCompanion entry) =>
      into(items).insert(entry);

  Future<void> updateItem(ItemsCompanion entry) =>
      (update(items)..where((i) => i.id.equals(entry.id.value))).write(entry);

  Future<void> deleteItem(String id) =>
      (delete(items)..where((i) => i.id.equals(id))).go();

  Stream<List<Item>> searchItems(String query) {
    final like = '%${query.toLowerCase()}%';
    return (select(items)
          ..where((i) => i.name.lower().like(like) | i.brand.lower().like(like)))
        .watch();
  }

  // ── Inventory ──────────────────────────────────────────────────────────────

  Stream<List<InventoryEntry>> watchInventoryForItem(String itemId) =>
      (select(inventoryEntries)..where((e) => e.itemId.equals(itemId))).watch();

  Future<List<InventoryEntry>> expiringWithin(int days) {
    final cutoff = DateTime.now().add(Duration(days: days));
    return (select(inventoryEntries)
          ..where((e) =>
              e.expiryDate.isNotNull() &
              e.expiryDate.isSmallerOrEqualValue(cutoff))
          ..orderBy([(e) => OrderingTerm.asc(e.expiryDate)]))
        .get();
  }

  Future<void> insertInventoryEntry(InventoryEntriesCompanion entry) =>
      into(inventoryEntries).insert(entry);

  Future<void> updateInventoryEntry(InventoryEntriesCompanion entry) =>
      (update(inventoryEntries)..where((e) => e.id.equals(entry.id.value)))
          .write(entry);

  Future<void> deleteInventoryEntry(String id) =>
      (delete(inventoryEntries)..where((e) => e.id.equals(id))).go();

  // ── Item Events ────────────────────────────────────────────────────────────

  Future<void> insertItemEvent(ItemEventsCompanion entry) =>
      into(itemEvents).insert(entry);

  Stream<List<ItemEvent>> watchEventsForItem(String itemId) =>
      (select(itemEvents)
            ..where((e) => e.itemId.equals(itemId))
            ..orderBy([(e) => OrderingTerm.desc(e.createdAt)]))
          .watch();

  // ── Item States ────────────────────────────────────────────────────────────

  Future<void> upsertItemState(ItemStatesCompanion entry) =>
      into(itemStates).insertOnConflictUpdate(entry);

  Future<void> deleteItemState(String inventoryEntryId) =>
      (delete(itemStates)
            ..where((s) => s.inventoryEntryId.equals(inventoryEntryId)))
          .go();

  Stream<List<ItemState>> watchStatesForItem(String itemId) =>
      (select(itemStates)..where((s) => s.itemId.equals(itemId))).watch();

  // ── Locations ──────────────────────────────────────────────────────────────

  Stream<List<Location>> watchAllLocations() => select(locations).watch();

  Future<Location?> locationById(String id) =>
      (select(locations)..where((l) => l.id.equals(id))).getSingleOrNull();

  Future<void> insertLocation(LocationsCompanion entry) =>
      into(locations).insert(entry);

  Future<void> updateLocation(LocationsCompanion entry) =>
      (update(locations)..where((l) => l.id.equals(entry.id.value)))
          .write(entry);

  Future<void> deleteLocation(String id) =>
      (delete(locations)..where((l) => l.id.equals(id))).go();

  // ── Item Groups ────────────────────────────────────────────────────────────

  Stream<List<ItemGroup>> watchAllGroups() => select(itemGroups).watch();

  Future<void> insertItemGroup(ItemGroupsCompanion entry) =>
      into(itemGroups).insert(entry);

  Future<void> deleteItemGroup(String id) =>
      (delete(itemGroups)..where((g) => g.id.equals(id))).go();

  Future<List<ItemGroupMember>> membersForGroup(String groupId) =>
      (select(itemGroupMembers)..where((m) => m.groupId.equals(groupId))).get();

  Future<void> addItemToGroup(String groupId, String itemId) =>
      into(itemGroupMembers)
          .insertOnConflictUpdate(ItemGroupMembersCompanion.insert(
        groupId: groupId,
        itemId: itemId,
      ));

  Future<void> removeItemFromGroup(String groupId, String itemId) =>
      (delete(itemGroupMembers)
            ..where(
                (m) => m.groupId.equals(groupId) & m.itemId.equals(itemId)))
          .go();

  // ── Item States (future variant for shopping computation) ─────────────────

  Future<List<ItemState>> statesForItem(String itemId) =>
      (select(itemStates)..where((s) => s.itemId.equals(itemId))).get();

  Future<List<ItemGroup>> groupsWithMinStock() =>
      (select(itemGroups)..where((g) => g.minStockQuantity.isNotNull())).get();

  Future<void> updateItemGroup(ItemGroupsCompanion entry) =>
      (update(itemGroups)..where((g) => g.id.equals(entry.id.value)))
          .write(entry);

  Future<List<ItemGroupMember>> groupsForItem(String itemId) =>
      (select(itemGroupMembers)..where((m) => m.itemId.equals(itemId))).get();

  // ── Wishlist ───────────────────────────────────────────────────────────────

  Stream<List<WishListEntry>> watchWishlist() =>
      (select(wishListEntries)
            ..orderBy([(w) => OrderingTerm.desc(w.createdAt)]))
          .watch();

  Future<void> insertWishListEntry(WishListEntriesCompanion entry) =>
      into(wishListEntries).insert(entry);

  Future<void> updateWishListEntry(WishListEntriesCompanion entry) =>
      (update(wishListEntries)..where((w) => w.id.equals(entry.id.value)))
          .write(entry);

  Future<void> deleteWishListEntry(String id) =>
      (delete(wishListEntries)..where((w) => w.id.equals(id))).go();

  // ── Tasks ──────────────────────────────────────────────────────────────────

  Stream<List<Task>> watchTasks() =>
      (select(tasks)
            ..orderBy([
              (t) => OrderingTerm(
                  expression: t.status,
                  mode: OrderingMode.asc), // pending before done
              (t) => OrderingTerm(
                  expression: t.dueDate,
                  mode: OrderingMode.asc,
                  nulls: NullsOrder.last),
            ]))
          .watch();

  Future<void> insertTask(TasksCompanion entry) => into(tasks).insert(entry);

  Future<void> updateTask(TasksCompanion entry) =>
      (update(tasks)..where((t) => t.id.equals(entry.id.value))).write(entry);

  Future<void> deleteTask(String id) =>
      (delete(tasks)..where((t) => t.id.equals(id))).go();

  // ── Default unit seeding ──────────────────────────────────────────────────

  static const _defaultUnits = [
    ('g', 'g'), ('kg', 'kg'), ('mg', 'mg'),
    ('ml', 'ml'), ('l', 'l'),
    ('Stück', 'Stk.'), ('Packung', 'Pkg.'), ('Dose', 'Dose'),
    ('Flasche', 'Fl.'), ('Tüte', 'Tüte'), ('Glas', 'Glas'),
    ('EL', 'EL'), ('TL', 'TL'), ('Tasse', 'Tasse'),
    ('Scheibe', 'Scheibe'), ('Portion', 'Port.'), ('Prise', 'Prise'),
  ];

  /// Standard unit conversions seeded once on DB creation / v6 migration.
  /// Only inserts; existing rows are left unchanged (insertOnConflictUpdate
  /// would overwrite user-defined values with the same id).
  static const _defaultConversions = [
    // Weight
    ('def_g_kg',  'g',  'kg', 0.001),
    ('def_kg_g',  'kg', 'g',  1000.0),
    ('def_mg_g',  'mg', 'g',  0.001),
    ('def_g_mg',  'g',  'mg', 1000.0),
    ('def_kg_mg', 'kg', 'mg', 1000000.0),
    // Volume
    ('def_ml_l',  'ml', 'l',  0.001),
    ('def_l_ml',  'l',  'ml', 1000.0),
    // Cooking measures (approximate)
    ('def_el_ml', 'EL', 'ml', 15.0),
    ('def_tl_ml', 'TL', 'ml', 5.0),
    ('def_ml_el', 'ml', 'EL', 0.0667),
    ('def_ml_tl', 'ml', 'TL', 0.2),
  ];

  Future<void> _seedDefaultConversions() async {
    for (final (id, from, to, factor) in _defaultConversions) {
      // Skip if already exists — don't overwrite user changes
      final existing = await (select(unitConversions)
            ..where((c) => c.id.equals(id)))
          .getSingleOrNull();
      if (existing != null) continue;
      await into(unitConversions).insert(UnitConversionsCompanion.insert(
        id: id,
        fromUnit: from,
        toUnit: to,
        factor: factor,
      ));
    }
  }

  Future<void> _seedDefaultUnits() async {
    for (var i = 0; i < _defaultUnits.length; i++) {
      final (name, abbr) = _defaultUnits[i];
      await into(units).insertOnConflictUpdate(UnitsCompanion.insert(
        id: 'default_$i',
        name: name,
        abbreviation: Value(abbr),
        isDefault: const Value(true),
        sortOrder: Value(i),
      ));
    }
  }

  // ── Units ──────────────────────────────────────────────────────────────────

  Stream<List<Unit>> watchAllUnits() =>
      (select(units)..orderBy([(u) => OrderingTerm.asc(u.sortOrder)])).watch();

  Future<List<Unit>> allUnitsList() =>
      (select(units)..orderBy([(u) => OrderingTerm.asc(u.sortOrder)])).get();

  Future<void> insertUnit(UnitsCompanion entry) =>
      into(units).insertOnConflictUpdate(entry);

  Future<void> updateUnit(UnitsCompanion entry) =>
      (update(units)..where((u) => u.id.equals(entry.id.value))).write(entry);

  Future<void> deleteUnit(String id) =>
      (delete(units)..where((u) => u.id.equals(id))).go();

  // ── Recipes ────────────────────────────────────────────────────────────────

  Stream<List<Recipe>> watchAllRecipes() =>
      (select(recipes)..orderBy([(r) => OrderingTerm.asc(r.name)])).watch();

  Future<Recipe?> recipeById(String id) =>
      (select(recipes)..where((r) => r.id.equals(id))).getSingleOrNull();

  Future<Recipe?> recipeByMealieSlug(String slug) =>
      (select(recipes)..where((r) => r.mealieSlug.equals(slug)))
          .getSingleOrNull();

  Stream<List<Recipe>> searchRecipes(String query) {
    final like = '%${query.toLowerCase()}%';
    return (select(recipes)..where((r) => r.name.lower().like(like))).watch();
  }

  Future<void> insertRecipe(RecipesCompanion entry) =>
      into(recipes).insert(entry);

  Future<void> updateRecipe(RecipesCompanion entry) =>
      (update(recipes)..where((r) => r.id.equals(entry.id.value))).write(entry);

  Future<void> deleteRecipe(String id) =>
      (delete(recipes)..where((r) => r.id.equals(id))).go();

  // Recipe ingredients
  Future<List<RecipeIngredient>> ingredientsForRecipe(String recipeId) =>
      (select(recipeIngredients)
            ..where((i) => i.recipeId.equals(recipeId))
            ..orderBy([(i) => OrderingTerm.asc(i.sortOrder)]))
          .get();

  Future<void> insertRecipeIngredient(RecipeIngredientsCompanion entry) =>
      into(recipeIngredients).insert(entry);

  Future<void> deleteIngredientsForRecipe(String recipeId) =>
      (delete(recipeIngredients)
            ..where((i) => i.recipeId.equals(recipeId)))
          .go();

  // Recipe steps
  Future<List<RecipeStep>> stepsForRecipe(String recipeId) =>
      (select(recipeSteps)
            ..where((s) => s.recipeId.equals(recipeId))
            ..orderBy([(s) => OrderingTerm.asc(s.stepNumber)]))
          .get();

  Future<void> insertRecipeStep(RecipeStepsCompanion entry) =>
      into(recipeSteps).insert(entry);

  Future<void> deleteStepsForRecipe(String recipeId) =>
      (delete(recipeSteps)..where((s) => s.recipeId.equals(recipeId))).go();

  // Standard meals
  Stream<List<StandardMeal>> watchAllMeals() =>
      (select(standardMeals)..orderBy([(m) => OrderingTerm.asc(m.name)]))
          .watch();

  Future<void> insertMeal(StandardMealsCompanion entry) =>
      into(standardMeals).insert(entry);

  Future<void> updateMeal(StandardMealsCompanion entry) =>
      (update(standardMeals)..where((m) => m.id.equals(entry.id.value)))
          .write(entry);

  Future<void> deleteMeal(String id) =>
      (delete(standardMeals)..where((m) => m.id.equals(id))).go();

  Future<List<StandardMealIngredient>> ingredientsForMeal(String mealId) =>
      (select(standardMealIngredients)
            ..where((i) => i.mealId.equals(mealId))
            ..orderBy([(i) => OrderingTerm.asc(i.sortOrder)]))
          .get();

  Future<void> insertMealIngredient(StandardMealIngredientsCompanion entry) =>
      into(standardMealIngredients).insert(entry);

  Future<void> deleteMealIngredients(String mealId) =>
      (delete(standardMealIngredients)
            ..where((i) => i.mealId.equals(mealId)))
          .go();

  // ── Item States (all) ─────────────────────────────────────────────────────

  Stream<List<ItemState>> watchAllItemStates() => select(itemStates).watch();

  // ── Shops ──────────────────────────────────────────────────────────────────

  Stream<List<Shop>> watchAllShops() =>
      (select(shops)..orderBy([(s) => OrderingTerm.asc(s.name)])).watch();

  Future<void> insertShop(ShopsCompanion entry) => into(shops).insert(entry);

  Future<void> updateShop(ShopsCompanion entry) =>
      (update(shops)..where((s) => s.id.equals(entry.id.value))).write(entry);

  Future<void> deleteShop(String id) =>
      (delete(shops)..where((s) => s.id.equals(id))).go();

  // ── Unit Conversions ───────────────────────────────────────────────────────

  Stream<List<UnitConversion>> watchConversionsGlobal() =>
      (select(unitConversions)..where((c) => c.scope.equals('global')))
          .watch();

  Stream<List<UnitConversion>> watchConversionsForGroup(String groupId) =>
      (select(unitConversions)
            ..where((c) =>
                c.scope.equals('group') & c.scopeId.equals(groupId)))
          .watch();

  Stream<List<UnitConversion>> watchConversionsForItem(String itemId) =>
      (select(unitConversions)
            ..where(
                (c) => c.scope.equals('item') & c.scopeId.equals(itemId)))
          .watch();

  Future<void> insertConversion(UnitConversionsCompanion entry) =>
      into(unitConversions).insert(entry);

  Future<void> deleteConversion(String id) =>
      (delete(unitConversions)..where((c) => c.id.equals(id))).go();

  // ── Settings ───────────────────────────────────────────────────────────────

  Future<String?> getSetting(String key) async {
    final row = await (select(appSettings)
          ..where((s) => s.key.equals(key)))
        .getSingleOrNull();
    return row?.value;
  }

  Future<void> setSetting(String key, String value) async {
    await into(appSettings).insertOnConflictUpdate(
      AppSettingsCompanion.insert(key: key, value: value),
    );
  }

  // ── Body Weight Logs ───────────────────────────────────────────────────────

  Stream<List<BodyWeightLog>> watchWeightLogs({int limit = 90}) =>
      (select(bodyWeightLogs)
            ..orderBy([(l) => OrderingTerm.desc(l.loggedAt)])
            ..limit(limit))
          .watch();

  Future<void> insertWeightLog(BodyWeightLogsCompanion entry) =>
      into(bodyWeightLogs).insert(entry);

  Future<void> deleteWeightLog(String id) =>
      (delete(bodyWeightLogs)..where((l) => l.id.equals(id))).go();
}
