import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../db/database.dart';
import 'vault_provider.dart';

// ── Global conversions ─────────────────────────────────────────────────────

final globalConversionsProvider = StreamProvider<List<UnitConversion>>((ref) {
  final db = ref.watch(databaseProvider);
  if (db == null) return const Stream.empty();
  return db.watchConversionsGlobal();
});

// ── Group-level conversions ────────────────────────────────────────────────

final groupConversionsProvider =
    StreamProvider.family<List<UnitConversion>, String>((ref, groupId) {
  final db = ref.watch(databaseProvider);
  if (db == null) return const Stream.empty();
  return db.watchConversionsForGroup(groupId);
});

// ── Item-level conversions ─────────────────────────────────────────────────

final itemConversionsProvider =
    StreamProvider.family<List<UnitConversion>, String>((ref, itemId) {
  final db = ref.watch(databaseProvider);
  if (db == null) return const Stream.empty();
  return db.watchConversionsForItem(itemId);
});

// ── Notifier ───────────────────────────────────────────────────────────────

final conversionsNotifierProvider =
    AsyncNotifierProvider<ConversionsNotifier, void>(ConversionsNotifier.new);

class ConversionsNotifier extends AsyncNotifier<void> {
  static const _uuid = Uuid();

  @override
  Future<void> build() async {}

  AppDatabase get _db => ref.read(databaseProvider)!;

  Future<void> addGlobal({
    required String fromUnit,
    required String toUnit,
    required double factor,
    String? notes,
  }) =>
      _db.insertConversion(UnitConversionsCompanion.insert(
        id: _uuid.v4(),
        fromUnit: fromUnit,
        toUnit: toUnit,
        factor: factor,
        notes: Value(notes),
        // scope defaults to 'global' in table definition
      ));

  Future<void> addForGroup({
    required String groupId,
    required String fromUnit,
    required String toUnit,
    required double factor,
  }) =>
      _db.insertConversion(UnitConversionsCompanion.insert(
        id: _uuid.v4(),
        fromUnit: fromUnit,
        toUnit: toUnit,
        factor: factor,
        scope: const Value('group'),
        scopeId: Value(groupId),
      ));

  Future<void> addForItem({
    required String itemId,
    required String fromUnit,
    required String toUnit,
    required double factor,
  }) =>
      _db.insertConversion(UnitConversionsCompanion.insert(
        id: _uuid.v4(),
        fromUnit: fromUnit,
        toUnit: toUnit,
        factor: factor,
        scope: const Value('item'),
        scopeId: Value(itemId),
      ));

  Future<void> delete(String id) => _db.deleteConversion(id);
}
