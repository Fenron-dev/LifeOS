import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;

import '../../db/database.dart';
import '../../providers/entity_photos_provider.dart';
import '../../providers/recipe_suggestions_provider.dart';
import '../../providers/recipes_provider.dart';
import '../../providers/vault_provider.dart';
import '../../widgets/adaptive_shell.dart';
import '../../widgets/thumbnail_image.dart';
import 'recipe_detail_screen.dart';

class RecipesScreen extends ConsumerStatefulWidget {
  const RecipesScreen({super.key});

  @override
  ConsumerState<RecipesScreen> createState() => _RecipesScreenState();
}

class _RecipesScreenState extends ConsumerState<RecipesScreen> {
  static const double _splitBreakpoint = 720;
  bool _filterExpiring = false;
  bool _isGridView = false;
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

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
      if (_isGridView) {
        return _RecipesGrid(
          recipes: filtered,
          onTap: (r) => isSplit
              ? ref.read(selectedRecipeIdProvider.notifier).state = r.id
              : context.push('/haushalt/recipe/${r.id}'),
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
            icon: Icon(
                _isGridView ? Icons.view_list_outlined : Icons.grid_view),
            tooltip: _isGridView ? 'Listenansicht' : 'Rasteransicht',
            onPressed: () => setState(() => _isGridView = !_isGridView),
          ),
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
                  controller: _searchCtrl,
                  hintText: 'Rezept suchen…',
                  leading: const Icon(Icons.search),
                  trailing: query.isNotEmpty
                      ? [
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () {
                              _searchCtrl.clear();
                              ref
                                  .read(recipeSearchQueryProvider.notifier)
                                  .state = '';
                            },
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

// ── Grid view ─────────────────────────────────────────────────────────────────

class _RecipesGrid extends ConsumerWidget {
  final List<Recipe> recipes;
  final void Function(Recipe) onTap;
  const _RecipesGrid({required this.recipes, required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 0.85,
      ),
      itemCount: recipes.length,
      itemBuilder: (context, i) =>
          _RecipeGridCard(recipe: recipes[i], onTap: () => onTap(recipes[i])),
    );
  }
}

class _RecipeGridCard extends ConsumerWidget {
  final Recipe recipe;
  final VoidCallback onTap;
  const _RecipeGridCard({required this.recipe, required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final photosAsync = ref.watch(entityPhotosProvider(recipe.id));
    final firstPhoto = photosAsync.valueOrNull?.firstOrNull;
    final vaultPath = ref.watch(vaultPathProvider);

    Widget photoWidget;
    if (firstPhoto != null && vaultPath != null) {
      final fullPath = p.join(vaultPath, firstPhoto.photoPath);
      photoWidget = ThumbnailImage(
        sourcePath: fullPath,
        width: double.infinity,
        height: double.infinity,
        fit: BoxFit.cover,
      );
    } else if (recipe.imageUrl != null) {
      photoWidget = Image.network(
        recipe.imageUrl!,
        width: double.infinity,
        height: double.infinity,
        fit: BoxFit.cover,
        errorBuilder: (ctx, e, st) => _NoPhotoPlaceholder(cs: cs),
      );
    } else {
      photoWidget = _NoPhotoPlaceholder(cs: cs);
    }

    final totalTime =
        (recipe.prepTimeMinutes ?? 0) + (recipe.cookTimeMinutes ?? 0);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: photoWidget),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    recipe.name,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      if (totalTime > 0) ...[
                        Icon(Icons.schedule,
                            size: 11, color: cs.onSurfaceVariant),
                        const SizedBox(width: 2),
                        Text('$totalTime Min.',
                            style: TextStyle(
                                fontSize: 11,
                                color: cs.onSurfaceVariant)),
                        const SizedBox(width: 6),
                      ],
                      Icon(Icons.people_outline,
                          size: 11, color: cs.onSurfaceVariant),
                      const SizedBox(width: 2),
                      Text('${recipe.servings}',
                          style: TextStyle(
                              fontSize: 11,
                              color: cs.onSurfaceVariant)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoPhotoPlaceholder extends StatelessWidget {
  final ColorScheme cs;
  const _NoPhotoPlaceholder({required this.cs});

  @override
  Widget build(BuildContext context) => Container(
        color: cs.surfaceContainerHighest,
        child: Center(
          child: Icon(Icons.restaurant,
              size: 40, color: cs.onSurfaceVariant.withValues(alpha: 0.4)),
        ),
      );
}

// ── List card ─────────────────────────────────────────────────────────────────

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
