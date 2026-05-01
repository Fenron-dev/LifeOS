import 'dart:math' as math;

/// Pure-Dart calculations for the health sub-system. Kept separate from any
/// Flutter / Drift code so they're trivially unit-testable.
class HealthCalc {
  HealthCalc._();

  /// Age in whole years on [today] given a [birthDate]. Returns null if the
  /// birth date is missing or in the future.
  static int? ageYears(DateTime? birthDate, {DateTime? today}) {
    if (birthDate == null) return null;
    final now = today ?? DateTime.now();
    if (!birthDate.isBefore(now)) return null;
    var years = now.year - birthDate.year;
    final notYetThisYear = now.month < birthDate.month ||
        (now.month == birthDate.month && now.day < birthDate.day);
    if (notYetThisYear) years -= 1;
    return years;
  }

  /// Mifflin-St Jeor BMR in kcal/day.
  /// `sex` accepted: 'male', 'female', 'diverse'/null → returns the average.
  /// Returns null when any input is missing or non-positive.
  static double? bmrMifflin({
    required double? weightKg,
    required double? heightCm,
    required int? ageYears,
    required String? sex,
  }) {
    if (weightKg == null || weightKg <= 0) return null;
    if (heightCm == null || heightCm <= 0) return null;
    if (ageYears == null || ageYears < 0) return null;

    final base = 10 * weightKg + 6.25 * heightCm - 5 * ageYears;
    return switch (sex) {
      'male' => base + 5,
      'female' => base - 161,
      _ => base - 78, // average of +5 and −161 for diverse / unspecified
    };
  }

  /// Total daily energy expenditure (TDEE) in kcal/day.
  /// [activityLevel] is the PAL multiplier: 1.2 / 1.4 / 1.55 / 1.75 / 1.9.
  static double? tdee({
    required double? bmr,
    required double activityLevel,
  }) {
    if (bmr == null || bmr <= 0) return null;
    if (activityLevel <= 0) return null;
    return bmr * activityLevel;
  }

  /// BMI in kg/m². Returns null when inputs are missing or non-positive.
  static double? bmi({required double? weightKg, required double? heightCm}) {
    if (weightKg == null || weightKg <= 0) return null;
    if (heightCm == null || heightCm <= 0) return null;
    final m = heightCm / 100.0;
    return weightKg / (m * m);
  }

  /// Suggested daily calorie goal: TDEE minus a deficit (defaults 500 kcal).
  /// Floored at a sane minimum so a careless deficit can't recommend
  /// unhealthy targets.
  static int? suggestedDailyCalories({
    required double? tdee,
    int deficit = 500,
    int minimumKcal = 1200,
  }) {
    if (tdee == null) return null;
    final raw = (tdee - deficit).round();
    return math.max(raw, minimumKcal);
  }
}
