import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:drift/drift.dart' show Value;

import '../db/database.dart';
import 'vault_provider.dart';

/// Live stream of all user-defined categories, sorted by sortOrder then name.
final categoryDefinitionsProvider =
    StreamProvider<List<CategoryDefinition>>((ref) {
  final db = ref.watch(databaseProvider);
  if (db == null) return const Stream.empty();
  return db.watchAllCategories();
});

final categoryOpsProvider =
    AsyncNotifierProvider<CategoryOpsNotifier, void>(CategoryOpsNotifier.new);

class CategoryOpsNotifier extends AsyncNotifier<void> {
  static const _uuid = Uuid();

  @override
  Future<void> build() async {}

  AppDatabase get _db => ref.read(databaseProvider)!;

  Future<void> addCategory({
    required String name,
    String? iconName,
    int sortOrder = 0,
  }) async {
    await _db.insertCategory(CategoryDefinitionsCompanion.insert(
      id: _uuid.v4(),
      name: name,
      iconName: Value(iconName),
      sortOrder: Value(sortOrder),
    ));
    ref.invalidate(categoryDefinitionsProvider);
  }

  Future<void> updateCategory({
    required String id,
    required String name,
    String? iconName,
    int sortOrder = 0,
  }) async {
    await _db.updateCategory(CategoryDefinitionsCompanion(
      id: Value(id),
      name: Value(name),
      iconName: Value(iconName),
      sortOrder: Value(sortOrder),
    ));
    ref.invalidate(categoryDefinitionsProvider);
  }

  Future<void> deleteCategory(String id) async {
    await _db.deleteCategory(id);
    ref.invalidate(categoryDefinitionsProvider);
  }
}
