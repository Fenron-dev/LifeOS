import 'package:drift/drift.dart';
import 'shops_table.dart';

/// Free-text items manually added to the shopping list.
class CustomShoppingItems extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  RealColumn get quantity => real().nullable()();
  TextColumn get unit => text().nullable()();
  TextColumn get shopId =>
      text().nullable().references(Shops, #id)();
  BoolColumn get checked => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}
