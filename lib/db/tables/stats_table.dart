import 'package:drift/drift.dart';

/// Body measurements log — one row per measurement session. All metrics are
/// in centimetres and nullable so the user can capture any subset (e.g. only
/// waist and hip) without leaving other fields empty in the UI.
class BodyMeasurements extends Table {
  TextColumn get id => text()();
  DateTimeColumn get loggedAt => dateTime()();

  RealColumn get chestCm => real().nullable()();        // Brust
  RealColumn get waistCm => real().nullable()();        // Taille
  RealColumn get hipCm => real().nullable()();          // Hüfte
  RealColumn get thighCm => real().nullable()();        // Oberschenkel
  RealColumn get armCm => real().nullable()();          // Arm / Bizeps
  RealColumn get neckCm => real().nullable()();         // Nacken

  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// Body weight log entries — one row per weigh-in. Also captures full
/// body-composition data when the scale provides it (body-fat / muscle /
/// visceral / water / bone). All extra metrics are nullable so a manual
/// quick-entry with just a weight value still works.
class BodyWeightLogs extends Table {
  TextColumn get id => text()();
  DateTimeColumn get loggedAt => dateTime()();
  RealColumn get weightKg => real()();

  // Body composition (smart-scale extras). All optional.
  RealColumn get bodyFatPct => real().nullable()();
  RealColumn get muscleMassPct => real().nullable()();
  RealColumn get visceralFat => real().nullable()();
  RealColumn get waterPct => real().nullable()();
  RealColumn get boneMassKg => real().nullable()();

  // Where the data came from. Defaults to manual; future Bluetooth or
  // health-platform imports would set 'scale' / 'import'.
  TextColumn get source => text().withDefault(const Constant('manual'))();

  TextColumn get notes => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Singleton row holding the user's personal profile: birth date, sex,
/// height and activity level for BMR/TDEE calculation, plus weight goals
/// and daily calorie/water targets used by the diary screen.
///
/// One row per vault. The `id` column is fixed at 1 for all upserts.
class UserProfile extends Table {
  IntColumn get id => integer().withDefault(const Constant(1))();

  TextColumn get displayName => text().nullable()();
  DateTimeColumn get birthDate => dateTime().nullable()();
  TextColumn get sex => text().nullable()();             // male|female|diverse
  RealColumn get heightCm => real().nullable()();

  // PAL multiplier — 1.2 sedentary / 1.4 light / 1.55 moderate / 1.75 strong
  // / 1.9 extreme. Default 1.4 for someone with a normal day-job.
  RealColumn get activityLevel => real().withDefault(const Constant(1.4))();

  // Weight goal context (used by the weight chart's reference lines).
  RealColumn get startWeightKg => real().nullable()();
  RealColumn get targetWeightKg => real().nullable()();

  // Daily targets (manual override of the BMR/TDEE-derived suggestion).
  IntColumn get dailyCalorieGoal => integer().nullable()();
  IntColumn get dailyWaterGoalMl =>
      integer().withDefault(const Constant(2000))();

  // Optional macro split (g/day). Filled when a diet plan is picked.
  RealColumn get proteinTargetG => real().nullable()();
  RealColumn get carbsTargetG => real().nullable()();
  RealColumn get fatTargetG => real().nullable()();

  // Diet plan tag: keto|mediterranean|if|highprotein|lowcarb|balanced|custom
  TextColumn get dietPlan => text().nullable()();

  DateTimeColumn get updatedAt =>
      dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// Water intake log — one row per drink. All amounts in millilitres.
class WaterLogs extends Table {
  TextColumn get id => text()();
  DateTimeColumn get loggedAt => dateTime()();
  IntColumn get amountMl => integer()();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}
