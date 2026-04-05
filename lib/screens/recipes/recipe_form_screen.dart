import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../db/database.dart';
import '../../providers/recipes_provider.dart';
import '../../providers/units_provider.dart';
import '../../providers/vault_provider.dart';

class RecipeFormScreen extends ConsumerStatefulWidget {
  final String? recipeId; // null = new recipe
  const RecipeFormScreen({super.key, this.recipeId});

  @override
  ConsumerState<RecipeFormScreen> createState() => _RecipeFormScreenState();
}

class _RecipeFormScreenState extends ConsumerState<RecipeFormScreen> {
  final _formKey = GlobalKey<FormState>();

  // Basic fields
  late TextEditingController _nameCtrl;
  late TextEditingController _descCtrl;
  late TextEditingController _notesCtrl;
  late TextEditingController _sourceUrlCtrl;
  int _servings = 2;
  int? _prepTime;
  int? _cookTime;

  // Ingredient rows
  final List<_IngRow> _ingredients = [];

  // Step rows
  final List<TextEditingController> _steps = [];

  bool _loading = true;
  Recipe? _existing;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController();
    _descCtrl = TextEditingController();
    _notesCtrl = TextEditingController();
    _sourceUrlCtrl = TextEditingController();
    _init();
  }

  Future<void> _init() async {
    if (widget.recipeId != null) {
      final db = ref.read(databaseProvider);
      if (db != null) {
        _existing = await db.recipeById(widget.recipeId!);
        if (_existing != null) {
          _nameCtrl.text = _existing!.name;
          _descCtrl.text = _existing!.description ?? '';
          _notesCtrl.text = _existing!.notes ?? '';
          _sourceUrlCtrl.text = _existing!.sourceUrl ?? '';
          _servings = _existing!.servings;
          _prepTime = _existing!.prepTimeMinutes;
          _cookTime = _existing!.cookTimeMinutes;

          final ings = await db.ingredientsForRecipe(widget.recipeId!);
          for (final ing in ings) {
            _ingredients.add(_IngRow.fromDB(ing));
          }
          final steps = await db.stepsForRecipe(widget.recipeId!);
          for (final s in steps) {
            _steps.add(TextEditingController(text: s.instruction));
          }
        }
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _notesCtrl.dispose();
    _sourceUrlCtrl.dispose();
    for (final row in _ingredients) {
      row.dispose();
    }
    for (final c in _steps) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.recipeId == null ? 'Neues Rezept' : 'Rezept bearbeiten'),
        actions: [
          TextButton(
            onPressed: _save,
            child: const Text('Speichern'),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Name
            TextFormField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Name *',
                border: OutlineInputBorder(),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Name ist erforderlich' : null,
            ),
            const SizedBox(height: 12),

            // Description
            TextFormField(
              controller: _descCtrl,
              decoration: const InputDecoration(
                labelText: 'Beschreibung',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 12),

            // Servings + times
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    initialValue: _servings.toString(),
                    decoration: const InputDecoration(
                      labelText: 'Portionen',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    onChanged: (v) => _servings = int.tryParse(v) ?? _servings,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    initialValue: _prepTime?.toString() ?? '',
                    decoration: const InputDecoration(
                      labelText: 'Vorbereitung (Min.)',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    onChanged: (v) => _prepTime = int.tryParse(v),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    initialValue: _cookTime?.toString() ?? '',
                    decoration: const InputDecoration(
                      labelText: 'Kochen (Min.)',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    onChanged: (v) => _cookTime = int.tryParse(v),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Source URL
            TextFormField(
              controller: _sourceUrlCtrl,
              decoration: const InputDecoration(
                labelText: 'Quelle (URL)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),

            // Ingredients section
            Row(
              children: [
                Text('Zutaten',
                    style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => setState(() => _ingredients.add(_IngRow())),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Hinzufügen'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ..._ingredients.asMap().entries.map(
                  (e) => _IngredientEditor(
                    key: ValueKey(e.key),
                    row: e.value,
                    onRemove: () =>
                        setState(() => _ingredients.removeAt(e.key)),
                  ),
                ),

            const SizedBox(height: 20),

            // Steps section
            Row(
              children: [
                Text('Zubereitung',
                    style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => setState(
                      () => _steps.add(TextEditingController())),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Schritt'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ..._steps.asMap().entries.map(
                  (e) => _StepEditor(
                    key: ValueKey(e.key),
                    number: e.key + 1,
                    controller: e.value,
                    onRemove: () =>
                        setState(() => _steps.removeAt(e.key)),
                  ),
                ),

            const SizedBox(height: 20),

            // Notes
            TextFormField(
              controller: _notesCtrl,
              decoration: const InputDecoration(
                labelText: 'Notizen',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final ingredients = _ingredients
        .where((r) => r.nameCtrl.text.trim().isNotEmpty)
        .map((r) => IngredientInput(
              name: r.nameCtrl.text.trim(),
              quantity:
                  double.tryParse(r.qtyCtrl.text.replaceAll(',', '.')) ?? 1,
              unit: r.unit,
              optional: r.optional,
            ))
        .toList();

    final steps = _steps
        .map((c) => c.text.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    final notifier = ref.read(recipesNotifierProvider.notifier);

    if (_existing == null) {
      final id = await notifier.createRecipe(
        name: _nameCtrl.text.trim(),
        description:
            _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
        prepTimeMinutes: _prepTime,
        cookTimeMinutes: _cookTime,
        servings: _servings,
        sourceUrl: _sourceUrlCtrl.text.trim().isEmpty
            ? null
            : _sourceUrlCtrl.text.trim(),
        notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        ingredients: ingredients,
        steps: steps,
      );
      if (mounted) {
        context.pop();
        context.push('/recipes/$id');
      }
    } else {
      await notifier.updateRecipe(
        _existing!.copyWith(
          name: _nameCtrl.text.trim(),
          description: Value(_descCtrl.text.trim().isEmpty
              ? null
              : _descCtrl.text.trim()),
          prepTimeMinutes: Value(_prepTime),
          cookTimeMinutes: Value(_cookTime),
          servings: _servings,
          sourceUrl: Value(_sourceUrlCtrl.text.trim().isEmpty
              ? null
              : _sourceUrlCtrl.text.trim()),
          notes: Value(
              _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim()),
          updatedAt: DateTime.now(),
        ),
        ingredients: ingredients,
        steps: steps,
      );
      if (mounted) context.pop();
    }
  }
}

// ---------------------------------------------------------------------------
// Ingredient row model
// ---------------------------------------------------------------------------

class _IngRow {
  final TextEditingController nameCtrl;
  final TextEditingController qtyCtrl;
  String unit;
  bool optional;

  _IngRow()
      : nameCtrl = TextEditingController(),
        qtyCtrl = TextEditingController(text: '1'),
        unit = 'Stück',
        optional = false;

  _IngRow.fromDB(RecipeIngredient ing)
      : nameCtrl = TextEditingController(text: ing.name),
        qtyCtrl = TextEditingController(
            text: ing.quantity == ing.quantity.truncateToDouble()
                ? ing.quantity.toInt().toString()
                : ing.quantity.toStringAsFixed(1)),
        unit = ing.unit,
        optional = ing.optional;

  void dispose() {
    nameCtrl.dispose();
    qtyCtrl.dispose();
  }
}

// ---------------------------------------------------------------------------
// Ingredient editor widget
// ---------------------------------------------------------------------------

class _IngredientEditor extends ConsumerStatefulWidget {
  final _IngRow row;
  final VoidCallback onRemove;
  const _IngredientEditor(
      {super.key, required this.row, required this.onRemove});

  @override
  ConsumerState<_IngredientEditor> createState() => _IngredientEditorState();
}

class _IngredientEditorState extends ConsumerState<_IngredientEditor> {
  @override
  Widget build(BuildContext context) {
    final units = ref.watch(unitNamesProvider);
    final row = widget.row;

    // Ensure unit is in list
    if (!units.contains(row.unit)) units.add(row.unit);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          // Quantity
          SizedBox(
            width: 60,
            child: TextFormField(
              controller: row.qtyCtrl,
              decoration: const InputDecoration(
                labelText: 'Menge',
                border: OutlineInputBorder(),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              ),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
            ),
          ),
          const SizedBox(width: 6),

          // Unit dropdown
          SizedBox(
            width: 88,
            child: InputDecorator(
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              ),
              child: DropdownButton<String>(
                value: units.contains(row.unit) ? row.unit : units.first,
                isExpanded: true,
                underline: const SizedBox.shrink(),
                isDense: true,
                items: units
                    .map((u) => DropdownMenuItem(value: u, child: Text(u)))
                    .toList(),
                onChanged: (v) => setState(() => row.unit = v ?? row.unit),
              ),
            ),
          ),
          const SizedBox(width: 6),

          // Name
          Expanded(
            child: TextFormField(
              controller: row.nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Zutat',
                border: OutlineInputBorder(),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              ),
            ),
          ),
          const SizedBox(width: 4),

          // Optional checkbox
          Checkbox(
            value: row.optional,
            onChanged: (v) => setState(() => row.optional = v ?? false),
            visualDensity: VisualDensity.compact,
          ),

          // Delete
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            onPressed: widget.onRemove,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Step editor widget
// ---------------------------------------------------------------------------

class _StepEditor extends StatelessWidget {
  final int number;
  final TextEditingController controller;
  final VoidCallback onRemove;
  const _StepEditor(
      {super.key,
      required this.number,
      required this.controller,
      required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
            child: Text(
              '$number',
              style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onPrimaryContainer),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextFormField(
              controller: controller,
              decoration: const InputDecoration(
                hintText: 'Schritt beschreiben…',
                border: OutlineInputBorder(),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              ),
              maxLines: null,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            onPressed: onRemove,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}
