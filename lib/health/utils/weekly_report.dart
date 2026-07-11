import '../../db/database.dart';

/// Pure aggregation for the "Deine Woche" card — testable without providers.
class WeeklyReport {
  final double avgKcal; // average over days that have logs
  final int daysLogged; // 0–7
  final int proteinTargetHits; // days with protein ≥ target
  final bool hasProteinTarget;
  final double? weightDeltaKg; // last log − first log within the week
  final int workoutCount;

  const WeeklyReport({
    required this.avgKcal,
    required this.daysLogged,
    required this.proteinTargetHits,
    required this.hasProteinTarget,
    required this.weightDeltaKg,
    required this.workoutCount,
  });

  bool get isEmpty => daysLogged == 0 && workoutCount == 0 && weightDeltaKg == null;

  /// [dailyTotals] must contain one entry per day of the report week
  /// (null/zero-kcal days count as "not logged").
  static WeeklyReport compute({
    required List<DailyNutritionTotals?> dailyTotals,
    required double? proteinTargetG,
    required List<BodyWeightLog> weightLogsInWeek,
    required int workoutCount,
  }) {
    final logged = dailyTotals
        .whereType<DailyNutritionTotals>()
        .where((t) => t.kcal > 0)
        .toList();
    final avgKcal = logged.isEmpty
        ? 0.0
        : logged.fold<double>(0, (s, t) => s + t.kcal) / logged.length;
    final proteinHits = proteinTargetG == null || proteinTargetG <= 0
        ? 0
        : logged.where((t) => t.proteinG >= proteinTargetG).length;

    double? weightDelta;
    if (weightLogsInWeek.length >= 2) {
      final sorted = [...weightLogsInWeek]
        ..sort((a, b) => a.loggedAt.compareTo(b.loggedAt));
      weightDelta = sorted.last.weightKg - sorted.first.weightKg;
    }

    return WeeklyReport(
      avgKcal: avgKcal,
      daysLogged: logged.length,
      proteinTargetHits: proteinHits,
      hasProteinTarget: proteinTargetG != null && proteinTargetG > 0,
      weightDeltaKg: weightDelta,
      workoutCount: workoutCount,
    );
  }
}
