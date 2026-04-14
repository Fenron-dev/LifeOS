import 'package:drift/drift.dart';

/// User-managed unit names.
/// Default units are seeded on first open; custom units can be added.
class Units extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()(); // e.g. 'Packung', 'Stück', 'kg'
  TextColumn get plural => text().nullable()(); // e.g. 'Tüten', 'Stück', 'kg'
  TextColumn get abbreviation => text().nullable()(); // short display, e.g. 'kg'
  BoolColumn get isDefault => boolean().withDefault(const Constant(false))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}
