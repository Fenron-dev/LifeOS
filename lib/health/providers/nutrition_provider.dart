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

final nutritionOpsProvider =
    AsyncNotifierProvider<NutritionOpsNotifier, void>(
        NutritionOpsNotifier.new);

class NutritionOpsNotifier extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  AppDatabase get _db => ref.read(databaseProvider)!;

  Future<void> logFood({
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
    await _db.insertNutritionLog(NutritionLogsCompanion.insert(
      id: _uuid.v4(),
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
  }

  Future<void> updateLog(NutritionLogsCompanion entry) async {
    await _db.updateNutritionLog(entry);
    // Drift streams should auto-emit, but explicit invalidation ensures
    // derived FutureProviders (dailyTotalsProvider) refresh immediately.
    ref.invalidate(nutritionLogsForDayProvider);
    ref.invalidate(dailyTotalsProvider);
  }

  Future<void> deleteLog(String id) async {
    await _db.deleteNutritionLog(id);
    ref.invalidate(nutritionLogsForDayProvider);
    ref.invalidate(dailyTotalsProvider);
  }
}
