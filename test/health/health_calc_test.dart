import 'package:flutter_test/flutter_test.dart';
import 'package:lifeos/health/services/health_calc.dart';

void main() {
  group('HealthCalc.ageYears', () {
    test('returns age before/after birthday correctly', () {
      // Birthday 1990-06-15. Today simulated.
      final bd = DateTime(1990, 6, 15);
      expect(HealthCalc.ageYears(bd, today: DateTime(2026, 5, 1)), 35);
      expect(HealthCalc.ageYears(bd, today: DateTime(2026, 6, 14)), 35);
      expect(HealthCalc.ageYears(bd, today: DateTime(2026, 6, 15)), 36);
      expect(HealthCalc.ageYears(bd, today: DateTime(2026, 7, 1)), 36);
    });

    test('returns null for missing or future birth date', () {
      expect(HealthCalc.ageYears(null), isNull);
      final future = DateTime.now().add(const Duration(days: 1));
      expect(HealthCalc.ageYears(future), isNull);
    });
  });

  group('HealthCalc.bmrMifflin', () {
    test('male formula matches the textbook example', () {
      // Reference: 80kg, 180cm, 30y, male → 1780
      final bmr = HealthCalc.bmrMifflin(
        weightKg: 80,
        heightCm: 180,
        ageYears: 30,
        sex: 'male',
      );
      expect(bmr, closeTo(1780, 0.5));
    });

    test('female formula offsets by 161 below the base', () {
      final male = HealthCalc.bmrMifflin(
        weightKg: 65,
        heightCm: 170,
        ageYears: 30,
        sex: 'male',
      )!;
      final female = HealthCalc.bmrMifflin(
        weightKg: 65,
        heightCm: 170,
        ageYears: 30,
        sex: 'female',
      )!;
      expect(male - female, closeTo(166, 0.001)); // (+5) − (−161) = 166
    });

    test('returns null when any input is missing or non-positive', () {
      expect(
          HealthCalc.bmrMifflin(
              weightKg: null, heightCm: 170, ageYears: 30, sex: 'male'),
          isNull);
      expect(
          HealthCalc.bmrMifflin(
              weightKg: 0, heightCm: 170, ageYears: 30, sex: 'male'),
          isNull);
      expect(
          HealthCalc.bmrMifflin(
              weightKg: 70, heightCm: 0, ageYears: 30, sex: 'male'),
          isNull);
    });
  });

  group('HealthCalc.tdee', () {
    test('multiplies BMR by activity level', () {
      expect(HealthCalc.tdee(bmr: 1500, activityLevel: 1.55),
          closeTo(2325, 0.001));
    });

    test('returns null for missing BMR', () {
      expect(HealthCalc.tdee(bmr: null, activityLevel: 1.4), isNull);
    });
  });

  group('HealthCalc.suggestedDailyCalories', () {
    test('subtracts deficit from TDEE', () {
      expect(HealthCalc.suggestedDailyCalories(tdee: 2500), 2000);
      expect(HealthCalc.suggestedDailyCalories(tdee: 2500, deficit: 300),
          2200);
    });

    test('floors at safe minimum so a careless deficit cannot starve', () {
      expect(
          HealthCalc.suggestedDailyCalories(tdee: 1300, deficit: 800), 1200);
    });
  });

  group('HealthCalc.bmi', () {
    test('80kg / 1.80m → 24.69', () {
      expect(HealthCalc.bmi(weightKg: 80, heightCm: 180),
          closeTo(24.69, 0.01));
    });
  });
}
