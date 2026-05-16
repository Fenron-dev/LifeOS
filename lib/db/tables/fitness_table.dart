import 'package:drift/drift.dart';

/// Phase 6.8 – Fitness tracking: exercise library, workout sessions, sets.
/// Phase 7.x – Extended exercise details + workout plans.

class Exercises extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  /// chest|back|legs|shoulders|arms|core|cardio
  TextColumn get category => text()();
  /// barbell|dumbbell|machine|bodyweight|cable|other
  TextColumn get equipment => text().nullable()();
  /// JSON list of primary muscle groups, e.g. '["Brust","Trizeps"]'
  TextColumn get muscleGroups => text().nullable()();
  /// JSON list of secondary muscle groups
  TextColumn get muscleGroupsSecondary => text().nullable()();
  TextColumn get notes => text().nullable()();
  /// beginner | intermediate | advanced
  TextColumn get difficulty => text().nullable()();
  /// Step-by-step instructions (plain text, newline-separated)
  TextColumn get instructions => text().nullable()();
  /// YouTube or GIF URL for demonstration
  TextColumn get videoUrl => text().nullable()();
  /// Estimated kcal burned per minute at moderate intensity
  RealColumn get caloriesPerMinute => real().nullable()();
  /// Tips for safe/correct execution
  TextColumn get tips => text().nullable()();
  BoolColumn get isCustom =>
      boolean().withDefault(const Constant(false))();
  /// One-liner description shown below the title in the detail view
  TextColumn get shortDescription => text().nullable()();
  BoolColumn get isFavorite =>
      boolean().withDefault(const Constant(false))();
  IntColumn get starRating => integer().nullable()(); // 1–5
  IntColumn get thumbRating => integer().nullable()(); // -1 | 0 | 1
  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

class Workouts extends Table {
  TextColumn get id => text()();
  /// Optional session name, e.g. "Push Day", "Montag A"
  TextColumn get name => text().nullable()();
  /// Optional plan reference
  TextColumn get planId =>
      text().nullable().references(WorkoutPlans, #id, onDelete: KeyAction.setNull)();
  DateTimeColumn get startedAt => dateTime()();
  DateTimeColumn get endedAt => dateTime().nullable()();
  IntColumn get durationMinutes => integer().nullable()();
  /// Null = timer not yet started; set when user taps "Training starten"
  DateTimeColumn get timerStartedAt => dateTime().nullable()();
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
  /// Cardio / timed: duration in seconds
  IntColumn get durationSeconds => integer().nullable()();
  /// Cardio: distance in km
  RealColumn get distanceKm => real().nullable()();
  /// Rate of Perceived Exertion 1–10
  RealColumn get rpe => real().nullable()();
  TextColumn get notes => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

// ── Workout Plans ─────────────────────────────────────────────────────────────

class WorkoutPlans extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get description => text().nullable()();
  /// Personal notes, goals, equipment list etc.
  TextColumn get notes => text().nullable()();
  BoolColumn get isActive =>
      boolean().withDefault(const Constant(true))();
  BoolColumn get isFavorite =>
      boolean().withDefault(const Constant(false))();
  IntColumn get starRating => integer().nullable()(); // 1–5
  IntColumn get thumbRating => integer().nullable()(); // -1 | 0 | 1
  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// An exercise slot inside a plan for a specific day of week.
class WorkoutPlanExercises extends Table {
  TextColumn get id => text()();
  TextColumn get planId => text()
      .references(WorkoutPlans, #id, onDelete: KeyAction.cascade)();
  TextColumn get exerciseId => text()
      .references(Exercises, #id, onDelete: KeyAction.restrict)();
  /// 0 = Monday … 6 = Sunday; null = template (no specific day, always shown)
  IntColumn get dayOfWeek => integer().nullable()();
  IntColumn get targetSets => integer().nullable()();
  IntColumn get targetReps => integer().nullable()();
  IntColumn get targetDurationSeconds => integer().nullable()();
  /// Rest time between sets in seconds (default 60)
  IntColumn get targetRestSeconds =>
      integer().withDefault(const Constant(60))();
  IntColumn get sortOrder =>
      integer().withDefault(const Constant(0))();
  /// HH:mm reminder time for this day, e.g. "07:30". Null = no reminder.
  TextColumn get reminderTime => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
