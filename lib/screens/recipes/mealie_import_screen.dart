import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../providers/recipes_provider.dart';
import '../../services/mealie_service.dart';

// ---------------------------------------------------------------------------
// Persistent Mealie connection settings
// ---------------------------------------------------------------------------

const _kMealieUrl = 'mealie_url';
const _kMealieToken = 'mealie_token';

class MealieImportScreen extends ConsumerStatefulWidget {
  const MealieImportScreen({super.key});

  @override
  ConsumerState<MealieImportScreen> createState() => _MealieImportScreenState();
}

class _MealieImportScreenState extends ConsumerState<MealieImportScreen> {
  final _urlCtrl = TextEditingController();
  final _tokenCtrl = TextEditingController();

  MealieService? _service;
  List<MealieSummary> _list = [];
  bool _loadingList = false;
  String? _error;

  // Recipes being imported (slug → loading state)
  final Map<String, bool> _importing = {};

  @override
  void initState() {
    super.initState();
    _loadSaved();
  }

  Future<void> _loadSaved() async {
    final prefs = await SharedPreferences.getInstance();
    final url = prefs.getString(_kMealieUrl) ?? '';
    final token = prefs.getString(_kMealieToken) ?? '';
    _urlCtrl.text = url;
    _tokenCtrl.text = token;
    if (url.isNotEmpty && token.isNotEmpty) {
      _service = MealieService(baseUrl: url, apiToken: token);
      _fetchList();
    }
  }

  Future<void> _connect() async {
    final url = _urlCtrl.text.trim().replaceAll(RegExp(r'/+$'), '');
    final token = _tokenCtrl.text.trim();
    if (url.isEmpty || token.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kMealieUrl, url);
    await prefs.setString(_kMealieToken, token);

    setState(() {
      _service = MealieService(baseUrl: url, apiToken: token);
      _error = null;
    });
    _fetchList();
  }

  Future<void> _fetchList() async {
    setState(() {
      _loadingList = true;
      _error = null;
    });
    try {
      final list = await _service!.fetchRecipeList(perPage: 100);
      setState(() => _list = list);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loadingList = false);
    }
  }

  Future<void> _import(MealieSummary summary) async {
    setState(() => _importing[summary.slug] = true);
    try {
      final recipe = await _service!.fetchRecipe(summary.slug);
      final notifier = ref.read(recipesNotifierProvider.notifier);

      final ingredients = recipe.ingredients
          .map((i) => IngredientInput(
                name: i.name,
                quantity: i.quantity,
                unit: i.unit,
                optional: i.optional,
              ))
          .toList();

      await notifier.createRecipe(
        name: recipe.name,
        description: recipe.description,
        prepTimeMinutes: recipe.prepTime,
        cookTimeMinutes: recipe.cookTime,
        servings: recipe.servings ?? 2,
        sourceUrl: recipe.sourceUrl,
        mealieSlug: recipe.slug,
        imageUrl: recipe.imageUrl,
        tags: recipe.tags.isEmpty ? null : recipe.tags,
        caloriesPerServing: recipe.calories,
        proteinPerServing: recipe.protein,
        carbsPerServing: recipe.carbs,
        fatPerServing: recipe.fat,
        fiberPerServing: recipe.fiber,
        sodiumPerServing: recipe.sodium,
        ingredients: ingredients,
        steps: recipe.steps,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('«${recipe.name}» importiert')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _importing.remove(summary.slug));
    }
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _tokenCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Get already-imported slugs
    final existingRecipes = ref.watch(allRecipesProvider).valueOrNull ?? [];
    final importedSlugs =
        existingRecipes.map((r) => r.mealieSlug).whereType<String>().toSet();

    return Scaffold(
      appBar: AppBar(title: const Text('Von Mealie importieren')),
      body: Column(
        children: [
          // Connection panel
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _urlCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Mealie URL (z.B. http://192.168.1.5:9000)',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.url,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _tokenCtrl,
                  decoration: const InputDecoration(
                    labelText: 'API-Token',
                    border: OutlineInputBorder(),
                  ),
                  obscureText: true,
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: _connect,
                  child: const Text('Verbinden'),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(_error!,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error)),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Recipe list
          Expanded(
            child: _loadingList
                ? const Center(child: CircularProgressIndicator())
                : _list.isEmpty
                    ? Center(
                        child: Text(_service == null
                            ? 'Verbindungsdaten eingeben und auf Verbinden tippen.'
                            : 'Keine Rezepte gefunden.'),
                      )
                    : ListView.builder(
                        itemCount: _list.length,
                        itemBuilder: (context, i) {
                          final s = _list[i];
                          final alreadyImported =
                              importedSlugs.contains(s.slug);
                          final loading = _importing[s.slug] == true;
                          return ListTile(
                            leading: s.imageUrl != null
                                ? ClipRRect(
                                    borderRadius: BorderRadius.circular(4),
                                    child: Image.network(
                                      s.imageUrl!,
                                      width: 44,
                                      height: 44,
                                      fit: BoxFit.cover,
                                      headers: {
                                        'Authorization':
                                            'Bearer ${_tokenCtrl.text.trim()}'
                                      },
                                      errorBuilder: (c, e, st) =>
                                          const Icon(Icons.restaurant),
                                    ),
                                  )
                                : const Icon(Icons.restaurant),
                            title: Text(s.name),
                            subtitle: alreadyImported
                                ? const Text('Bereits importiert',
                                    style: TextStyle(color: Colors.green))
                                : null,
                            trailing: loading
                                ? const SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  )
                                : alreadyImported
                                    ? IconButton(
                                        icon: const Icon(Icons.sync),
                                        tooltip: 'Erneut importieren',
                                        onPressed: () => _import(s),
                                      )
                                    : FilledButton.tonal(
                                        onPressed: () => _import(s),
                                        child: const Text('Import'),
                                      ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
