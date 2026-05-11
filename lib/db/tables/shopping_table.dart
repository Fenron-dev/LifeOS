import 'package:drift/drift.dart';
import 'items_table.dart';
import 'shops_table.dart';

/// Free-text items manually added to the shopping list.
class CustomShoppingItems extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  RealColumn get quantity => real().nullable()();
  TextColumn get unit => text().nullable()();
  TextColumn get shopId =>
      text().nullable().references(Shops, #id)();
  /// Optional link to an inventory item — when checked off the add-stock flow
  /// opens automatically so the purchase gets booked into inventory.
  TextColumn get itemId =>
      text().nullable().references(Items, #id, onDelete: KeyAction.setNull)();
  BoolColumn get checked => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}
