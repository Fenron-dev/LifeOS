import 'package:drift/drift.dart';

/// Body weight log entries — one row per weigh-in.
class BodyWeightLogs extends Table {
  TextColumn get id => text()();
  DateTimeColumn get loggedAt => dateTime()();
  RealColumn get weightKg => real()();
  TextColumn get notes => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
