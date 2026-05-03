import 'package:drift/drift.dart';

/// Phase 6.8 – Fitness tracking: exercise library, workout sessions, sets.

class Exercises extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  /// chest|back|legs|shoulders|arms|core|cardio
  TextColumn get category => text()();
  /// barbell|dumbbell|machine|bodyweight|cable|other
  TextColumn get equipment => text().nullable()();
  /// JSON list of primary muscle groups, e.g. '["Brust","Trizeps"]'
  TextColumn get muscleGroups => text().nullable()();
  TextColumn get notes => text().nullable()();
  BoolColumn get isCustom =>
      boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

class Workouts extends Table {
  TextColumn get id => text()();
  /// Optional session name, e.g. "Push Day", "Montag A"
  TextColumn get name => text().nullable()();
  DateTimeColumn get startedAt => dateTime()();
  DateTimeColumn get endedAt => dateTime().nullable()();
  IntColumn get durationMinutes => integer().nullable()();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

class WorkoutSets extends Table {
  TextColumn get id => text()();
  TextColumn get workoutId => text()
      .references(Workouts, #id, onDelete: KeyAction.cascade)();
  TextColumn get exerciseId => text()
      .references(Exercises, #id, onDelete: KeyAction.restrict)();
  IntColumn get setNumber => integer()();
  IntColumn get reps => integer().nullable()();
  RealColumn get weightKg => real().nullable()();
  /// Cardio: duration in seconds
  IntColumn get durationSeconds => integer().nullable()();
  /// Cardio: distance in km
  RealColumn get distanceKm => real().nullable()();
  /// Rate of Perceived Exertion 1–10
  RealColumn get rpe => real().nullable()();
  TextColumn get notes => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
