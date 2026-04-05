import 'package:drift/drift.dart';

/// Hierarchical storage locations (Kitchen > Fridge > Top shelf)
class Locations extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get parentId => text().nullable()(); // FK → Locations (self-reference)
  TextColumn get photoPath => text().nullable()(); // relative to vault root
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}
