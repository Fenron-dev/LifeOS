import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/database.dart';
import 'vault_provider.dart';

final relationsForItemProvider =
    FutureProvider.family<List<({ItemRelation relation, Item peer})>, String>(
        (ref, itemId) async {
  final db = ref.watch(databaseProvider);
  if (db == null) return [];
  return db.relationsForItem(itemId);
});

final relationsNotifierProvider =
    AsyncNotifierProvider<RelationsNotifier, void>(RelationsNotifier.new);

class RelationsNotifier extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  AppDatabase get _db => ref.read(databaseProvider)!;

  Future<void> add(String fromId, String toId, {String? notes}) async {
    await _db.addItemRelation(fromId, toId, notes: notes);
    ref.invalidate(relationsForItemProvider(fromId));
    ref.invalidate(relationsForItemProvider(toId));
  }

  Future<void> delete(String relationId,
      {required String fromId, required String toId}) async {
    await _db.deleteItemRelation(relationId);
    ref.invalidate(relationsForItemProvider(fromId));
    ref.invalidate(relationsForItemProvider(toId));
  }

  Future<void> updateNotes(
      String relationId, String? notes,
      {required String fromId, required String toId}) async {
    await _db.updateItemRelationNotes(relationId, notes);
    ref.invalidate(relationsForItemProvider(fromId));
    ref.invalidate(relationsForItemProvider(toId));
  }
}
