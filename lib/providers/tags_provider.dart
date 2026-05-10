import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/database.dart';
import 'vault_provider.dart';

final tagsForItemProvider =
    StreamProvider.family<List<TagDefinition>, String>((ref, itemId) {
  final db = ref.watch(databaseProvider);
  if (db == null) return const Stream.empty();
  return db.watchTagsForItem(itemId);
});

final tagDefinitionsForCategoryProvider =
    StreamProvider.family<List<TagDefinition>, String>((ref, categoryId) {
  final db = ref.watch(databaseProvider);
  if (db == null) return const Stream.empty();
  return db.watchTagDefinitionsForCategory(categoryId);
});

final tagsNotifierProvider =
    AsyncNotifierProvider<TagsNotifier, void>(TagsNotifier.new);

class TagsNotifier extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  AppDatabase get _db => ref.read(databaseProvider)!;

  Future<void> setTagsForItem(
          String itemId, String categoryId, List<String> tagNames) =>
      _db.setTagsForItem(itemId, categoryId, tagNames);

  Future<void> addTagToItem(
      String itemId, String categoryId, String tagName) async {
    final current = await _db.watchTagsForItem(itemId).first;
    final names = current.map((t) => t.name).toList()..add(tagName);
    await _db.setTagsForItem(itemId, categoryId, names);
  }

  Future<void> removeTagFromItem(
      String itemId, String categoryId, String tagName) async {
    final current = await _db.watchTagsForItem(itemId).first;
    final names =
        current.map((t) => t.name).where((n) => n != tagName).toList();
    await _db.setTagsForItem(itemId, categoryId, names);
  }
}
