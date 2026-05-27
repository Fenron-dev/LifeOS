import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../core/item_categories.dart';
import '../db/database.dart';
import 'vault_provider.dart';

// ---------------------------------------------------------------------------
// Shopping need (computed: group or item below min stock)
// ---------------------------------------------------------------------------

class ShoppingNeed {
  /// Non-null for group-based needs (existing behaviour).
  final ItemGroup? group;

  /// Non-null for per-item min-stock needs.
  final Item? item;

  final double currentQty;
  final double neededQty;

  ShoppingNeed({
    this.group,
    this.item,
    required this.currentQty,
    required this.neededQty,
  }) {
    if (group == null && item == null) {
      throw ArgumentError('ShoppingNeed requires either group or item');
    }
  }

  String get name => group?.name ?? item?.name ?? '';
  String get unit => group?.minStockUnit ?? item?.minStockUnit ?? '';
  String? get shopId => group?.preferredShopId ?? item?.preferredShopId;
}

// ---------------------------------------------------------------------------
// Shopping needs grouped by shop
// ---------------------------------------------------------------------------

class ShoppingSection {
  final Shop? shop;
  final List<ShoppingNeed> needs;
  final List<CustomShoppingItem> customItems;
  const ShoppingSection({
    this.shop,
    required this.needs,
    this.customItems = const [],
  });
}

// ---------------------------------------------------------------------------
// Custom shopping items
// ---------------------------------------------------------------------------

final customShoppingItemsProvider =
    StreamProvider<List<CustomShoppingItem>>((ref) {
  final db = ref.watch(databaseProvider);
  if (db == null) return const Stream.empty();
  return db.watchCustomShoppingItems();
});

// Tracks temporarily snoozed need IDs (item.id or group.id). Resets on restart.
final snoozedShoppingNeedsProvider =
    StateProvider<Set<String>>((ref) => const {});

// Watches all item states so shoppingNeedsProvider reacts to inventory changes.
final _allItemStatesProvider = StreamProvider<List<ItemState>>((ref) {
  final db = ref.watch(databaseProvider);
  if (db == null) return const Stream.empty();
  return db.watchAllItemStates();
});

final shoppingByShopProvider = FutureProvider<List<ShoppingSection>>((ref) async {
  final snoozed = ref.watch(snoozedShoppingNeedsProvider);
  final allNeeds = await ref.watch(shoppingNeedsProvider.future);
  final needs = allNeeds
      .where((n) => !snoozed.contains(n.group?.id ?? n.item?.id))
      .toList();
  final customItems = ref.watch(customShoppingItemsProvider).valueOrNull ?? [];
  final db = ref.watch(databaseProvider);
  if (db == null) return [];

  final shops = await db.watchAllShops().first;
  final shopMap = {for (final s in shops) s.id: s};

  // Group needs by shopId (null = no shop)
  final groupedNeeds = <String?, List<ShoppingNeed>>{};
  for (final need in needs) {
    groupedNeeds.putIfAbsent(need.shopId, () => []).add(need);
  }

  // Group custom items by shopId
  final groupedCustom = <String?, List<CustomShoppingItem>>{};
  for (final item in customItems) {
    groupedCustom.putIfAbsent(item.shopId, () => []).add(item);
  }

  // Collect all shop IDs that appear in either collection
  final allShopIds = <String?>{
    ...groupedNeeds.keys,
    ...groupedCustom.keys,
  };

  // Build sections: named shops first (sorted by name), then null
  final sections = <ShoppingSection>[];
  final namedShopIds = allShopIds
      .where((k) => k != null)
      .cast<String>()
      .toList()
    ..sort((a, b) {
      final sa = shopMap[a]?.name ?? '';
      final sb = shopMap[b]?.name ?? '';
      return sa.compareTo(sb);
    });

  for (final id in namedShopIds) {
    sections.add(ShoppingSection(
      shop: shopMap[id],
      needs: groupedNeeds[id] ?? [],
      customItems: groupedCustom[id] ?? [],
    ));
  }
  if (allShopIds.contains(null)) {
    sections.add(ShoppingSection(
      shop: null,
      needs: groupedNeeds[null] ?? [],
      customItems: groupedCustom[null] ?? [],
    ));
  }
  return sections;
});

// ---------------------------------------------------------------------------
// All groups stream
// ---------------------------------------------------------------------------

final allGroupsProvider = StreamProvider<List<ItemGroup>>((ref) {
  final db = ref.watch(databaseProvider);
  if (db == null) return const Stream.empty();
  return db.watchAllGroups();
});

// ---------------------------------------------------------------------------
// Shopping needs (async computed from groups + item states)
// ---------------------------------------------------------------------------

final shoppingNeedsProvider = FutureProvider<List<ShoppingNeed>>((ref) async {
  // React to inventory changes so the list updates without manual refresh.
  ref.watch(_allItemStatesProvider);
  final db = ref.watch(databaseProvider);
  if (db == null) return [];

  final globalConvs = await db.watchConversionsGlobal().first;
  final needs = <ShoppingNeed>[];

  // ── Group-based needs ────────────────────────────────────────────────────
  final groups = await db.groupsWithMinStock();
  // Collect all item IDs that belong to at least one group with min-stock,
  // so we skip those items in the per-item pass.
  final itemsInGroups = <String>{};

  for (final group in groups) {
    final members = await db.membersForGroup(group.id);
    if (members.isEmpty) continue;
    for (final m in members) {
      itemsInGroups.add(m.itemId);
    }

    final groupConvs = await db.watchConversionsForGroup(group.id).first;
    final baseConvs = [...groupConvs, ...globalConvs];
    final targetUnit = group.minStockUnit;

    double total = 0;
    for (final member in members) {
      final itemConvs = await db.watchConversionsForItem(member.itemId).first;
      final allConvs = [...itemConvs, ...baseConvs];
      final states = await db.statesForItem(member.itemId);
      for (final s in states) {
        if (targetUnit == null || s.unit == targetUnit) {
          total += s.currentQuantity;
        } else {
          final conv = allConvs
              .where((c) => c.fromUnit == s.unit && c.toUnit == targetUnit)
              .firstOrNull;
          total += conv != null
              ? s.currentQuantity * conv.factor
              : s.currentQuantity;
        }
      }
    }

    final minQty = group.minStockQuantity!;
    if (total < minQty) {
      needs.add(ShoppingNeed(
        group: group,
        currentQty: total,
        neededQty: minQty - total,
      ));
    }
  }

  // ── Per-item needs (only items NOT in any min-stock group) ───────────────
  final allItems = await db.watchAllItems().first;
  for (final item in allItems) {
    if (item.minStockQuantity == null) continue;
    if (itemsInGroups.contains(item.id)) continue;

    final minQty = item.minStockQuantity!;
    final targetUnit = item.minStockUnit;

    final itemConvs = await db.watchConversionsForItem(item.id).first;
    final allConvs = [...itemConvs, ...globalConvs];
    final states = await db.statesForItem(item.id);

    double total = 0;
    for (final s in states) {
      if (targetUnit == null || s.unit == targetUnit) {
        total += s.currentQuantity;
      } else {
        final conv = allConvs
            .where((c) => c.fromUnit == s.unit && c.toUnit == targetUnit)
            .firstOrNull;
        total += conv != null
            ? s.currentQuantity * conv.factor
            : s.currentQuantity;
      }
    }

    if (total < minQty) {
      needs.add(ShoppingNeed(
        item: item,
        currentQty: total,
        neededQty: minQty - total,
      ));
    }
  }

  return needs;
});

// ---------------------------------------------------------------------------
// Groups CRUD
// ---------------------------------------------------------------------------

final groupsNotifierProvider =
    AsyncNotifierProvider<GroupsNotifier, void>(GroupsNotifier.new);

class GroupsNotifier extends AsyncNotifier<void> {
  static const _uuid = Uuid();

  @override
  Future<void> build() async {}

  AppDatabase get _db => ref.read(databaseProvider)!;

  Future<String> create({
    required String name,
    String categoryId = ItemCategory.food,
    double? minStockQuantity,
    String? minStockUnit,
    String? notes,
  }) async {
    final id = _uuid.v4();
    await _db.insertItemGroup(ItemGroupsCompanion.insert(
      id: id,
      name: name,
      categoryId: categoryId,
      minStockQuantity: Value(minStockQuantity),
      minStockUnit: Value(minStockUnit),
      notes: Value(notes),
    ));
    return id;
  }

  Future<void> save({
    required String id,
    required String name,
    String categoryId = ItemCategory.food,
    double? minStockQuantity,
    String? minStockUnit,
    String? notes,
  }) async {
    await _db.updateItemGroup(ItemGroupsCompanion(
      id: Value(id),
      name: Value(name),
      categoryId: Value(categoryId),
      minStockQuantity: Value(minStockQuantity),
      minStockUnit: Value(minStockUnit),
      notes: Value(notes),
    ));
  }

  Future<void> delete(String id) => _db.deleteItemGroup(id);

  Future<void> addMember(String groupId, String itemId) =>
      _db.addItemToGroup(groupId, itemId);

  Future<void> removeMember(String groupId, String itemId) =>
      _db.removeItemFromGroup(groupId, itemId);
}
