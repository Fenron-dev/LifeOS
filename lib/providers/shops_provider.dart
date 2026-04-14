import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../db/database.dart';
import 'vault_provider.dart';

final allShopsProvider = StreamProvider<List<Shop>>((ref) {
  final db = ref.watch(databaseProvider);
  if (db == null) return const Stream.empty();
  return db.watchAllShops();
});

final shopsNotifierProvider =
    AsyncNotifierProvider<ShopsNotifier, void>(ShopsNotifier.new);

class ShopsNotifier extends AsyncNotifier<void> {
  static const _uuid = Uuid();

  @override
  Future<void> build() async {}

  AppDatabase get _db => ref.read(databaseProvider)!;

  Future<String> create(String name, {String? notes}) async {
    final id = _uuid.v4();
    await _db.insertShop(ShopsCompanion.insert(
      id: id,
      name: name,
      notes: Value(notes),
    ));
    return id;
  }

  Future<void> save(Shop shop) async {
    await _db.updateShop(ShopsCompanion(
      id: Value(shop.id),
      name: Value(shop.name),
      notes: Value(shop.notes),
    ));
  }

  Future<void> delete(String id) => _db.deleteShop(id);
}
