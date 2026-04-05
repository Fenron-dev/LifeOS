import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../db/database.dart';
import 'vault_provider.dart';

final wishlistProvider = StreamProvider<List<WishListEntry>>((ref) {
  final db = ref.watch(databaseProvider);
  if (db == null) return const Stream.empty();
  return db.watchWishlist();
});

final wishlistNotifierProvider =
    AsyncNotifierProvider<WishlistNotifier, void>(WishlistNotifier.new);

class WishlistNotifier extends AsyncNotifier<void> {
  static const _uuid = Uuid();

  @override
  Future<void> build() async {}

  AppDatabase get _db => ref.read(databaseProvider)!;

  Future<void> create({
    required String title,
    String? url,
    double? price,
    String priority = 'medium',
    String? forPerson,
    String? notes,
  }) async {
    await _db.insertWishListEntry(WishListEntriesCompanion.insert(
      id: _uuid.v4(),
      title: title,
      url: Value(url),
      price: Value(price),
      priority: Value(priority),
      forPerson: Value(forPerson),
      notes: Value(notes),
    ));
  }

  Future<void> save(WishListEntry entry) async {
    await _db.updateWishListEntry(WishListEntriesCompanion(
      id: Value(entry.id),
      title: Value(entry.title),
      url: Value(entry.url),
      price: Value(entry.price),
      priority: Value(entry.priority),
      forPerson: Value(entry.forPerson),
      notes: Value(entry.notes),
      fulfilled: Value(entry.fulfilled),
    ));
  }

  Future<void> toggleFulfilled(WishListEntry entry) =>
      save(entry.copyWith(fulfilled: !entry.fulfilled));

  Future<void> delete(String id) => _db.deleteWishListEntry(id);
}
