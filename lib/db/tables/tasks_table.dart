import 'package:drift/drift.dart';

import 'items_table.dart';
import 'recipes_table.dart';

class Tasks extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get description => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('pending'))(); // pending | done | skipped
  BoolColumn get recurring => boolean().withDefault(const Constant(false))();
  // Recurrence: 'daily' | 'weekly' | 'monthly' | 'yearly' | 'custom'
  TextColumn get recurrenceType => text().nullable()();
  IntColumn get recurrenceInterval => integer().nullable()();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get dueDate => dateTime().nullable()();
  DateTimeColumn get completedAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// Wish list entries — can link to items, recipes, or URLs
class WishListEntries extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get url => text().nullable()();
  RealColumn get price => real().nullable()();
  TextColumn get priority => text().withDefault(const Constant('medium'))(); // low | medium | high
  TextColumn get forPerson => text().nullable()();
  TextColumn get linkedItemId => text()
      .nullable()
      .references(Items, #id, onDelete: KeyAction.setNull)();
  TextColumn get linkedRecipeId => text()
      .nullable()
      .references(Recipes, #id, onDelete: KeyAction.setNull)();
  TextColumn get notes => text().nullable()();
  BoolColumn get fulfilled => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}
