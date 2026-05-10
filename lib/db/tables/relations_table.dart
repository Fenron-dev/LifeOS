import 'package:drift/drift.dart';
import 'items_table.dart';

class ItemRelations extends Table {
  TextColumn get id => text()();
  @ReferenceName('fromRelations')
  TextColumn get fromItemId =>
      text().references(Items, #id, onDelete: KeyAction.cascade)();
  @ReferenceName('toRelations')
  TextColumn get toItemId =>
      text().references(Items, #id, onDelete: KeyAction.cascade)();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}
