import 'package:drift/drift.dart';

/// Shops where items are purchased.
class Shops extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// Unit conversion rules.
/// Meaning: 1 [fromUnit] = [factor] × [toUnit]
/// Example: Packung → Stück, factor = 6  →  1 Packung = 6 Stück
///
/// Scope resolution order (highest wins): item > group > global
class UnitConversions extends Table {
  TextColumn get id => text()();
  TextColumn get fromUnit => text()();
  TextColumn get toUnit => text()();
  RealColumn get factor => real()(); // 1 fromUnit = factor toUnit

  // 'global' | 'group' | 'item'
  TextColumn get scope =>
      text().withDefault(const Constant('global'))();
  // Null for global; groupId or itemId otherwise
  TextColumn get scopeId => text().nullable()();

  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}
