import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../core/item_categories.dart';

import 'sql_cipher_loader.dart';

import 'tables/items_table.dart';
import 'tables/events_table.dart';
import 'tables/locations_table.dart';
import 'tables/shops_table.dart';
import 'tables/units_table.dart';
import 'tables/tags_table.dart';
import 'tables/recipes_table.dart';
import 'tables/tasks_table.dart';
import 'tables/automation_table.dart';
import 'tables/nutrition_table.dart';
import 'tables/stats_table.dart';
import 'tables/meal_plan_table.dart';
import 'tables/categories_table.dart';
import 'tables/body_photos_table.dart';
import 'tables/fitness_table.dart';
import 'tables/shopping_table.dart';
import 'tables/relations_table.dart';
import 'tables/templates_table.dart';
import 'tables/product_types_table.dart';

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
  RecipeTags,
  EntityPhotos,
  // Recipes & meal planning
  Recipes,
  RecipeIngredients,
  RecipeSteps,
  StandardMeals,
  StandardMealIngredients,
  MealTypes,
  MealTypeAssignments,
  PreparedDishes,
  MealRelations,
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
  // Stats / Health
  BodyWeightLogs,
  BodyMeasurements,
  UserProfile,
  // Nutrition diary
  NutritionLogs,
  // Water tracking
  WaterLogs,
  // Meal plan
  MealPlanEntries,
  // Custom categories (Phase 4)
  CategoryDefinitions,
  // Private body photos (Phase 6.7)
  BodyPhotos,
  // Fitness tracking (Phase 6.8 / 7.x)
  Exercises,
  Workouts,
  WorkoutSets,
  WorkoutPlans,
  WorkoutPlanExercises,
  // Custom shopping list entries
  CustomShoppingItems,
  // Item relations (Obsidian-style)
  ItemRelations,
  // Templates & custom properties (Sprint B)
  ItemTemplates,
  TemplateFields,
  ItemPropertyValues,
  // User-manageable product type definitions
  ProductTypeDefinitions,
])
class AppDatabase extends _$AppDatabase {
  /// [encryptionKey] enables SQLCipher when non-null. Pass `null` for plain
  /// SQLite (legacy vaults / unencrypted mode).
  AppDatabase(String vaultPath, {String? encryptionKey})
      : super(_openDb(vaultPath, encryptionKey));

  /// Test-only constructor that accepts an arbitrary [QueryExecutor] — used
  /// by the migration and smoke tests to open an in-memory database without
  /// touching SQLCipher or the filesystem.
  @visibleForTesting
  AppDatabase.forTesting(super.e);

  @override
  int get schemaVersion => 41;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await _seedDefaultUnits();
          await _seedDefaultConversions();
          await _seedDefaultMealTypes();
          await _seedDefaultExercises();
          await _seedProductTypeDefinitions();
          await _seedBuiltInTemplates();
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
            // v4 added `recipes.tags TEXT` (JSON) — v10 later normalizes it
            // into recipe_tags and drops the column. Add via raw SQL because
            // the column no longer exists on the Dart-side Recipes table.
            await customStatement('ALTER TABLE recipes ADD COLUMN tags TEXT');
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
          if (from < 10) {
            // Normalize recipe tags: JSON column → recipe_tags junction +
            // tag_definitions (scope 'recipe'). Reads the old column via raw
            // SQL before it disappears from the schema.
            await m.createTable(recipeTags);
            await _migrateRecipeTagsJson();
            await customStatement('PRAGMA foreign_keys = OFF');
            await transaction(() async {
              await m.alterTable(TableMigration(recipes));
            });
            await customStatement('PRAGMA foreign_keys = ON');
          }
          if (from < 11) {
            // Phase 6.1 — body composition + user profile.
            await m.addColumn(bodyWeightLogs, bodyWeightLogs.bodyFatPct);
            await m.addColumn(bodyWeightLogs, bodyWeightLogs.muscleMassPct);
            await m.addColumn(bodyWeightLogs, bodyWeightLogs.visceralFat);
            await m.addColumn(bodyWeightLogs, bodyWeightLogs.waterPct);
            await m.addColumn(bodyWeightLogs, bodyWeightLogs.boneMassKg);
            await m.addColumn(bodyWeightLogs, bodyWeightLogs.source);
            await m.createTable(userProfile);
          }
          if (from < 12) {
            // Phase 6.2 — body measurements (Körpermaße).
            await m.createTable(bodyMeasurements);
          }
          if (from < 13) {
            // Phase 6.4 — nutrition diary.
            await m.createTable(nutritionLogs);
            await customStatement(
              'CREATE INDEX IF NOT EXISTS idx_nutr_logged_at '
              'ON nutrition_logs (logged_at)',
            );
            await customStatement(
              'CREATE INDEX IF NOT EXISTS idx_nutr_meal_type '
              'ON nutrition_logs (meal_type_id)',
            );
          }
          if (from < 14) {
            // Per-100ml nutrition reference unit for liquid items.
            await m.addColumn(items, items.nutritionRefUnit);
          }
          if (from < 15) {
            // Phase 6.5 — water intake tracking.
            await m.createTable(waterLogs);
            await customStatement(
              'CREATE INDEX IF NOT EXISTS idx_water_logged_at '
              'ON water_logs (logged_at)',
            );
          }
          if (from < 16) {
            // Phase 6.6 — stored nutrition on StandardMeals for manual fallback.
            await m.addColumn(standardMeals, standardMeals.kcalTotal);
            await m.addColumn(standardMeals, standardMeals.proteinG);
            await m.addColumn(standardMeals, standardMeals.carbsG);
            await m.addColumn(standardMeals, standardMeals.fatG);
          }
          if (from < 17) {
            // Phase 6.7 — opened-state tracking for inventory entries.
            await m.addColumn(items, items.daysAfterOpening);
            await m.addColumn(inventoryEntries, inventoryEntries.openedAt);
          }
          if (from < 18) {
            // Phase 6.8 — flexible serving unit for recipes and meals.
            await m.addColumn(recipes, recipes.servingUnit);
            await m.addColumn(standardMeals, standardMeals.servingUnit);
          }
          if (from < 20) {
            // Phase 7.0 — meal plan.
            await m.createTable(mealPlanEntries);
          }
          if (from < 21) {
            // Phase 4 — custom user-defined categories.
            await m.createTable(categoryDefinitions);
          }
          if (from < 22) {
            // Phase 6.7 — private encrypted body photos.
            await m.createTable(bodyPhotos);
          }
          if (from < 23) {
            // Phase 6.8 — fitness tracking.
            await m.createTable(exercises);
            await m.createTable(workouts);
            await m.createTable(workoutSets);
            await _seedDefaultExercises();
          }
          if (from < 24) {
            // Phase 6.9 — default consume unit per item.
            await m.addColumn(items, items.consumeQty);
            await m.addColumn(items, items.consumeUnit);
          }
          if (from < 25) {
            // Phase 7.1 — per-item min-stock + preferred shop.
            await m.addColumn(items, items.minStockQuantity);
            await m.addColumn(items, items.minStockUnit);
            await m.addColumn(items, items.preferredShopId);
            await m.addColumn(itemGroups, itemGroups.preferredShopId);
          }
          if (from < 26) {
            // Phase 7.2 — custom shopping list entries.
            await m.createTable(customShoppingItems);
          }
          if (from < 27) {
            // Phase 7.3 — item relations (Obsidian-style bidirectional links).
            await m.createTable(itemRelations);
          }
          if (from < 28) {
            // Sprint B — templates, custom properties, product type definitions.
            await m.createTable(itemTemplates);
            await m.createTable(templateFields);
            await m.createTable(itemPropertyValues);
            await m.createTable(productTypeDefinitions);
            await m.addColumn(items, items.templateId);
            await _seedProductTypeDefinitions();
            await _seedBuiltInTemplates();
          }
          if (from < 29) {
            // Sprint C — task priority column.
            await m.addColumn(tasks, tasks.priority);
          }
          if (from < 32) {
            // Sprint G — Tasks: parentId (subtasks) + linkedItemId (item link).
            await m.addColumn(tasks, tasks.parentId);
            await m.addColumn(tasks, tasks.linkedItemId);
          }
          if (from < 31) {
            // Sprint F — PreparedDishes, MealRelations, StandardMeals freeze fields.
            await m.addColumn(standardMeals, standardMeals.frozenShelfMonths);
            await m.addColumn(standardMeals, standardMeals.thawedShelfDays);
            await m.addColumn(
                standardMeals, standardMeals.defaultFreezeLocationId);
            await m.createTable(preparedDishes);
            await m.createTable(mealRelations);
          }
          if (from < 30) {
            // Sprint D — openedLocationId + taraWeightG on items.
            await m.addColumn(items, items.openedLocationId);
            await m.addColumn(items, items.taraWeightG);
          }
          if (from < 33) {
            // Sprint H — entity photos (general photo attachments).
            await m.createTable(entityPhotos);
          }
          if (from < 34) {
            // Sprint I — item link on custom shopping list entries.
            await m.addColumn(customShoppingItems, customShoppingItems.itemId);
          }
          if (from < 35) {
            // Phase 7.x — extended exercise details + workout plans.
            await m.addColumn(exercises, exercises.muscleGroupsSecondary);
            await m.addColumn(exercises, exercises.difficulty);
            await m.addColumn(exercises, exercises.instructions);
            await m.addColumn(exercises, exercises.videoUrl);
            await m.addColumn(exercises, exercises.caloriesPerMinute);
            await m.addColumn(exercises, exercises.tips);
            await m.addColumn(workouts, workouts.planId);
            await m.createTable(workoutPlans);
            await m.createTable(workoutPlanExercises);
          }
          if (from < 36) {
            // Configurable workout frequency goal.
            await m.addColumn(userProfile, userProfile.workoutsPerWeekGoal);
          }
          if (from < 37) {
            // Sprint E — isStaple flag + purchaseUnit/purchaseQty for pack-size shopping.
            await m.addColumn(items, items.isStaple);
            await m.addColumn(items, items.purchaseUnit);
            await m.addColumn(items, items.purchaseQty);
          }
          if (from < 41) {
            await m.addColumn(items, items.healthFactor);
          }
          if (from < 40) {
            await m.addColumn(workoutPlans, workoutPlans.notes);
          }
          if (from < 39) {
            // Expiry type + shelf-life-days for auto-calculated MHD on stock booking.
            await m.addColumn(items, items.expiryType);
            await m.addColumn(items, items.shelfLifeDays);
          }
          if (from < 38) {
            // Sprint E — fitness ratings, wiki, timer, template plans.
            await m.addColumn(exercises, exercises.shortDescription);
            await m.addColumn(exercises, exercises.isFavorite);
            await m.addColumn(exercises, exercises.starRating);
            await m.addColumn(exercises, exercises.thumbRating);
            await m.addColumn(workoutPlans, workoutPlans.isFavorite);
            await m.addColumn(workoutPlans, workoutPlans.starRating);
            await m.addColumn(workoutPlans, workoutPlans.thumbRating);
            await m.addColumn(workouts, workouts.timerStartedAt);
            // dayOfWeek becomes nullable: recreate table
            await customStatement('PRAGMA foreign_keys = OFF');
            await transaction(() async {
              await m.alterTable(TableMigration(workoutPlanExercises));
            });
            await customStatement('PRAGMA foreign_keys = ON');
          }
          if (from < 19) {
            // Phase 6.9 — ratings, consumption reasons, diary thumbs.
            await m.addColumn(items, items.starRating);
            await m.addColumn(items, items.isFavorite);
            await m.addColumn(items, items.isTrashed);
            await m.addColumn(recipes, recipes.starRating);
            await m.addColumn(recipes, recipes.isFavorite);
            await m.addColumn(recipes, recipes.isTrashed);
            await m.addColumn(standardMeals, standardMeals.starRating);
            await m.addColumn(standardMeals, standardMeals.isFavorite);
            await m.addColumn(standardMeals, standardMeals.isTrashed);
            await m.addColumn(itemEvents, itemEvents.consumptionReason);
            await m.addColumn(itemEvents, itemEvents.thumbRating);
            await m.addColumn(nutritionLogs, nutritionLogs.thumbRating);
            await m.addColumn(nutritionLogs, nutritionLogs.inventoryDeducted);
          }
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
          await customStatement('PRAGMA journal_mode = WAL');
        },
      );

  static QueryExecutor _openDb(String vaultPath, String? encryptionKey) {
    final dbFile = File(p.join(vaultPath, 'lifeos.db'));
    return NativeDatabase.createInBackground(
      dbFile,
      isolateSetup: () async {
        // Re-register the SQLCipher loader inside the Drift background isolate
        // so the encrypted `libsqlite3` is used for actual queries.
        SqlCipherLoader.registerOpenOverride();
      },
      setup: (rawDb) {
        if (encryptionKey != null && encryptionKey.isNotEmpty) {
          // PRAGMA key must be the very first statement — it unlocks the DB.
          // Quotes inside the key would break the literal; the keys we generate
          // are hex-only / PBKDF2-hex so this is safe.
          rawDb.execute("PRAGMA key = '$encryptionKey'");
        }
      },
    );
  }

  // ── Items ──────────────────────────────────────────────────────────────────

  Future<List<Item>> allItems() => select(items).get();

  Stream<List<Item>> watchAllItems() =>
      (select(items)
            ..orderBy([(i) => OrderingTerm.asc(i.name)])
            ..limit(1000))
          .watch();

  Stream<List<Item>> watchItemsByCategory(String categoryId) =>
      (select(items)
            ..where((i) => i.categoryId.equals(categoryId))
            ..orderBy([(i) => OrderingTerm.asc(i.name)])
            ..limit(1000))
          .watch();

  Future<Item?> itemById(String id) =>
      (select(items)..where((i) => i.id.equals(id))).getSingleOrNull();

  Stream<Item?> watchItemById(String id) =>
      (select(items)..where((i) => i.id.equals(id))).watchSingleOrNull();

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
          ..where((i) => i.name.lower().like(like) | i.brand.lower().like(like))
          ..limit(50))
        .watch();
  }

  // ── Inventory ──────────────────────────────────────────────────────────────

  Stream<List<InventoryEntry>> watchInventoryForItem(String itemId) =>
      (select(inventoryEntries)..where((e) => e.itemId.equals(itemId))).watch();

  /// Streams every inventory entry with a non-null expiry date, joined with
  /// its [Item] so callers get the display name in one query. Used by the
  /// notification scheduler to rebuild the zoned-alert list on every change.
  Stream<List<({InventoryEntry entry, Item item})>> watchExpirableInventory() {
    final query = select(inventoryEntries).join([
      innerJoin(items, items.id.equalsExp(inventoryEntries.itemId)),
    ])..where(inventoryEntries.expiryDate.isNotNull());
    return query.watch().map(
          (rows) => rows
              .map((r) => (
                    entry: r.readTable(inventoryEntries),
                    item: r.readTable(items),
                  ))
              .toList(),
        );
  }

  Future<List<InventoryEntry>> expiringWithin(int days) {
    final cutoff = DateTime.now().add(Duration(days: days));
    return (select(inventoryEntries)
          ..where((e) =>
              e.expiryDate.isNotNull() &
              e.expiryDate.isSmallerOrEqualValue(cutoff))
          ..orderBy([(e) => OrderingTerm.asc(e.expiryDate)]))
        .get();
  }

  /// Streams ALL inventory entries joined with their item, for the shelf-life
  /// overview screen. Includes entries without an expiry date so the user can
  /// also set `openedAt` on those. Sorting by effective expiry is done in Dart
  /// (effective = min(expiryDate, openedAt + daysAfterOpening)).
  Stream<List<({InventoryEntry entry, Item item})>> watchShelfLife() {
    final query = select(inventoryEntries).join([
      innerJoin(items, items.id.equalsExp(inventoryEntries.itemId)),
    ])
      // Only fetch entries that actually have shelf-life data to sort on.
      ..where(
        inventoryEntries.expiryDate.isNotNull() |
            inventoryEntries.openedAt.isNotNull(),
      )
      ..orderBy([OrderingTerm.asc(inventoryEntries.expiryDate)]);
    return query.watch().map(
          (rows) => rows
              .map((r) => (
                    entry: r.readTable(inventoryEntries),
                    item: r.readTable(items),
                  ))
              .toList(),
        );
  }

  Future<void> setInventoryOpenedAt(String entryId, DateTime? openedAt) =>
      (update(inventoryEntries)..where((e) => e.id.equals(entryId))).write(
        InventoryEntriesCompanion(openedAt: Value(openedAt)),
      );

  Future<void> batchSetExpiryDate(List<String> ids, DateTime? date) =>
      transaction(() async {
        for (final id in ids) {
          await (update(inventoryEntries)..where((e) => e.id.equals(id)))
              .write(InventoryEntriesCompanion(expiryDate: Value(date)));
        }
      });

  Future<void> batchDeleteEntries(List<String> ids) =>
      transaction(() async {
        for (final id in ids) {
          await (delete(itemStates)
                ..where((s) => s.inventoryEntryId.equals(id)))
              .go();
          await (delete(inventoryEntries)..where((e) => e.id.equals(id))).go();
        }
      });

  /// Undo for freshly booked purchases: removes entries, states AND the
  /// purchase events — so an accidental booking leaves no trace in the
  /// price history or budget statistics.
  Future<void> undoPurchases(List<String> entryIds) =>
      transaction(() async {
        for (final id in entryIds) {
          await (delete(itemStates)
                ..where((s) => s.inventoryEntryId.equals(id)))
              .go();
          await (delete(inventoryEntries)..where((e) => e.id.equals(id))).go();
          await (delete(itemEvents)
                ..where((e) =>
                    e.inventoryEntryId.equals(id) & e.type.equals('purchase')))
              .go();
        }
      });

  /// Returns all inventory entries for an item, sorted by expiry date (FIFO:
  /// consume soonest-expiring first; entries without expiry date come last).
  Future<List<InventoryEntry>> inventoryEntriesForItem(String itemId) =>
      (select(inventoryEntries)
            ..where((e) => e.itemId.equals(itemId))
            ..orderBy([
              (e) => OrderingTerm(
                    expression: e.expiryDate,
                    nulls: NullsOrder.last,
                  ),
            ]))
          .get();

  /// Streams non-expired item states. Used for stock badges and min-stock
  /// checks so that entries past their expiry date don't inflate the count.
  Stream<List<ItemState>> watchValidItemStates() {
    final today = DateTime.now();
    return (select(itemStates)
          ..where((s) =>
              s.expiryDate.isNull() |
              s.expiryDate.isBiggerOrEqualValue(today)))
        .watch();
  }

  // ── Item ratings ──────────────────────────────────────────────────────────

  Future<void> setItemRating(
    String id, {
    required int? starRating,
    required bool isFavorite,
    required bool isTrashed,
  }) =>
      (update(items)..where((i) => i.id.equals(id))).write(
        ItemsCompanion(
          starRating: Value(starRating),
          isFavorite: Value(isFavorite),
          isTrashed: Value(isTrashed),
        ),
      );

  Future<void> setRecipeRating(
    String id, {
    required int? starRating,
    required bool isFavorite,
    required bool isTrashed,
  }) =>
      (update(recipes)..where((r) => r.id.equals(id))).write(
        RecipesCompanion(
          starRating: Value(starRating),
          isFavorite: Value(isFavorite),
          isTrashed: Value(isTrashed),
        ),
      );

  Future<void> setMealRating(
    String id, {
    required int? starRating,
    required bool isFavorite,
    required bool isTrashed,
  }) =>
      (update(standardMeals)..where((m) => m.id.equals(id))).write(
        StandardMealsCompanion(
          starRating: Value(starRating),
          isFavorite: Value(isFavorite),
          isTrashed: Value(isTrashed),
        ),
      );

  /// Returns cumulative thumbs-up / thumbs-down count for a given item
  /// by aggregating over nutrition_logs entries referencing that item.
  Future<({int up, int down, int total})> getNutritionLogStats(
      String itemId) async {
    final rows = await (select(nutritionLogs)
          ..where((l) => l.itemId.equals(itemId)))
        .get();
    final up = rows.where((l) => l.thumbRating == 'up').length;
    final down = rows.where((l) => l.thumbRating == 'down').length;
    return (up: up, down: down, total: rows.length);
  }

  // ── Nutrition log rating helpers ──────────────────────────────────────────

  Future<void> setNutritionLogThumb(String id, String? thumbRating) =>
      (update(nutritionLogs)..where((l) => l.id.equals(id))).write(
        NutritionLogsCompanion(thumbRating: Value(thumbRating)),
      );

  Future<void> setNutritionLogDeducted(String id, bool deducted) =>
      (update(nutritionLogs)..where((l) => l.id.equals(id))).write(
        NutritionLogsCompanion(inventoryDeducted: Value(deducted)),
      );

  Future<void> insertInventoryEntry(InventoryEntriesCompanion entry) =>
      into(inventoryEntries).insert(entry);

  Future<void> updateInventoryEntry(InventoryEntriesCompanion entry) =>
      (update(inventoryEntries)..where((e) => e.id.equals(entry.id.value)))
          .write(entry);

  Future<void> deleteInventoryEntry(String id) =>
      (delete(inventoryEntries)..where((e) => e.id.equals(id))).go();

  /// Changes state of an inventory entry and writes a state_change event.
  Future<void> updateEntryState(
    String entryId,
    String itemId, {
    required String fromState,
    required String newState,
    DateTime? frozenAt,
    DateTime? thawedAt,
  }) =>
      transaction(() async {
        await (update(inventoryEntries)..where((e) => e.id.equals(entryId)))
            .write(InventoryEntriesCompanion(
          state: Value(newState),
          frozenAt: Value(frozenAt),
          thawedAt: Value(thawedAt),
        ));
        await into(itemEvents).insert(ItemEventsCompanion.insert(
          id: _uuid.v4(),
          type: 'state_change',
          itemId: itemId,
          inventoryEntryId: Value(entryId),
          fromState: Value(fromState),
          toState: Value(newState),
          deviceId: 'system',
        ));
      });

  /// Marks an entry as opened; if the item has an openedLocationId that differs
  /// from the current location, auto-relocates the entry.
  Future<void> openEntry(String entryId, String itemId) async {
    final entry = await (select(inventoryEntries)
          ..where((e) => e.id.equals(entryId)))
        .getSingleOrNull();
    final item = await (select(items)
          ..where((i) => i.id.equals(itemId)))
        .getSingleOrNull();
    if (entry == null || item == null) return;

    final now = DateTime.now();
    final targetLocation = item.openedLocationId;

    await transaction(() async {
      await (update(inventoryEntries)..where((e) => e.id.equals(entryId)))
          .write(InventoryEntriesCompanion(
        openedAt: Value(now),
        locationId: targetLocation != null
            ? Value(targetLocation)
            : const Value.absent(),
      ));
      await into(itemEvents).insert(ItemEventsCompanion.insert(
        id: _uuid.v4(),
        type: 'opened',
        itemId: itemId,
        inventoryEntryId: Value(entryId),
        deviceId: 'system',
      ));
      // Write relocation event if location changed
      if (targetLocation != null && targetLocation != entry.locationId) {
        await into(itemEvents).insert(ItemEventsCompanion.insert(
          id: _uuid.v4(),
          type: 'relocation',
          itemId: itemId,
          inventoryEntryId: Value(entryId),
          fromLocationId: Value(entry.locationId),
          toLocationId: Value(targetLocation),
          deviceId: 'system',
        ));
      }
    });
  }

  /// Average purchase price for an item across all purchase events with a price.
  Stream<double?> watchAvgPrice(String itemId) =>
      customSelect(
        'SELECT AVG(price) AS avg_price FROM item_events '
        'WHERE item_id = ? AND type = ? AND price IS NOT NULL',
        variables: [Variable.withString(itemId), Variable.withString('purchase')],
        readsFrom: {itemEvents},
      ).map((row) => row.read<double?>('avg_price')).watchSingle();

  /// Most recent purchase price for an item (null if no purchase events).
  Future<double?> lastPurchasePrice(String itemId) async {
    final rows = await customSelect(
      'SELECT price FROM item_events '
      'WHERE item_id = ? AND type = ? AND price IS NOT NULL '
      'ORDER BY created_at DESC LIMIT 1',
      variables: [Variable.withString(itemId), Variable.withString('purchase')],
      readsFrom: {itemEvents},
    ).get();
    if (rows.isEmpty) return null;
    return rows.first.read<double?>('price');
  }

  /// Estimated recipe cost: sum of (lastPurchasePrice/100g × amount_in_g)
  /// for all ingredients that have an itemId and a purchase price.
  Future<double?> estimatedRecipeCost(String recipeId) async {
    final ingredients = await (select(recipeIngredients)
          ..where((i) => i.recipeId.equals(recipeId)))
        .get();
    double total = 0;
    bool hasAny = false;
    for (final ing in ingredients) {
      if (ing.itemId == null) continue;
      final pricePerUnit = await lastPurchasePrice(ing.itemId!);
      if (pricePerUnit == null) continue;
      // Use quantity as-is; price stored is per purchase unit, not per gram.
      // Approximation: pricePerUnit * quantity gives rough cost.
      total += pricePerUnit * ing.quantity;
      hasAny = true;
    }
    return hasAny ? total : null;
  }

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

  /// Streams purchase events with a price for a single item (newest first).
  Stream<List<ItemEvent>> watchPurchaseHistory(String itemId) =>
      (select(itemEvents)
            ..where((e) =>
                e.itemId.equals(itemId) &
                e.type.equals('purchase') &
                e.price.isNotNull())
            ..orderBy([(e) => OrderingTerm.desc(e.createdAt)]))
          .watch();

  // ── Item States ────────────────────────────────────────────────────────────

  Future<void> upsertItemState(ItemStatesCompanion entry) =>
      into(itemStates).insertOnConflictUpdate(entry);

  /// Partial update of an existing item_states row keyed by inventoryEntryId.
  /// Use this for follow-up changes (consumption, stocktake) where the state
  /// row already exists — `upsertItemState` would try a full INSERT first and
  /// fail validation if non-null required columns are absent from [patch].
  Future<int> updateItemStateByEntry(
    String inventoryEntryId,
    ItemStatesCompanion patch,
  ) =>
      (update(itemStates)
            ..where((s) => s.inventoryEntryId.equals(inventoryEntryId)))
          .write(patch);

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

  Future<List<Task>> searchTasks(String query) =>
      (select(tasks)
            ..where((t) =>
                t.title.like('%$query%') | t.notes.like('%$query%'))
            ..limit(25))
          .get();

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

  Stream<List<Task>> watchRootTasks() =>
      (select(tasks)
            ..where((t) => t.parentId.isNull())
            ..orderBy([
              (t) => OrderingTerm(expression: t.status, mode: OrderingMode.asc),
              (t) => OrderingTerm(
                  expression: t.dueDate,
                  mode: OrderingMode.asc,
                  nulls: NullsOrder.last),
            ]))
          .watch();

  Stream<List<Task>> watchSubtasks(String parentId) =>
      (select(tasks)
            ..where((t) => t.parentId.equals(parentId))
            ..orderBy([(t) => OrderingTerm(expression: t.status)]))
          .watch();

  Future<void> insertTask(TasksCompanion entry) => into(tasks).insert(entry);

  Future<void> updateTask(TasksCompanion entry) =>
      (update(tasks)..where((t) => t.id.equals(entry.id.value))).write(entry);

  Future<void> deleteTask(String id) =>
      (delete(tasks)..where((t) => t.id.equals(id))).go();

  // ── Automation rules ───────────────────────────────────────────────────────

  Stream<List<AutomationRule>> watchAutomationRules() =>
      (select(automationRules)
            ..orderBy([(r) => OrderingTerm.asc(r.createdAt)]))
          .watch();

  Future<void> insertAutomationRule(AutomationRulesCompanion entry) =>
      into(automationRules).insert(entry);

  Future<void> updateAutomationRule(AutomationRulesCompanion entry) =>
      (update(automationRules)..where((r) => r.id.equals(entry.id.value)))
          .write(entry);

  Future<void> deleteAutomationRule(String id) =>
      (delete(automationRules)..where((r) => r.id.equals(id))).go();

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
      'CREATE INDEX IF NOT EXISTS idx_nutr_logged_at ON nutrition_logs (logged_at)',
      'CREATE INDEX IF NOT EXISTS idx_nutr_meal_type ON nutrition_logs (meal_type_id)',
      // Composite for day-view queries that filter by date and group by meal type.
      'CREATE INDEX IF NOT EXISTS idx_nutr_logged_meal ON nutrition_logs (logged_at, meal_type_id)',
      // Inventory hot-path: state filter (fresh/opened/frozen) and shelf-life calc.
      'CREATE INDEX IF NOT EXISTS idx_inv_state ON inventory_entries (state)',
      'CREATE INDEX IF NOT EXISTS idx_inv_opened_at ON inventory_entries (opened_at)',
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
      (select(recipes)
            ..orderBy([(r) => OrderingTerm.asc(r.name)])
            ..limit(1000))
          .watch();

  Future<Recipe?> recipeById(String id) =>
      (select(recipes)..where((r) => r.id.equals(id))).getSingleOrNull();

  Future<Recipe?> recipeByMealieSlug(String slug) =>
      (select(recipes)..where((r) => r.mealieSlug.equals(slug)))
          .getSingleOrNull();

  Stream<List<Recipe>> searchRecipes(String query) {
    final like = '%${query.toLowerCase()}%';
    return (select(recipes)
          ..where((r) => r.name.lower().like(like))
          ..limit(50))
        .watch();
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
  Future<List<StandardMeal>> searchMeals(String query) {
    final like = '%${query.toLowerCase()}%';
    return (select(standardMeals)..where((m) => m.name.lower().like(like))).get();
  }

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

  // ── Prepared dishes ──────────────────────────────────────────────────────

  Stream<List<PreparedDishe>> watchPreparedDishes() =>
      (select(preparedDishes)
            ..where((d) => d.state.isNotValue('consumed'))
            ..orderBy([(d) => OrderingTerm.asc(d.expiresAt)]))
          .watch();

  Stream<List<PreparedDishe>> watchExpiringPreparedDishes(DateTime threshold) =>
      (select(preparedDishes)
            ..where((d) =>
                d.state.isNotValue('consumed') &
                d.expiresAt.isSmallerOrEqualValue(threshold))
            ..orderBy([(d) => OrderingTerm.asc(d.expiresAt)]))
          .watch();

  Future<void> insertPreparedDishe(PreparedDishesCompanion entry) =>
      into(preparedDishes).insert(entry);

  Future<void> updatePreparedDishe(PreparedDishesCompanion entry) =>
      (update(preparedDishes)..where((d) => d.id.equals(entry.id.value)))
          .write(entry);

  Future<void> deletePreparedDishe(String id) =>
      (delete(preparedDishes)..where((d) => d.id.equals(id))).go();

  // ── Meal relations ────────────────────────────────────────────────────────

  Stream<List<MealRelation>> watchMealRelations(String fromId) =>
      (select(mealRelations)..where((r) => r.fromId.equals(fromId))).watch();

  Future<void> addMealRelation(MealRelationsCompanion entry) =>
      into(mealRelations).insert(entry);

  Future<void> removeMealRelation(String id) =>
      (delete(mealRelations)..where((r) => r.id.equals(id))).go();

  Future<void> removeMealRelationByIds(String fromId, String toId) =>
      (delete(mealRelations)
            ..where((r) =>
                (r.fromId.equals(fromId) & r.toId.equals(toId)) |
                (r.fromId.equals(toId) & r.toId.equals(fromId))))
          .go();

  // ── Inventory entry relocation ────────────────────────────────────────────

  Future<void> updateEntryLocation(String entryId, String? newLocationId) async {
    final entry = await (select(inventoryEntries)
          ..where((e) => e.id.equals(entryId)))
        .getSingleOrNull();
    if (entry == null) return;
    await (update(inventoryEntries)..where((e) => e.id.equals(entryId)))
        .write(InventoryEntriesCompanion(
            locationId: Value(newLocationId)));
    await into(itemEvents).insert(ItemEventsCompanion.insert(
      id: const Uuid().v4(),
      itemId: entry.itemId,
      type: 'relocation',
      deviceId: 'system',
      fromLocationId: Value(entry.locationId),
      toLocationId: Value(newLocationId),
    ));
  }

  // ── Item States (all) ─────────────────────────────────────────────────────

  Stream<List<ItemState>> watchAllItemStates() =>
      (select(itemStates)..limit(2000)).watch();

  /// Streams items that currently have at least one stock entry with quantity > 0.
  Stream<List<Item>> watchItemsWithStock() {
    final query = select(items).join([
      innerJoin(itemStates, itemStates.itemId.equalsExp(items.id),
          useColumns: false),
    ])
      ..where(itemStates.currentQuantity.isBiggerThanValue(0))
      ..groupBy([items.id]);
    return query.watch().map(
          (rows) => rows.map((r) => r.readTable(items)).toList(),
        );
  }

  /// Counts inventory entries whose effective expiry is within [days] days from now.
  Stream<int> watchExpiringWithinDays(int days) {
    final cutoff = DateTime.now().add(Duration(days: days));
    return (select(inventoryEntries)
          ..where((e) =>
              e.expiryDate.isNotNull() &
              e.expiryDate.isSmallerOrEqualValue(cutoff)))
        .watch()
        .map((rows) => rows.length);
  }

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

  Future<void> updateWeightLog(BodyWeightLogsCompanion entry) =>
      (update(bodyWeightLogs)..where((l) => l.id.equals(entry.id.value)))
          .write(entry);

  Future<void> deleteWeightLog(String id) =>
      (delete(bodyWeightLogs)..where((l) => l.id.equals(id))).go();

  /// Newest log first; used to populate the "Aktuelles Gewicht"-Karte.
  Future<BodyWeightLog?> latestWeightLog() => (select(bodyWeightLogs)
        ..orderBy([(l) => OrderingTerm.desc(l.loggedAt)])
        ..limit(1))
      .getSingleOrNull();

  /// Number of distinct calendar days within the given window that have at
  /// least one weight log. Drives the "Erfassungsquote"-Anzeige.
  Future<int> weightLogDaysSince(DateTime since) async {
    final rows = await customSelect(
      "SELECT COUNT(DISTINCT date(logged_at, 'unixepoch')) AS c "
      "FROM body_weight_logs WHERE logged_at >= ?",
      variables: [Variable<DateTime>(since)],
    ).getSingle();
    return rows.read<int>('c');
  }

  // ── Nutrition Logs ─────────────────────────────────────────────────────────

  /// All entries for the calendar day containing [day], ordered by meal-slot
  /// (loggedAt asc so entries appear in time order within each slot).
  Stream<List<NutritionLog>> watchLogsForDay(DateTime day) {
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));
    return (select(nutritionLogs)
          ..where((l) =>
              l.loggedAt.isBiggerOrEqualValue(start) &
              l.loggedAt.isSmallerThanValue(end))
          ..orderBy([(l) => OrderingTerm.asc(l.loggedAt)]))
        .watch();
  }

  Future<List<NutritionLog>> getLogsForRange(DateTime from, DateTime to) =>
      (select(nutritionLogs)
            ..where((l) =>
                l.loggedAt.isBiggerOrEqualValue(from) &
                l.loggedAt.isSmallerThanValue(to))
            ..orderBy([(l) => OrderingTerm.desc(l.loggedAt)]))
          .get();

  Future<void> insertNutritionLog(NutritionLogsCompanion entry) =>
      into(nutritionLogs).insert(entry);

  Future<void> updateNutritionLog(NutritionLogsCompanion entry) =>
      (update(nutritionLogs)..where((l) => l.id.equals(entry.id.value)))
          .write(entry);

  Future<void> deleteNutritionLog(String id) =>
      (delete(nutritionLogs)..where((l) => l.id.equals(id))).go();

  Future<NutritionLog?> getNutritionLogById(String id) =>
      (select(nutritionLogs)..where((l) => l.id.equals(id))).getSingleOrNull();

  /// Most recent distinct food entries (one per food, newest first).
  /// Optionally filtered by [mealTypeId].
  Future<List<NutritionLog>> recentlyLoggedFoods({
    String? mealTypeId,
    int limit = 20,
  }) async {
    final all = await (select(nutritionLogs)
          ..where((l) => mealTypeId != null
              ? l.mealTypeId.equals(mealTypeId)
              : const Constant(true))
          ..orderBy([(l) => OrderingTerm.desc(l.loggedAt)])
          ..limit(500))
        .get();
    final seen = <String>{};
    final result = <NutritionLog>[];
    for (final log in all) {
      final key = log.itemId ?? '${log.productName}|${log.source}';
      if (seen.add(key)) {
        result.add(log);
        if (result.length >= limit) break;
      }
    }
    return result;
  }

  /// Most frequently logged distinct foods (highest count first).
  /// Optionally filtered by [mealTypeId].
  Future<List<NutritionLog>> mostFrequentlyLoggedFoods({
    String? mealTypeId,
    int limit = 20,
  }) async {
    final all = await (select(nutritionLogs)
          ..where((l) => mealTypeId != null
              ? l.mealTypeId.equals(mealTypeId)
              : const Constant(true))
          ..orderBy([(l) => OrderingTerm.desc(l.loggedAt)]))
        .get();
    final counts = <String, int>{};
    final examples = <String, NutritionLog>{};
    for (final log in all) {
      final key = log.itemId ?? '${log.productName}|${log.source}';
      counts[key] = (counts[key] ?? 0) + 1;
      examples.putIfAbsent(key, () => log);
    }
    final keys = counts.keys.toList()
      ..sort((a, b) => counts[b]!.compareTo(counts[a]!));
    return keys.take(limit).map((k) => examples[k]!).toList();
  }

  // ── Water logs ────────────────────────────────────────────────────────────

  Stream<List<WaterLog>> watchWaterLogsForDay(DateTime day) {
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));
    return (select(waterLogs)
          ..where((l) =>
              l.loggedAt.isBiggerOrEqualValue(start) &
              l.loggedAt.isSmallerThanValue(end))
          ..orderBy([(l) => OrderingTerm.asc(l.loggedAt)]))
        .watch();
  }

  Future<void> insertWaterLog(WaterLogsCompanion entry) =>
      into(waterLogs).insert(entry);

  Future<void> deleteWaterLog(String id) =>
      (delete(waterLogs)..where((l) => l.id.equals(id))).go();

  /// Count of nutrition log entries grouped by item.healthFactor for [from]..[to].
  /// Returns {1: healthy, 0: neutral, -1: unhealthy, null: unknown}.
  /// Only entries with an itemId linked to an item with a set healthFactor are counted.
  /// Grams per unit for basic SI weight/volume units. Null for non-weight units.
  static double? _weightUnitToGrams(String unit) => switch (unit.toLowerCase().trim()) {
    'g' || 'gr' || 'gramm' => 1.0,
    'kg' || 'kilogramm' => 1000.0,
    'ml' || 'milliliter' => 1.0,
    'cl' => 10.0,
    'dl' => 100.0,
    'l' || 'liter' => 1000.0,
    _ => null,
  };

  /// €/gram from the most recent purchase event with a weight/volume unit.
  /// Returns null if the item has no priced weight-unit purchase events.
  Future<double?> lastPurchasePricePerGram(String itemId) async {
    final rows = await customSelect(
      'SELECT price, quantity, unit FROM item_events '
      "WHERE item_id = ? AND type = 'purchase' "
      'AND price IS NOT NULL AND price > 0 '
      'AND quantity IS NOT NULL AND quantity > 0 '
      'ORDER BY created_at DESC LIMIT 1',
      variables: [Variable.withString(itemId)],
      readsFrom: {itemEvents},
    ).get();
    if (rows.isEmpty) return null;
    final price = rows.first.read<double?>('price');
    final qty = rows.first.read<double?>('quantity');
    final unit = rows.first.read<String?>('unit');
    if (price == null || qty == null || unit == null) return null;
    final gFactor = _weightUnitToGrams(unit);
    if (gFactor == null) return null;
    return price / (qty * gFactor);
  }

  /// Estimated cost of food logged in nutrition_logs from [from] to [to].
  /// Only counts entries with a weight/volume displayUnit where an item
  /// purchase price per gram is known.
  Future<double?> consumedFoodCostForRange(DateTime from, DateTime to) async {
    final logs = await (select(nutritionLogs)
          ..where((l) =>
              l.loggedAt.isBiggerOrEqualValue(from) &
              l.loggedAt.isSmallerThanValue(to) &
              l.itemId.isNotNull()))
        .get();
    if (logs.isEmpty) return null;

    double total = 0;
    bool hasAny = false;
    final priceCache = <String, double?>{};
    final checked = <String>{};

    for (final log in logs) {
      final itemId = log.itemId;
      if (itemId == null) continue;
      if (_weightUnitToGrams(log.displayUnit) == null) continue;
      if (!checked.contains(itemId)) {
        priceCache[itemId] = await lastPurchasePricePerGram(itemId);
        checked.add(itemId);
      }
      final pricePerGram = priceCache[itemId];
      if (pricePerGram == null) continue;
      total += log.quantityG * pricePerGram;
      hasAny = true;
    }
    return hasAny ? total : null;
  }

  /// Estimated consumed vs. wasted food cost for [year] from item_events.
  /// Only counts consumption events with weight/volume units where a
  /// purchase price per gram is known for the item.
  Future<({double consumed, double wasted})> foodFinancialStatsForYear(int year) async {
    final from = DateTime(year, 1, 1);
    final to = DateTime(year + 1, 1, 1);

    final events = await (select(itemEvents)
          ..where((e) =>
              e.type.equals('consumption') &
              e.createdAt.isBiggerOrEqualValue(from) &
              e.createdAt.isSmallerThanValue(to) &
              e.itemId.isNotNull() &
              e.quantity.isNotNull()))
        .get();

    double consumed = 0, wasted = 0;
    final priceCache = <String, double?>{};
    final checked = <String>{};

    for (final event in events) {
      final itemId = event.itemId;
      final qty = event.quantity;
      final unit = event.unit;
      if (qty == null || unit == null) continue;
      final gFactor = _weightUnitToGrams(unit);
      if (gFactor == null) continue;
      if (!checked.contains(itemId)) {
        priceCache[itemId] = await lastPurchasePricePerGram(itemId);
        checked.add(itemId);
      }
      final pricePerGram = priceCache[itemId];
      if (pricePerGram == null) continue;
      final cost = qty * gFactor * pricePerGram;
      final reason = event.consumptionReason;
      if (reason == 'consumed') {
        consumed += cost;
      } else if (reason == 'expired' || reason == 'discarded') {
        wasted += cost;
      }
    }
    return (consumed: consumed, wasted: wasted);
  }

  Future<Map<int?, int>> healthFactorStats(
      DateTime from, DateTime to) async {
    final logs = await (select(nutritionLogs)
          ..where((l) =>
              l.loggedAt.isBiggerOrEqualValue(from) &
              l.loggedAt.isSmallerThanValue(to)))
        .get();
    final itemIds = logs
        .map((l) => l.itemId)
        .whereType<String>()
        .toSet()
        .toList();
    if (itemIds.isEmpty) return {null: logs.length};

    final linkedItems = await (select(items)
          ..where((i) => i.id.isIn(itemIds)))
        .get();
    final factorById = {for (final i in linkedItems) i.id: i.healthFactor};

    final counts = <int?, int>{};
    for (final log in logs) {
      final factor = log.itemId != null ? factorById[log.itemId] : null;
      counts[factor] = (counts[factor] ?? 0) + 1;
    }
    return counts;
  }

  /// Summed kcal / protein / carbs / fat for the calendar day of [day].
  Future<DailyNutritionTotals> dailyNutritionTotals(DateTime day) async {
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));
    final row = await customSelect(
      'SELECT '
      '  COALESCE(SUM(kcal), 0)      AS kcal, '
      '  COALESCE(SUM(protein_g), 0) AS protein, '
      '  COALESCE(SUM(carbs_g), 0)   AS carbs, '
      '  COALESCE(SUM(fat_g), 0)     AS fat '
      'FROM nutrition_logs '
      'WHERE logged_at >= ? AND logged_at < ?',
      variables: [Variable<DateTime>(start), Variable<DateTime>(end)],
    ).getSingle();
    return DailyNutritionTotals(
      kcal: row.read<double>('kcal'),
      proteinG: row.read<double>('protein'),
      carbsG: row.read<double>('carbs'),
      fatG: row.read<double>('fat'),
    );
  }

  // ── Body Measurements ──────────────────────────────────────────────────────

  Stream<List<BodyMeasurement>> watchBodyMeasurements({int limit = 90}) =>
      (select(bodyMeasurements)
            ..orderBy([(m) => OrderingTerm.desc(m.loggedAt)])
            ..limit(limit))
          .watch();

  Future<void> insertBodyMeasurement(BodyMeasurementsCompanion entry) =>
      into(bodyMeasurements).insert(entry);

  Future<void> updateBodyMeasurement(BodyMeasurementsCompanion entry) =>
      (update(bodyMeasurements)..where((m) => m.id.equals(entry.id.value)))
          .write(entry);

  Future<void> deleteBodyMeasurement(String id) =>
      (delete(bodyMeasurements)..where((m) => m.id.equals(id))).go();

  Future<BodyMeasurement?> latestBodyMeasurement() =>
      (select(bodyMeasurements)
            ..orderBy([(m) => OrderingTerm.desc(m.loggedAt)])
            ..limit(1))
          .getSingleOrNull();

  // ── User Profile (singleton) ───────────────────────────────────────────────

  Stream<UserProfileData?> watchUserProfile() =>
      (select(userProfile)..where((p) => p.id.equals(1)))
          .watchSingleOrNull();

  Future<UserProfileData?> getUserProfile() =>
      (select(userProfile)..where((p) => p.id.equals(1)))
          .getSingleOrNull();

  Future<void> upsertUserProfile(UserProfileCompanion entry) async {
    // Force the singleton id, regardless of what the caller passed in.
    final fixed = entry.copyWith(id: const Value(1));
    await into(userProfile).insertOnConflictUpdate(fixed);
  }

  // ── Recipe tags ────────────────────────────────────────────────────────────

  static const _uuid = Uuid();

  /// Reads all tag names currently linked to a recipe, sorted alphabetically.
  Future<List<String>> tagsForRecipe(String recipeId) async {
    final query = select(recipeTags).join([
      innerJoin(
        tagDefinitions,
        tagDefinitions.id.equalsExp(recipeTags.tagId),
      ),
    ])
      ..where(recipeTags.recipeId.equals(recipeId))
      ..orderBy([OrderingTerm.asc(tagDefinitions.name)]);
    final rows = await query.get();
    return rows.map((r) => r.readTable(tagDefinitions).name).toList();
  }

  /// Replaces the tag set for a recipe. Tag names are resolved against
  /// [tagDefinitions] in the `recipe` scope — missing definitions are created
  /// on the fly. Removes any link not in [tagNames].
  Future<void> setTagsForRecipe(
    String recipeId,
    List<String> tagNames,
  ) async {
    final cleaned = tagNames
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toSet()
        .toList();

    await transaction(() async {
      await (delete(recipeTags)..where((t) => t.recipeId.equals(recipeId)))
          .go();
      for (final name in cleaned) {
        final tagId = await _ensureRecipeTag(name);
        // Insert-or-ignore: case-insensitive resolution above can map two
        // inputs ('foo', 'Foo') to the same tag id. The junction key is
        // (recipe_id, tag_id), so we keep duplicates harmless.
        await into(recipeTags).insertOnConflictUpdate(
          RecipeTagsCompanion.insert(recipeId: recipeId, tagId: tagId),
        );
      }
    });
  }

  /// Finds or creates a [TagDefinitions] row for the recipe scope with the
  /// given name. Case-insensitive match on the name.
  Future<String> _ensureRecipeTag(String name) async {
    final existing = await (select(tagDefinitions)
          ..where((t) =>
              t.categoryId.equals(ItemCategory.recipe) &
              t.name.lower().equals(name.toLowerCase())))
        .getSingleOrNull();
    if (existing != null) return existing.id;
    final id = _uuid.v4();
    await into(tagDefinitions).insert(TagDefinitionsCompanion.insert(
      id: id,
      name: name,
      categoryId: ItemCategory.recipe,
    ));
    return id;
  }

  /// v10 migration: pulls legacy `recipes.tags` JSON strings via raw SQL and
  /// materialises them into [tagDefinitions] + [recipeTags]. Safe to run
  /// multiple times — [_ensureRecipeTag] is idempotent.
  Future<void> _migrateRecipeTagsJson() async {
    final rows = await customSelect(
      'SELECT id, tags FROM recipes WHERE tags IS NOT NULL',
    ).get();
    for (final row in rows) {
      final recipeId = row.read<String>('id');
      final raw = row.read<String?>('tags');
      if (raw == null || raw.isEmpty) continue;
      List<dynamic> decoded;
      try {
        decoded = jsonDecode(raw) as List<dynamic>;
      } catch (_) {
        continue;
      }
      final names = decoded
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toSet();
      for (final name in names) {
        final tagId = await _ensureRecipeTag(name);
        await into(recipeTags).insertOnConflictUpdate(
          RecipeTagsCompanion.insert(recipeId: recipeId, tagId: tagId),
        );
      }
    }
  }

  // ── Item tags ───────────────────────────────────────────────────────────────

  Stream<Set<String>> watchItemIdsByTag(String tagId) {
    return (select(itemTags)..where((t) => t.tagId.equals(tagId)))
        .watch()
        .map((rows) => rows.map((r) => r.itemId).toSet());
  }

  Stream<List<TagDefinition>> watchTagsForItem(String itemId) {
    final query = select(itemTags).join([
      innerJoin(
        tagDefinitions,
        tagDefinitions.id.equalsExp(itemTags.tagId),
      ),
    ])
      ..where(itemTags.itemId.equals(itemId))
      ..orderBy([OrderingTerm.asc(tagDefinitions.name)]);
    return query.watch().map(
          (rows) => rows.map((r) => r.readTable(tagDefinitions)).toList());
  }

  Stream<List<TagDefinition>> watchTagDefinitionsForCategory(String categoryId) {
    return (select(tagDefinitions)
          ..where((t) => t.categoryId.equals(categoryId))
          ..orderBy([(t) => OrderingTerm.asc(t.name)]))
        .watch();
  }

  Future<void> setTagsForItem(
    String itemId,
    String categoryId,
    List<String> tagNames,
  ) async {
    final cleaned = tagNames
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toSet()
        .toList();

    await transaction(() async {
      await (delete(itemTags)..where((t) => t.itemId.equals(itemId))).go();
      for (final name in cleaned) {
        final tagId = await _ensureItemTag(name, categoryId);
        await into(itemTags).insertOnConflictUpdate(
          ItemTagsCompanion.insert(itemId: itemId, tagId: tagId),
        );
      }
    });
  }

  Future<String> _ensureItemTag(String name, String categoryId) async {
    final existing = await (select(tagDefinitions)
          ..where((t) =>
              t.categoryId.equals(categoryId) &
              t.name.lower().equals(name.toLowerCase())))
        .getSingleOrNull();
    if (existing != null) return existing.id;
    final id = _uuid.v4();
    await into(tagDefinitions).insert(TagDefinitionsCompanion.insert(
      id: id,
      name: name,
      categoryId: categoryId,
    ));
    return id;
  }

  // ── Item relations ──────────────────────────────────────────────────────────

  Future<List<({ItemRelation relation, Item peer})>> relationsForItem(
      String itemId) async {
    final fromRows = await (select(itemRelations).join([
      innerJoin(items, items.id.equalsExp(itemRelations.toItemId)),
    ])
          ..where(itemRelations.fromItemId.equals(itemId)))
        .get();
    final toRows = await (select(itemRelations).join([
      innerJoin(items, items.id.equalsExp(itemRelations.fromItemId)),
    ])
          ..where(itemRelations.toItemId.equals(itemId)))
        .get();

    return [
      ...fromRows.map((r) => (
            relation: r.readTable(itemRelations),
            peer: r.readTable(items),
          )),
      ...toRows.map((r) => (
            relation: r.readTable(itemRelations),
            peer: r.readTable(items),
          )),
    ];
  }

  Future<void> addItemRelation(String fromId, String toId,
      {String? notes}) async {
    await into(itemRelations).insert(ItemRelationsCompanion.insert(
      id: _uuid.v4(),
      fromItemId: fromId,
      toItemId: toId,
      notes: Value(notes),
    ));
  }

  Future<void> deleteItemRelation(String relationId) async {
    await (delete(itemRelations)
          ..where((r) => r.id.equals(relationId)))
        .go();
  }

  Future<void> updateItemRelationNotes(String id, String? notes) async {
    await (update(itemRelations)..where((r) => r.id.equals(id)))
        .write(ItemRelationsCompanion(notes: Value(notes)));
  }

  // ── Recipe nutrition ────────────────────────────────────────────────────────

  /// Sums all ingredient contributions to compute the total nutrition for a
  /// recipe (not per-100g — total for the whole recipe). Only ingredients
  /// with an [itemId] and a known per-100g value contribute.
  Future<RecipeNutritionData?> computeRecipeNutrition(String recipeId) async {
    final ingredients = await ingredientsForRecipe(recipeId);
    double kcal = 0, protein = 0, carbs = 0, fat = 0, fiber = 0;
    double totalG = 0; // all convertible weight (for portion sizing)
    double nutritionG = 0; // weight only from items with nutrition (for per-100g)
    bool hasAny = false;
    for (final ing in ingredients) {
      if (ing.itemId == null) continue;
      final item = await itemById(ing.itemId!);
      if (item == null) continue;
      final qG = _unitToGrams(ing.quantity, ing.unit,
              servingSizeG: item.servingSizeG) ??
          await _conversionToGrams(ing.unit, ing.quantity, itemId: item.id);
      if (qG == null || qG <= 0) continue;
      totalG += qG;
      if (item.caloriesPer100g != null) {
        kcal += item.caloriesPer100g! * qG / 100;
        nutritionG += qG;
        hasAny = true;
      }
      if (item.proteinPer100g != null) protein += item.proteinPer100g! * qG / 100;
      if (item.carbsPer100g != null) carbs += item.carbsPer100g! * qG / 100;
      if (item.fatPer100g != null) fat += item.fatPer100g! * qG / 100;
      if (item.fiberPer100g != null) fiber += item.fiberPer100g! * qG / 100;
    }
    if (!hasAny && totalG == 0) return null;
    return RecipeNutritionData(
      kcal: kcal,
      proteinG: protein,
      carbsG: carbs,
      fatG: fat,
      fiberG: fiber,
      totalWeightG: totalG,
      nutritionWeightG: nutritionG,
    );
  }

  Future<RecipeNutritionData?> computeMealNutrition(String mealId) async {
    final ingredients = await ingredientsForMeal(mealId);
    double kcal = 0, protein = 0, carbs = 0, fat = 0, fiber = 0;
    double totalG = 0;
    double nutritionG = 0;
    bool hasAny = false;
    for (final ing in ingredients) {
      if (ing.itemId == null) continue;
      final item = await itemById(ing.itemId!);
      if (item == null) continue;
      final qG = _unitToGrams(ing.quantity, ing.unit,
              servingSizeG: item.servingSizeG) ??
          await _conversionToGrams(ing.unit, ing.quantity, itemId: item.id);
      if (qG == null || qG <= 0) continue;
      totalG += qG;
      if (item.caloriesPer100g != null) {
        kcal += item.caloriesPer100g! * qG / 100;
        nutritionG += qG;
        hasAny = true;
      }
      if (item.proteinPer100g != null) protein += item.proteinPer100g! * qG / 100;
      if (item.carbsPer100g != null) carbs += item.carbsPer100g! * qG / 100;
      if (item.fatPer100g != null) fat += item.fatPer100g! * qG / 100;
      if (item.fiberPer100g != null) fiber += item.fiberPer100g! * qG / 100;
    }
    if (!hasAny && totalG == 0) return null;
    return RecipeNutritionData(
      kcal: kcal,
      proteinG: protein,
      carbsG: carbs,
      fatG: fat,
      fiberG: fiber,
      totalWeightG: totalG,
      nutritionWeightG: nutritionG,
    );
  }

  /// Looks up a unit conversion to grams/ml in the DB.
  /// Checks item-scoped conversions first, then global. Handles duplicates and
  /// one-hop conversions (e.g. Stück → Portion → g via _unitToGrams).
  Future<double?> _conversionToGrams(String unit, double qty,
      {String? itemId}) async {
    final u = unit.toLowerCase().trim();

    // Collect item-scoped then global conversions
    List<UnitConversion> candidates = [];
    if (itemId != null) {
      final rows = await (select(unitConversions)
            ..where((c) =>
                c.scope.equals('item') & c.scopeId.equals(itemId)))
          .get();
      candidates.addAll(rows);
    }
    final global = await (select(unitConversions)
          ..where((c) => c.scope.equals('global')))
        .get();
    candidates.addAll(global);

    // Filter to conversions that start with our unit
    final matching =
        candidates.where((c) => c.fromUnit.toLowerCase().trim() == u).toList();

    // Pass 1: direct → g/ml/kg/l (normalise to grams)
    for (final c in matching) {
      final to = c.toUnit.toLowerCase().trim();
      final factor = switch (to) {
        'g' || 'gramm' || 'gr' => 1.0,
        'ml' || 'milliliter' => 1.0,
        'kg' || 'kilogramm' => 1000.0,
        'l' || 'liter' => 1000.0,
        'dl' => 100.0,
        'cl' => 10.0,
        'mg' => 0.001,
        _ => null,
      };
      if (factor != null) return qty * c.factor * factor;
    }

    // Pass 2: one-hop via _unitToGrams (e.g. Stück → Portion, then Portion → g)
    for (final c in matching) {
      final intermediate = _unitToGrams(qty * c.factor, c.toUnit);
      if (intermediate != null) return intermediate;
    }

    return null;
  }

  /// Converts [qty] in [unit] to a gram-equivalent value.
  /// For piece/container units (Stück, Portion, Scheibe, …) [servingSizeG] is
  /// used: 1 Stück = servingSizeG grams. Returns null when conversion is
  /// impossible (unknown unit AND no serving size).
  static double? _unitToGrams(double qty, String unit,
      {double? servingSizeG}) {
    return switch (unit.toLowerCase().trim()) {
      'g' || 'gramm' || 'gr' => qty,
      'ml' || 'milliliter' => qty,
      'kg' || 'kilogramm' => qty * 1000,
      'l' || 'liter' => qty * 1000,
      'dl' => qty * 100,
      'cl' => qty * 10,
      'mg' => qty * 0.001,
      'el' || 'esslöffel' => qty * 15,
      'tl' || 'teelöffel' => qty * 5,
      'tasse' || 'cup' => qty * 237,
      // Piece/container units: 1 unit ≈ servingSizeG grams
      _ when servingSizeG != null => qty * servingSizeG,
      _ => null,
    };
  }

  // ── Meal Plan ─────────────────────────────────────────────────────────────

  Stream<List<MealPlanEntry>> watchPlanEntriesForRange(
      DateTime from, DateTime to) =>
      (select(mealPlanEntries)
            ..where((e) =>
                e.date.isBiggerOrEqualValue(from) &
                e.date.isSmallerThanValue(to))
            ..orderBy([
              (e) => OrderingTerm.asc(e.date),
              (e) => OrderingTerm.asc(e.createdAt),
            ]))
          .watch();

  Future<void> insertMealPlanEntry(MealPlanEntriesCompanion entry) =>
      into(mealPlanEntries).insert(entry);

  Future<void> deleteMealPlanEntry(String id) =>
      (delete(mealPlanEntries)..where((e) => e.id.equals(id))).go();

  Future<void> updateMealPlanEntry(MealPlanEntriesCompanion entry) =>
      (update(mealPlanEntries)
            ..where((e) => e.id.equals(entry.id.value)))
          .write(entry);

  /// Returns aggregated ingredient needs for all plan entries in a date range.
  /// Recipe + meal entries expand into their ingredients;
  /// item entries contribute themselves (quantity = servings).
  Future<List<({String? itemId, String name, double qty, String unit})>>
      getPlanIngredientNeeds(DateTime from, DateTime to) async {
    final entries = await (select(mealPlanEntries)
          ..where((e) =>
              e.date.isBiggerOrEqualValue(from) &
              e.date.isSmallerThanValue(to)))
        .get();

    final needs = <String, ({String? itemId, String name, double qty, String unit})>{};

    void addNeed(String key, String? itemId, String name, double qty, String unit) {
      final existing = needs[key];
      if (existing != null) {
        needs[key] = (itemId: itemId, name: name, qty: existing.qty + qty, unit: unit);
      } else {
        needs[key] = (itemId: itemId, name: name, qty: qty, unit: unit);
      }
    }

    for (final e in entries) {
      final s = e.servings;
      if (e.recipeId != null) {
        final ings = await ingredientsForRecipe(e.recipeId!);
        for (final ing in ings) {
          if (ing.itemId == null) continue;
          addNeed(ing.itemId!, ing.itemId, ing.name, ing.quantity * s, ing.unit);
        }
      } else if (e.dishId != null) {
        final ings = await ingredientsForMeal(e.dishId!);
        for (final ing in ings) {
          if (ing.itemId == null) continue;
          addNeed(ing.itemId!, ing.itemId, ing.name, ing.quantity * s, ing.unit);
        }
      } else if (e.itemId != null) {
        addNeed(e.itemId!, e.itemId, e.entryName, s, 'Portion');
      }
    }

    return needs.values.toList();
  }

  // ── Custom Categories ──────────────────────────────────────────────────────

  Stream<List<CategoryDefinition>> watchAllCategories() =>
      (select(categoryDefinitions)
            ..orderBy([
              (c) => OrderingTerm.asc(c.sortOrder),
              (c) => OrderingTerm.asc(c.name),
            ]))
          .watch();

  Future<void> insertCategory(CategoryDefinitionsCompanion entry) =>
      into(categoryDefinitions).insert(entry);

  Future<void> updateCategory(CategoryDefinitionsCompanion entry) =>
      (update(categoryDefinitions)
            ..where((c) => c.id.equals(entry.id.value)))
          .write(entry);

  Future<void> deleteCategory(String id) =>
      (delete(categoryDefinitions)..where((c) => c.id.equals(id))).go();
}

/// Aggregated nutritional totals for a single calendar day.
class DailyNutritionTotals {
  final double kcal;
  final double proteinG;
  final double carbsG;
  final double fatG;
  const DailyNutritionTotals({
    required this.kcal,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
  });
}

/// Computed nutrition totals for an entire recipe, derived from its
/// ingredient list.
/// [totalWeightG] — all convertible ingredient weights (used for serving-size
///   estimation, e.g. totalWeightG / servings).
/// [nutritionWeightG] — weight of ingredients that have per-100g data (used
///   for per-100g calculations so items without nutrition don't deflate them).
class RecipeNutritionData {
  final double kcal;
  final double proteinG;
  final double carbsG;
  final double fatG;
  final double fiberG;
  final double totalWeightG;
  final double nutritionWeightG;

  const RecipeNutritionData({
    required this.kcal,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
    required this.fiberG,
    required this.totalWeightG,
    required this.nutritionWeightG,
  });

  double? get caloriesPer100g =>
      nutritionWeightG > 0 ? kcal / nutritionWeightG * 100 : null;
  double? get proteinPer100g =>
      nutritionWeightG > 0 ? proteinG / nutritionWeightG * 100 : null;
  double? get carbsPer100g =>
      nutritionWeightG > 0 ? carbsG / nutritionWeightG * 100 : null;
  double? get fatPer100g =>
      nutritionWeightG > 0 ? fatG / nutritionWeightG * 100 : null;
  double? get fiberPer100g =>
      nutritionWeightG > 0 ? fiberG / nutritionWeightG * 100 : null;
}

// ── Fitness ───────────────────────────────────────────────────────────────────

extension FitnessDao on AppDatabase {
  // Exercises
  Stream<List<Exercise>> watchAllExercises() =>
      (select(exercises)..orderBy([(e) => OrderingTerm.asc(e.name)])).watch();

  Future<List<Exercise>> searchExercises(String query) =>
      (select(exercises)
            ..where((e) =>
                e.name.like('%$query%') |
                e.category.like('%$query%'))
            ..orderBy([(e) => OrderingTerm.asc(e.name)]))
          .get();

  Future<void> insertExercise(ExercisesCompanion entry) =>
      into(exercises).insertOnConflictUpdate(entry);

  Future<void> deleteExercise(String id) =>
      (delete(exercises)..where((e) => e.id.equals(id))).go();

  // Workouts
  Stream<List<Workout>> watchAllWorkouts() =>
      (select(workouts)
            ..orderBy([(w) => OrderingTerm.desc(w.startedAt)]))
          .watch();

  Future<void> insertWorkout(WorkoutsCompanion entry) =>
      into(workouts).insert(entry);

  Future<void> updateWorkout(WorkoutsCompanion entry) =>
      (update(workouts)..where((w) => w.id.equals(entry.id.value)))
          .write(entry);

  Future<void> deleteWorkout(String id) =>
      (delete(workouts)..where((w) => w.id.equals(id))).go();

  // WorkoutSets
  Stream<List<WorkoutSet>> watchSetsForWorkout(String workoutId) =>
      (select(workoutSets)
            ..where((s) => s.workoutId.equals(workoutId))
            ..orderBy([
              (s) => OrderingTerm.asc(s.exerciseId),
              (s) => OrderingTerm.asc(s.setNumber),
            ]))
          .watch();

  Future<void> insertWorkoutSet(WorkoutSetsCompanion entry) =>
      into(workoutSets).insert(entry);

  Future<void> updateWorkoutSet(WorkoutSetsCompanion entry) =>
      (update(workoutSets)..where((s) => s.id.equals(entry.id.value)))
          .write(entry);

  Future<void> deleteWorkoutSet(String id) =>
      (delete(workoutSets)..where((s) => s.id.equals(id))).go();

  Future<void> deleteAllSetsForWorkout(String workoutId) =>
      (delete(workoutSets)
            ..where((s) => s.workoutId.equals(workoutId)))
          .go();

  // ── Workout Plans ────────────────────────────────────────────────────────

  Stream<List<WorkoutPlan>> watchAllWorkoutPlans() =>
      (select(workoutPlans)
            ..orderBy([(p) => OrderingTerm.asc(p.name)]))
          .watch();

  Future<WorkoutPlan?> workoutPlanById(String id) =>
      (select(workoutPlans)..where((p) => p.id.equals(id))).getSingleOrNull();

  Future<void> insertWorkoutPlan(WorkoutPlansCompanion entry) =>
      into(workoutPlans).insert(entry);

  Future<void> updateWorkoutPlan(WorkoutPlansCompanion entry) =>
      (update(workoutPlans)..where((p) => p.id.equals(entry.id.value)))
          .write(entry);

  Future<void> deleteWorkoutPlan(String id) =>
      (delete(workoutPlans)..where((p) => p.id.equals(id))).go();

  Stream<List<WorkoutPlanExercise>> watchPlanExercises(String planId) =>
      (select(workoutPlanExercises)
            ..where((e) => e.planId.equals(planId))
            ..orderBy([
              (e) => OrderingTerm.asc(e.dayOfWeek),
              (e) => OrderingTerm.asc(e.sortOrder),
            ]))
          .watch();

  Future<void> insertPlanExercise(WorkoutPlanExercisesCompanion entry) =>
      into(workoutPlanExercises).insert(entry);

  Future<void> updatePlanExercise(WorkoutPlanExercisesCompanion entry) =>
      (update(workoutPlanExercises)
            ..where((e) => e.id.equals(entry.id.value)))
          .write(entry);

  Future<void> deletePlanExercise(String id) =>
      (delete(workoutPlanExercises)..where((e) => e.id.equals(id))).go();

  Future<void> deletePlanExercisesForDay(String planId, int dayOfWeek) =>
      (delete(workoutPlanExercises)
            ..where((e) =>
                e.planId.equals(planId) & e.dayOfWeek.equals(dayOfWeek)))
          .go();

  Stream<Workout?> watchWorkoutById(String id) =>
      (select(workouts)..where((w) => w.id.equals(id))).watchSingleOrNull();

  Future<void> setWorkoutTimerStart(String workoutId, DateTime at) =>
      (update(workouts)..where((w) => w.id.equals(workoutId)))
          .write(WorkoutsCompanion(timerStartedAt: Value(at)));

  /// Plan exercises for a specific day PLUS template exercises (dayOfWeek IS NULL).
  Future<List<WorkoutPlanExercise>> planExercisesForDay(
      String planId, int dayOfWeek) =>
      (select(workoutPlanExercises)
            ..where((e) =>
                e.planId.equals(planId) &
                (e.dayOfWeek.equals(dayOfWeek) | e.dayOfWeek.isNull()))
            ..orderBy([
              (e) => OrderingTerm.asc(e.sortOrder),
            ]))
          .get();

  /// Items with isStaple = true that have no inventory stock.
  Stream<List<Item>> watchMissingStapleItems() {
    final stapleStream = (select(items)
          ..where((i) => i.isStaple.equals(true) & i.isTrashed.equals(false))
          ..orderBy([(i) => OrderingTerm.asc(i.name)]))
        .watch();

    return stapleStream.asyncExpand((staples) {
      if (staples.isEmpty) return Stream.value([]);
      final ids = staples.map((i) => i.id).toList();
      return (select(inventoryEntries)
              ..where((e) => e.itemId.isIn(ids)))
          .watch()
          .map((entries) {
        final stockById = <String, double>{};
        for (final e in entries) {
          stockById[e.itemId] = (stockById[e.itemId] ?? 0) + e.quantity;
        }
        return staples.where((i) => (stockById[i.id] ?? 0) <= 0).toList();
      });
    });
  }

  // ── Exercise statistics ─────────────────────────────────────────────────

  /// Best performance for a given exercise (max weight × reps in a single set).
  Future<WorkoutSet?> bestSetForExercise(String exerciseId) async {
    final allSets = await (select(workoutSets)
          ..where((s) => s.exerciseId.equals(exerciseId)))
        .get();
    if (allSets.isEmpty) return null;
    allSets.sort((a, b) {
      final scoreA = (a.weightKg ?? 0) * (a.reps ?? 1);
      final scoreB = (b.weightKg ?? 0) * (b.reps ?? 1);
      return scoreB.compareTo(scoreA);
    });
    return allSets.first;
  }

  /// Volume (sum of weightKg × reps) per workout session for an exercise.
  Future<List<({DateTime date, double volume, int totalSets})>>
      exerciseVolumeHistory(String exerciseId) async {
    final rows = await customSelect(
      '''
      SELECT w.started_at,
             SUM(COALESCE(ws.weight_kg, 0) * COALESCE(ws.reps, 1)) as volume,
             COUNT(ws.id) as total_sets
      FROM workout_sets ws
      JOIN workouts w ON w.id = ws.workout_id
      WHERE ws.exercise_id = ?
      GROUP BY w.id
      ORDER BY w.started_at ASC
      ''',
      variables: [Variable.withString(exerciseId)],
      readsFrom: {workoutSets, workouts},
    ).get();
    return rows
        .map((r) => (
              date: DateTime.fromMillisecondsSinceEpoch(
                  r.read<int>('started_at')),
              volume: r.read<double>('volume'),
              totalSets: r.read<int>('total_sets'),
            ))
        .toList();
  }

  // ── Seed ─────────────────────────────────────────────────────────────────

  Future<void> _seedDefaultExercises() async {
    for (final e in _defaultExercises) {
      final existing = await (select(exercises)
                ..where((ex) => ex.id.equals(e.id)))
            .getSingleOrNull();
      if (existing != null) {
        // Update details for built-in exercises on every open (non-destructive)
        await (update(exercises)..where((ex) => ex.id.equals(e.id))).write(
          ExercisesCompanion(
            instructions: Value(e.instructions),
            difficulty: Value(e.difficulty),
            caloriesPerMinute: Value(e.caloriesPerMinute),
            tips: Value(e.tips),
            muscleGroupsSecondary: Value(e.muscleGroupsSecondary),
          ),
        );
        continue;
      }
      await into(exercises).insert(ExercisesCompanion.insert(
        id: e.id,
        name: e.name,
        category: e.category,
        equipment: Value(e.equipment),
        muscleGroups: Value(e.muscleGroups),
        muscleGroupsSecondary: Value(e.muscleGroupsSecondary),
        difficulty: Value(e.difficulty),
        instructions: Value(e.instructions),
        caloriesPerMinute: Value(e.caloriesPerMinute),
        tips: Value(e.tips),
      ));
    }
  }
}

class _ExSeed {
  final String id;
  final String name;
  final String category;
  final String? equipment;
  final String? muscleGroups;
  final String? muscleGroupsSecondary;
  final String? difficulty;
  final String? instructions;
  final double? caloriesPerMinute;
  final String? tips;
  const _ExSeed(this.id, this.name, this.category, this.equipment,
      this.muscleGroups, this.muscleGroupsSecondary, this.difficulty,
      this.instructions, this.caloriesPerMinute, this.tips);
}

const _defaultExercises = <_ExSeed>[
  // ── Brust ──────────────────────────────────────────────────────────────────
  _ExSeed('ex_bench_bar','Bankdrücken','chest','barbell',
    '["Brust","Trizeps","Schultern"]','["Rumpf"]','intermediate',
    '1. Lege dich flach auf die Bank, Stange über der Brust.\n2. Greife die Stange schulterbreit oder etwas weiter.\n3. Senke die Stange kontrolliert zur Mitte der Brust.\n4. Drücke explosiv nach oben, ohne die Ellbogen zu sperren.',
    5.5,'Halte die Schulterblätter zusammengezogen. Nicht mit dem Rücken Brücke machen.'),
  _ExSeed('ex_bench_db','Kurzhantel Bankdrücken','chest','dumbbell',
    '["Brust","Trizeps"]','["Schultern"]','beginner',
    '1. Setze dich auf die Bank, Kurzhanteln auf den Oberschenkeln.\n2. Schwinge die Hanteln nach oben und lege dich zurück.\n3. Senke die Hanteln seitlich ab, bis die Ellbogen auf Bankhöhe sind.\n4. Drücke beide Hanteln gleichmäßig nach oben.',
    5.0,'Guter Einstieg für Anfänger, da der Bewegungsradius frei wählbar ist.'),
  _ExSeed('ex_incline_bar','Schrägbankdrücken','chest','barbell',
    '["Obere Brust","Trizeps"]','["Schultern"]','intermediate',
    '1. Stelle die Bank auf 30–45° Neigung.\n2. Greife die Stange etwas breiter als schulterbreit.\n3. Senke die Stange zur oberen Brust.\n4. Drücke zurück in die Ausgangsposition.',
    5.5,'Betont die obere Brust. Neigung nicht zu steil wählen, sonst wird es zur Schulterübung.'),
  _ExSeed('ex_incline_db','Schrägbank Kurzhantel','chest','dumbbell',
    '["Obere Brust"]','["Schultern","Trizeps"]','beginner',null,5.0,null),
  _ExSeed('ex_fly_db','Fliegende','chest','dumbbell',
    '["Brust"]','["Schultern"]','intermediate',
    '1. Lege dich flach auf die Bank, Hanteln über der Brust.\n2. Senke die Hanteln seitlich mit leicht gebeugten Ellbogen.\n3. Stoppe, wenn du eine Dehnung in der Brust spürst.\n4. Führe die Hanteln in einer Bogenbewegung wieder zusammen.',
    4.5,'Führe die Bewegung langsam aus. Keine zu schweren Gewichte – Risiko für Schulterprobleme.'),
  _ExSeed('ex_cable_cross','Kabelkreuzen','chest','cable',
    '["Brust"]','["Schultern"]','intermediate',
    '1. Stehe in der Mitte der Kabelstation, je ein Kabel in jeder Hand (oben oder unten).\n2. Tritt einen Schritt vor.\n3. Führe die Kabel in einem Bogen vor dem Körper zusammen.\n4. Kehre kontrolliert zur Ausgangsposition zurück.',
    4.5,'Perfekt für Kontraktion am Ende der Bewegung. Kein Körperschwung.'),
  _ExSeed('ex_pushup','Liegestütze','chest','bodyweight',
    '["Brust","Trizeps"]','["Schultern","Core"]','beginner',
    '1. Stütze dich auf Hände und Zehen, Hände etwas breiter als schulterbreit.\n2. Halte den Körper von Kopf bis Ferse in einer geraden Linie.\n3. Senke den Körper, bis die Brust fast den Boden berührt.\n4. Drücke dich zurück in die Ausgangsposition.',
    7.0,'Variante für Anfänger: auf den Knien abstützen. Körperspannung halten – kein Hohlkreuz.'),
  _ExSeed('ex_dip','Dips','chest','bodyweight',
    '["Brust","Trizeps"]','["Schultern"]','intermediate',
    '1. Stütze dich auf parallelen Stangen, Arme gestreckt.\n2. Lehne den Oberkörper leicht nach vorne (betont Brust).\n3. Senke den Körper, bis Oberarme waagerecht sind.\n4. Drücke zurück in die Ausgangsposition.',
    7.0,'Leicht vorgebeugt = Brust. Aufrecht = Trizeps. Bei Schulterproblemen vermeiden.'),
  // ── Rücken ─────────────────────────────────────────────────────────────────
  _ExSeed('ex_deadlift','Kreuzheben','back','barbell',
    '["Rücken","Gesäß","Beinbeuger"]','["Core","Unterarme"]','intermediate',
    '1. Stehe schulterbreit, Stange über den Mittelfüßen.\n2. Beuge die Knie, greife die Stange (Schulterbreite).\n3. Brust raus, Rücken gerade – keine Rundung!\n4. Hebe die Stange nah am Körper entlang.\n5. Strecke Knie und Hüfte gleichzeitig aus.\n6. Senke die Stange kontrolliert zurück.',
    7.0,'Wichtigste Übung für den Rücken. Niemals mit rundem Rücken! Mit leichtem Gewicht beginnen.'),
  _ExSeed('ex_rdl','Romanian Deadlift','back','barbell',
    '["Beinbeuger","Gesäß"]','["Rücken"]','intermediate',
    '1. Stehe aufrecht, Stange in den Händen.\n2. Schiebe die Hüfte zurück, senke die Stange die Beine entlang.\n3. Halte den Rücken gerade und die Knie leicht gebeugt.\n4. Senke bis du Dehnung im hinteren Oberschenkel spürst.\n5. Drücke die Hüfte nach vorne zurück in die Ausgangsposition.',
    6.0,'Betont Gesäß und Beinbeuger. Knie nicht zu stark beugen – das ist kein Squat.'),
  _ExSeed('ex_pullup','Klimmzug','back','bodyweight',
    '["Latissimus","Bizeps"]','["Schultern","Core"]','intermediate',
    '1. Hänge an der Stange, Hände etwas breiter als schulterbreit (Ristgriff).\n2. Ziehe dich hoch, bis das Kinn über der Stange ist.\n3. Kontrolliert wieder absenken, bis die Arme gestreckt sind.\n4. Wiederholen ohne Schwung.',
    8.0,'Für Anfänger: mit Band-Unterstützung oder Assisted-Maschine starten. Brustbein zur Stange führen.'),
  _ExSeed('ex_lat_pull','Lat-Pulldown','back','machine',
    '["Latissimus","Bizeps"]','["Schultern"]','beginner',
    '1. Setze dich an die Maschine, Knie unter der Polsterung.\n2. Greife die Stange breiter als schulterbreit.\n3. Ziehe die Stange zu deiner oberen Brust.\n4. Halte kurz an, Schulterblätter zusammendrücken.\n5. Kontrolliert zurück in die Ausgangsposition.',
    5.5,'Gute Alternative zum Klimmzug für Einsteiger. Stange zur Brust, nicht hinter den Kopf ziehen.'),
  _ExSeed('ex_cable_row','Kabelrudern','back','cable',
    '["Rücken","Bizeps"]','["Schultern"]','beginner',
    '1. Sitze aufrecht, Füße auf den Stützen, Knie leicht gebeugt.\n2. Greife den Griff mit beiden Händen.\n3. Ziehe den Griff zur Körpermitte, Ellbogen nah am Körper.\n4. Schulterblätter zusammendrücken.\n5. Kontrolliert zurück, leichtes Vorbeugen erlaubt.',
    5.0,'Aufrechter Rücken ist wichtig. Nicht mit Schwung ziehen.'),
  _ExSeed('ex_bb_row','Langhantelrudern','back','barbell',
    '["Rücken","Bizeps"]','["Schultern","Core"]','intermediate',
    '1. Beuge dich mit geradem Rücken ca. 45° vor.\n2. Halte die Stange schulterbreit.\n3. Ziehe die Stange zur unteren Bauchregion.\n4. Schulterblätter zusammendrücken.\n5. Kontrolliert wieder absenken.',
    6.0,'Niemals mit rundem Rücken. Rumpf stabilisieren.'),
  _ExSeed('ex_db_row','Kurzhantelrudern','back','dumbbell',
    '["Rücken"]','["Bizeps"]','beginner',
    '1. Stütze eine Hand und Knie auf der Bank ab.\n2. Halte die Kurzhantel mit der anderen Hand.\n3. Ziehe die Hantel zur Hüfte, Ellbogen nah am Körper.\n4. Schulterblatt einziehen.\n5. Kontrolliert absenken.',
    5.0,'Gut für Anfänger. Rücken parallel zum Boden halten.'),
  _ExSeed('ex_hyper','Rückenstrecker','back','machine',
    '["Unterer Rücken","Gesäß"]','["Beinbeuger"]','beginner',
    '1. Lege dich auf die Rückenstreckerbank, Füße unter der Polsterung.\n2. Arme verschränken oder hinter dem Kopf.\n3. Senke den Oberkörper nach unten.\n4. Hebe den Oberkörper wieder auf Linie mit dem Körper.',
    4.0,'Nicht überstrecken! Nur bis zur geraden Linie heben.'),
  // ── Beine ──────────────────────────────────────────────────────────────────
  _ExSeed('ex_squat','Kniebeuge','legs','barbell',
    '["Quadrizeps","Gesäß"]','["Beinbeuger","Core"]','intermediate',
    '1. Stange auf den oberen Rücken, schulterbreiter Stand.\n2. Brust raus, Blick geradeaus.\n3. Beuge die Knie und senke die Hüfte nach unten-hinten.\n4. Knie in Fußrichtung halten – nicht nach innen fallen lassen.\n5. Senke bis Oberschenkel parallel zum Boden sind.\n6. Drücke durch die Fersen zurück nach oben.',
    6.5,'Die Knie-Fußspitzen-Linie einhalten. Fersen bleiben am Boden. Mit Körpergewicht beginnen.'),
  _ExSeed('ex_leg_press','Beinpresse','legs','machine',
    '["Quadrizeps","Gesäß"]','["Beinbeuger","Waden"]','beginner',
    '1. Sitze in der Maschine, Füße schulterbreit auf der Platte.\n2. Löse die Sicherung und senke die Platte kontrolliert.\n3. Knie beugen bis ca. 90°.\n4. Drücke die Platte zurück, Knie nicht sperren.',
    5.5,'Füße weiter oben auf der Platte = mehr Gesäß. Weiter unten = mehr Quadrizeps.'),
  _ExSeed('ex_lunge','Ausfallschritte','legs','dumbbell',
    '["Quadrizeps","Gesäß"]','["Beinbeuger","Gleichgewicht"]','beginner',
    '1. Stehe aufrecht, Hanteln in den Händen.\n2. Mache einen großen Schritt nach vorne.\n3. Senke das hintere Knie Richtung Boden (ca. 2 cm über dem Boden).\n4. Vorderes Knie bleibt über dem Fuß.\n5. Drücke dich wieder in die Ausgangsposition.',
    6.0,'Gleichgewicht üben. Oberkörper aufrecht halten.'),
  _ExSeed('ex_leg_ext','Beinstrecker','legs','machine',
    '["Quadrizeps"]',null,'beginner',
    '1. Sitze in der Maschine, Fußpolster auf den Fußrücken.\n2. Strecke die Beine langsam aus.\n3. Kurz oben halten.\n4. Kontrolliert wieder senken.',
    4.5,'Isolation für den Quadrizeps. Bei Knieproblemen mit Arzt abklären.'),
  _ExSeed('ex_leg_curl','Beinbeuger','legs','machine',
    '["Beinbeuger"]',null,'beginner',
    '1. Lege dich auf die Maschine (Bauch unten), Fußpolster auf die Ferse.\n2. Beugen die Knie und ziehe die Fersen zum Gesäß.\n3. Kurz halten.\n4. Kontrolliert wieder strecken.',
    4.5,'Isolation für die Beinrückseite. Hüfte auf der Bank halten.'),
  _ExSeed('ex_calf_raise','Wadenheben','legs','machine',
    '["Waden"]',null,'beginner',
    '1. Stehe auf der Maschine oder Erhöhung, Schultern unter den Polstern.\n2. Hebe die Fersen so weit wie möglich.\n3. Kurz oben halten.\n4. Senke die Fersen unter die Zehenebene für volle Dehnung.',
    4.0,'Voller Bewegungsradius ist wichtig. Nicht bouncing – kontrolliert.'),
  _ExSeed('ex_hip_thrust','Hip Thrust','legs','barbell',
    '["Gesäß","Beinbeuger"]','["Core"]','intermediate',
    '1. Lehne den oberen Rücken gegen eine Bank, Stange auf den Hüften.\n2. Füße schulterbreit, flach auf dem Boden.\n3. Senke die Hüfte nach unten.\n4. Drücke die Hüfte nach oben bis der Körper eine gerade Linie bildet.\n5. Gesäß oben anspannen und kurz halten.',
    6.0,'Beste Übung für das Gesäß. Kinn an die Brust nehmen, um den Nacken zu schonen.'),
  // ── Schultern ──────────────────────────────────────────────────────────────
  _ExSeed('ex_ohp','Schulterdrücken','shoulders','barbell',
    '["Schultern","Trizeps"]','["Core","Nacken"]','intermediate',
    '1. Stange auf Schulterhöhe, schulterbreiter Griff.\n2. Drücke die Stange senkrecht nach oben.\n3. Kopf leicht zurückneigen wenn die Stange passiert.\n4. Arme oben fast gestreckt.\n5. Kontrolliert zurück auf Schulterhöhe.',
    5.5,'Bauch anspannen für Stabilität. Kein Hohlkreuz.'),
  _ExSeed('ex_db_press_sh','Kurzhantel Schulterdrücken','shoulders','dumbbell',
    '["Schultern"]','["Trizeps"]','beginner',
    '1. Sitze aufrecht auf einer Bank (mit Rückenlehne für Anfänger).\n2. Hanteln auf Schulterhöhe, Handflächen nach vorne.\n3. Drücke beide Hanteln gerade nach oben.\n4. Oben kurz halten.\n5. Kontrolliert absenken.',
    5.0,'Rückenlehne für Anfänger nutzen. Ellbogen 30–45° nach vorne für Schultergesundheit.'),
  _ExSeed('ex_lateral','Seitheben','shoulders','dumbbell',
    '["Seitliche Schulter"]','["Fallen"]','beginner',
    '1. Stehe aufrecht, Hanteln an den Seiten.\n2. Hebe die Arme seitlich bis auf Schulterhöhe.\n3. Daumen leicht nach unten (Ausgießerbewegung).\n4. Kurz halten.\n5. Kontrolliert absenken.',
    4.0,'Leichte Gewichte verwenden. Keine Schwungbewegung. Nicht über Schulterhöhe heben.'),
  _ExSeed('ex_frontal','Frontheben','shoulders','dumbbell',
    '["Vordere Schulter"]',null,'beginner',
    '1. Stehe aufrecht, Hanteln vor dem Körper.\n2. Hebe eine oder beide Hanteln vor den Körper bis Schulterhöhe.\n3. Kurz halten.\n4. Kontrolliert absenken.',
    4.0,'Leichte Gewichte. Oft schon durch Drückübungen trainiert – nicht übertreiben.'),
  _ExSeed('ex_face_pull','Face Pulls','shoulders','cable',
    '["Hintere Schulter","Rotatorenmanschette"]','["Fallen"]','beginner',
    '1. Kabelzug auf Gesichtshöhe einstellen, Seilgriff befestigen.\n2. Greife je eine Seite des Seils.\n3. Trete einen Schritt zurück.\n4. Ziehe das Seil zum Gesicht, Ellbogen nach außen und oben.\n5. Schulterblätter zusammendrücken.\n6. Kontrolliert zurück.',
    4.0,'Gesundheitsübung für die Schulterrotatorenmanschette. In jedes Training integrieren.'),
  _ExSeed('ex_upright_row','Aufrechtes Rudern','shoulders','barbell',
    '["Schultern","Fallen"]','["Bizeps"]','intermediate',
    '1. Stehe mit der Stange, Griff etwas enger als schulterbreit.\n2. Ziehe die Stange nah am Körper nach oben bis Kinnhöhe.\n3. Ellbogen führen die Bewegung nach oben.\n4. Kontrolliert absenken.',
    5.0,'Bei Schulterproblemen meiden. Ellbogen immer über den Handgelenken.'),
  // ── Arme ───────────────────────────────────────────────────────────────────
  _ExSeed('ex_bicurl_bar','Bizepscurl','arms','barbell',
    '["Bizeps"]','["Unterarme"]','beginner',
    '1. Stehe aufrecht, Stange schulterbreit im Untergriff.\n2. Halte die Ellbogen fest an der Hüfte.\n3. Beuge die Ellbogen und hebe die Stange zur Brust.\n4. Bizeps oben anspannen.\n5. Kontrolliert absenken, Arme nicht ganz strecken.',
    4.5,'Keine Schwungbewegung. Ellbogen fixiert halten.'),
  _ExSeed('ex_bicurl_db','Kurzhantel Bizepscurl','arms','dumbbell',
    '["Bizeps"]','["Unterarme"]','beginner',
    '1. Stehe aufrecht, je eine Hantel in jeder Hand.\n2. Wechselnd oder gleichzeitig curlen.\n3. Handfläche dreht beim Heben nach außen (Supination).\n4. Kontrolliert absenken.',
    4.5,'Ermöglicht Supination für bessere Bizepsisolation.'),
  _ExSeed('ex_hammer','Hammer Curls','arms','dumbbell',
    '["Bizeps","Brachialis"]','["Unterarme"]','beginner',
    '1. Stehe aufrecht, Hanteln an den Seiten (Daumen oben).\n2. Beuge die Ellbogen, Handhaltung bleibt neutral (Hammer-Griff).\n3. Bis die Hanteln auf Schulterhöhe sind.\n4. Kontrolliert absenken.',
    4.5,'Trainiert Brachialis unter dem Bizeps – macht den Arm dicker aussehen.'),
  _ExSeed('ex_tricep_press','Trizepsdrücken','arms','machine',
    '["Trizeps"]',null,'beginner',
    '1. Setze dich an die Trizeps-Maschine.\n2. Greife die Griffe auf Schulterhöhe.\n3. Drücke die Griffe nach unten bis die Arme gestreckt sind.\n4. Kurz halten.\n5. Kontrolliert zurückführen.',
    4.5,'Gut für Anfänger zur sicheren Trizepsisolation.'),
  _ExSeed('ex_tricep_dip','Trizeps Dips','arms','bodyweight',
    '["Trizeps"]','["Schultern","Brust"]','intermediate',
    '1. Stütze dich auf parallelen Stangen, Arme gestreckt.\n2. Halte den Oberkörper aufrecht (betont Trizeps).\n3. Senke den Körper, bis die Ellbogen ca. 90° gebeugt sind.\n4. Drücke zurück in die Ausgangsposition.',
    6.5,'Aufrechter Oberkörper = mehr Trizeps. Bei Schulterproblemen vorsichtig.'),
  _ExSeed('ex_tricep_down','Trizeps Pushdowns','arms','cable',
    '["Trizeps"]',null,'beginner',
    '1. Kabelzug auf Höhe einstellen, Seil- oder Stangengriff.\n2. Stehe aufrecht vor der Maschine.\n3. Ellbogen nah am Körper fixiert halten.\n4. Drücke den Griff nach unten bis die Arme gestreckt sind.\n5. Kontrolliert zurückführen.',
    4.0,'Einsteigerfreundlich. Ellbogen nicht bewegen.'),
  _ExSeed('ex_skull','Skull Crushers','arms','barbell',
    '["Trizeps"]',null,'advanced',
    '1. Lege dich auf die Bank, Stange mit engem Griff über der Brust.\n2. Senke die Stange zur Stirn (daher der Name), Ellbogen zeigen nach oben.\n3. Ellbogen bleiben fixiert.\n4. Strecke die Arme zurück in die Ausgangsposition.',
    5.0,'Fortgeschrittene Übung. Sicherung durch Partner oder Stangen empfohlen.'),
  // ── Core ───────────────────────────────────────────────────────────────────
  _ExSeed('ex_plank','Plank (Unterarmstütz)','core','bodyweight',
    '["Core","Bauch"]','["Schultern","Rücken"]','beginner',
    '1. Stütze dich auf die Unterarme und Zehen.\n2. Körper von Kopf bis Ferse in einer geraden Linie.\n3. Bauch, Gesäß und Oberschenkel anspannen.\n4. Tief ein- und ausatmen.\n5. Position halten (z.B. 30 Sekunden).',
    4.0,'Für Anfänger: auf den Knien stützen. Kein Hohlkreuz – Nabel zur Wirbelsäule ziehen.'),
  _ExSeed('ex_side_plank','Seitstütz','core','bodyweight',
    '["Schrägmuskel","Core"]','["Schultern"]','beginner',
    '1. Lege dich auf die Seite, stütze dich auf einen Unterarm.\n2. Hebe die Hüfte, bis Körper gerade ist.\n3. Freie Hand zur Decke oder an der Hüfte.\n4. Position halten (z.B. 20 Sekunden).\n5. Seite wechseln.',
    3.5,'Für beide Seiten gleich lange halten. Hüfte nicht durchhängen lassen.'),
  _ExSeed('ex_crunch','Crunches','core','bodyweight',
    '["Bauch"]','["Hüftbeuger"]','beginner',
    '1. Lege dich auf den Rücken, Knie angewinkelt, Füße flach.\n2. Hände locker hinter dem Kopf oder an den Schläfen.\n3. Hebe die Schultern vom Boden ab (nicht den Rücken!).\n4. Bauch anspannen und kurz halten.\n5. Kontrolliert absenken.',
    4.0,'Nur die Schultern heben, nicht den Rücken. Nacken nicht ziehen.'),
  _ExSeed('ex_legrise','Beinheben','core','bodyweight',
    '["Unterer Bauch","Hüftbeuger"]',null,'intermediate',
    '1. Lege dich auf den Rücken, Arme neben dem Körper.\n2. Hebe die Beine gestreckt oder leicht gebeugt bis 90°.\n3. Senke die Beine kontrolliert, ohne den Boden zu berühren.\n4. Rücken bleibt flach auf dem Boden.',
    4.5,'Beine nicht ganz auf den Boden senken für maximale Spannung. Lendenwirbelsäule geschützt halten.'),
  _ExSeed('ex_russian','Russian Twist','core','bodyweight',
    '["Schrägmuskel","Core"]',null,'beginner',
    '1. Sitze auf dem Boden, Knie angewinkelt, Oberkörper ca. 45° nach hinten geneigt.\n2. Hände zusammen vor der Brust (oder ein Gewicht halten).\n3. Drehe den Oberkörper von Seite zu Seite.\n4. Kontrolliert rotieren, nicht Schwingen.',
    4.5,'Füße können auf dem Boden bleiben (leichter) oder angehoben werden (schwerer).'),
  _ExSeed('ex_abroller','Ab-Roller','core','other',
    '["Bauch","Core"]','["Rücken","Schultern"]','intermediate',
    '1. Knie auf dem Boden, Hände auf dem Ab-Roller.\n2. Rolle langsam nach vorne, bis du fast flach bist.\n3. Bauch stark anspannen.\n4. Ziehe dich mit den Bauchmuskeln zurück in die Ausgangsposition.',
    5.0,'Eine der effektivsten Core-Übungen. Anfänger beginnen mit kurzem Rollweg.'),
  _ExSeed('ex_situp','Situps','core','bodyweight',
    '["Bauch","Hüftbeuger"]',null,'beginner',
    '1. Lege dich auf den Rücken, Knie gebeugt, Füße fixiert.\n2. Hände locker hinter dem Kopf.\n3. Setze dich vollständig auf.\n4. Kontrolliert zurücklegen.',
    4.5,'Trainiert auch den Hüftbeuger. Für reinen Bauchfokus Crunches bevorzugen.'),
  _ExSeed('ex_mountain','Mountain Climbers','core','bodyweight',
    '["Core","Kardio"]','["Schultern","Hüftbeuger"]','beginner',
    '1. Gehe in die Liegestützposition.\n2. Ziehe abwechselnd das rechte und linke Knie zur Brust.\n3. Schneller Wechsel wie Laufen auf der Stelle.\n4. Core angespannt halten.',
    8.0,'Kombination aus Core-Training und Kardio. Tempo steigerbar.'),
  // ── Kardio ─────────────────────────────────────────────────────────────────
  _ExSeed('ex_treadmill','Laufband','cardio','machine',
    '["Kardio"]','["Beine","Waden"]','beginner',
    '1. Starte langsam (3–5 km/h) und steigere das Tempo schrittweise.\n2. Aufrechte Körperhaltung, Blick nach vorne.\n3. Arme leicht angewinkelt mitschwingen.\n4. Abkühlen: Letzte 5 Minuten Tempo reduzieren.',
    10.0,'Vor dem Rennen aufwärmen. Gute Laufschuhe tragen.'),
  _ExSeed('ex_bike','Ergometer','cardio','machine',
    '["Kardio"]','["Beine","Gesäß"]','beginner',
    '1. Sattelhöhe einstellen (Knie leicht gebeugt am unteren Totpunkt).\n2. Gleichmäßiger Tritt in runden Bewegungen.\n3. Aufrechte oder leicht vorgebeugte Haltung.\n4. Widerstand nach Fitness anpassen.',
    9.0,'Gelenkschonend. Gut für Aufwärmen und Ausdauertraining.'),
  _ExSeed('ex_rowing_erg','Rudergerät','cardio','machine',
    '["Kardio","Rücken","Arme"]','["Beine","Core"]','beginner',
    '1. Sitze auf dem Gerät, Füße fixiert.\n2. Beine strecken (70% der Kraft), dann Rücken aufrichten, dann Arme ziehen.\n3. Umgekehrte Reihenfolge beim Zurückfahren: Arme, Rücken, Beine.\n4. Gleichmäßiger Rhythmus.',
    10.0,'Ganzköper-Kardio. Häufiger Fehler: mit dem Rücken beginnen statt mit den Beinen.'),
  _ExSeed('ex_jumprope','Seilspringen','cardio','bodyweight',
    '["Kardio"]','["Waden","Schultern"]','beginner',
    '1. Seil hinter den Füßen auf dem Boden.\n2. Schwinge das Seil über den Kopf und springe mit beiden Füßen.\n3. Nur minimal vom Boden abheben (2–3 cm).\n4. Kleine Kreisbewegungen mit den Handgelenken.',
    12.0,'Einer der effizientesten Kalorienverbrenner. Mit kurzen Intervallen beginnen.'),
  _ExSeed('ex_stairmaster','Stairmaster','cardio','machine',
    '["Kardio"]','["Beine","Gesäß"]','beginner',
    '1. Stelle die Geschwindigkeit niedrig ein.\n2. Aufrechte Körperhaltung, nicht auf den Handläufen abstützen.\n3. Ganze Fußfläche auf die Stufe setzen.\n4. Gleichmäßiger Rhythmus.',
    10.0,'Intensives Kardio für Gesäß und Beine. Nicht auf die Handläufe stützen.'),
  _ExSeed('ex_run_outdoor','Laufen (draußen)','cardio',null,
    '["Kardio"]','["Beine","Waden"]','beginner',
    '1. Mit Aufwärmen beginnen (5 Minuten zügiges Gehen).\n2. Gleichmäßiges Tempo wählen (Konversationstempo = richtige Intensität).\n3. Aufrechte Haltung, Blick nach vorne.\n4. Mit Abkühlen beenden (5 Minuten langsames Gehen).',
    10.0,'Kein Vergleich mit dem Laufband – draußen abwechslungsreicher. Gutes Schuhwerk wichtig.'),
  _ExSeed('ex_hiit','HIIT','cardio','bodyweight',
    '["Kardio"]','["Core","Beine","Arme"]','advanced',
    '1. Aufwärmen: 5 Minuten leichtes Kardio.\n2. Intervall: 20–40 Sekunden maximale Intensität (z.B. Burpees, Sprints).\n3. Pause: 10–20 Sekunden Ruhe oder leichte Bewegung.\n4. 8–12 Runden wiederholen.\n5. Abkühlen: 5 Minuten dehnen.',
    14.0,'Für Anfänger: längere Pausen und weniger Runden. Nicht täglich – Erholung ist wichtig.'),
  _ExSeed('ex_burpee','Burpees','cardio','bodyweight',
    '["Kardio","Core"]','["Brust","Beine","Schultern"]','intermediate',
    '1. Stehe aufrecht.\n2. Gehe in die Kniebeuge und setze die Hände auf den Boden.\n3. Spring oder gehe in die Liegestützposition.\n4. (Optional: eine Liegestütze machen.)\n5. Spring zurück in die Kniebeuge.\n6. Spring hoch und klatsche über dem Kopf.',
    10.0,'Ganzkörperübung. Tempo bestimmt die Intensität. Modifizierung für Anfänger: ohne Sprung.'),
  // ── Core / Dehnen ──────────────────────────────────────────────────────────
  _ExSeed('ex_cat_cow','Katzenbuckel / Kuhkopf','core','bodyweight',
    '["Rücken","Core"]','["Hals"]','beginner',
    '1. Knie auf dem Boden, Hände unter den Schultern (Vierfüßlerstand).\n2. Katzenbuckel: Rücken runden, Kinn zur Brust, ausatmen.\n3. Kuhkopf: Rücken durchhängen lassen, Kopf heben, einatmen.\n4. Langsam abwechseln – 10 Wiederholungen.',
    2.0,'Perfekte Mobilisationsübung für den Rücken. Als Aufwärmen oder Abkühlen nutzen.'),
  _ExSeed('ex_glute_bridge','Brücke (Glute Bridge)','legs','bodyweight',
    '["Gesäß","Beinbeuger"]','["Core","Unterer Rücken"]','beginner',
    '1. Lege dich auf den Rücken, Knie gebeugt, Füße flach.\n2. Drücke die Fersen in den Boden.\n3. Hebe die Hüfte, bis Knie, Hüfte und Schultern eine Linie bilden.\n4. Gesäß oben anspannen.\n5. Kontrolliert absenken.\n6. Variante: einbeinig für mehr Intensität.',
    4.5,'Einsteigerfreundlich. Perfekt als Aktivierungsübung für das Gesäß.'),
];

// ── Body Photos ───────────────────────────────────────────────────────────────

extension BodyPhotosDao on AppDatabase {
  Stream<List<BodyPhoto>> watchAllBodyPhotos() =>
      (select(bodyPhotos)..orderBy([(p) => OrderingTerm.desc(p.takenAt)]))
          .watch();

  Future<void> insertBodyPhoto(BodyPhotosCompanion entry) =>
      into(bodyPhotos).insert(entry);

  Future<void> deleteBodyPhoto(String id) =>
      (delete(bodyPhotos)..where((p) => p.id.equals(id))).go();

  Future<void> updateBodyPhotoNotes(String id, String? notes) =>
      (update(bodyPhotos)..where((p) => p.id.equals(id)))
          .write(BodyPhotosCompanion(notes: Value(notes)));

  // ── Custom Shopping Items ─────────────────────────────────────────────────

  Stream<List<CustomShoppingItem>> watchCustomShoppingItems() =>
      (select(customShoppingItems)
            ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
          .watch();

  Future<void> insertCustomShoppingItem(CustomShoppingItemsCompanion entry) =>
      into(customShoppingItems).insert(entry);

  Future<void> toggleCustomShoppingItem(String id, bool checked) =>
      (update(customShoppingItems)..where((t) => t.id.equals(id)))
          .write(CustomShoppingItemsCompanion(checked: Value(checked)));

  Future<void> updateCustomShoppingItem(CustomShoppingItemsCompanion entry) =>
      (update(customShoppingItems)..where((t) => t.id.equals(entry.id.value)))
          .write(entry);

  Future<void> deleteCustomShoppingItem(String id) =>
      (delete(customShoppingItems)..where((t) => t.id.equals(id))).go();

  Future<void> deleteCheckedCustomShoppingItems() =>
      (delete(customShoppingItems)..where((t) => t.checked.equals(true))).go();

  // ── Product type definitions ─────────────────────────────────────────────

  Stream<List<ProductTypeDefinition>> watchAllProductTypes() =>
      (select(productTypeDefinitions)
            ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]))
          .watch();

  Future<void> upsertProductTypeDefinition(
          ProductTypeDefinitionsCompanion entry) =>
      into(productTypeDefinitions).insertOnConflictUpdate(entry);

  Future<void> deleteProductTypeDefinition(String id) =>
      (delete(productTypeDefinitions)..where((t) => t.id.equals(id))).go();

  Future<void> _seedProductTypeDefinitions() async {
    const types = [
      ('readyToEat', 'Fertiggericht', 'ready_to_eat', 0),
      ('needsCooking', 'Muss gekocht werden', 'soup_kitchen', 1),
      ('ingredient', 'Zutat', 'spa', 2),
      ('device', 'Gerät / Ausstattung', 'devices_other', 3),
      ('tool', 'Werkzeug / Zubehör', 'build', 4),
      ('consumable', 'Verbrauchsmaterial', 'inventory_2', 5),
      ('general', 'Allgemein / Sonstiges', 'category', 6),
    ];
    for (final (id, name, icon, order) in types) {
      await into(productTypeDefinitions).insertOnConflictUpdate(
        ProductTypeDefinitionsCompanion.insert(
          id: id,
          nameDe: name,
          isBuiltIn: const Value(true),
          iconName: Value(icon),
          sortOrder: Value(order),
        ),
      );
    }
  }

  // ── Templates & fields ───────────────────────────────────────────────────

  Stream<List<ItemTemplate>> watchAllTemplates() =>
      (select(itemTemplates)
            ..orderBy([(t) => OrderingTerm.asc(t.name)]))
          .watch();

  Stream<List<TemplateField>> watchFieldsForTemplate(String templateId) =>
      (select(templateFields)
            ..where((f) => f.templateId.equals(templateId))
            ..orderBy([(f) => OrderingTerm.asc(f.sortOrder)]))
          .watch();

  Future<ItemTemplate?> templateById(String id) =>
      (select(itemTemplates)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<String> insertTemplate(ItemTemplatesCompanion entry) async {
    await into(itemTemplates).insertOnConflictUpdate(entry);
    return entry.id.value;
  }

  Future<void> updateTemplate(ItemTemplatesCompanion entry) =>
      (update(itemTemplates)..where((t) => t.id.equals(entry.id.value)))
          .write(entry);

  Future<void> deleteTemplate(String id) =>
      (delete(itemTemplates)..where((t) => t.id.equals(id))).go();

  Future<void> upsertTemplateField(TemplateFieldsCompanion entry) =>
      into(templateFields).insertOnConflictUpdate(entry);

  Future<void> deleteTemplateField(String id) =>
      (delete(templateFields)..where((f) => f.id.equals(id))).go();

  Future<void> reorderTemplateFields(
      List<({String id, int sortOrder})> updates) async {
    await transaction(() async {
      for (final u in updates) {
        await (update(templateFields)..where((f) => f.id.equals(u.id)))
            .write(TemplateFieldsCompanion(sortOrder: Value(u.sortOrder)));
      }
    });
  }

  // ── Item property values ─────────────────────────────────────────────────

  Stream<List<ItemPropertyValue>> watchPropertiesForItem(String itemId) =>
      (select(itemPropertyValues)
            ..where((p) => p.itemId.equals(itemId)))
          .watch();

  Future<void> upsertProperty(ItemPropertyValuesCompanion entry) =>
      into(itemPropertyValues).insertOnConflictUpdate(entry);

  Future<void> deleteProperty(String id) =>
      (delete(itemPropertyValues)..where((p) => p.id.equals(id))).go();

  Future<void> deletePropertiesForItem(String itemId) =>
      (delete(itemPropertyValues)..where((p) => p.itemId.equals(itemId))).go();

  // ── Template seeds ───────────────────────────────────────────────────────

  Future<void> _seedBuiltInTemplates() async {
    final templates = [
      (
        id: 'tpl_laptop',
        name: 'Laptop / Computer',
        fields: [
          ('Seriennummer', 'text', false, 0),
          ('RAM', 'text', false, 1),
          ('Speicher', 'text', false, 2),
          ('Betriebssystem', 'text', false, 3),
          ('Kaufdatum', 'date', false, 4),
          ('Garantieende', 'date', false, 5),
          ('Hersteller-Link', 'link', false, 6),
        ]
      ),
      (
        id: 'tpl_smartphone',
        name: 'Smartphone',
        fields: [
          ('IMEI', 'text', false, 0),
          ('Speicher', 'text', false, 1),
          ('Kaufdatum', 'date', false, 2),
          ('Garantieende', 'date', false, 3),
        ]
      ),
      (
        id: 'tpl_haushaltsgeraet',
        name: 'Haushaltsgerät',
        fields: [
          ('Modellnummer', 'text', false, 0),
          ('Kaufdatum', 'date', false, 1),
          ('Garantieende', 'date', false, 2),
          ('Hat Netzteil', 'boolean', false, 3),
          ('Hersteller-Link', 'link', false, 4),
        ]
      ),
      (
        id: 'tpl_werkzeug',
        name: 'Werkzeug / Zubehör',
        fields: [
          ('Kompatible Modelle', 'liste', false, 0),
          ('Kaufdatum', 'date', false, 1),
        ]
      ),
    ];

    for (final tpl in templates) {
      await into(itemTemplates).insertOnConflictUpdate(
        ItemTemplatesCompanion.insert(
          id: tpl.id,
          name: tpl.name,
          isBuiltIn: const Value(true),
        ),
      );
      int order = 0;
      for (final (fieldName, fieldType, required, sortOrder) in tpl.fields) {
        final fId = '${tpl.id}_f${order++}';
        await into(templateFields).insertOnConflictUpdate(
          TemplateFieldsCompanion.insert(
            id: fId,
            templateId: tpl.id,
            fieldName: fieldName,
            fieldType: fieldType,
            required: Value(required),
            sortOrder: Value(sortOrder),
          ),
        );
      }
    }
  }

  // ── Entity Photos ────────────────────────────────────────────────────────

  Stream<List<EntityPhoto>> watchEntityPhotos(String entityId) =>
      (select(entityPhotos)
            ..where((p) => p.entityId.equals(entityId))
            ..orderBy([(p) => OrderingTerm.asc(p.createdAt)]))
          .watch();

  Future<void> insertEntityPhoto(EntityPhotosCompanion entry) =>
      into(entityPhotos).insert(entry);

  Future<void> deleteEntityPhoto(String id) =>
      (delete(entityPhotos)..where((p) => p.id.equals(id))).go();

  Future<void> deleteEntityPhotosForEntity(String entityId) =>
      (delete(entityPhotos)..where((p) => p.entityId.equals(entityId))).go();

  Future<void> updateEntityPhotoCaption(String id, String? caption) =>
      (update(entityPhotos)..where((p) => p.id.equals(id)))
          .write(EntityPhotosCompanion(caption: Value(caption)));

  // ── Sync ──────────────────────────────────────────────────────────────────

  /// Returns all item events created after [since], optionally excluding
  /// events from [excludeDeviceId] (the requesting device's own events).
  Future<List<ItemEvent>> getItemEventsSince(
    DateTime since, {
    String? excludeDeviceId,
  }) {
    final query = select(itemEvents)
      ..where((e) => e.createdAt.isBiggerThanValue(since));
    if (excludeDeviceId != null) {
      query.where((e) => e.deviceId.equals(excludeDeviceId).not());
    }
    query.orderBy([(e) => OrderingTerm.asc(e.createdAt)]);
    return query.get();
  }

  /// Batch-inserts events received from a sync peer. Events whose IDs already
  /// exist in the database are skipped (insert-or-ignore).
  Future<void> insertSyncedEvents(List<ItemEventsCompanion> events) async {
    if (events.isEmpty) return;
    await batch((b) {
      b.insertAllOnConflictUpdate(itemEvents, events);
    });
  }

  /// Returns the timestamp of the most recent event from a foreign device,
  /// or epoch if no foreign events exist. Used as the `since` cursor.
  Future<DateTime> lastSyncedAt({required String localDeviceId}) async {
    final result = await (select(itemEvents)
          ..where((e) => e.deviceId.equals(localDeviceId).not())
          ..orderBy([(e) => OrderingTerm.desc(e.createdAt)])
          ..limit(1))
        .getSingleOrNull();
    return result?.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
  }
}
