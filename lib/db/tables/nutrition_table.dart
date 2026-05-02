import 'package:drift/drift.dart';

/// One food diary entry. Nutritional values are stored pre-computed
/// (per-100g × quantity / 100) so daily-total queries are a single SUM —
/// no join with the items table needed at read-time.
///
/// Both `itemId` and `ean` are optional back-references: `itemId` links to a
/// vault item when the product was picked from the local inventory; `ean` is
/// the OFF barcode for products that were looked up but not imported.
/// For purely manual entries both are null.
class NutritionLogs extends Table {
  TextColumn get id => text()();
  DateTimeColumn get loggedAt => dateTime()();

  // Meal slot — references meal_types.id (e.g. mt_fruehstueck). Nullable so
  // entries without a slot are still valid.
  TextColumn get mealTypeId => text().nullable()();

  // Back-references (both optional)
  TextColumn get itemId => text().nullable()();
  TextColumn get ean => text().nullable()();

  // Display fields — denormalised so the entry is self-contained after logging
  TextColumn get productName => text()();
  TextColumn get brand => text().nullable()();

  // Quantity entered by the user and the display unit
  RealColumn get quantityG => real()(); // always in grams (or ml ≈ g)
  TextColumn get displayUnit => text().withDefault(const Constant('g'))();

  // Nutritional totals for this entry (pre-computed)
  RealColumn get kcal => real().nullable()();
  RealColumn get proteinG => real().nullable()();
  RealColumn get carbsG => real().nullable()();
  RealColumn get fatG => real().nullable()();
  RealColumn get fiberG => real().nullable()();

  // Where the data came from: manual | off | barcode | recipe
  TextColumn get source =>
      text().withDefault(const Constant('manual'))();

  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}
