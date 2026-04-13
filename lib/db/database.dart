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
  // Recipes & meal planning
  Recipes,
  RecipeIngredients,
  RecipeSteps,
  StandardMeals,
  StandardMealIngredients,
  MealTypes,
  MealTypeAssignments,
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
  int get schemaVersion => 9;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await _seedDefaultUnits();
          await _seedDefaultConversions();
          await _seedDefaultMealTypes();
          await _createIndexes();
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
          if (from < 4) {
            await m.createTable(units);
            await m.addColumn(items, items.stockUnit);
            await m.addColumn(recipes, recipes.sourceUrl);
            await m.addColumn(recipes, recipes.mealieSlug);
            await m.addColumn(recipes, recipes.imageUrl);
            await m.addColumn(recipes, recipes.tags);
            await m.addColumn(recipes, recipes.fiberPerServing);
            await m.addColumn(recipes, recipes.sodiumPerServing);
            await _seedDefaultUnits();
          }
          if (from < 5) {
            await m.addColumn(locations, locations.locationType);
          }
          if (from < 6) {
            await m.createTable(bodyWeightLogs);
            await _seedDefaultConversions();
          }
          if (from < 7) {
            await m.addColumn(units, units.plural);
            await m.addColumn(items, items.defaultLocationId);
          }
          if (from < 8) {
            await m.addColumn(inventoryEntries, inventoryEntries.price);
            await m.createTable(mealTypes);
            await m.createTable(mealTypeAssignments);
            await _seedDefaultMealTypes();
            // Remove old numeric-id default units to prevent duplicates
            await _deleteOldDefaultUnits();
            await _seedDefaultUnits(); // re-seed with new named IDs
            await _seedDefaultConversions(); // add American conversions
          }
          if (from < 9) {
            // Rebuild tables to pick up newly declared FOREIGN KEY constraints,
            // then add hot-path indexes. FKs must be off during rebuild.
            // ignore_for_file: experimental_member_use
            await customStatement('PRAGMA foreign_keys = OFF');
            await transaction(() async {
              await m.alterTable(TableMigration(items));
              await m.alterTable(TableMigration(inventoryEntries));
              await m.alterTable(TableMigration(itemGroupMembers));
              await m.alterTable(TableMigration(itemEvents));
              await m.alterTable(TableMigration(itemStates));
              await m.alterTable(TableMigration(locations));
              await m.alterTable(TableMigration(itemTags));
              await m.alterTable(TableMigration(recipeIngredients));
              await m.alterTable(TableMigration(recipeSteps));
              await m.alterTable(TableMigration(standardMealIngredients));
              await m.alterTable(TableMigration(mealTypeAssignments));
              await m.alterTable(TableMigration(wishListEntries));
            });
            await customStatement('PRAGMA foreign_keys = ON');
            await _createIndexes();
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

  Future<void> deleteItemEvent(String id) =>
      (delete(itemEvents)..where((e) => e.id.equals(id))).go();

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

  // (id_suffix, name, abbreviation)
  static const _defaultUnits = [
    // Metric weight
    ('g',       'g',        'g'),
    ('kg',      'kg',       'kg'),
    ('mg',      'mg',       'mg'),
    // Metric volume
    ('ml',      'ml',       'ml'),
    ('l',       'l',        'l'),
    ('dl',      'dl',       'dl'),
    ('cl',      'cl',       'cl'),
    // Containers & pieces
    ('stueck',  'Stück',    'Stk.'),
    ('packung', 'Packung',  'Pkg.'),
    ('dose',    'Dose',     'Dose'),
    ('flasche', 'Flasche',  'Fl.'),
    ('tuete',   'Tüte',     'Tüte'),
    ('glas',    'Glas',     'Glas'),
    ('beutel',  'Beutel',   'Btl.'),
    // Cooking measures
    ('el',      'EL',       'EL'),
    ('tl',      'TL',       'TL'),
    ('tasse',   'Tasse',    'Tasse'),
    ('scheibe', 'Scheibe',  'Scheibe'),
    ('portion', 'Portion',  'Port.'),
    ('prise',   'Prise',    'Prise'),
    // American units
    ('cup',     'Cup',      'cup'),
    ('oz',      'Unze',     'oz'),
    ('lb',      'Pfund',    'lb'),
    ('floz',    'fl oz',    'fl oz'),
    ('tbsp',    'Esslöffel (US)', 'tbsp'),
    ('tsp',     'Teelöffel (US)', 'tsp'),
    ('qt',      'Quart',    'qt'),
    ('pt',      'Pint',     'pt'),
    ('gallon',  'Gallon',   'gal'),
  ];

  /// Standard unit conversions. Only inserts; existing rows are left unchanged.
  static const _defaultConversions = [
    // Metric weight
    ('def_g_kg',   'g',   'kg',  0.001),
    ('def_kg_g',   'kg',  'g',   1000.0),
    ('def_mg_g',   'mg',  'g',   0.001),
    ('def_g_mg',   'g',   'mg',  1000.0),
    ('def_kg_mg',  'kg',  'mg',  1000000.0),
    // Metric volume
    ('def_ml_l',   'ml',  'l',   0.001),
    ('def_l_ml',   'l',   'ml',  1000.0),
    ('def_dl_ml',  'dl',  'ml',  100.0),
    ('def_ml_dl',  'ml',  'dl',  0.01),
    ('def_cl_ml',  'cl',  'ml',  10.0),
    ('def_ml_cl',  'ml',  'cl',  0.1),
    // Cooking measures → ml
    ('def_el_ml',  'EL',  'ml',  15.0),
    ('def_tl_ml',  'TL',  'ml',  5.0),
    ('def_ml_el',  'ml',  'EL',  0.0667),
    ('def_ml_tl',  'ml',  'TL',  0.2),
    // American weight → metric
    ('def_oz_g',   'Unze',  'g',   28.3495),
    ('def_g_oz',   'g',     'Unze', 0.03527),
    ('def_lb_g',   'Pfund', 'g',   453.592),
    ('def_g_lb',   'g',     'Pfund', 0.002205),
    ('def_lb_kg',  'Pfund', 'kg',  0.453592),
    ('def_kg_lb',  'kg',    'Pfund', 2.20462),
    // American volume → ml
    ('def_floz_ml',  'fl oz', 'ml',    29.5735),
    ('def_ml_floz',  'ml',    'fl oz', 0.033814),
    ('def_cup_ml',   'Cup',   'ml',    236.588),
    ('def_ml_cup',   'ml',    'Cup',   0.004227),
    ('def_tbsp_ml',  'Esslöffel (US)', 'ml', 14.787),
    ('def_tsp_ml',   'Teelöffel (US)', 'ml', 4.929),
    ('def_pt_ml',    'Pint',   'ml',   473.176),
    ('def_qt_ml',    'Quart',  'ml',   946.353),
    ('def_gal_ml',   'Gallon', 'ml',   3785.41),
    // American ↔ EL/TL
    ('def_tbsp_el',  'Esslöffel (US)', 'EL', 0.986),
    ('def_tsp_tl',   'Teelöffel (US)', 'TL', 0.986),
  ];

  // Default meal types seeded once
  static const _defaultMealTypes = [
    ('mt_fruehstueck', 'Frühstück',       'free_breakfast'),
    ('mt_mittagessen', 'Mittagessen',      'lunch_dining'),
    ('mt_abendessen',  'Abendessen',       'dinner_dining'),
    ('mt_snack',       'Snack',            'apple'),
    ('mt_suessigkeit', 'Süßigkeit/Dessert','cake'),
    ('mt_getraenk',    'Getränk',          'local_cafe'),
    ('mt_sonstiges',   'Sonstiges',        'more_horiz'),
  ];

  Future<void> _seedDefaultConversions() async {
    for (final (id, from, to, factor) in _defaultConversions) {
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
      final (idSuffix, name, abbr) = _defaultUnits[i];
      await into(units).insertOnConflictUpdate(UnitsCompanion.insert(
        id: 'default_$idSuffix',
        name: name,
        abbreviation: Value(abbr),
        isDefault: const Value(true),
        sortOrder: Value(i),
      ));
    }
  }

  /// Delete old numeric-id default units (default_0 … default_16) created by
  /// the original seed that used index-based IDs. The new seed uses name-based
  /// IDs (default_g, default_kg, …) so numeric ones become duplicates.
  Future<void> _deleteOldDefaultUnits() async {
    for (var i = 0; i <= 30; i++) {
      await (delete(units)..where((u) => u.id.equals('default_$i'))).go();
    }
  }

  /// Creates indexes on hot-path columns. Idempotent.
  Future<void> _createIndexes() async {
    const stmts = [
      'CREATE INDEX IF NOT EXISTS idx_items_ean ON items (ean)',
      'CREATE INDEX IF NOT EXISTS idx_items_category ON items (category_id)',
      'CREATE INDEX IF NOT EXISTS idx_inv_item ON inventory_entries (item_id)',
      'CREATE INDEX IF NOT EXISTS idx_inv_expiry ON inventory_entries (expiry_date)',
      'CREATE INDEX IF NOT EXISTS idx_inv_location ON inventory_entries (location_id)',
      'CREATE INDEX IF NOT EXISTS idx_events_item ON item_events (item_id)',
      'CREATE INDEX IF NOT EXISTS idx_events_created ON item_events (created_at)',
      'CREATE INDEX IF NOT EXISTS idx_events_sync ON item_events (sync_status)',
      'CREATE INDEX IF NOT EXISTS idx_states_item ON item_states (item_id)',
      'CREATE INDEX IF NOT EXISTS idx_tags_item ON item_tags (item_id)',
      'CREATE INDEX IF NOT EXISTS idx_tags_tag ON item_tags (tag_id)',
      'CREATE INDEX IF NOT EXISTS idx_locations_parent ON locations (parent_id)',
      'CREATE INDEX IF NOT EXISTS idx_recipe_ing_recipe ON recipe_ingredients (recipe_id)',
      'CREATE INDEX IF NOT EXISTS idx_meal_ing_meal ON standard_meal_ingredients (meal_id)',
      'CREATE INDEX IF NOT EXISTS idx_mta_mealtype ON meal_type_assignments (meal_type_id)',
    ];
    for (final s in stmts) {
      await customStatement(s);
    }
  }

  Future<void> _seedDefaultMealTypes() async {
    for (var i = 0; i < _defaultMealTypes.length; i++) {
      final (id, name, icon) = _defaultMealTypes[i];
      final existing = await (select(mealTypes)..where((m) => m.id.equals(id)))
          .getSingleOrNull();
      if (existing != null) continue;
      await into(mealTypes).insert(MealTypesCompanion.insert(
        id: id,
        name: name,
        iconName: Value(icon),
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

  // ── Meal types ────────────────────────────────────────────────────────────

  Stream<List<MealType>> watchAllMealTypes() =>
      (select(mealTypes)..orderBy([(m) => OrderingTerm.asc(m.sortOrder)])).watch();

  Future<void> insertMealType(MealTypesCompanion entry) =>
      into(mealTypes).insert(entry);

  Future<void> updateMealType(MealTypesCompanion entry) =>
      (update(mealTypes)..where((m) => m.id.equals(entry.id.value))).write(entry);

  Future<void> deleteMealType(String id) =>
      (delete(mealTypes)..where((m) => m.id.equals(id))).go();

  // ── Meal type assignments ─────────────────────────────────────────────────

  Stream<List<MealTypeAssignment>> watchAssignmentsForMealType(String mealTypeId) =>
      (select(mealTypeAssignments)
            ..where((a) => a.mealTypeId.equals(mealTypeId)))
          .watch();

  Future<void> insertMealTypeAssignment(MealTypeAssignmentsCompanion entry) =>
      into(mealTypeAssignments).insert(entry);

  Future<void> deleteMealTypeAssignment(String id) =>
      (delete(mealTypeAssignments)..where((a) => a.id.equals(id))).go();

  Future<void> deleteAssignmentsForMealType(String mealTypeId) =>
      (delete(mealTypeAssignments)
            ..where((a) => a.mealTypeId.equals(mealTypeId)))
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
