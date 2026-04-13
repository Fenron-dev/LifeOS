import 'package:drift/drift.dart';

import 'items_table.dart';

/// Tag definitions — scoped per category so food tags != electronics tags
class TagDefinitions extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get categoryId => text()(); // scope: 'food' | 'appliance' | 'task' | custom
  TextColumn get parentTagId => text().nullable()(); // FK → TagDefinitions (subtag hierarchy)
  TextColumn get color => text().withDefault(const Constant('#6B7280'))(); // hex color
  TextColumn get icon => text().nullable()(); // icon name
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// Many-to-many: items ↔ tags
class ItemTags extends Table {
  TextColumn get itemId =>
      text().references(Items, #id, onDelete: KeyAction.cascade)();
  TextColumn get tagId => text()
      .references(TagDefinitions, #id, onDelete: KeyAction.cascade)();

  @override
  Set<Column> get primaryKey => {itemId, tagId};
}

/// Photos attached to any entity (item, location, recipe, task, etc.)
class EntityPhotos extends Table {
  TextColumn get id => text()();
  TextColumn get entityId => text()(); // FK to any entity
  TextColumn get entityType => text()(); // 'item' | 'location' | 'recipe' | 'task'
  TextColumn get photoPath => text()(); // relative to vault root: photos/UUID.jpg
  TextColumn get caption => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}
