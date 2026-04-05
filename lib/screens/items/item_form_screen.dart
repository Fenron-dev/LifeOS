import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../db/database.dart';
import '../../providers/items_provider.dart';
import '../../services/open_food_facts_service.dart';
import 'off_import_dialog.dart';

/// Create or edit an item.
/// Pass [itemId] for edit mode (loaded internally), null for create.
/// Pass [prefillEan] when coming from a barcode scan.
class ItemFormScreen extends ConsumerWidget {
  final String? itemId;
  final Item? item;
  final String? prefillEan;

  const ItemFormScreen({super.key, this.itemId, this.item, this.prefillEan});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (item != null || itemId == null) {
      return _ItemFormBody(item: item, prefillEan: prefillEan);
    }
    final itemAsync = ref.watch(itemByIdProvider(itemId!));
    return itemAsync.when(
      loading: () => const Scaffold(
          body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(body: Center(child: Text('Fehler: $e'))),
      data: (loaded) => _ItemFormBody(item: loaded, prefillEan: prefillEan),
    );
  }
}

class _ItemFormBody extends ConsumerStatefulWidget {
  final Item? item;
  final String? prefillEan;

  const _ItemFormBody({this.item, this.prefillEan});

  @override
  ConsumerState<_ItemFormBody> createState() => _ItemFormScreenState();
}

class _ItemFormScreenState extends ConsumerState<_ItemFormBody> {
  final _formKey = GlobalKey<FormState>();

  // Basic info
  late final TextEditingController _nameCtrl;
  late final TextEditingController _brandCtrl;
  late final TextEditingController _eanCtrl;
  late final TextEditingController _notesCtrl;
  late final TextEditingController _ingredientsCtrl;

  // Nutrition controllers (per 100g)
  late final TextEditingController _caloriesCtrl;
  late final TextEditingController _proteinCtrl;
  late final TextEditingController _carbsCtrl;
  late final TextEditingController _sugarCtrl;
  late final TextEditingController _fatCtrl;
  late final TextEditingController _satFatCtrl;
  late final TextEditingController _fiberCtrl;
  late final TextEditingController _saltCtrl;
  late final TextEditingController _servingSizeCtrl;

  String _productType = 'needsCooking';
  bool _alwaysConsumedFully = false;
  bool _openedFlag = true;
  String _categoryId = 'food';
  String? _nutriscore;
  int? _novaGroup;
  bool _loadingOff = false;
  bool _showNutrition = false;

  @override
  void initState() {
    super.initState();
    final i = widget.item;
    _nameCtrl = TextEditingController(text: i?.name ?? '');
    _brandCtrl = TextEditingController(text: i?.brand ?? '');
    _eanCtrl = TextEditingController(text: i?.ean ?? widget.prefillEan ?? '');
    _notesCtrl = TextEditingController(text: i?.notes ?? '');
    _ingredientsCtrl = TextEditingController(text: i?.ingredientsText ?? '');

    _caloriesCtrl = TextEditingController(text: _fmtCtrl(i?.caloriesPer100g));
    _proteinCtrl = TextEditingController(text: _fmtCtrl(i?.proteinPer100g));
    _carbsCtrl = TextEditingController(text: _fmtCtrl(i?.carbsPer100g));
    _sugarCtrl = TextEditingController(text: _fmtCtrl(i?.sugarsPer100g));
    _fatCtrl = TextEditingController(text: _fmtCtrl(i?.fatPer100g));
    _satFatCtrl = TextEditingController(text: _fmtCtrl(i?.saturatedFatPer100g));
    _fiberCtrl = TextEditingController(text: _fmtCtrl(i?.fiberPer100g));
    _saltCtrl = TextEditingController(text: _fmtCtrl(i?.saltPer100g));
    _servingSizeCtrl = TextEditingController(text: _fmtCtrl(i?.servingSizeG));

    if (i != null) {
      _productType = i.productType;
      _alwaysConsumedFully = i.alwaysConsumedFully;
      _openedFlag = i.openedFlag;
      _categoryId = i.categoryId;
      _nutriscore = i.nutriscore;
      _novaGroup = i.novaGroup;
      // Show section if any nutrition data exists
      _showNutrition = _hasAnyNutrition(i);
    }
    if (widget.prefillEan != null && widget.item == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _lookupOff());
    }
  }

  bool _hasAnyNutrition(Item i) =>
      i.caloriesPer100g != null ||
      i.proteinPer100g != null ||
      i.carbsPer100g != null ||
      i.fatPer100g != null ||
      i.nutriscore != null;

  String _fmtCtrl(double? v) {
    if (v == null) return '';
    return v == v.truncateToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _brandCtrl.dispose();
    _eanCtrl.dispose();
    _notesCtrl.dispose();
    _ingredientsCtrl.dispose();
    _caloriesCtrl.dispose();
    _proteinCtrl.dispose();
    _carbsCtrl.dispose();
    _sugarCtrl.dispose();
    _fatCtrl.dispose();
    _satFatCtrl.dispose();
    _fiberCtrl.dispose();
    _saltCtrl.dispose();
    _servingSizeCtrl.dispose();
    super.dispose();
  }

  Future<void> _lookupOff() async {
    final ean = _eanCtrl.text.trim();
    if (ean.isEmpty) return;
    setState(() => _loadingOff = true);
    final product = await OpenFoodFactsService.lookup(ean);
    if (!mounted) return;
    setState(() => _loadingOff = false);
    if (product == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kein Produkt gefunden (OpenFoodFacts)')),
      );
      return;
    }

    // Show selection dialog
    final selected = await showOffImportDialog(context, product);
    if (selected == null || !mounted) return;

    setState(() {
      if (selected.contains(OFFField.name) && product.name != null) {
        _nameCtrl.text = product.name!;
      }
      if (selected.contains(OFFField.brand) && product.brand != null) {
        _brandCtrl.text = product.brand!;
      }
      if (selected.contains(OFFField.calories)) {
        _caloriesCtrl.text = _fmtCtrl(product.calories);
      }
      if (selected.contains(OFFField.protein)) {
        _proteinCtrl.text = _fmtCtrl(product.protein);
      }
      if (selected.contains(OFFField.carbs)) {
        _carbsCtrl.text = _fmtCtrl(product.carbs);
      }
      if (selected.contains(OFFField.sugars)) {
        _sugarCtrl.text = _fmtCtrl(product.sugars);
      }
      if (selected.contains(OFFField.fat)) {
        _fatCtrl.text = _fmtCtrl(product.fat);
      }
      if (selected.contains(OFFField.saturatedFat)) {
        _satFatCtrl.text = _fmtCtrl(product.saturatedFat);
      }
      if (selected.contains(OFFField.fiber)) {
        _fiberCtrl.text = _fmtCtrl(product.fiber);
      }
      if (selected.contains(OFFField.salt)) {
        _saltCtrl.text = _fmtCtrl(product.salt);
      }
      if (selected.contains(OFFField.servingSize)) {
        _servingSizeCtrl.text = _fmtCtrl(product.servingSizeG);
      }
      if (selected.contains(OFFField.nutriscore)) {
        _nutriscore = product.nutriscore;
      }
      if (selected.contains(OFFField.novaGroup)) {
        _novaGroup = product.novaGroup;
      }
      if (selected.contains(OFFField.ingredientsText) &&
          product.ingredientsText != null) {
        _ingredientsCtrl.text = product.ingredientsText!;
      }
      // Show section if any nutrition was selected
      final nutritionFields = {
        OFFField.calories, OFFField.protein, OFFField.carbs, OFFField.sugars,
        OFFField.fat, OFFField.saturatedFat, OFFField.fiber, OFFField.salt,
        OFFField.servingSize, OFFField.nutriscore, OFFField.novaGroup,
      };
      if (selected.any((f) => nutritionFields.contains(f))) {
        _showNutrition = true;
      }
    });
  }

  double? _parseNutrition(TextEditingController ctrl) =>
      double.tryParse(ctrl.text.trim().replaceAll(',', '.'));

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final notifier = ref.read(itemsNotifierProvider.notifier);
    final existing = widget.item;

    final calories = _parseNutrition(_caloriesCtrl);
    final protein = _parseNutrition(_proteinCtrl);
    final carbs = _parseNutrition(_carbsCtrl);
    final sugars = _parseNutrition(_sugarCtrl);
    final fat = _parseNutrition(_fatCtrl);
    final satFat = _parseNutrition(_satFatCtrl);
    final fiber = _parseNutrition(_fiberCtrl);
    final salt = _parseNutrition(_saltCtrl);
    final serving = _parseNutrition(_servingSizeCtrl);
    final ingredients = _ingredientsCtrl.text.trim().isNotEmpty
        ? _ingredientsCtrl.text.trim()
        : null;

    if (existing == null) {
      await notifier.createItem(
        name: _nameCtrl.text.trim(),
        brand: _brandCtrl.text.trim().isEmpty ? null : _brandCtrl.text.trim(),
        ean: _eanCtrl.text.trim().isEmpty ? null : _eanCtrl.text.trim(),
        categoryId: _categoryId,
        productType: _productType,
        alwaysConsumedFully: _alwaysConsumedFully,
        openedFlag: _openedFlag,
        notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        caloriesPer100g: calories,
        proteinPer100g: protein,
        carbsPer100g: carbs,
        sugarsPer100g: sugars,
        fatPer100g: fat,
        saturatedFatPer100g: satFat,
        fiberPer100g: fiber,
        saltPer100g: salt,
        servingSizeG: serving,
        nutriscore: _nutriscore,
        novaGroup: _novaGroup,
        ingredientsText: ingredients,
      );
    } else {
      await notifier.updateItem(existing.copyWith(
        name: _nameCtrl.text.trim(),
        brand: Value(_brandCtrl.text.trim().isEmpty ? null : _brandCtrl.text.trim()),
        ean: Value(_eanCtrl.text.trim().isEmpty ? null : _eanCtrl.text.trim()),
        categoryId: _categoryId,
        productType: _productType,
        alwaysConsumedFully: _alwaysConsumedFully,
        openedFlag: _openedFlag,
        notes: Value(_notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim()),
        caloriesPer100g: Value(calories),
        proteinPer100g: Value(protein),
        carbsPer100g: Value(carbs),
        sugarsPer100g: Value(sugars),
        fatPer100g: Value(fat),
        saturatedFatPer100g: Value(satFat),
        fiberPer100g: Value(fiber),
        saltPer100g: Value(salt),
        servingSizeG: Value(serving),
        nutriscore: Value(_nutriscore),
        novaGroup: Value(_novaGroup),
        ingredientsText: Value(ingredients),
        updatedAt: DateTime.now(),
      ));
    }
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.item != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? 'Artikel bearbeiten' : 'Neuer Artikel'),
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
            // EAN + OFF-Lookup
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _eanCtrl,
                    decoration: const InputDecoration(
                      labelText: 'EAN / Barcode',
                      prefixIcon: Icon(Icons.barcode_reader),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.outlined(
                  onPressed: _loadingOff ? null : _lookupOff,
                  tooltip: 'OpenFoodFacts nachschlagen',
                  icon: _loadingOff
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.search),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _nameCtrl,
              decoration: const InputDecoration(labelText: 'Name *'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Name erforderlich' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _brandCtrl,
              decoration: const InputDecoration(labelText: 'Marke'),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              // ignore: deprecated_member_use
              value: _categoryId,
              decoration: const InputDecoration(labelText: 'Kategorie'),
              items: const [
                DropdownMenuItem(value: 'food', child: Text('Lebensmittel')),
                DropdownMenuItem(value: 'appliance', child: Text('Gerät / Haushalt')),
                DropdownMenuItem(value: 'task', child: Text('Aufgabe')),
                DropdownMenuItem(value: 'wishlist', child: Text('Wunschliste')),
              ],
              onChanged: (v) => setState(() => _categoryId = v!),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              // ignore: deprecated_member_use
              value: _productType,
              decoration: const InputDecoration(labelText: 'Produkttyp'),
              items: const [
                DropdownMenuItem(
                  value: 'readyToEat',
                  child: Text('Fertiggericht / Konserve / TK'),
                ),
                DropdownMenuItem(
                  value: 'needsCooking',
                  child: Text('Muss zubereitet werden'),
                ),
                DropdownMenuItem(
                  value: 'ingredient',
                  child: Text('Zutat / Gewürz'),
                ),
              ],
              onChanged: (v) => setState(() => _productType = v!),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              value: _alwaysConsumedFully,
              onChanged: (v) => setState(() => _alwaysConsumedFully = v),
              title: const Text('Immer komplett verbraucht'),
              subtitle: const Text('Beim Scan wird der gesamte Bestand abgezogen'),
              contentPadding: EdgeInsets.zero,
            ),
            SwitchListTile(
              value: _openedFlag,
              onChanged: (v) => setState(() => _openedFlag = v),
              title: const Text('Bleibt nach Öffnen vorhanden'),
              subtitle: const Text('Für Mindestmengen: gilt als vorhanden bis leer'),
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _notesCtrl,
              decoration: const InputDecoration(labelText: 'Notizen'),
              maxLines: 3,
            ),

            // ── Nutrition section ─────────────────────────────────────────
            const SizedBox(height: 16),
            InkWell(
              onTap: () => setState(() => _showNutrition = !_showNutrition),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    const Icon(Icons.restaurant_menu, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Nährwerte (pro 100g)',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const Spacer(),
                    Icon(_showNutrition
                        ? Icons.expand_less
                        : Icons.expand_more),
                  ],
                ),
              ),
            ),
            if (_showNutrition) ...[
              const Divider(height: 8),
              const SizedBox(height: 8),
              // Nutri-Score + NOVA row
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String?>(
                      // ignore: deprecated_member_use
                      value: _nutriscore,
                      decoration: const InputDecoration(labelText: 'Nutri-Score'),
                      items: [
                        const DropdownMenuItem(value: null, child: Text('–')),
                        ...['a', 'b', 'c', 'd', 'e'].map((s) =>
                            DropdownMenuItem(
                                value: s, child: Text(s.toUpperCase()))),
                      ],
                      onChanged: (v) => setState(() => _nutriscore = v),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<int?>(
                      // ignore: deprecated_member_use
                      value: _novaGroup,
                      decoration: const InputDecoration(labelText: 'NOVA-Gruppe'),
                      items: [
                        const DropdownMenuItem(value: null, child: Text('–')),
                        ...[1, 2, 3, 4].map((n) =>
                            DropdownMenuItem(value: n, child: Text('$n'))),
                      ],
                      onChanged: (v) => setState(() => _novaGroup = v),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _NutritionField(
                        ctrl: _caloriesCtrl, label: 'Kalorien (kcal)'),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _NutritionField(
                        ctrl: _servingSizeCtrl, label: 'Portion (g)'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _NutritionField(
                        ctrl: _proteinCtrl, label: 'Eiweiß (g)'),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _NutritionField(
                        ctrl: _fiberCtrl, label: 'Ballaststoffe (g)'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _NutritionField(
                        ctrl: _carbsCtrl, label: 'Kohlenhydrate (g)'),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _NutritionField(
                        ctrl: _sugarCtrl, label: 'davon Zucker (g)'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _NutritionField(ctrl: _fatCtrl, label: 'Fett (g)'),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _NutritionField(
                        ctrl: _satFatCtrl, label: 'gesättigte Fettsäuren (g)'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _NutritionField(ctrl: _saltCtrl, label: 'Salz (g)'),
              const SizedBox(height: 12),
              TextFormField(
                controller: _ingredientsCtrl,
                decoration: const InputDecoration(labelText: 'Zutaten'),
                maxLines: 4,
              ),
              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }
}

class _NutritionField extends StatelessWidget {
  final TextEditingController ctrl;
  final String label;
  const _NutritionField({required this.ctrl, required this.label});

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: ctrl,
      decoration: InputDecoration(labelText: label),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      validator: (v) {
        if (v == null || v.trim().isEmpty) return null;
        final parsed = double.tryParse(v.trim().replaceAll(',', '.'));
        if (parsed == null) return 'Ungültige Zahl';
        return null;
      },
    );
  }
}
