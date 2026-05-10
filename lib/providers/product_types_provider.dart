import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/database.dart';
import 'vault_provider.dart';

final allProductTypesProvider =
    StreamProvider<List<ProductTypeDefinition>>((ref) {
  final db = ref.watch(databaseProvider);
  if (db == null) return const Stream.empty();
  return db.watchAllProductTypes();
});

final productTypesNotifierProvider =
    AsyncNotifierProvider<ProductTypesNotifier, void>(
        ProductTypesNotifier.new);

class ProductTypesNotifier extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  AppDatabase get _db => ref.read(databaseProvider)!;

  Future<void> create({
    required String id,
    required String nameDe,
    String? nameEn,
    String? iconName,
    int sortOrder = 99,
  }) =>
      _db.upsertProductTypeDefinition(
        ProductTypeDefinitionsCompanion.insert(
          id: id,
          nameDe: nameDe,
          nameEn: Value(nameEn),
          iconName: Value(iconName),
          sortOrder: Value(sortOrder),
        ),
      );

  Future<void> save({
    required String id,
    required String nameDe,
    String? nameEn,
    String? iconName,
    int sortOrder = 99,
  }) =>
      _db.upsertProductTypeDefinition(
        ProductTypeDefinitionsCompanion(
          id: Value(id),
          nameDe: Value(nameDe),
          nameEn: Value(nameEn),
          iconName: Value(iconName),
          sortOrder: Value(sortOrder),
        ),
      );

  Future<void> delete(String id) =>
      _db.deleteProductTypeDefinition(id);
}
