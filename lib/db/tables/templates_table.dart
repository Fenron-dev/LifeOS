import 'package:drift/drift.dart';
import 'items_table.dart';

/// User-manageable item templates — define which custom fields an article has.
class ItemTemplates extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get description => text().nullable()();
  TextColumn get categoryId => text().nullable()();
  BoolColumn get isBuiltIn =>
      boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// Fields defined per template.
class TemplateFields extends Table {
  TextColumn get id => text()();
  TextColumn get templateId =>
      text().references(ItemTemplates, #id, onDelete: KeyAction.cascade)();
  TextColumn get fieldName => text()();
  // text | number | date | boolean | tags | liste | link
  TextColumn get fieldType => text()();
  TextColumn get defaultValue => text().nullable()();
  BoolColumn get required =>
      boolean().withDefault(const Constant(false))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Values per item — both template-driven and free-form fields.
class ItemPropertyValues extends Table {
  TextColumn get id => text()();
  TextColumn get itemId =>
      text().references(Items, #id, onDelete: KeyAction.cascade)();
  TextColumn get fieldKey => text()();
  // mirrors the fieldType from the template or a free-form type
  TextColumn get fieldType => text()();
  // plain text for text/number/date/boolean; JSON for tags/liste/link
  TextColumn get value => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}
