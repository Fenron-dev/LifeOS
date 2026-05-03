import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../db/database.dart';
import 'vault_provider.dart';

// ---------------------------------------------------------------------------
// All items (watched stream)
// ---------------------------------------------------------------------------

final allItemsProvider = StreamProvider<List<Item>>((ref) {
  final db = ref.watch(databaseProvider);
  if (db == null) return const Stream.empty();
  return db.watchAllItems();
});

// ---------------------------------------------------------------------------
// Search query state
// ---------------------------------------------------------------------------

final itemSearchQueryProvider = StateProvider<String>((ref) => '');

/// null = all categories; non-null = filter by categoryId
final itemCategoryFilterProvider = StateProvider<String?>((ref) => null);

// ---------------------------------------------------------------------------
// Filtered items (search + category filter)
// ---------------------------------------------------------------------------

final filteredItemsProvider = StreamProvider<List<Item>>((ref) {
  final db = ref.watch(databaseProvider);
  if (db == null) return const Stream.empty();
  final query = ref.watch(itemSearchQueryProvider).trim();
  final category = ref.watch(itemCategoryFilterProvider);

  Stream<List<Item>> base;
  if (query.isEmpty && category == null) {
    base = db.watchAllItems();
  } else if (query.isEmpty) {
    base = db.watchItemsByCategory(category!);
  } else {
    base = db.searchItems(query);
  }

  // If both search and category are active, filter stream client-side
  if (query.isNotEmpty && category != null) {
    return base.map((items) =>
        items.where((i) => i.categoryId == category).toList());
  }
  return base;
});

// ---------------------------------------------------------------------------
// Single item by id
// ---------------------------------------------------------------------------

final itemByIdProvider =
    StreamProvider.family<Item?, String>((ref, id) {
  final db = ref.watch(databaseProvider);
  if (db == null) return const Stream.empty();
  return db.watchItemById(id);
});

// ---------------------------------------------------------------------------
// Item by EAN (for barcode scan routing)
// ---------------------------------------------------------------------------

final itemsDaoProvider = Provider<AppDatabase?>((ref) => ref.watch(databaseProvider));

// ---------------------------------------------------------------------------
// Item operations
// ---------------------------------------------------------------------------

final itemsNotifierProvider =
    AsyncNotifierProvider<ItemsNotifier, void>(ItemsNotifier.new);

class ItemsNotifier extends AsyncNotifier<void> {
  static const _uuid = Uuid();

  @override
  Future<void> build() async {}

  AppDatabase get _db => ref.read(databaseProvider)!;

  Future<String> createItem({
    required String name,
    String? brand,
    String? ean,
    required String categoryId,
    String productType = 'needsCooking',
    bool alwaysConsumedFully = false,
    bool openedFlag = true,
    int? daysAfterOpening,
    String? notes,
    // Nutrition
    double? caloriesPer100g,
    double? proteinPer100g,
    double? carbsPer100g,
    double? fatPer100g,
    double? fiberPer100g,
    double? sugarsPer100g,
    double? saturatedFatPer100g,
    double? saltPer100g,
    double? servingSizeG,
    String? nutriscore,
    int? novaGroup,
    String? ingredientsText,
    String? stockUnit,
    String? defaultLocationId,
    String nutritionRefUnit = 'g',
  }) async {
    final id = _uuid.v4();
    await _db.insertItem(ItemsCompanion.insert(
      id: id,
      name: name,
      brand: Value(brand),
      ean: Value(ean),
      categoryId: categoryId,
      productType: Value(productType),
      alwaysConsumedFully: Value(alwaysConsumedFully),
      openedFlag: Value(openedFlag),
      daysAfterOpening: Value(daysAfterOpening),
      notes: Value(notes),
      caloriesPer100g: Value(caloriesPer100g),
      proteinPer100g: Value(proteinPer100g),
      carbsPer100g: Value(carbsPer100g),
      fatPer100g: Value(fatPer100g),
      fiberPer100g: Value(fiberPer100g),
      sugarsPer100g: Value(sugarsPer100g),
      saturatedFatPer100g: Value(saturatedFatPer100g),
      saltPer100g: Value(saltPer100g),
      servingSizeG: Value(servingSizeG),
      nutriscore: Value(nutriscore),
      novaGroup: Value(novaGroup),
      ingredientsText: Value(ingredientsText),
      stockUnit: Value(stockUnit),
      defaultLocationId: Value(defaultLocationId),
      nutritionRefUnit: Value(nutritionRefUnit),
    ));
    return id;
  }

  Future<void> updateItem(Item item) async {
    await _db.updateItem(ItemsCompanion(
      id: Value(item.id),
      name: Value(item.name),
      brand: Value(item.brand),
      ean: Value(item.ean),
      categoryId: Value(item.categoryId),
      productType: Value(item.productType),
      alwaysConsumedFully: Value(item.alwaysConsumedFully),
      openedFlag: Value(item.openedFlag),
      daysAfterOpening: Value(item.daysAfterOpening),
      containerItemId: Value(item.containerItemId),
      notes: Value(item.notes),
      caloriesPer100g: Value(item.caloriesPer100g),
      proteinPer100g: Value(item.proteinPer100g),
      carbsPer100g: Value(item.carbsPer100g),
      fatPer100g: Value(item.fatPer100g),
      fiberPer100g: Value(item.fiberPer100g),
      sugarsPer100g: Value(item.sugarsPer100g),
      saturatedFatPer100g: Value(item.saturatedFatPer100g),
      saltPer100g: Value(item.saltPer100g),
      servingSizeG: Value(item.servingSizeG),
      nutriscore: Value(item.nutriscore),
      novaGroup: Value(item.novaGroup),
      ingredientsText: Value(item.ingredientsText),
      stockUnit: Value(item.stockUnit),
      defaultLocationId: Value(item.defaultLocationId),
      nutritionRefUnit: Value(item.nutritionRefUnit),
      updatedAt: Value(DateTime.now()),
    ));
  }

  Future<void> deleteItem(String id) => _db.deleteItem(id);
}
