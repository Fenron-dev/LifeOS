import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;

import 'tables/items_table.dart';
import 'tables/events_table.dart';
import 'tables/locations_table.dart';
import 'tables/tags_table.dart';
import 'tables/recipes_table.dart';
import 'tables/tasks_table.dart';
import 'tables/automation_table.dart';

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
  // Automation & settings
  AutomationRules,
  AppSettings,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase(String vaultPath) : super(_openDb(vaultPath));

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          // Incremental migrations added here as schema evolves
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
}
