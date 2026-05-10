import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../db/database.dart';
import 'vault_provider.dart';

// All templates stream
final allTemplatesProvider = StreamProvider<List<ItemTemplate>>((ref) {
  final db = ref.watch(databaseProvider);
  if (db == null) return const Stream.empty();
  return db.watchAllTemplates();
});

// Fields for a specific template
final templateFieldsProvider =
    StreamProvider.family<List<TemplateField>, String>((ref, templateId) {
  final db = ref.watch(databaseProvider);
  if (db == null) return const Stream.empty();
  return db.watchFieldsForTemplate(templateId);
});

// Properties for a specific item
final itemPropertiesProvider =
    StreamProvider.family<List<ItemPropertyValue>, String>((ref, itemId) {
  final db = ref.watch(databaseProvider);
  if (db == null) return const Stream.empty();
  return db.watchPropertiesForItem(itemId);
});

final templatesNotifierProvider =
    AsyncNotifierProvider<TemplatesNotifier, void>(TemplatesNotifier.new);

class TemplatesNotifier extends AsyncNotifier<void> {
  static const _uuid = Uuid();

  @override
  Future<void> build() async {}

  AppDatabase get _db => ref.read(databaseProvider)!;

  Future<String> createTemplate({
    required String name,
    String? description,
    String? categoryId,
  }) async {
    final id = _uuid.v4();
    await _db.insertTemplate(ItemTemplatesCompanion.insert(
      id: id,
      name: name,
      description: Value(description),
      categoryId: Value(categoryId),
    ));
    return id;
  }

  Future<void> updateTemplate({
    required String id,
    required String name,
    String? description,
    String? categoryId,
  }) =>
      _db.updateTemplate(ItemTemplatesCompanion(
        id: Value(id),
        name: Value(name),
        description: Value(description),
        categoryId: Value(categoryId),
      ));

  Future<void> deleteTemplate(String id) => _db.deleteTemplate(id);

  Future<String> addField({
    required String templateId,
    required String fieldName,
    required String fieldType,
    bool required = false,
    String? defaultValue,
    int sortOrder = 0,
  }) async {
    final id = _uuid.v4();
    await _db.upsertTemplateField(TemplateFieldsCompanion.insert(
      id: id,
      templateId: templateId,
      fieldName: fieldName,
      fieldType: fieldType,
      required: Value(required),
      defaultValue: Value(defaultValue),
      sortOrder: Value(sortOrder),
    ));
    return id;
  }

  Future<void> updateField({
    required String id,
    required String templateId,
    required String fieldName,
    required String fieldType,
    bool required = false,
    String? defaultValue,
    int sortOrder = 0,
  }) =>
      _db.upsertTemplateField(TemplateFieldsCompanion(
        id: Value(id),
        templateId: Value(templateId),
        fieldName: Value(fieldName),
        fieldType: Value(fieldType),
        required: Value(required),
        defaultValue: Value(defaultValue),
        sortOrder: Value(sortOrder),
      ));

  Future<void> deleteField(String id) => _db.deleteTemplateField(id);

  Future<void> reorderFields(List<({String id, int sortOrder})> updates) =>
      _db.reorderTemplateFields(updates);
}

final propertiesNotifierProvider =
    AsyncNotifierProvider<PropertiesNotifier, void>(PropertiesNotifier.new);

class PropertiesNotifier extends AsyncNotifier<void> {
  static const _uuid = Uuid();

  @override
  Future<void> build() async {}

  AppDatabase get _db => ref.read(databaseProvider)!;

  Future<void> upsert({
    required String itemId,
    required String fieldKey,
    required String fieldType,
    required String value,
    String? existingId,
  }) =>
      _db.upsertProperty(ItemPropertyValuesCompanion.insert(
        id: existingId ?? _uuid.v4(),
        itemId: itemId,
        fieldKey: fieldKey,
        fieldType: fieldType,
        value: value,
      ));

  Future<void> delete(String id) => _db.deleteProperty(id);

  Future<void> deleteAll(String itemId) => _db.deletePropertiesForItem(itemId);
}
