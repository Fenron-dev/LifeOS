import 'package:drift/drift.dart';

class Recipes extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get description => text().nullable()();
  IntColumn get prepTimeMinutes => integer().nullable()();
  IntColumn get cookTimeMinutes => integer().nullable()();
  IntColumn get servings => integer().withDefault(const Constant(2))();
  TextColumn get videoUrl => text().nullable()(); // YouTube URL or local path
  TextColumn get notes => text().nullable()();
  // Nutrition per serving (derived from ingredients, cached here)
  RealColumn get caloriesPerServing => real().nullable()();
  RealColumn get proteinPerServing => real().nullable()();
  RealColumn get carbsPerServing => real().nullable()();
  RealColumn get fatPerServing => real().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

class RecipeIngredients extends Table {
  TextColumn get id => text()();
  TextColumn get recipeId => text().references(Recipes, #id)();
  TextColumn get itemId => text().nullable()(); // FK → Items (linked product)
  TextColumn get itemGroupId => text().nullable()(); // FK → ItemGroups (alternative)
  TextColumn get name => text()(); // display name (may differ from item name)
  RealColumn get quantity => real()();
  TextColumn get unit => text()();
  BoolColumn get optional => boolean().withDefault(const Constant(false))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

class RecipeSteps extends Table {
  TextColumn get id => text()();
  TextColumn get recipeId => text().references(Recipes, #id)();
  IntColumn get stepNumber => integer()();
  TextColumn get instruction => text()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Standard meals: consumption templates (e.g. "Breakfast = 2 slices bread + ...")
class StandardMeals extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

class StandardMealIngredients extends Table {
  TextColumn get id => text()();
  TextColumn get mealId => text().references(StandardMeals, #id)();
  TextColumn get itemId => text().nullable()();
  TextColumn get itemGroupId => text().nullable()();
  TextColumn get name => text()();
  RealColumn get quantity => real()();
  TextColumn get unit => text()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}
