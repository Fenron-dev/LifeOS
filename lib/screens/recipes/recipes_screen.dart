import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../db/database.dart';
import '../../providers/recipe_suggestions_provider.dart';
import '../../providers/recipes_provider.dart';
import '../../widgets/adaptive_shell.dart';
import 'recipe_detail_screen.dart';

class RecipesScreen extends ConsumerStatefulWidget {
  const RecipesScreen({super.key});

  @override
  ConsumerState<RecipesScreen> createState() => _RecipesScreenState();
}

class _RecipesScreenState extends ConsumerState<RecipesScreen> {
  static const double _splitBreakpoint = 720;
  bool _filterExpiring = false;

  @override
  Widget build(BuildContext context) {
    final recipesAsync = ref.watch(filteredRecipesProvider);
    final query = ref.watch(recipeSearchQueryProvider);
    final isSplit = MediaQuery.sizeOf(context).width >= _splitBreakpoint;
    final selectedId = ref.watch(selectedRecipeIdProvider);

    final suggestedIds = _filterExpiring
        ? ref
                .watch(recipeSuggestionsForExpiringProvider)
                .valueOrNull
                ?.map((r) => r.id)
                .toSet() ??
            {}
        : null;

    Widget buildList(List<Recipe> recipes) {
      final filtered = suggestedIds != null
          ? recipes.where((r) => suggestedIds.contains(r.id)).toList()
          : recipes;

      if (filtered.isEmpty) {
        return _EmptyState(
          hasQuery: query.isNotEmpty,
          filterExpiring: _filterExpiring,
          onClearFilter: () => setState(() => _filterExpiring = false),
        );
      }
      return _RecipesList(recipes: filtered, splitMode: isSplit);
    }

    final listPane = recipesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Fehler: $e')),
      data: buildList,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Rezepte'),
        actions: [
          IconButton(
            icon: const Icon(Icons.cloud_download_outlined),
            tooltip: 'Von Mealie importieren',
            onPressed: () => context.push('/haushalt/recipe/import'),
          ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Rezept hinzufügen',
            onPressed: () => context.push('/haushalt/recipe/new'),
          ),
          ...shellMenuActions(context),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(104),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
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
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Row(
                  children: [
                    FilterChip(
                      label: const Text('Ablaufende Zutaten'),
                      avatar: Icon(
                        Icons.event_busy_outlined,
                        size: 16,
                        color: _filterExpiring
                            ? Theme.of(context)
                                .colorScheme
                                .onSecondaryContainer
                            : null,
                      ),
                      selected: _filterExpiring,
                      onSelected: (v) => setState(() => _filterExpiring = v),
                    ),
                  ],
                ),
              ),
            ],
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
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      itemCount: recipes.length,
      itemBuilder: (context, i) => _RecipeCard(
        recipe: recipes[i],
        selected: splitMode && recipes[i].id == selectedId,
        onTap: () {
          if (splitMode) {
            ref.read(selectedRecipeIdProvider.notifier).state = recipes[i].id;
          } else {
            context.push('/haushalt/recipe/${recipes[i].id}');
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
  final bool filterExpiring;
  final VoidCallback onClearFilter;
  const _EmptyState({
    required this.hasQuery,
    required this.filterExpiring,
    required this.onClearFilter,
  });

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
            filterExpiring
                ? 'Keine passenden Rezepte gefunden'
                : hasQuery
                    ? 'Keine Treffer'
                    : 'Noch keine Rezepte',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (filterExpiring) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: onClearFilter,
              child: const Text('Filter entfernen'),
            ),
          ] else if (!hasQuery) ...[
            const SizedBox(height: 8),
            const Text(
                'Tippe + um ein Rezept hinzuzufügen\noder importiere aus Mealie.'),
          ],
        ],
      ),
    );
  }
}
