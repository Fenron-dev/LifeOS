import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../db/database.dart';
import '../../providers/vault_provider.dart';

/// All meal types, sorted by sort_order. Shared across diary and settings.
final mealTypesProvider = StreamProvider<List<MealType>>((ref) {
  final db = ref.watch(databaseProvider);
  if (db == null) return const Stream.empty();
  return db.watchAllMealTypes();
});

const _uuid = Uuid();

/// Stream of all nutrition log entries for the given calendar [day].
final nutritionLogsForDayProvider =
    StreamProvider.family<List<NutritionLog>, DateTime>((ref, day) {
  final db = ref.watch(databaseProvider);
  if (db == null) return const Stream.empty();
  return db.watchLogsForDay(day);
});

/// Summed macros for [day] — re-fetched whenever the log stream changes.
final dailyTotalsProvider =
    FutureProvider.family<DailyNutritionTotals, DateTime>((ref, day) async {
  // Invalidate when any log entry for this day is added/removed.
  ref.watch(nutritionLogsForDayProvider(day));
  final db = ref.watch(databaseProvider);
  if (db == null) {
    return const DailyNutritionTotals(
        kcal: 0, proteinG: 0, carbsG: 0, fatG: 0);
  }
  return db.dailyNutritionTotals(day);
});

/// All logs within a date range [from, to) for the history/overview screen.
final nutritionLogsForRangeProvider =
    FutureProvider.family<List<NutritionLog>, (DateTime, DateTime)>(
        (ref, range) async {
  final db = ref.watch(databaseProvider);
  if (db == null) return [];
  return db.getLogsForRange(range.$1, range.$2);
});

/// Estimated food cost in € for the given date range.
/// Returns null when no priced items were logged.
final consumedFoodCostProvider =
    FutureProvider.family<double?, (DateTime, DateTime)>((ref, range) async {
  final db = ref.watch(databaseProvider);
  if (db == null) return null;
  ref.watch(nutritionLogsForDayProvider(range.$1));
  return db.consumedFoodCostForRange(range.$1, range.$2);
});

/// Estimated consumed vs. wasted food cost for [year].
final foodFinancialStatsProvider =
    FutureProvider.family<({double consumed, double wasted}), int>((ref, year) async {
  final db = ref.watch(databaseProvider);
  if (db == null) return (consumed: 0.0, wasted: 0.0);
  return db.foodFinancialStatsForYear(year);
});

/// Health factor counts for [from]..[to]: {1: healthy, 0: neutral, -1: unhealthy, null: unknown}.
final healthFactorStatsProvider =
    FutureProvider.family<Map<int?, int>, (DateTime, DateTime)>((ref, range) async {
  final db = ref.watch(databaseProvider);
  if (db == null) return {};
  return db.healthFactorStats(range.$1, range.$2);
});

final nutritionOpsProvider =
    AsyncNotifierProvider<NutritionOpsNotifier, void>(
        NutritionOpsNotifier.new);

class NutritionOpsNotifier extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  AppDatabase get _db => ref.read(databaseProvider)!;

  Future<String> logFood({
    String? id,
    required DateTime loggedAt,
    required String productName,
    String? brand,
    String? mealTypeId,
    String? itemId,
    String? ean,
    required double quantityG,
    String displayUnit = 'g',
    double? kcal,
    double? proteinG,
    double? carbsG,
    double? fatG,
    double? fiberG,
    String source = 'manual',
    String? notes,
  }) async {
    final logId = id ?? _uuid.v4();
    await _db.insertNutritionLog(NutritionLogsCompanion.insert(
      id: logId,
      loggedAt: loggedAt,
      productName: productName,
      quantityG: quantityG,
      mealTypeId: Value(mealTypeId),
      itemId: Value(itemId),
      ean: Value(ean),
      brand: Value(brand),
      displayUnit: Value(displayUnit),
      kcal: Value(kcal),
      proteinG: Value(proteinG),
      carbsG: Value(carbsG),
      fatG: Value(fatG),
      fiberG: Value(fiberG),
      source: Value(source),
      notes: Value(notes),
    ));
    return logId;
  }

  Future<void> setThumbRating(String logId, String? thumbRating) async {
    await _db.setNutritionLogThumb(logId, thumbRating);
    ref.invalidate(nutritionLogsForDayProvider);
  }

  Future<void> setInventoryDeducted(String logId, bool deducted) async {
    await _db.setNutritionLogDeducted(logId, deducted);
    ref.invalidate(nutritionLogsForDayProvider);
  }

  Future<void> updateLog(NutritionLogsCompanion entry) async {
    await _db.updateNutritionLog(entry);
    // Drift streams auto-emit; dailyTotalsProvider watches nutritionLogsForDayProvider
    // and rebuilds automatically — no explicit invalidation needed.
    ref.invalidate(nutritionLogsForDayProvider);
  }

  Future<void> deleteLog(String id) async {
    await _db.deleteNutritionLog(id);
    ref.invalidate(nutritionLogsForDayProvider);
  }
}
