import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../db/database.dart';
import 'vault_provider.dart';

// ---------------------------------------------------------------------------
// All recipes (watched stream)
// ---------------------------------------------------------------------------

final allRecipesProvider = StreamProvider<List<Recipe>>((ref) {
  final db = ref.watch(databaseProvider);
  if (db == null) return const Stream.empty();
  return db.watchAllRecipes();
});

// ---------------------------------------------------------------------------
// Search query state
// ---------------------------------------------------------------------------

final recipeSearchQueryProvider = StateProvider<String>((ref) => '');

/// Currently selected recipe in the tablet/desktop split view. Null when
/// nothing is selected. Mobile navigates via the router and ignores this.
final selectedRecipeIdProvider = StateProvider<String?>((ref) => null);

// ---------------------------------------------------------------------------
// Filtered recipes
// ---------------------------------------------------------------------------

final filteredRecipesProvider = StreamProvider<List<Recipe>>((ref) {
  final db = ref.watch(databaseProvider);
  if (db == null) return const Stream.empty();
  final query = ref.watch(recipeSearchQueryProvider);
  if (query.trim().isEmpty) return db.watchAllRecipes();
  return db.searchRecipes(query.trim());
});

// ---------------------------------------------------------------------------
// Single recipe by id
// ---------------------------------------------------------------------------

final recipeByIdProvider =
    FutureProvider.family<Recipe?, String>((ref, id) async {
  final db = ref.watch(databaseProvider);
  return db?.recipeById(id);
});

// ---------------------------------------------------------------------------
// Ingredients for recipe
// ---------------------------------------------------------------------------

final recipeIngredientsProvider =
    FutureProvider.family<List<RecipeIngredient>, String>((ref, recipeId) async {
  final db = ref.watch(databaseProvider);
  if (db == null) return [];
  return db.ingredientsForRecipe(recipeId);
});

// ---------------------------------------------------------------------------
// Steps for recipe
// ---------------------------------------------------------------------------

final recipeStepsProvider =
    FutureProvider.family<List<RecipeStep>, String>((ref, recipeId) async {
  final db = ref.watch(databaseProvider);
  if (db == null) return [];
  return db.stepsForRecipe(recipeId);
});

// ---------------------------------------------------------------------------
// Tags for recipe (normalized via recipe_tags junction)
// ---------------------------------------------------------------------------

final recipeTagsProvider =
    FutureProvider.family<List<String>, String>((ref, recipeId) async {
  final db = ref.watch(databaseProvider);
  if (db == null) return [];
  return db.tagsForRecipe(recipeId);
});

// ---------------------------------------------------------------------------
// Computed nutrition from recipe ingredients (linked items only)
// ---------------------------------------------------------------------------

final recipeComputedNutritionProvider =
    FutureProvider.family<RecipeNutritionData?, String>((ref, recipeId) async {
  final db = ref.watch(databaseProvider);
  if (db == null) return null;
  // Re-compute when ingredients change
  ref.watch(recipeIngredientsProvider(recipeId));
  return db.computeRecipeNutrition(recipeId);
});

// ---------------------------------------------------------------------------
// Standard meals
// ---------------------------------------------------------------------------

final allMealsProvider = StreamProvider<List<StandardMeal>>((ref) {
  final db = ref.watch(databaseProvider);
  if (db == null) return const Stream.empty();
  return db.watchAllMeals();
});

final mealIngredientsProvider =
    FutureProvider.family<List<StandardMealIngredient>, String>(
        (ref, mealId) async {
  final db = ref.watch(databaseProvider);
  if (db == null) return [];
  return db.ingredientsForMeal(mealId);
});

/// Computed nutrition for a standard meal. Re-triggers when ingredients change.
final mealNutritionProvider =
    FutureProvider.family<RecipeNutritionData?, String>((ref, mealId) async {
  final db = ref.watch(databaseProvider);
  if (db == null) return null;
  ref.watch(mealIngredientsProvider(mealId));
  return db.computeMealNutrition(mealId);
});

// ---------------------------------------------------------------------------
// Recipe operations
// ---------------------------------------------------------------------------

final recipesNotifierProvider =
    AsyncNotifierProvider<RecipesNotifier, void>(RecipesNotifier.new);

class RecipesNotifier extends AsyncNotifier<void> {
  static const _uuid = Uuid();

  @override
  Future<void> build() async {}

  AppDatabase get _db => ref.read(databaseProvider)!;

  Future<String> createRecipe({
    required String name,
    String? description,
    int? prepTimeMinutes,
    int? cookTimeMinutes,
    int servings = 2,
    String servingUnit = 'Portion',
    String? sourceUrl,
    String? mealieSlug,
    String? imageUrl,
    List<String>? tags,
    String? notes,
    double? caloriesPerServing,
    double? proteinPerServing,
    double? carbsPerServing,
    double? fatPerServing,
    double? fiberPerServing,
    double? sodiumPerServing,
    List<IngredientInput> ingredients = const [],
    List<String> steps = const [],
  }) async {
    final id = _uuid.v4();
    await _db.insertRecipe(RecipesCompanion.insert(
      id: id,
      name: name,
      description: Value(description),
      prepTimeMinutes: Value(prepTimeMinutes),
      cookTimeMinutes: Value(cookTimeMinutes),
      servings: Value(servings),
      servingUnit: Value(servingUnit),
      sourceUrl: Value(sourceUrl),
      mealieSlug: Value(mealieSlug),
      imageUrl: Value(imageUrl),
      notes: Value(notes),
      caloriesPerServing: Value(caloriesPerServing),
      proteinPerServing: Value(proteinPerServing),
      carbsPerServing: Value(carbsPerServing),
      fatPerServing: Value(fatPerServing),
      fiberPerServing: Value(fiberPerServing),
      sodiumPerServing: Value(sodiumPerServing),
    ));
    await _saveIngredients(id, ingredients);
    await _saveSteps(id, steps);
    if (tags != null) {
      await _db.setTagsForRecipe(id, tags);
    }
    return id;
  }

  Future<void> updateRecipe(
    Recipe recipe, {
    List<IngredientInput>? ingredients,
    List<String>? steps,
    List<String>? tags,
  }) async {
    await _db.updateRecipe(RecipesCompanion(
      id: Value(recipe.id),
      name: Value(recipe.name),
      description: Value(recipe.description),
      prepTimeMinutes: Value(recipe.prepTimeMinutes),
      cookTimeMinutes: Value(recipe.cookTimeMinutes),
      servings: Value(recipe.servings),
      servingUnit: Value(recipe.servingUnit),
      sourceUrl: Value(recipe.sourceUrl),
      mealieSlug: Value(recipe.mealieSlug),
      imageUrl: Value(recipe.imageUrl),
      notes: Value(recipe.notes),
      caloriesPerServing: Value(recipe.caloriesPerServing),
      proteinPerServing: Value(recipe.proteinPerServing),
      carbsPerServing: Value(recipe.carbsPerServing),
      fatPerServing: Value(recipe.fatPerServing),
      fiberPerServing: Value(recipe.fiberPerServing),
      sodiumPerServing: Value(recipe.sodiumPerServing),
      updatedAt: Value(DateTime.now()),
    ));
    if (ingredients != null) await _saveIngredients(recipe.id, ingredients);
    if (steps != null) await _saveSteps(recipe.id, steps);
    if (tags != null) await _db.setTagsForRecipe(recipe.id, tags);
  }

  Future<void> deleteRecipe(String id) async {
    await _db.deleteIngredientsForRecipe(id);
    await _db.deleteStepsForRecipe(id);
    await _db.deleteRecipe(id);
  }

  Future<void> _saveIngredients(
      String recipeId, List<IngredientInput> ingredients) async {
    await _db.deleteIngredientsForRecipe(recipeId);
    for (var i = 0; i < ingredients.length; i++) {
      final ing = ingredients[i];
      await _db.insertRecipeIngredient(RecipeIngredientsCompanion.insert(
        id: _uuid.v4(),
        recipeId: recipeId,
        name: ing.name,
        quantity: ing.quantity,
        unit: ing.unit,
        itemId: Value(ing.itemId),
        optional: Value(ing.optional),
        sortOrder: Value(i),
      ));
    }
  }

  Future<void> _saveSteps(String recipeId, List<String> steps) async {
    await _db.deleteStepsForRecipe(recipeId);
    for (var i = 0; i < steps.length; i++) {
      await _db.insertRecipeStep(RecipeStepsCompanion.insert(
        id: _uuid.v4(),
        recipeId: recipeId,
        stepNumber: i + 1,
        instruction: steps[i],
      ));
    }
  }
}

// ---------------------------------------------------------------------------
// Meals operations
// ---------------------------------------------------------------------------

final mealsNotifierProvider =
    AsyncNotifierProvider<MealsNotifier, void>(MealsNotifier.new);

class MealsNotifier extends AsyncNotifier<void> {
  static const _uuid = Uuid();

  @override
  Future<void> build() async {}

  AppDatabase get _db => ref.read(databaseProvider)!;

  Future<String> createMeal({
    required String name,
    String? notes,
    String servingUnit = 'Portion',
    List<IngredientInput> ingredients = const [],
    double? kcalTotal,
    double? proteinG,
    double? carbsG,
    double? fatG,
  }) async {
    final id = _uuid.v4();
    await _db.insertMeal(StandardMealsCompanion.insert(
      id: id,
      name: name,
      notes: Value(notes),
      servingUnit: Value(servingUnit),
      kcalTotal: Value(kcalTotal),
      proteinG: Value(proteinG),
      carbsG: Value(carbsG),
      fatG: Value(fatG),
    ));
    await _saveMealIngredients(id, ingredients);
    return id;
  }

  Future<void> updateMeal(
    StandardMeal meal, {
    List<IngredientInput>? ingredients,
    String? servingUnit,
    double? kcalTotal,
    double? proteinG,
    double? carbsG,
    double? fatG,
    bool clearNutrition = false,
  }) async {
    await _db.updateMeal(StandardMealsCompanion(
      id: Value(meal.id),
      name: Value(meal.name),
      notes: Value(meal.notes),
      servingUnit: servingUnit != null ? Value(servingUnit) : Value(meal.servingUnit),
      kcalTotal: clearNutrition ? const Value(null) : Value(kcalTotal),
      proteinG: clearNutrition ? const Value(null) : Value(proteinG),
      carbsG: clearNutrition ? const Value(null) : Value(carbsG),
      fatG: clearNutrition ? const Value(null) : Value(fatG),
    ));
    if (ingredients != null) await _saveMealIngredients(meal.id, ingredients);
  }

  Future<void> deleteMeal(String id) async {
    await _db.deleteMealIngredients(id);
    await _db.deleteMeal(id);
  }

  Future<void> _saveMealIngredients(
      String mealId, List<IngredientInput> ingredients) async {
    await _db.deleteMealIngredients(mealId);
    for (var i = 0; i < ingredients.length; i++) {
      final ing = ingredients[i];
      await _db.insertMealIngredient(StandardMealIngredientsCompanion.insert(
        id: _uuid.v4(),
        mealId: mealId,
        name: ing.name,
        quantity: ing.quantity,
        unit: ing.unit,
        itemId: Value(ing.itemId),
        itemGroupId: Value(ing.itemGroupId),
        sortOrder: Value(i),
      ));
    }
  }
}

// ---------------------------------------------------------------------------
// Helper input model (not a DB type)
// ---------------------------------------------------------------------------

class IngredientInput {
  final String name;
  final double quantity;
  final String unit;
  final String? itemId;
  final String? itemGroupId;
  final bool optional;

  const IngredientInput({
    required this.name,
    required this.quantity,
    required this.unit,
    this.itemId,
    this.itemGroupId,
    this.optional = false,
  });
}
