import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../db/database.dart';
import '../../providers/vault_provider.dart';
import '../services/health_calc.dart';

/// Single-row profile stream. `null` while no row exists yet (fresh vault).
final userProfileProvider = StreamProvider<UserProfileData?>((ref) {
  final db = ref.watch(databaseProvider);
  if (db == null) return const Stream.empty();
  return db.watchUserProfile();
});

/// Derived BMR/TDEE/calorie suggestion based on the current profile + most
/// recent weight. Returns nulls when prerequisites are missing so the UI can
/// nudge the user to fill in the missing pieces.
class HealthDerivedTargets {
  final int? ageYears;
  final double? bmr;
  final double? tdee;
  final int? suggestedDailyKcal;
  final double? bmi;

  const HealthDerivedTargets({
    required this.ageYears,
    required this.bmr,
    required this.tdee,
    required this.suggestedDailyKcal,
    required this.bmi,
  });

  static const empty = HealthDerivedTargets(
    ageYears: null,
    bmr: null,
    tdee: null,
    suggestedDailyKcal: null,
    bmi: null,
  );
}

final healthDerivedTargetsProvider = Provider<HealthDerivedTargets>((ref) {
  final profile = ref.watch(userProfileProvider).valueOrNull;
  final db = ref.watch(databaseProvider);
  if (profile == null || db == null) return HealthDerivedTargets.empty;

  // Use the most recent weight if available; fall back to the start weight
  // so a brand-new user with only a goal can still see a BMR estimate.
  final logs = ref.watch(_latestWeightForCalcProvider).valueOrNull;
  final weight = logs ?? profile.startWeightKg;

  final age = HealthCalc.ageYears(profile.birthDate);
  final bmr = HealthCalc.bmrMifflin(
    weightKg: weight,
    heightCm: profile.heightCm,
    ageYears: age,
    sex: profile.sex,
  );
  final tdee = HealthCalc.tdee(
    bmr: bmr,
    activityLevel: profile.activityLevel,
  );
  final suggested = HealthCalc.suggestedDailyCalories(tdee: tdee);
  final bmi = HealthCalc.bmi(
    weightKg: weight,
    heightCm: profile.heightCm,
  );

  return HealthDerivedTargets(
    ageYears: age,
    bmr: bmr,
    tdee: tdee,
    suggestedDailyKcal: suggested,
    bmi: bmi,
  );
});

/// Internal helper that fetches just the latest weight as a `double?`.
/// Lives here (not in weight_provider) because it's only useful as
/// dependency for [healthDerivedTargetsProvider].
final _latestWeightForCalcProvider = FutureProvider<double?>((ref) async {
  final db = ref.watch(databaseProvider);
  final log = await db?.latestWeightLog();
  return log?.weightKg;
});

final profileOpsProvider =
    AsyncNotifierProvider<ProfileOpsNotifier, void>(ProfileOpsNotifier.new);

class ProfileOpsNotifier extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  AppDatabase get _db => ref.read(databaseProvider)!;

  /// Patch the singleton profile row. Pass `Value.absent()` to leave a field
  /// untouched. The DB layer pins `id = 1` so multiple-row corruption isn't
  /// possible even if a caller supplied a different id.
  Future<void> save({
    Value<String?> displayName = const Value.absent(),
    Value<DateTime?> birthDate = const Value.absent(),
    Value<String?> sex = const Value.absent(),
    Value<double?> heightCm = const Value.absent(),
    Value<double> activityLevel = const Value.absent(),
    Value<double?> startWeightKg = const Value.absent(),
    Value<double?> targetWeightKg = const Value.absent(),
    Value<int?> dailyCalorieGoal = const Value.absent(),
    Value<int> dailyWaterGoalMl = const Value.absent(),
    Value<double?> proteinTargetG = const Value.absent(),
    Value<double?> carbsTargetG = const Value.absent(),
    Value<double?> fatTargetG = const Value.absent(),
    Value<String?> dietPlan = const Value.absent(),
  }) async {
    await _db.upsertUserProfile(UserProfileCompanion(
      displayName: displayName,
      birthDate: birthDate,
      sex: sex,
      heightCm: heightCm,
      activityLevel: activityLevel,
      startWeightKg: startWeightKg,
      targetWeightKg: targetWeightKg,
      dailyCalorieGoal: dailyCalorieGoal,
      dailyWaterGoalMl: dailyWaterGoalMl,
      proteinTargetG: proteinTargetG,
      carbsTargetG: carbsTargetG,
      fatTargetG: fatTargetG,
      dietPlan: dietPlan,
      updatedAt: Value(DateTime.now()),
    ));
  }
}
