import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeos/db/database.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  // ── helpers ────────────────────────────────────────────────────────────────

  Future<void> addLog({
    required String id,
    required DateTime at,
    double kcal = 0,
    double protein = 0,
    double carbs = 0,
    double fat = 0,
    String? mealTypeId,
  }) =>
      db.insertNutritionLog(NutritionLogsCompanion.insert(
        id: id,
        loggedAt: at,
        productName: 'Test $id',
        quantityG: 100,
        kcal: Value(kcal),
        proteinG: Value(protein),
        carbsG: Value(carbs),
        fatG: Value(fat),
        mealTypeId: Value(mealTypeId),
      ));

  // ── tests ──────────────────────────────────────────────────────────────────

  test('insert and retrieve a full nutrition log entry', () async {
    await db.insertNutritionLog(NutritionLogsCompanion.insert(
      id: 'n1',
      loggedAt: DateTime(2026, 5, 1, 8, 0),
      productName: 'Haferflocken',
      brand: const Value('Quaker'),
      quantityG: 80,
      displayUnit: const Value('g'),
      kcal: const Value(302.4),
      proteinG: const Value(8.6),
      carbsG: const Value(55.2),
      fatG: const Value(5.6),
      fiberG: const Value(7.2),
      source: const Value('off'),
      mealTypeId: const Value('mt_fruehstueck'),
    ));

    final rows = await db.select(db.nutritionLogs).get();
    expect(rows.length, 1);
    final row = rows.single;
    expect(row.productName, 'Haferflocken');
    expect(row.brand, 'Quaker');
    expect(row.quantityG, 80);
    expect(row.kcal, closeTo(302.4, 0.01));
    expect(row.proteinG, closeTo(8.6, 0.01));
    expect(row.carbsG, closeTo(55.2, 0.01));
    expect(row.source, 'off');
    expect(row.mealTypeId, 'mt_fruehstueck');
  });

  test('watchLogsForDay only returns entries on the same calendar day',
      () async {
    final day = DateTime(2026, 5, 1);
    await addLog(id: 'morning', at: DateTime(2026, 5, 1, 8, 0), kcal: 300);
    await addLog(id: 'noon', at: DateTime(2026, 5, 1, 12, 30), kcal: 650);
    await addLog(id: 'yesterday', at: DateTime(2026, 4, 30, 20, 0), kcal: 200);
    await addLog(id: 'tomorrow', at: DateTime(2026, 5, 2, 7, 0), kcal: 100);

    final logs = await db.watchLogsForDay(day).first;
    final ids = logs.map((l) => l.id).toSet();
    expect(ids, containsAll(['morning', 'noon']));
    expect(ids, isNot(contains('yesterday')));
    expect(ids, isNot(contains('tomorrow')));
  });

  test('watchLogsForDay returns entries ordered by loggedAt ascending',
      () async {
    final day = DateTime(2026, 5, 1);
    await addLog(id: 'late', at: DateTime(2026, 5, 1, 19, 0));
    await addLog(id: 'early', at: DateTime(2026, 5, 1, 7, 0));
    await addLog(id: 'mid', at: DateTime(2026, 5, 1, 12, 0));

    final logs = await db.watchLogsForDay(day).first;
    expect(logs.map((l) => l.id).toList(), ['early', 'mid', 'late']);
  });

  test('dailyNutritionTotals sums macros for the day', () async {
    final day = DateTime(2026, 5, 1);
    await addLog(
        id: 'a', at: DateTime(2026, 5, 1, 8), kcal: 300, protein: 10, carbs: 50, fat: 5);
    await addLog(
        id: 'b', at: DateTime(2026, 5, 1, 12), kcal: 700, protein: 30, carbs: 80, fat: 20);
    // different day — must NOT be included
    await addLog(id: 'c', at: DateTime(2026, 5, 2, 8), kcal: 999);

    final totals = await db.dailyNutritionTotals(day);
    expect(totals.kcal, closeTo(1000, 0.01));
    expect(totals.proteinG, closeTo(40, 0.01));
    expect(totals.carbsG, closeTo(130, 0.01));
    expect(totals.fatG, closeTo(25, 0.01));
  });

  test('dailyNutritionTotals returns zeros for an empty day', () async {
    final totals =
        await db.dailyNutritionTotals(DateTime(2026, 5, 1));
    expect(totals.kcal, 0);
    expect(totals.proteinG, 0);
    expect(totals.carbsG, 0);
    expect(totals.fatG, 0);
  });

  test('deleteNutritionLog removes the entry', () async {
    await addLog(id: 'del', at: DateTime(2026, 5, 1, 8), kcal: 500);
    expect((await db.select(db.nutritionLogs).get()).length, 1);
    await db.deleteNutritionLog('del');
    expect((await db.select(db.nutritionLogs).get()).length, 0);
  });

  test('nutrition_logs indexes exist after onCreate', () async {
    await db.customSelect('SELECT 1').get(); // trigger onCreate
    final rows = await db.customSelect(
      "SELECT name FROM sqlite_master WHERE type='index' "
      "AND name IN ('idx_nutr_logged_at','idx_nutr_meal_type')",
    ).get();
    final names = rows.map((r) => r.read<String>('name')).toSet();
    expect(names, containsAll(['idx_nutr_logged_at', 'idx_nutr_meal_type']));
  });
}
