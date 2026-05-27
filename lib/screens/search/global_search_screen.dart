import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../db/database.dart';
import '../../providers/vault_provider.dart';

class GlobalSearchScreen extends ConsumerStatefulWidget {
  const GlobalSearchScreen({super.key});

  @override
  ConsumerState<GlobalSearchScreen> createState() => _GlobalSearchScreenState();
}

class _GlobalSearchScreenState extends ConsumerState<GlobalSearchScreen> {
  final _ctrl = TextEditingController();
  Timer? _debounce;

  List<Item> _items = [];
  List<Recipe> _recipes = [];
  List<Task> _tasks = [];
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(_onChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.removeListener(_onChanged);
    _ctrl.dispose();
    super.dispose();
  }

  void _onChanged() {
    _debounce?.cancel();
    final q = _ctrl.text.trim();
    if (q.isEmpty) {
      setState(() {
        _items = [];
        _recipes = [];
        _tasks = [];
        _searching = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 250), () => _search(q));
  }

  Future<void> _search(String q) async {
    final db = ref.read(databaseProvider);
    if (db == null) return;
    setState(() => _searching = true);
    final results = await Future.wait([
      db.searchItems(q).first,
      db.searchRecipes(q).first,
      db.searchTasks(q),
    ]);
    if (!mounted) return;
    setState(() {
      _items = results[0] as List<Item>;
      _recipes = results[1] as List<Recipe>;
      _tasks = results[2] as List<Task>;
      _searching = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasQuery = _ctrl.text.trim().isNotEmpty;
    final hasResults = _items.isNotEmpty || _recipes.isNotEmpty || _tasks.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _ctrl,
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'Artikel, Rezepte, Aufgaben…',
            border: InputBorder.none,
            suffixIcon: hasQuery
                ? IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      _ctrl.clear();
                      setState(() {
                        _items = [];
                        _recipes = [];
                        _tasks = [];
                      });
                    },
                  )
                : null,
          ),
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      ),
      body: _searching
          ? const LinearProgressIndicator()
          : !hasQuery
              ? _EmptyPrompt()
              : !hasResults
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.search_off,
                              size: 48, color: cs.outline),
                          const SizedBox(height: 12),
                          Text('Keine Treffer für «${_ctrl.text.trim()}»',
                              style: TextStyle(color: cs.onSurfaceVariant)),
                        ],
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.only(bottom: 32),
                      children: [
                        if (_items.isNotEmpty) ...[
                          _SectionHeader(
                              icon: Icons.inventory_2_outlined,
                              label: 'Artikel',
                              count: _items.length),
                          for (final item in _items)
                            ListTile(
                              leading: const Icon(Icons.inventory_2_outlined),
                              title: Text(item.name),
                              subtitle: item.brand != null
                                  ? Text(item.brand!)
                                  : null,
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () =>
                                  context.push('/haushalt/item/${item.id}'),
                            ),
                          const Divider(),
                        ],
                        if (_recipes.isNotEmpty) ...[
                          _SectionHeader(
                              icon: Icons.menu_book_outlined,
                              label: 'Rezepte',
                              count: _recipes.length),
                          for (final recipe in _recipes)
                            ListTile(
                              leading: const Icon(Icons.menu_book_outlined),
                              title: Text(recipe.name),
                              subtitle: recipe.description != null &&
                                      recipe.description!.isNotEmpty
                                  ? Text(
                                      recipe.description!,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    )
                                  : null,
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () =>
                                  context.push('/haushalt/recipe/${recipe.id}'),
                            ),
                          const Divider(),
                        ],
                        if (_tasks.isNotEmpty) ...[
                          _SectionHeader(
                              icon: Icons.task_alt_outlined,
                              label: 'Aufgaben',
                              count: _tasks.length),
                          for (final task in _tasks)
                            ListTile(
                              leading: Icon(
                                task.status == 'done'
                                    ? Icons.check_circle_outline
                                    : Icons.radio_button_unchecked,
                                color: task.status == 'done'
                                    ? cs.primary
                                    : cs.onSurfaceVariant,
                              ),
                              title: Text(
                                task.title,
                                style: task.status == 'done'
                                    ? TextStyle(
                                        decoration: TextDecoration.lineThrough,
                                        color: cs.onSurfaceVariant,
                                      )
                                    : null,
                              ),
                              subtitle: task.notes != null &&
                                      task.notes!.isNotEmpty
                                  ? Text(task.notes!,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis)
                                  : null,
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => context.push('/aufgaben'),
                            ),
                        ],
                      ],
                    ),
    );
  }
}

class _EmptyPrompt extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.search, size: 56, color: cs.outline),
          const SizedBox(height: 12),
          Text('Überall suchen',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text('Artikel, Rezepte und Aufgaben',
              style: TextStyle(color: cs.onSurfaceVariant)),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String label;
  final int count;

  const _SectionHeader(
      {required this.icon, required this.label, required this.count});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: cs.primary),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: cs.primary,
                  letterSpacing: 0.5)),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: cs.primaryContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text('$count',
                style: TextStyle(
                    fontSize: 11,
                    color: cs.onPrimaryContainer,
                    fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}
