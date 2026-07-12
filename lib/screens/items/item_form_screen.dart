import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/ean_validator.dart';
import '../../core/item_categories.dart';
import '../../core/product_types.dart';
import '../../providers/tags_provider.dart';
import '../../providers/templates_provider.dart';
import '../../providers/product_types_provider.dart';
import '../../db/database.dart';
import '../../providers/groups_provider.dart';
import '../../providers/items_provider.dart';
import '../../providers/locations_provider.dart';
import '../../providers/unit_conversions_provider.dart';
import '../../providers/units_provider.dart';
import '../../providers/categories_provider.dart';
import '../../providers/shops_provider.dart';
import '../../providers/vault_provider.dart';
import '../../utils/consumption_stats.dart';
import '../../screens/settings/unit_conversions_screen.dart';
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
  int? _daysAfterOpening;
  String _categoryId = ItemCategory.food;
  String? _templateId;
  String? _nutriscore;
  int? _novaGroup;
  bool _loadingOff = false;
  bool _loadingNameSearch = false;
  bool _showNutrition = false;

  // Nutrition reference unit: 'g' (per 100g) or 'ml' (per 100ml for liquids)
  String _nutritionRefUnit = 'g';

  // Stock unit for inventory aggregation
  String? _stockUnit;
  String? _defaultLocationId;
  String? _openedLocationId;
  bool _taraEnabled = false;
  late final TextEditingController _taraWeightGCtrl;
  String? _containerItemId;

  // Default consume unit (per-item deduction override)
  late final TextEditingController _consumeQtyCtrl;
  String? _consumeUnit;

  // Per-item minimum stock
  bool _hasMinStock = false;
  late final TextEditingController _minStockQtyCtrl;
  String? _minStockUnit;
  String? _preferredShopId;

  // Staple + purchase unit
  bool _isStaple = false;
  late final TextEditingController _purchaseUnitCtrl;
  String _expiryType = 'bestBefore';
  int? _shelfLifeDays;

  // Health factor: 1=healthy, 0=neutral, -1=unhealthy
  int? _healthFactor;
  late final TextEditingController _purchaseQtyCtrl;

  // Group membership
  Set<String> _selectedGroupIds = {};
  Set<String> _originalGroupIds = {};

  // Tags
  List<String> _tagNames = [];

  // Item-specific unit conversions (local list, synced on save)
  List<({String fromUnit, String toUnit, double factor})> _conversions = [];

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
    _consumeQtyCtrl = TextEditingController(
        text: i?.consumeQty != null ? _fmtCtrl(i!.consumeQty) : '');
    _minStockQtyCtrl = TextEditingController(
        text: i?.minStockQuantity != null ? _fmtCtrl(i!.minStockQuantity) : '');
    _taraWeightGCtrl = TextEditingController(
        text: i?.taraWeightG != null ? _fmtCtrl(i!.taraWeightG) : '');
    _purchaseUnitCtrl = TextEditingController(text: i?.purchaseUnit ?? '');
    _purchaseQtyCtrl = TextEditingController(
        text: i?.purchaseQty != null ? _fmtCtrl(i!.purchaseQty) : '');

    if (i != null) {
      _productType = i.productType;
      _alwaysConsumedFully = i.alwaysConsumedFully;
      _openedFlag = i.openedFlag;
      _daysAfterOpening = i.daysAfterOpening;
      _categoryId = i.categoryId;
      _templateId = i.templateId;
      _nutriscore = i.nutriscore;
      _novaGroup = i.novaGroup;
      _stockUnit = i.stockUnit;
      _defaultLocationId = i.defaultLocationId;
      _openedLocationId = i.openedLocationId;
      _taraEnabled = i.taraWeightG != null;
      _containerItemId = i.containerItemId;
      _nutritionRefUnit = i.nutritionRefUnit;
      _consumeUnit = i.consumeUnit;
      _showNutrition = _hasAnyNutrition(i);
      _isStaple = i.isStaple;
      _expiryType = i.expiryType;
      _shelfLifeDays = i.shelfLifeDays;
      _healthFactor = i.healthFactor;
      if (i.minStockQuantity != null) {
        _hasMinStock = true;
        _minStockUnit = i.minStockUnit;
        _preferredShopId = i.preferredShopId;
      }
    }
    // Load existing group memberships, item conversions and tags
    if (i != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final db = ref.read(databaseProvider);
        if (db == null || !mounted) return;
        final members = await db.groupsForItem(i.id);
        final convs = await db.watchConversionsForItem(i.id).first;
        final existingTags = await db.watchTagsForItem(i.id).first;
        if (!mounted) return;
        setState(() {
          _originalGroupIds = members.map((m) => m.groupId).toSet();
          _selectedGroupIds = Set.from(_originalGroupIds);
          _conversions = convs
              .map((c) => (
                    fromUnit: c.fromUnit,
                    toUnit: c.toUnit,
                    factor: c.factor,
                  ))
              .toList();
          _tagNames = existingTags.map((t) => t.name).toList();
        });
      });
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
    _consumeQtyCtrl.dispose();
    _minStockQtyCtrl.dispose();
    _taraWeightGCtrl.dispose();
    _purchaseUnitCtrl.dispose();
    _purchaseQtyCtrl.dispose();
    super.dispose();
  }

  /// Delegates to the shared validator (core/ean_validator.dart).
  String? _validateEan(String? v) => validateEanMessage(v);

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
    // Skip products with no importable data
    if (!OFFField.values.any(product.hasField)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Produkt in OpenFoodFacts ohne verwertbare Daten')),
      );
      return;
    }

    // Show selection dialog
    final selected = await showOffImportDialog(context, product);
    if (selected == null || !mounted) return;
    _applyOffProduct(product, selected);
  }

  Future<void> _searchByName() async {
    final query = _nameCtrl.text.trim();
    if (query.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bitte zuerst einen Namen eingeben')),
      );
      return;
    }
    setState(() => _loadingNameSearch = true);
    final results = await OpenFoodFactsService.searchByName(query);
    if (!mounted) return;
    setState(() => _loadingNameSearch = false);

    // Filter out entries without a real name
    final usableResults = results
        .where((p) =>
            p.name != null &&
            p.name!.isNotEmpty &&
            p.name!.toLowerCase() != 'unknown' &&
            OFFField.values.any(p.hasField))
        .toList();

    if (usableResults.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Keine verwertbaren Treffer in OpenFoodFacts')),
      );
      return;
    }

    // Let user pick one result
    final chosen = await showDialog<OFFProduct>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Produkt auswählen'),
        children: usableResults.map((p) {
          return SimpleDialogOption(
            onPressed: () => Navigator.of(ctx).pop(p),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.name ?? p.ean,
                    style: const TextStyle(fontWeight: FontWeight.w500)),
                if (p.brand != null)
                  Text(p.brand!, style: const TextStyle(fontSize: 12)),
                const Divider(height: 8),
              ],
            ),
          );
        }).toList(),
      ),
    );
    if (chosen == null || !mounted) return;

    // Fill EAN and trigger import dialog
    setState(() => _eanCtrl.text = chosen.ean);
    final selected = await showOffImportDialog(context, chosen);
    if (selected == null || !mounted) return;
    _applyOffProduct(chosen, selected);
  }

  void _applyOffProduct(OFFProduct product, Set<OFFField> selected) {
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

  void _showTagPickerInForm(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _FormTagPickerSheet(
        categoryId: _categoryId,
        selected: List.from(_tagNames),
        onSaved: (names) => setState(() => _tagNames = names),
      ),
    );
  }

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

    final consumeQty = double.tryParse(_consumeQtyCtrl.text.trim().replaceAll(',', '.'));
    final minStockQty = _hasMinStock
        ? double.tryParse(_minStockQtyCtrl.text.trim().replaceAll(',', '.'))
        : null;

    final String itemId;
    if (existing == null) {
      itemId = await notifier.createItem(
        name: _nameCtrl.text.trim(),
        brand: _brandCtrl.text.trim().isEmpty ? null : _brandCtrl.text.trim(),
        ean: _eanCtrl.text.trim().isEmpty ? null : _eanCtrl.text.trim(),
        categoryId: _categoryId,
        productType: _productType,
        alwaysConsumedFully: _alwaysConsumedFully,
        openedFlag: _openedFlag,
        daysAfterOpening: _daysAfterOpening,
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
        stockUnit: _stockUnit,
        defaultLocationId: _defaultLocationId,
        openedLocationId: _openedLocationId,
        nutritionRefUnit: _nutritionRefUnit,
        consumeQty: consumeQty,
        consumeUnit: consumeQty != null ? _consumeUnit : null,
        minStockQuantity: minStockQty,
        minStockUnit: minStockQty != null ? _minStockUnit : null,
        preferredShopId: _preferredShopId,
        templateId: _templateId,
        containerItemId: _containerItemId,
        taraWeightG: _taraEnabled
            ? double.tryParse(_taraWeightGCtrl.text.replaceAll(',', '.'))
            : null,
        isStaple: _isStaple,
        purchaseUnit: _purchaseUnitCtrl.text.trim().isEmpty ? null : _purchaseUnitCtrl.text.trim(),
        purchaseQty: double.tryParse(_purchaseQtyCtrl.text.trim().replaceAll(',', '.')),
        expiryType: _expiryType,
        shelfLifeDays: _shelfLifeDays,
        healthFactor: _healthFactor,
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
        daysAfterOpening: Value(_daysAfterOpening),
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
        stockUnit: Value(_stockUnit),
        defaultLocationId: Value(_defaultLocationId),
        openedLocationId: Value(_openedLocationId),
        nutritionRefUnit: _nutritionRefUnit,
        consumeQty: Value(consumeQty),
        consumeUnit: Value(consumeQty != null ? _consumeUnit : null),
        minStockQuantity: Value(minStockQty),
        minStockUnit: Value(minStockQty != null ? _minStockUnit : null),
        preferredShopId: Value(_preferredShopId),
        templateId: Value(_templateId),
        containerItemId: Value(_containerItemId),
        taraWeightG: Value(_taraEnabled
            ? double.tryParse(_taraWeightGCtrl.text.replaceAll(',', '.'))
            : null),
        isStaple: _isStaple,
        purchaseUnit: Value(_purchaseUnitCtrl.text.trim().isEmpty ? null : _purchaseUnitCtrl.text.trim()),
        purchaseQty: Value(double.tryParse(_purchaseQtyCtrl.text.trim().replaceAll(',', '.'))),
        expiryType: _expiryType,
        shelfLifeDays: Value(_shelfLifeDays),
        healthFactor: Value(_healthFactor),
        updatedAt: DateTime.now(),
      ));
      itemId = existing.id;
    }

    // Sync group memberships
    final db = ref.read(databaseProvider)!;
    for (final gId in _selectedGroupIds.difference(_originalGroupIds)) {
      await db.addItemToGroup(gId, itemId);
    }
    for (final gId in _originalGroupIds.difference(_selectedGroupIds)) {
      await db.removeItemFromGroup(gId, itemId);
    }

    // Sync item-specific unit conversions (delete all, reinsert current list)
    final convNotifier = ref.read(conversionsNotifierProvider.notifier);
    final existingConvs = await db.watchConversionsForItem(itemId).first;
    for (final c in existingConvs) {
      await convNotifier.delete(c.id);
    }
    for (final c in _conversions) {
      await convNotifier.addForItem(
        itemId: itemId,
        fromUnit: c.fromUnit,
        toUnit: c.toUnit,
        factor: c.factor,
      );
    }

    // Sync tags
    if (_tagNames.isNotEmpty) {
      await db.setTagsForItem(itemId, _categoryId, _tagNames);
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
                    validator: _validateEan,
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
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _nameCtrl,
                    decoration: const InputDecoration(labelText: 'Name *'),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Name erforderlich' : null,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.outlined(
                  onPressed: _loadingNameSearch ? null : _searchByName,
                  tooltip: 'Nach Name in OpenFoodFacts suchen',
                  icon: _loadingNameSearch
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.travel_explore),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _brandCtrl,
              decoration: const InputDecoration(labelText: 'Marke'),
            ),
            const SizedBox(height: 16),
            Builder(builder: (context) {
              final customCats =
                  ref.watch(categoryDefinitionsProvider).valueOrNull ?? [];
              return DropdownButtonFormField<String>(
                // ignore: deprecated_member_use
                value: _categoryId,
                decoration: const InputDecoration(labelText: 'Kategorie'),
                items: [
                  ...ItemCategory.allItemCategories.map((c) =>
                      DropdownMenuItem(
                        value: c,
                        child: Row(
                          children: [
                            Icon(ItemCategory.iconFor(c), size: 16),
                            const SizedBox(width: 8),
                            Text(ItemCategory.labelDe(c)),
                          ],
                        ),
                      )),
                  if (customCats.isNotEmpty) ...[
                    const DropdownMenuItem(
                      enabled: false,
                      value: '__divider__',
                      child: Divider(height: 1),
                    ),
                    ...customCats.map((cat) => DropdownMenuItem(
                          value: cat.id,
                          child: Row(
                            children: [
                              Icon(_categoryIconData(cat.iconName), size: 16),
                              const SizedBox(width: 8),
                              Text(cat.name),
                            ],
                          ),
                        )),
                  ],
                ],
                onChanged: (v) {
                  if (v == null || v == '__divider__') return;
                  setState(() => _categoryId = v);
                },
              );
            }),
            const SizedBox(height: 12),
            Consumer(builder: (context, ref, _) {
              final templatesAsync = ref.watch(allTemplatesProvider);
              final templates = templatesAsync.valueOrNull ?? [];
              return DropdownButtonFormField<String?>(
                // ignore: deprecated_member_use
                value: _templateId,
                decoration: const InputDecoration(labelText: 'Template'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('Kein Template')),
                  ...templates.map((t) => DropdownMenuItem(
                        value: t.id,
                        child: Row(
                          children: [
                            const Icon(Icons.description_outlined, size: 16),
                            const SizedBox(width: 8),
                            Text(t.name),
                          ],
                        ),
                      )),
                ],
                onChanged: (v) => setState(() => _templateId = v),
              );
            }),
            const SizedBox(height: 12),
            Consumer(builder: (context, ref, _) {
              final dbTypes = ref.watch(allProductTypesProvider).valueOrNull ?? [];
              // Merge DB types (primary) with ProductType.all fallback for display
              final items = dbTypes.isNotEmpty
                  ? dbTypes.map((t) => DropdownMenuItem<String>(
                        value: t.id,
                        child: Row(
                          children: [
                            Icon(ProductType.iconFor(t.id),
                                size: 18, color: ProductType.colorFor(t.id)),
                            const SizedBox(width: 8),
                            Text(t.nameDe),
                          ],
                        ),
                      )).toList()
                  : ProductType.all.map((t) => DropdownMenuItem<String>(
                        value: t,
                        child: Row(
                          children: [
                            Icon(ProductType.iconFor(t),
                                size: 18, color: ProductType.colorFor(t)),
                            const SizedBox(width: 8),
                            Text(ProductType.labelDe(t)),
                          ],
                        ),
                      )).toList();
              return DropdownButtonFormField<String>(
                // ignore: deprecated_member_use
                value: _productType,
                decoration: const InputDecoration(labelText: 'Produkttyp'),
                items: items,
                onChanged: (v) => setState(() => _productType = v!),
              );
            }),
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
            const SizedBox(height: 8),
            TextFormField(
              initialValue: _daysAfterOpening?.toString() ?? '',
              decoration: const InputDecoration(
                labelText: 'Haltbar nach Öffnen (Tage)',
                helperText: 'Wie viele Tage das Produkt nach Öffnen noch haltbar ist',
                prefixIcon: Icon(Icons.lock_open_outlined),
              ),
              keyboardType: TextInputType.number,
              onChanged: (v) {
                final n = int.tryParse(v.trim());
                setState(() => _daysAfterOpening = n);
              },
            ),
            const SizedBox(height: 12),
            // Expiry type selector
            InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Haltbarkeitsangabe',
                prefixIcon: Icon(Icons.event_available_outlined),
                helperText: 'Wie das Ablaufdatum beim Einlagern erfasst wird',
              ),
              child: DropdownButton<String>(
                value: _expiryType,
                isExpanded: true,
                underline: const SizedBox.shrink(),
                items: const [
                  DropdownMenuItem(
                      value: 'bestBefore',
                      child: Text('MHD (Mindesthaltbarkeitsdatum)')),
                  DropdownMenuItem(
                      value: 'useBy', child: Text('Verbrauchsdatum')),
                  DropdownMenuItem(
                      value: 'daysAfterPurchase',
                      child: Text('Haltbar nach Kauf (Tage)')),
                ],
                onChanged: (v) =>
                    setState(() => _expiryType = v ?? 'bestBefore'),
              ),
            ),
            if (_expiryType == 'daysAfterPurchase') ...[
              const SizedBox(height: 8),
              TextFormField(
                key: ValueKey(_expiryType),
                initialValue: _shelfLifeDays?.toString() ?? '',
                decoration: const InputDecoration(
                  labelText: 'Haltbarkeit nach Kauf (Tage)',
                  helperText:
                      'z.B. 5 für Obst – MHD wird beim Einlagern automatisch berechnet',
                  prefixIcon: Icon(Icons.calendar_month_outlined),
                ),
                keyboardType: TextInputType.number,
                onChanged: (v) =>
                    setState(() => _shelfLifeDays = int.tryParse(v.trim())),
              ),
            ],
            const SizedBox(height: 12),
            // Stock unit dropdown
            Consumer(builder: (context, ref, _) {
              final unitNames = ref.watch(unitNamesProvider);
              final currentValue = unitNames.contains(_stockUnit) ? _stockUnit : null;
              return InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Bestandseinheit',
                  helperText: 'Einheit für Bestandssummierung im Inventar',
                  prefixIcon: Icon(Icons.straighten),
                ),
                child: DropdownButton<String?>(
                  value: currentValue,
                  isExpanded: true,
                  underline: const SizedBox.shrink(),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('— keine —')),
                    ...unitNames.map((n) => DropdownMenuItem(value: n, child: Text(n))),
                  ],
                  onChanged: (v) => setState(() => _stockUnit = v),
                ),
              );
            }),
            const SizedBox(height: 12),
            // Default consume amount (overrides the servingSizeG heuristic when deducting)
            Consumer(builder: (context, ref, _) {
              final unitNames = ref.watch(unitNamesProvider);
              return Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: _consumeQtyCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Verbrauchsmenge',
                        helperText: 'Standard-Abzug beim Ausbuchen',
                        prefixIcon: Icon(Icons.remove_circle_outline),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 3,
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Einheit',
                        helperText: ' ',
                      ),
                      child: DropdownButton<String?>(
                        value: unitNames.contains(_consumeUnit) ? _consumeUnit : null,
                        isExpanded: true,
                        underline: const SizedBox.shrink(),
                        items: [
                          const DropdownMenuItem(value: null, child: Text('— auto —')),
                          ...unitNames.map((n) => DropdownMenuItem(value: n, child: Text(n))),
                        ],
                        onChanged: (v) => setState(() => _consumeUnit = v),
                      ),
                    ),
                  ),
                ],
              );
            }),
            const SizedBox(height: 12),
            // Minimum stock section
            SwitchListTile(
              value: _hasMinStock,
              onChanged: (v) => setState(() => _hasMinStock = v),
              title: const Text('Mindestbestand festlegen'),
              subtitle: const Text('Artikel erscheint in der Einkaufsliste wenn Bestand darunter fällt'),
              contentPadding: EdgeInsets.zero,
            ),
            if (_hasMinStock) ...[
              Consumer(builder: (context, ref, _) {
                final unitNames = ref.watch(unitNamesProvider);
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        controller: _minStockQtyCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Mindestmenge',
                          prefixIcon: Icon(Icons.inventory_outlined),
                        ),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 3,
                      child: InputDecorator(
                        decoration: const InputDecoration(labelText: 'Einheit'),
                        child: DropdownButton<String?>(
                          value: unitNames.contains(_minStockUnit) ? _minStockUnit : null,
                          isExpanded: true,
                          underline: const SizedBox.shrink(),
                          items: [
                            const DropdownMenuItem(value: null, child: Text('— keine —')),
                            ...unitNames.map((n) => DropdownMenuItem(value: n, child: Text(n))),
                          ],
                          onChanged: (v) => setState(() => _minStockUnit = v),
                        ),
                      ),
                    ),
                  ],
                );
              }),
              // F3: min-stock suggestion learned from the item's own
              // consumption rate × purchase interval (+20 % buffer).
              if (widget.item != null)
                Consumer(builder: (context, ref, _) {
                  final db = ref.watch(databaseProvider);
                  if (db == null) return const SizedBox.shrink();
                  return StreamBuilder(
                    stream: db.watchEventsForItem(widget.item!.id),
                    builder: (context, snap) {
                      final events = snap.data ?? const <ItemEvent>[];
                      final suggestion = suggestedMinStock(
                        dailyConsumptionRate(events),
                        avgDaysBetweenPurchases(events),
                      );
                      if (suggestion == null) return const SizedBox.shrink();
                      final current = double.tryParse(_minStockQtyCtrl.text
                          .trim()
                          .replaceAll(',', '.'));
                      if (current != null &&
                          (current - suggestion).abs() < 0.001) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: ActionChip(
                            avatar: const Icon(Icons.auto_awesome, size: 16),
                            label: Text(
                                'Vorschlag: ${suggestion % 1 == 0 ? suggestion.toStringAsFixed(0) : suggestion.toStringAsFixed(1)} (aus deinem Verbrauch)'),
                            onPressed: () => setState(() =>
                                _minStockQtyCtrl.text = suggestion % 1 == 0
                                    ? suggestion.toStringAsFixed(0)
                                    : suggestion.toStringAsFixed(1)),
                          ),
                        ),
                      );
                    },
                  );
                }),
              const SizedBox(height: 8),
              Consumer(builder: (context, ref, _) {
                final shops = ref.watch(allShopsProvider).valueOrNull ?? [];
                if (shops.isEmpty) return const SizedBox.shrink();
                return DropdownButtonFormField<String?>(
                  // ignore: deprecated_member_use
                  value: _preferredShopId,
                  decoration: const InputDecoration(
                    labelText: 'Bevorzugtes Geschäft',
                    prefixIcon: Icon(Icons.store_outlined),
                  ),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('— keins —')),
                    ...shops.map((s) => DropdownMenuItem(value: s.id, child: Text(s.name))),
                  ],
                  onChanged: (v) => setState(() => _preferredShopId = v),
                );
              }),
              const SizedBox(height: 4),
            ],
            const SizedBox(height: 12),
            // Staple + purchase unit
            SwitchListTile(
              value: _isStaple,
              onChanged: (v) => setState(() => _isStaple = v),
              title: const Text('Grundnahrungsmittel'),
              subtitle: const Text('Warnung im Dashboard wenn leer'),
              contentPadding: EdgeInsets.zero,
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  flex: 3,
                  child: TextFormField(
                    controller: _purchaseUnitCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Ich kaufe in',
                      helperText: 'z. B. „Packung", „Karton"',
                      prefixIcon: Icon(Icons.shopping_bag_outlined),
                    ),
                    textCapitalization: TextCapitalization.sentences,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller: _purchaseQtyCtrl,
                    decoration: InputDecoration(
                      labelText: 'Inhalt',
                      helperText: _stockUnit != null
                          ? '1 Kaufeinheit = ? $_stockUnit'
                          : 'Menge je Kaufeinheit',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Text(
                'Einkaufsliste zeigt Packungsanzahl statt Einzelmenge',
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Health factor
            _HealthFactorPicker(
              value: _healthFactor,
              onChanged: (v) => setState(() => _healthFactor = v),
            ),
            const SizedBox(height: 12),
            // Default location picker
            Consumer(builder: (context, ref, _) {
              final locations = ref.watch(allLocationsProvider).valueOrNull ?? [];
              if (locations.isEmpty) return const SizedBox.shrink();
              return DropdownButtonFormField<String?>(
                // ignore: deprecated_member_use
                value: _defaultLocationId,
                decoration: const InputDecoration(
                  labelText: 'Standard-Lagerort',
                  helperText: 'Wird beim Einlagern vorausgewählt',
                  prefixIcon: Icon(Icons.place_outlined),
                ),
                items: [
                  const DropdownMenuItem(value: null, child: Text('— keiner —')),
                  ...locations.map((l) =>
                      DropdownMenuItem(value: l.id, child: Text(l.name))),
                ],
                onChanged: (v) => setState(() => _defaultLocationId = v),
              );
            }),
            const SizedBox(height: 12),
            // Opened location picker
            Consumer(builder: (context, ref, _) {
              final locations = ref.watch(allLocationsProvider).valueOrNull ?? [];
              if (locations.isEmpty) return const SizedBox.shrink();
              return DropdownButtonFormField<String?>(
                // ignore: deprecated_member_use
                value: _openedLocationId,
                decoration: const InputDecoration(
                  labelText: 'Lagerort (nach Öffnen)',
                  helperText: 'Wohin wird der Artikel nach dem Öffnen umgelagert?',
                  prefixIcon: Icon(Icons.open_in_new_outlined),
                ),
                items: [
                  const DropdownMenuItem(value: null, child: Text('— keiner —')),
                  ...locations.map((l) =>
                      DropdownMenuItem(value: l.id, child: Text(l.name))),
                ],
                onChanged: (v) => setState(() => _openedLocationId = v),
              );
            }),
            SwitchListTile(
              value: _taraEnabled,
              onChanged: (v) => setState(() {
                _taraEnabled = v;
                if (!v) _taraWeightGCtrl.clear();
              }),
              title: const Text('Tara-Gewicht verwenden'),
              subtitle: const Text(
                  'Für Artikel die nach dem Öffnen per Gramm verwaltet werden (z. B. Mehl, Milch, Zucker)'),
              contentPadding: EdgeInsets.zero,
            ),
            if (_taraEnabled) ...[
              const SizedBox(height: 4),
              TextFormField(
                controller: _taraWeightGCtrl,
                decoration: const InputDecoration(
                  labelText: 'Tara-Gewicht (g)',
                  helperText:
                      'Verpackungsgewicht – wird beim Einlagern vom Bruttogewicht abgezogen',
                  prefixIcon: Icon(Icons.scale_outlined),
                ),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
              ),
            ],
            const SizedBox(height: 8),
            // Smart Tara: default container item
            Consumer(builder: (context, ref, _) {
              final allItems = ref.watch(allItemsProvider).valueOrNull ?? [];
              final containers = allItems
                  .where((i) => i.taraWeightG != null && i.id != (widget.item?.id ?? ''))
                  .toList();
              if (containers.isEmpty) return const SizedBox.shrink();
              final selected = containers.cast<Item?>().firstWhere(
                    (i) => i?.id == _containerItemId,
                    orElse: () => null,
                  );
              return ListTile(
                leading: const Icon(Icons.inventory_2_outlined),
                title: const Text('Standard-Behälter (Smart Tara)'),
                subtitle: Text(selected?.name ?? 'Keiner ausgewählt'),
                contentPadding: EdgeInsets.zero,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_containerItemId != null)
                      IconButton(
                        icon: const Icon(Icons.clear),
                        tooltip: 'Behälter entfernen',
                        onPressed: () => setState(() => _containerItemId = null),
                      ),
                    const Icon(Icons.chevron_right),
                  ],
                ),
                onTap: () async {
                  final picked = await showModalBottomSheet<String?>(
                    context: context,
                    isScrollControlled: true,
                    useSafeArea: true,
                    builder: (_) => _ContainerItemPickerSheet(
                      containers: containers,
                      selectedId: _containerItemId,
                    ),
                  );
                  if (picked != null && mounted) {
                    setState(() => _containerItemId = picked.isEmpty ? null : picked);
                  }
                },
              );
            }),
            const SizedBox(height: 12),
            TextFormField(
              controller: _notesCtrl,
              decoration: const InputDecoration(labelText: 'Notizen'),
              maxLines: 3,
            ),

            // ── Tags section ──────────────────────────────────────────────
            const SizedBox(height: 16),
            Row(
              children: [
                const Icon(Icons.label_outline, size: 20),
                const SizedBox(width: 8),
                Text('Tags', style: Theme.of(context).textTheme.titleSmall),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => _showTagPickerInForm(context),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Tag hinzufügen'),
                  style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      textStyle: const TextStyle(fontSize: 12)),
                ),
              ],
            ),
            if (_tagNames.isNotEmpty) ...[
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: _tagNames
                    .map((name) => InputChip(
                          label: Text(name,
                              style: const TextStyle(fontSize: 12)),
                          visualDensity: VisualDensity.compact,
                          onDeleted: () =>
                              setState(() => _tagNames.remove(name)),
                        ))
                    .toList(),
              ),
            ],

            // ── Groups section ────────────────────────────────────────────
            const SizedBox(height: 16),
            Consumer(builder: (context, ref, _) {
              final groupsAsync = ref.watch(allGroupsProvider);
              return groupsAsync.when(
                loading: () => const SizedBox.shrink(),
                error: (e, _) => const SizedBox.shrink(),
                data: (groups) {
                  if (groups.isEmpty) return const SizedBox.shrink();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.category_outlined, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            'Produktgruppen',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: groups.map((g) {
                          final selected = _selectedGroupIds.contains(g.id);
                          return FilterChip(
                            label: Text(g.name),
                            selected: selected,
                            onSelected: (v) => setState(() {
                              if (v) {
                                _selectedGroupIds.add(g.id);
                              } else {
                                _selectedGroupIds.remove(g.id);
                              }
                            }),
                          );
                        }).toList(),
                      ),
                    ],
                  );
                },
              );
            }),

            // ── Unit conversions section ──────────────────────────────────
            const SizedBox(height: 16),
            Row(
              children: [
                const Icon(Icons.swap_horiz, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Einheiten (artikelspezifisch)',
                    style: Theme.of(context).textTheme.titleSmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                TextButton.icon(
                  onPressed: () => showAddConversionDialog(
                    context,
                    onSave: (from, to, factor) async {
                      setState(() {
                        _conversions.add((
                          fromUnit: from,
                          toUnit: to,
                          factor: factor,
                        ));
                      });
                    },
                  ),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Hinzufügen'),
                ),
              ],
            ),
            if (_conversions.isEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 28, bottom: 4),
                child: Text(
                  'Noch keine Umrechnungen für diesen Artikel.',
                  style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.outline),
                ),
              )
            else
              ...List.generate(_conversions.length, (i) {
                final c = _conversions[i];
                final factor = c.factor == c.factor.truncateToDouble()
                    ? c.factor.toInt().toString()
                    : c.factor.toStringAsFixed(3);
                return Row(
                  children: [
                    const SizedBox(width: 28),
                    Expanded(
                      child: Text(
                        '1 ${c.fromUnit} = $factor ${c.toUnit}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline,
                          size: 18, color: Colors.red),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () =>
                          setState(() => _conversions.removeAt(i)),
                    ),
                  ],
                );
              }),

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
                      'Nährwerte (pro 100 $_nutritionRefUnit)',
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
              // g / ml toggle
              Row(
                children: [
                  Text('Bezugsgröße:',
                      style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(width: 8),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'g', label: Text('pro 100g')),
                      ButtonSegment(value: 'ml', label: Text('pro 100ml')),
                    ],
                    selected: {_nutritionRefUnit},
                    onSelectionChanged: (s) =>
                        setState(() => _nutritionRefUnit = s.first),
                    style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
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

IconData _categoryIconData(String? name) {
  return switch (name) {
    'fitness_center' => Icons.fitness_center,
    'restaurant' => Icons.restaurant_outlined,
    'local_cafe' => Icons.local_cafe_outlined,
    'sports' => Icons.sports_outlined,
    'spa' => Icons.spa_outlined,
    'medical_services' => Icons.medical_services_outlined,
    'school' => Icons.school_outlined,
    'work' => Icons.work_outline,
    'home' => Icons.home_outlined,
    'pets' => Icons.pets_outlined,
    'child_care' => Icons.child_care_outlined,
    'nature' => Icons.nature_outlined,
    'local_grocery_store' => Icons.local_grocery_store_outlined,
    'kitchen' => Icons.kitchen_outlined,
    'outdoor_grill' => Icons.outdoor_grill_outlined,
    'blender' => Icons.blender_outlined,
    'emoji_food_beverage' => Icons.emoji_food_beverage_outlined,
    'set_meal' => Icons.set_meal_outlined,
    'bakery_dining' => Icons.bakery_dining_outlined,
    _ => Icons.category_outlined,
  };
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

// ── Form tag picker sheet ─────────────────────────────────────────────────────

class _FormTagPickerSheet extends ConsumerStatefulWidget {
  final String categoryId;
  final List<String> selected;
  final ValueChanged<List<String>> onSaved;
  const _FormTagPickerSheet({
    required this.categoryId,
    required this.selected,
    required this.onSaved,
  });

  @override
  ConsumerState<_FormTagPickerSheet> createState() =>
      _FormTagPickerSheetState();
}

class _FormTagPickerSheetState extends ConsumerState<_FormTagPickerSheet> {
  final _ctrl = TextEditingController();
  late List<String> _selected;

  @override
  void initState() {
    super.initState();
    _selected = List.from(widget.selected);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final allAsync = ref
        .watch(tagDefinitionsForCategoryProvider(widget.categoryId));
    final all = allAsync.valueOrNull ?? [];
    final query = _ctrl.text.trim().toLowerCase();
    final filtered = query.isEmpty
        ? all
        : all.where((t) => t.name.toLowerCase().contains(query)).toList();
    final showCreate =
        query.isNotEmpty && !all.any((t) => t.name.toLowerCase() == query);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      builder: (_, scrollCtrl) => Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: TextField(
                controller: _ctrl,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Tag suchen oder neu erstellen…',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            Expanded(
              child: ListView(
                controller: scrollCtrl,
                children: [
                  if (showCreate)
                    ListTile(
                      leading: const Icon(Icons.add),
                      title:
                          Text('Neu erstellen: "${_ctrl.text.trim()}"'),
                      onTap: () {
                        final name = _ctrl.text.trim();
                        if (!_selected.contains(name)) {
                          setState(() => _selected.add(name));
                        }
                        _ctrl.clear();
                        setState(() {});
                      },
                    ),
                  ...filtered.map((tag) {
                    final checked = _selected.contains(tag.name);
                    return CheckboxListTile(
                      title: Text(tag.name),
                      value: checked,
                      onChanged: (v) => setState(() {
                        if (v == true) {
                          _selected.add(tag.name);
                        } else {
                          _selected.remove(tag.name);
                        }
                      }),
                    );
                  }),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Abbrechen'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () {
                        widget.onSaved(_selected);
                        Navigator.of(context).pop();
                      },
                      child: const Text('Übernehmen'),
                    ),
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

// ── Health factor picker ──────────────────────────────────────────────────────

/// Emoji row for selecting a health classification.
/// [value]: 1=healthy, 0=neutral, -1=unhealthy, null=not set.
class _HealthFactorPicker extends StatelessWidget {
  final int? value;
  final ValueChanged<int?> onChanged;
  const _HealthFactorPicker({required this.value, required this.onChanged});

  static const _options = [
    (1, '😊', 'Gesund'),
    (0, '😐', 'Neutral'),
    (-1, '😞', 'Ungesund'),
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text('Gesundheitsfaktor',
              style: Theme.of(context)
                  .textTheme
                  .labelLarge
                  ?.copyWith(color: cs.onSurfaceVariant)),
        ),
        Row(
          children: [
            for (final (val, emoji, label) in _options) ...[
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => onChanged(value == val ? null : val),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: value == val
                          ? cs.primaryContainer
                          : cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: value == val
                            ? cs.primary
                            : cs.outlineVariant,
                        width: value == val ? 2 : 1,
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(emoji,
                            style: const TextStyle(fontSize: 28)),
                        const SizedBox(height: 2),
                        Text(label,
                            style: TextStyle(
                                fontSize: 11,
                                color: value == val
                                    ? cs.onPrimaryContainer
                                    : cs.onSurfaceVariant)),
                      ],
                    ),
                  ),
                ),
              ),
              if (val != -1) const SizedBox(width: 8),
            ],
          ],
        ),
        if (value != null) ...[
          const SizedBox(height: 4),
          TextButton.icon(
            onPressed: () => onChanged(null),
            icon: const Icon(Icons.close, size: 14),
            label: const Text('Zurücksetzen'),
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
            ),
          ),
        ],
      ],
    );
  }
}

// ── Smart Tara: Container item picker sheet ───────────────────────────────────

class _ContainerItemPickerSheet extends StatefulWidget {
  final List<Item> containers;
  final String? selectedId;

  const _ContainerItemPickerSheet({
    required this.containers,
    required this.selectedId,
  });

  @override
  State<_ContainerItemPickerSheet> createState() =>
      _ContainerItemPickerSheetState();
}

class _ContainerItemPickerSheetState
    extends State<_ContainerItemPickerSheet> {
  late String _query;
  late String? _selectedId;

  @override
  void initState() {
    super.initState();
    _query = '';
    _selectedId = widget.selectedId;
  }

  @override
  Widget build(BuildContext context) {
    final filtered = widget.containers
        .where((i) => i.name.toLowerCase().contains(_query.toLowerCase()))
        .toList();

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Text('Behälter auswählen',
                    style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                if (_selectedId != null)
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(''),
                    child: const Text('Entfernen'),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Suchen…',
                prefixIcon: Icon(Icons.search),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.4,
            ),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: filtered.length,
              itemBuilder: (_, i) {
                final c = filtered[i];
                return ListTile(
                  leading: Icon(
                    Icons.inventory_2_outlined,
                    color: _selectedId == c.id
                        ? Theme.of(context).colorScheme.primary
                        : null,
                  ),
                  title: Text(c.name),
                  subtitle: Text('Tara: ${c.taraWeightG!.toStringAsFixed(0)} g'),
                  selected: _selectedId == c.id,
                  onTap: () => Navigator.of(context).pop(c.id),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
