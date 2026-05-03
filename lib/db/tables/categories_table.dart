import 'package:drift/drift.dart';

/// User-defined item categories (Phase 4).
/// Built-in categories (food, appliance, …) are defined in
/// [ItemCategory] constants and need no row here.
class CategoryDefinitions extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  /// Optional Material icon name (e.g. 'fitness_center', 'local_cafe').
  TextColumn get iconName => text().nullable()();
  IntColumn get sortOrder =>
      integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}
