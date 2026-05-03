import 'package:drift/drift.dart';

import 'items_table.dart';
import 'recipes_table.dart';

/// One entry in the meal plan: a recipe, dish, or item scheduled for a specific day.
class MealPlanEntries extends Table {
  TextColumn get id => text()();
  // Day this entry is planned for (stored as midnight local time)
  DateTimeColumn get date => dateTime()();
  // Which meal slot (nullable = no specific slot)
  TextColumn get mealTypeId => text().nullable()();
  // Source: exactly one of these is non-null
  @ReferenceName('mealPlanRecipeRefs')
  TextColumn get recipeId => text()
      .nullable()
      .references(Recipes, #id, onDelete: KeyAction.setNull)();
  @ReferenceName('mealPlanDishRefs')
  TextColumn get dishId => text()
      .nullable()
      .references(StandardMeals, #id, onDelete: KeyAction.setNull)();
  @ReferenceName('mealPlanItemRefs')
  TextColumn get itemId => text()
      .nullable()
      .references(Items, #id, onDelete: KeyAction.setNull)();
  // Cached display name (survives deletion of source)
  TextColumn get entryName => text()();
  RealColumn get servings => real().withDefault(const Constant(1.0))();
  // Cached kcal per serving for quick rollup
  RealColumn get kcalPerServing => real().nullable()();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}
