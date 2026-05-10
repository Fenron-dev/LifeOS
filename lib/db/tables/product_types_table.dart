import 'package:drift/drift.dart';

/// User-manageable product type definitions.
/// Built-in types (isBuiltIn=true) cannot be deleted via UI.
class ProductTypeDefinitions extends Table {
  TextColumn get id => text()();
  TextColumn get nameDe => text()();
  TextColumn get nameEn => text().nullable()();
  TextColumn get iconName => text().nullable()();
  BoolColumn get isBuiltIn =>
      boolean().withDefault(const Constant(false))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}
