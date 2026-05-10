import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/database.dart';
import 'inventory_provider.dart';
import 'vault_provider.dart';

/// Recipes/meals that use ≥1 ingredient expiring within 7 days.
/// Result type: list of matching [Recipe]s, sorted by number of expiring
/// ingredients descending (most matches first).
final recipeSuggestionsForExpiringProvider =
    FutureProvider<List<Recipe>>((ref) async {
  final db = ref.watch(databaseProvider);
  if (db == null) return [];

  final expiringRows = await ref.watch(expiringItemsProvider.future);
  if (expiringRows.isEmpty) return [];

  final expiringItemIds = expiringRows.map((r) => r.item.id).toSet();

  final allRecipes = await db.watchAllRecipes().first;

  // For each recipe, count how many ingredients match expiring items.
  final scores = <String, int>{};
  for (final recipe in allRecipes) {
    final ingredients = await db.ingredientsForRecipe(recipe.id);
    final matches = ingredients.where((i) =>
        i.itemId != null && expiringItemIds.contains(i.itemId)).length;
    if (matches > 0) scores[recipe.id] = matches;
  }

  if (scores.isEmpty) return [];

  return allRecipes
      .where((r) => scores.containsKey(r.id))
      .toList()
    ..sort((a, b) => (scores[b.id] ?? 0).compareTo(scores[a.id] ?? 0));
});

/// Item IDs of items expiring within 7 days (convenience set for filter checks).
final expiringItemIdsProvider = Provider<Set<String>>((ref) {
  return ref
          .watch(expiringItemsProvider)
          .valueOrNull
          ?.map((r) => r.item.id)
          .toSet() ??
      {};
});
