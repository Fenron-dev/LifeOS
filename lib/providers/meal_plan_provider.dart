import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../db/database.dart';
import 'vault_provider.dart';

/// Stream of plan entries for a given date range [from, to).
final mealPlanEntriesProvider =
    StreamProvider.family<List<MealPlanEntry>, (DateTime, DateTime)>(
        (ref, range) {
  final db = ref.watch(databaseProvider);
  if (db == null) return const Stream.empty();
  return db.watchPlanEntriesForRange(range.$1, range.$2);
});

final mealPlanOpsProvider =
    AsyncNotifierProvider<MealPlanOpsNotifier, void>(MealPlanOpsNotifier.new);

class MealPlanOpsNotifier extends AsyncNotifier<void> {
  static const _uuid = Uuid();

  @override
  Future<void> build() async {}

  AppDatabase get _db => ref.read(databaseProvider)!;

  Future<void> addEntry({
    required DateTime date,
    String? mealTypeId,
    String? recipeId,
    String? dishId,
    String? itemId,
    required String entryName,
    double servings = 1.0,
    double? kcalPerServing,
    String? notes,
  }) async {
    await _db.insertMealPlanEntry(MealPlanEntriesCompanion.insert(
      id: _uuid.v4(),
      date: date,
      mealTypeId: Value(mealTypeId),
      recipeId: Value(recipeId),
      dishId: Value(dishId),
      itemId: Value(itemId),
      entryName: entryName,
      servings: Value(servings),
      kcalPerServing: Value(kcalPerServing),
      notes: Value(notes),
    ));
    ref.invalidate(mealPlanEntriesProvider);
  }

  Future<void> deleteEntry(String id) async {
    await _db.deleteMealPlanEntry(id);
    ref.invalidate(mealPlanEntriesProvider);
  }

  Future<void> updateServings(String id, double servings,
      {double? kcalPerServing}) async {
    await _db.updateMealPlanEntry(MealPlanEntriesCompanion(
      id: Value(id),
      servings: Value(servings),
      kcalPerServing: Value(kcalPerServing),
    ));
    ref.invalidate(mealPlanEntriesProvider);
  }
}
