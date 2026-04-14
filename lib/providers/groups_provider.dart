import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../core/item_categories.dart';
import '../db/database.dart';
import 'vault_provider.dart';

// ---------------------------------------------------------------------------
// Shopping need (computed: group below min stock)
// ---------------------------------------------------------------------------

class ShoppingNeed {
  final ItemGroup group;
  final double currentQty;
  final double neededQty;

  const ShoppingNeed({
    required this.group,
    required this.currentQty,
    required this.neededQty,
  });
}

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
  final db = ref.watch(databaseProvider);
  if (db == null) return [];

  final groups = await db.groupsWithMinStock();
  // Load all conversions once
  final globalConvs = await db.watchConversionsGlobal().first;
  final needs = <ShoppingNeed>[];

  for (final group in groups) {
    final members = await db.membersForGroup(group.id);
    if (members.isEmpty) continue;

    final groupConvs = await db.watchConversionsForGroup(group.id).first;
    // group overrides global
    final baseConvs = [...groupConvs, ...globalConvs];
    final targetUnit = group.minStockUnit;

    double total = 0;
    for (final member in members) {
      final itemConvs = await db.watchConversionsForItem(member.itemId).first;
      // item-level overrides group/global
      final allConvs = [...itemConvs, ...baseConvs];
      final states = await db.statesForItem(member.itemId);
      for (final s in states) {
        if (targetUnit == null || s.unit == targetUnit) {
          total += s.currentQuantity;
        } else {
          // Try to convert s.unit → targetUnit
          final conv = allConvs
              .where((c) => c.fromUnit == s.unit && c.toUnit == targetUnit)
              .firstOrNull;
          total += conv != null
              ? s.currentQuantity * conv.factor
              : s.currentQuantity; // fallback: add raw
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
