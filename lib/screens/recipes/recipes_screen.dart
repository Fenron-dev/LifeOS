import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../db/database.dart';
import '../../providers/recipes_provider.dart';
import '../../widgets/adaptive_shell.dart';
import 'recipe_detail_screen.dart';

class RecipesScreen extends ConsumerWidget {
  const RecipesScreen({super.key});

  static const double _splitBreakpoint = 720;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recipesAsync = ref.watch(filteredRecipesProvider);
    final query = ref.watch(recipeSearchQueryProvider);
    final isSplit = MediaQuery.sizeOf(context).width >= _splitBreakpoint;
    final selectedId = ref.watch(selectedRecipeIdProvider);

    final listPane = recipesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Fehler: $e')),
      data: (recipes) => recipes.isEmpty
          ? _EmptyState(hasQuery: query.isNotEmpty)
          : _RecipesList(recipes: recipes, splitMode: isSplit),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Rezepte'),
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_month),
            tooltip: 'Mahlzeitenplan',
            onPressed: () => context.push('/recipes/plan'),
          ),
          IconButton(
            icon: const Icon(Icons.restaurant_menu),
            tooltip: 'Gerichte',
            onPressed: () => context.push('/recipes/meals'),
          ),
          ...shellMenuActions(context),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: SearchBar(
              hintText: 'Rezept suchen…',
              leading: const Icon(Icons.search),
              trailing: query.isNotEmpty
                  ? [
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => ref
                            .read(recipeSearchQueryProvider.notifier)
                            .state = '',
                      ),
                    ]
                  : null,
              onChanged: (v) =>
                  ref.read(recipeSearchQueryProvider.notifier).state = v,
            ),
          ),
        ),
      ),
      body: isSplit
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(width: 360, child: listPane),
                const VerticalDivider(width: 1),
                Expanded(
                  child: selectedId == null
                      ? const _SplitPlaceholder()
                      : RecipeSplitDetailPane(recipeId: selectedId),
                ),
              ],
            )
          : listPane,
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.small(
            heroTag: 'import',
            onPressed: () => context.push('/recipes/import'),
            tooltip: 'Von Mealie importieren',
            child: const Icon(Icons.cloud_download_outlined),
          ),
          const SizedBox(height: 8),
          FloatingActionButton(
            heroTag: 'add_recipe',
            onPressed: () => context.push('/recipes/new'),
            tooltip: 'Rezept hinzufügen',
            child: const Icon(Icons.add),
          ),
        ],
      ),
    );
  }
}

class _RecipesList extends ConsumerWidget {
  final List<Recipe> recipes;
  final bool splitMode;
  const _RecipesList({required this.recipes, required this.splitMode});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedId =
        splitMode ? ref.watch(selectedRecipeIdProvider) : null;
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      itemCount: recipes.length,
      itemBuilder: (context, i) => _RecipeCard(
        recipe: recipes[i],
        selected: splitMode && recipes[i].id == selectedId,
        onTap: () {
          if (splitMode) {
            ref.read(selectedRecipeIdProvider.notifier).state = recipes[i].id;
          } else {
            context.push('/recipes/${recipes[i].id}');
          }
        },
      ),
    );
  }
}

class _RecipeCard extends StatelessWidget {
  final Recipe recipe;
  final bool selected;
  final VoidCallback onTap;
  const _RecipeCard({
    required this.recipe,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final totalTime =
        (recipe.prepTimeMinutes ?? 0) + (recipe.cookTimeMinutes ?? 0);
    final scheme = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: selected ? scheme.secondaryContainer : null,
      child: ListTile(
        selected: selected,
        leading: recipe.imageUrl != null
            ? ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.network(
                  recipe.imageUrl!,
                  width: 48,
                  height: 48,
                  fit: BoxFit.cover,
                  errorBuilder: (context2, err, stack) =>
                      const Icon(Icons.restaurant, size: 32),
                ),
              )
            : const CircleAvatar(child: Icon(Icons.restaurant)),
        title: Text(recipe.name),
        subtitle: Row(
          children: [
            if (totalTime > 0) ...[
              const Icon(Icons.schedule, size: 14),
              const SizedBox(width: 2),
              Text('$totalTime Min.', style: const TextStyle(fontSize: 12)),
              const SizedBox(width: 8),
            ],
            const Icon(Icons.people_outline, size: 14),
            const SizedBox(width: 2),
            Text('${recipe.servings}', style: const TextStyle(fontSize: 12)),
            if (recipe.mealieSlug != null) ...[
              const SizedBox(width: 8),
              const Icon(Icons.cloud_done_outlined,
                  size: 14, color: Colors.green),
            ],
          ],
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

class _SplitPlaceholder extends StatelessWidget {
  const _SplitPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.menu_book_outlined,
              size: 64, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 12),
          Text('Rezept auswählen',
              style: Theme.of(context).textTheme.titleMedium),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final bool hasQuery;
  const _EmptyState({required this.hasQuery});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.menu_book_outlined,
              size: 64, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 16),
          Text(
            hasQuery ? 'Keine Treffer' : 'Noch keine Rezepte',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (!hasQuery) ...[
            const SizedBox(height: 8),
            const Text(
                'Tippe + um ein Rezept hinzuzufügen\noder importiere aus Mealie.'),
          ],
        ],
      ),
    );
  }
}
