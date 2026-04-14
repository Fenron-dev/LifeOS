import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../db/database.dart';
import '../../providers/recipes_provider.dart';

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
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => context.push('/recipes/${recipe.id}/edit'),
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
                      icon: const Icon(Icons.edit_outlined),
                      tooltip: 'Bearbeiten',
                      onPressed: () =>
                          context.push('/recipes/${recipe.id}/edit'),
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

        if (recipe.caloriesPerServing != null) ...[
          _NutritionCard(recipe: recipe),
          const SizedBox(height: 16),
        ],

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
  const _NutritionCard({required this.recipe});

  @override
  Widget build(BuildContext context) {
    String fmt(double? v) => v == null
        ? '–'
        : (v == v.truncateToDouble()
            ? v.toInt().toString()
            : v.toStringAsFixed(1));

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Nährwerte pro Portion',
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _NutCol('Kalorien', '${fmt(recipe.caloriesPerServing)} kcal'),
                _NutCol('Protein', '${fmt(recipe.proteinPerServing)} g'),
                _NutCol('Kohlenhydrate', '${fmt(recipe.carbsPerServing)} g'),
                _NutCol('Fett', '${fmt(recipe.fatPerServing)} g'),
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
