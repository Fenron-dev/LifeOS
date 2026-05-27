import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../db/database.dart';
import '../../health/widgets/diary_entry_sheet.dart';
import '../../health/widgets/food_search_sheet.dart';
import '../../providers/inventory_provider.dart';
import '../../providers/recipes_provider.dart';
import '../../providers/vault_provider.dart';
import '../../widgets/entity_photo_section.dart';

final _recipeCostProvider = FutureProvider.family<double?, String>((ref, recipeId) async {
  final db = ref.watch(databaseProvider);
  if (db == null) return null;
  return db.estimatedRecipeCost(recipeId);
});

class RecipeDetailScreen extends ConsumerWidget {
  final String recipeId;
  const RecipeDetailScreen({super.key, required this.recipeId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recipeAsync = ref.watch(recipeByIdProvider(recipeId));

    return recipeAsync.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(body: Center(child: Text('Fehler: $e'))),
      data: (recipe) {
        if (recipe == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: Text('Rezept nicht gefunden')),
          );
        }
        return Scaffold(
          appBar: AppBar(
            title: Text(recipe.name),
            actions: [
              IconButton(
                icon: const Icon(Icons.outdoor_grill_outlined),
                tooltip: 'Gekocht — Zutaten ausbuchen',
                onPressed: () => _cookRecipe(context, ref, recipe),
              ),
              IconButton(
                icon: const Icon(Icons.restaurant_outlined),
                tooltip: 'Im Tagebuch erfassen',
                onPressed: () => _logMeal(context, ref, recipe),
              ),
              IconButton(
                icon: const Icon(Icons.save_alt_outlined),
                tooltip: 'Als Gericht speichern',
                onPressed: () => _saveAsMeal(context, ref, recipe),
              ),
              IconButton(
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => context.push('/haushalt/recipe/${recipe.id}/edit'),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _confirmDelete(context, ref, recipe,
                    popOnSuccess: true),
              ),
            ],
          ),
          body: RecipeContentView(recipe: recipe),
        );
      },
    );
  }

  static Future<void> _logMeal(
      BuildContext context, WidgetRef ref, Recipe recipe) async {
    final db = ref.read(databaseProvider);
    if (db == null) return;
    RecipeNutritionData? nutr;
    try {
      nutr = await db.computeRecipeNutrition(recipe.id);
    } catch (_) {}
    if (!context.mounted) return;
    double? servingSizeG;
    if (nutr != null && nutr.totalWeightG > 0 && recipe.servings > 0) {
      servingSizeG = nutr.totalWeightG / recipe.servings;
    }
    final product = FoodSearchResult(
      productName: recipe.name,
      caloriesPer100g: nutr?.caloriesPer100g,
      proteinPer100g: nutr?.proteinPer100g,
      carbsPer100g: nutr?.carbsPer100g,
      fatPer100g: nutr?.fatPer100g,
      fiberPer100g: nutr?.fiberPer100g,
      servingSizeG: servingSizeG,
      isRecipe: true,
      source: 'recipe',
    );
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => DiaryEntrySheet(initialProduct: product),
    );
  }

  static Future<void> _saveAsMeal(
      BuildContext context, WidgetRef ref, Recipe recipe) async {
    try {
      await ref.read(mealsNotifierProvider.notifier).createFromRecipe(recipe);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('«${recipe.name}» als Gericht gespeichert'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fehler: $e'), behavior: SnackBarBehavior.floating),
      );
    }
  }

  static Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    Recipe recipe, {
    bool popOnSuccess = false,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rezept löschen?'),
        content: Text('«${recipe.name}» wird unwiderruflich gelöscht.'),
        actions: [
          TextButton(
              onPressed: () => ctx.pop(false), child: const Text('Abbrechen')),
          FilledButton(
              onPressed: () => ctx.pop(true), child: const Text('Löschen')),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      await ref.read(recipesNotifierProvider.notifier).deleteRecipe(recipe.id);
      if (!context.mounted) return;
      if (popOnSuccess) {
        context.pop();
      } else {
        ref.read(selectedRecipeIdProvider.notifier).state = null;
      }
    }
  }

  static Future<void> _cookRecipe(
      BuildContext context, WidgetRef ref, Recipe recipe) async {
    final db = ref.read(databaseProvider);
    if (db == null) return;
    final ings = await db.ingredientsForRecipe(recipe.id);
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _CookRecipeSheet(recipe: recipe, ingredients: ings),
    );
  }
}

/// Embeddable detail pane used by both the full-screen [RecipeDetailScreen]
/// and the tablet/desktop split view inside `RecipesScreen`. Builds its own
/// title bar + actions so it can live inside any parent without needing an
/// outer Scaffold.
class RecipeSplitDetailPane extends ConsumerWidget {
  final String recipeId;
  const RecipeSplitDetailPane({super.key, required this.recipeId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recipeAsync = ref.watch(recipeByIdProvider(recipeId));
    return recipeAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Fehler: $e')),
      data: (recipe) {
        if (recipe == null) {
          return const Center(child: Text('Rezept nicht gefunden'));
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Material(
              color: Theme.of(context).colorScheme.surface,
              elevation: 1,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        recipe.name,
                        style: Theme.of(context).textTheme.titleLarge,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.outdoor_grill_outlined),
                      tooltip: 'Gekocht — Zutaten ausbuchen',
                      onPressed: () =>
                          RecipeDetailScreen._cookRecipe(context, ref, recipe),
                    ),
                    IconButton(
                      icon: const Icon(Icons.restaurant_outlined),
                      tooltip: 'Im Tagebuch erfassen',
                      onPressed: () =>
                          RecipeDetailScreen._logMeal(context, ref, recipe),
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit_outlined),
                      tooltip: 'Bearbeiten',
                      onPressed: () =>
                          context.push('/haushalt/recipe/${recipe.id}/edit'),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      tooltip: 'Löschen',
                      onPressed: () => RecipeDetailScreen._confirmDelete(
                          context, ref, recipe),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(child: RecipeContentView(recipe: recipe)),
          ],
        );
      },
    );
  }
}

/// Scrollable recipe content (image, meta, tags, nutrition, ingredients,
/// steps, notes, source). No Scaffold / AppBar so it can be embedded in any
/// parent layout.
class RecipeContentView extends ConsumerWidget {
  final Recipe recipe;
  const RecipeContentView({super.key, required this.recipe});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ingredientsAsync = ref.watch(recipeIngredientsProvider(recipe.id));
    final stepsAsync = ref.watch(recipeStepsProvider(recipe.id));
    final tagsAsync = ref.watch(recipeTagsProvider(recipe.id));

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (recipe.imageUrl != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(
              recipe.imageUrl!,
              height: 200,
              width: double.infinity,
              fit: BoxFit.cover,
              errorBuilder: (context, err, stack) => const SizedBox.shrink(),
            ),
          ),
        if (recipe.imageUrl != null) const SizedBox(height: 16),

        EntityPhotoSection(entityId: recipe.id, entityType: 'recipe'),
        const SizedBox(height: 12),

        Wrap(
          spacing: 16,
          children: [
            if ((recipe.prepTimeMinutes ?? 0) > 0)
              _MetaChip(
                  icon: Icons.kitchen,
                  label: '${recipe.prepTimeMinutes} Min. Vorbereitung'),
            if ((recipe.cookTimeMinutes ?? 0) > 0)
              _MetaChip(
                  icon: Icons.local_fire_department,
                  label: '${recipe.cookTimeMinutes} Min. Kochen'),
            _MetaChip(
                icon: Icons.people_outline,
                label: '${recipe.servings} Portionen'),
            if (recipe.mealieSlug != null)
              _MetaChip(
                  icon: Icons.cloud_done_outlined,
                  label: 'Mealie',
                  color: Colors.green),
          ],
        ),
        const SizedBox(height: 12),

        if (recipe.description != null && recipe.description!.isNotEmpty) ...[
          Text(recipe.description!,
              style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 16),
        ],

        tagsAsync.maybeWhen(
          orElse: () => const SizedBox.shrink(),
          data: (tags) => tags.isEmpty
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: _TagsRow(tags: tags),
                ),
        ),

        Consumer(
          builder: (context, ref, _) {
            final nutrAsync =
                ref.watch(recipeComputedNutritionProvider(recipe.id));
            return nutrAsync.when(
              loading: () => const SizedBox.shrink(),
              error: (e, s) => const SizedBox.shrink(),
              data: (computed) {
                final hasData = computed != null ||
                    recipe.caloriesPerServing != null;
                if (!hasData) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: _NutritionCard(
                    recipe: recipe,
                    computed: computed,
                  ),
                );
              },
            );
          },
        ),

        Text('Zutaten', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        ingredientsAsync.when(
          loading: () => const CircularProgressIndicator(),
          error: (e, _) => Text('Fehler: $e'),
          data: (ings) => ings.isEmpty
              ? const Text('Keine Zutaten eingetragen.')
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: ings
                      .map((ing) => _IngredientRow(ingredient: ing))
                      .toList(),
                ),
        ),
        // Estimated cost from last purchase prices
        Builder(builder: (_) {
          final cost = ref.watch(_recipeCostProvider(recipe.id)).valueOrNull;
          if (cost == null) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              children: [
                Icon(Icons.euro, size: 14,
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
                const SizedBox(width: 4),
                Text(
                  'Geschätzte Kosten: ~${cost.toStringAsFixed(2)} €',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          );
        }),
        const SizedBox(height: 16),

        Text('Zubereitung', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        stepsAsync.when(
          loading: () => const CircularProgressIndicator(),
          error: (e, _) => Text('Fehler: $e'),
          data: (steps) => steps.isEmpty
              ? const Text('Keine Schritte eingetragen.')
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children:
                      steps.map((s) => _StepRow(step: s)).toList(),
                ),
        ),
        const SizedBox(height: 16),

        if (recipe.notes != null && recipe.notes!.isNotEmpty) ...[
          Text('Notizen', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(recipe.notes!),
          const SizedBox(height: 16),
        ],

        if (recipe.sourceUrl != null) ...[
          Text('Quelle', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(recipe.sourceUrl!,
              style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  decoration: TextDecoration.underline)),
          const SizedBox(height: 32),
        ],
      ],
    );
  }
}

class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;
  const _MetaChip({required this.icon, required this.label, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: c),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 13, color: c)),
      ],
    );
  }
}

class _TagsRow extends StatelessWidget {
  final List<String> tags;
  const _TagsRow({required this.tags});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      children: tags
          .map((t) => Chip(
                label: Text(t, style: const TextStyle(fontSize: 12)),
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 4),
              ))
          .toList(),
    );
  }
}

class _NutritionCard extends StatelessWidget {
  final Recipe recipe;
  final RecipeNutritionData? computed;
  const _NutritionCard({required this.recipe, this.computed});

  @override
  Widget build(BuildContext context) {
    String fmt(double? v) => v == null
        ? '–'
        : (v == v.truncateToDouble()
            ? v.toInt().toString()
            : v.toStringAsFixed(1));

    // Prefer computed-from-ingredients, fall back to stored values
    final servings = recipe.servings > 0 ? recipe.servings.toDouble() : 1;
    final kcal = computed != null
        ? computed!.kcal / servings
        : recipe.caloriesPerServing;
    final protein = computed != null
        ? computed!.proteinG / servings
        : recipe.proteinPerServing;
    final carbs = computed != null
        ? computed!.carbsG / servings
        : recipe.carbsPerServing;
    final fat = computed != null
        ? computed!.fatG / servings
        : recipe.fatPerServing;
    final fiber = computed != null ? computed!.fiberG / servings : null;
    final totalG = computed?.totalWeightG;

    final isComputed = computed != null;

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Nährwerte pro Portion',
                    style: Theme.of(context).textTheme.titleSmall),
                if (isComputed) ...[
                  const SizedBox(width: 6),
                  Chip(
                    label: const Text('berechnet'),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    labelStyle: const TextStyle(fontSize: 11),
                  ),
                ],
              ],
            ),
            if (totalG != null && totalG > 0)
              Padding(
                padding: const EdgeInsets.only(top: 2, bottom: 4),
                child: Text(
                  'ca. ${(totalG / servings).toStringAsFixed(0)} g pro Portion · ${totalG.toStringAsFixed(0)} g gesamt',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.outline),
                ),
              ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _NutCol('Kalorien', '${fmt(kcal)} kcal'),
                _NutCol('Protein', '${fmt(protein)} g'),
                _NutCol('Kohlenhydrate', '${fmt(carbs)} g'),
                _NutCol('Fett', '${fmt(fat)} g'),
                if (fiber != null && fiber > 0)
                  _NutCol('Ballaststoffe', '${fmt(fiber)} g'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _NutCol extends StatelessWidget {
  final String label;
  final String value;
  const _NutCol(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value, style: Theme.of(context).textTheme.titleSmall),
        Text(label,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: Theme.of(context).colorScheme.outline)),
      ],
    );
  }
}

class _IngredientRow extends StatelessWidget {
  final RecipeIngredient ingredient;
  const _IngredientRow({required this.ingredient});

  @override
  Widget build(BuildContext context) {
    final qty = ingredient.quantity == ingredient.quantity.truncateToDouble()
        ? ingredient.quantity.toInt().toString()
        : ingredient.quantity.toStringAsFixed(1);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: Text('$qty ${ingredient.unit}',
                style: const TextStyle(fontWeight: FontWeight.w500)),
          ),
          Expanded(
            child: Text(
              ingredient.name + (ingredient.optional ? ' (optional)' : ''),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Cook Recipe Sheet ─────────────────────────────────────────────────────────

class _CookRecipeSheet extends ConsumerStatefulWidget {
  final Recipe recipe;
  final List<RecipeIngredient> ingredients;

  const _CookRecipeSheet({required this.recipe, required this.ingredients});

  @override
  ConsumerState<_CookRecipeSheet> createState() => _CookRecipeSheetState();
}

class _CookRecipeSheetState extends ConsumerState<_CookRecipeSheet> {
  late double _portions;
  late Map<String, bool> _deduct; // ingredientId → selected for deduction
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _portions = widget.recipe.servings.toDouble();
    _deduct = {
      for (final ing in widget.ingredients)
        if (ing.itemId != null) ing.id: true,
    };
  }

  double get _scale =>
      widget.recipe.servings > 0 ? _portions / widget.recipe.servings : 1.0;

  String _fmtQty(double v) =>
      v == v.truncateToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

  Future<void> _cook(BuildContext context) async {
    setState(() => _loading = true);
    final db = ref.read(databaseProvider);
    final ops = ref.read(inventoryOpsProvider.notifier);
    if (db == null) {
      setState(() => _loading = false);
      return;
    }

    int deducted = 0;
    for (final ing in widget.ingredients) {
      if (ing.itemId == null) continue;
      if (!(_deduct[ing.id] ?? false)) continue;

      final needed = ing.quantity * _scale;
      final entries = await db.inventoryEntriesForItem(ing.itemId!);
      double remaining = needed;
      for (final entry in entries) {
        if (remaining <= 0) break;
        final take = remaining <= entry.quantity ? remaining : entry.quantity;
        final leftInEntry = entry.quantity - take;
        await ops.consume(
          itemId: ing.itemId!,
          inventoryEntryId: entry.id,
          quantity: take,
          unit: entry.unit,
          remainingQuantity: leftInEntry,
          consumptionReason: 'recipe_cook',
        );
        remaining -= take;
      }
      deducted++;
    }

    if (!context.mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          deducted > 0
              ? '${widget.recipe.name} gekocht – $deducted Zutaten ausgebucht'
              : '${widget.recipe.name} als gekocht markiert',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final linkedIngs =
        widget.ingredients.where((i) => i.itemId != null).toList();
    final unlinkedIngs =
        widget.ingredients.where((i) => i.itemId == null).toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollCtrl) => Column(
        children: [
          const SizedBox(height: 8),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: cs.onSurfaceVariant.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                const Icon(Icons.outdoor_grill_outlined, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Gekocht: ${widget.recipe.name}',
                    style: Theme.of(context).textTheme.titleMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          // Portions selector
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Text('Portionen:', style: Theme.of(context).textTheme.bodyMedium),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline),
                  onPressed: _portions > 0.5
                      ? () => setState(() => _portions =
                          (_portions - 0.5).clamp(0.5, 99.0))
                      : null,
                ),
                SizedBox(
                  width: 40,
                  child: Text(
                    _fmtQty(_portions),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline),
                  onPressed: () =>
                      setState(() => _portions = (_portions + 0.5).clamp(0.5, 99.0)),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              controller: scrollCtrl,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                if (linkedIngs.isNotEmpty) ...[
                  Text('Aus Inventar ausbuchen',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: cs.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          )),
                  const SizedBox(height: 4),
                  for (final ing in linkedIngs)
                    CheckboxListTile(
                      value: _deduct[ing.id] ?? false,
                      onChanged: (v) =>
                          setState(() => _deduct[ing.id] = v ?? false),
                      title: Text(ing.name),
                      subtitle: Text(
                          '${_fmtQty(ing.quantity * _scale)} ${ing.unit}'),
                      dense: true,
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                    ),
                ],
                if (unlinkedIngs.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text('Nicht verknüpft (kein Bestand)',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: cs.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          )),
                  const SizedBox(height: 4),
                  for (final ing in unlinkedIngs)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: [
                          const Icon(Icons.link_off, size: 14,
                              color: Colors.grey),
                          const SizedBox(width: 8),
                          Expanded(child: Text(ing.name,
                              style: const TextStyle(color: Colors.grey))),
                          Text(
                              '${_fmtQty(ing.quantity * _scale)} ${ing.unit}',
                              style: const TextStyle(
                                  color: Colors.grey, fontSize: 12)),
                        ],
                      ),
                    ),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: _loading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.check),
                label: Text(_deduct.values.any((v) => v)
                    ? 'Zutaten ausbuchen'
                    : 'Als gekocht markieren'),
                onPressed: _loading ? null : () => _cook(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  final RecipeStep step;
  const _StepRow({required this.step});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
            child: Text(
              '${step.stepNumber}',
              style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onPrimaryContainer),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(step.instruction)),
        ],
      ),
    );
  }
}
