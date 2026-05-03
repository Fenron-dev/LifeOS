import 'package:drift/drift.dart';

import 'locations_table.dart';

/// All objects in the system: food products, appliances, wish list entries, etc.
class Items extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get brand => text().nullable()();
  TextColumn get ean => text().nullable()(); // EAN barcode
  TextColumn get categoryId => text()(); // FK → CategoryDefinitions or built-in category key

  // Product type: 'readyToEat' | 'needsCooking' | 'ingredient'
  TextColumn get productType => text().withDefault(const Constant('needsCooking'))();
  BoolColumn get alwaysConsumedFully => boolean().withDefault(const Constant(false))();
  // When opened: is product still counted in stock? (e.g. ketchup = true, cracker pack = false)
  BoolColumn get openedFlag => boolean().withDefault(const Constant(true))();
  // How many days the product lasts after opening (null = no opened-expiry)
  IntColumn get daysAfterOpening => integer().nullable()();

  // Smart Tara: default container item for this product
  TextColumn get containerItemId => text()
      .nullable()
      .references(Items, #id, onDelete: KeyAction.setNull)();

  TextColumn get notes => text().nullable()();

  // Nutrition per 100g (from OpenFoodFacts or manual entry)
  RealColumn get caloriesPer100g => real().nullable()();
  RealColumn get proteinPer100g => real().nullable()();
  RealColumn get carbsPer100g => real().nullable()();
  RealColumn get fatPer100g => real().nullable()();
  RealColumn get fiberPer100g => real().nullable()();
  RealColumn get sugarsPer100g => real().nullable()();
  RealColumn get saturatedFatPer100g => real().nullable()();
  RealColumn get saltPer100g => real().nullable()();
  RealColumn get servingSizeG => real().nullable()();
  TextColumn get nutriscore => text().nullable()(); // a | b | c | d | e
  IntColumn get novaGroup => integer().nullable()(); // 1–4
  TextColumn get ingredientsText => text().nullable()();

  /// Whether nutrition values are per 100g or per 100ml (for liquids).
  TextColumn get nutritionRefUnit =>
      text().withDefault(const Constant('g'))();

  /// The unit used for stock aggregation (e.g. 'g', 'Stück').
  /// If null, quantities are summed per unit without conversion.
  TextColumn get stockUnit => text().nullable()();

  /// Default location for new inventory entries (pre-selects in AddStockSheet).
  TextColumn get defaultLocationId => text()
      .nullable()
      .references(Locations, #id, onDelete: KeyAction.setNull)();

  // User ratings
  IntColumn get starRating => integer().nullable()(); // 1–5
  BoolColumn get isFavorite => boolean().withDefault(const Constant(false))();
  BoolColumn get isTrashed => boolean().withDefault(const Constant(false))();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// Inventory entries: a specific quantity of an item at a location
class InventoryEntries extends Table {
  TextColumn get id => text()();
  TextColumn get itemId =>
      text().references(Items, #id, onDelete: KeyAction.cascade)();
  TextColumn get locationId => text()
      .nullable()
      .references(Locations, #id, onDelete: KeyAction.setNull)();
  RealColumn get quantity => real()();
  TextColumn get unit => text()(); // g, kg, ml, l, piece, package, ...
  TextColumn get state => text().withDefault(const Constant('fresh'))(); // fresh | frozen | thawed
  DateTimeColumn get expiryDate => dateTime().nullable()();
  // When this entry was opened (null = not opened yet)
  DateTimeColumn get openedAt => dateTime().nullable()();
  DateTimeColumn get frozenAt => dateTime().nullable()();
  DateTimeColumn get thawedAt => dateTime().nullable()();
  // Container currently used (may differ from item.containerItemId)
  @ReferenceName('activeContainerInventoryRefs')
  TextColumn get activeContainerId => text()
      .nullable()
      .references(Items, #id, onDelete: KeyAction.setNull)();
  RealColumn get price => real().nullable()(); // purchase price
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// Item groups: logical groupings for min-stock rules (e.g. "Eggs", "Oats")
class ItemGroups extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get categoryId => text()();
  RealColumn get minStockQuantity => real().nullable()();
  TextColumn get minStockUnit => text().nullable()();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// Many-to-many: items in groups
class ItemGroupMembers extends Table {
  TextColumn get groupId =>
      text().references(ItemGroups, #id, onDelete: KeyAction.cascade)();
  TextColumn get itemId =>
      text().references(Items, #id, onDelete: KeyAction.cascade)();

  @override
  Set<Column> get primaryKey => {groupId, itemId};
}
