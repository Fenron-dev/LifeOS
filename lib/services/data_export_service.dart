import 'dart:convert';
import 'dart:io';

import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;

import '../db/database.dart';

/// Vault-agnostic JSON export / import of all user data tables.
///
/// Does NOT include:
///   - photos (binary files stored outside the database)
///   - vault-path settings
///
/// Tables are exported in FK-dependency order so that an import into a
/// fresh vault can simply run them top to bottom without FK violations.
class DataExportService {
  // Ordered by dependency (parents first).
  static const _exportTables = [
    'locations',
    'units',
    'unit_conversions',
    'tag_definitions',
    'category_definitions',
    'product_type_definitions',
    'item_templates',
    'template_fields',
    'items',
    'inventory_entries',
    'item_events',
    'item_states',
    'item_tags',
    'item_relations',
    'item_property_values',
    'item_groups',
    'item_group_members',
    'custom_shopping_items',
    'shops',
    'recipes',
    'recipe_ingredients',
    'recipe_steps',
    'recipe_tags',
    'meal_types',
    'prepared_dishes',
    'meal_relations',
    'meal_plan_entries',
    'tasks',
    'user_profile',
    'body_weight_logs',
    'body_measurements',
    'nutrition_logs',
    'water_logs',
    'exercises',
    'workouts',
    'workout_sets',
    // entity_photos: keeps metadata but photos aren't copied
    'entity_photos',
  ];

  /// Exports all user data to a JSON file in [destDir].
  /// Returns the created [File].
  static Future<File> exportData(AppDatabase db, String destDir) async {
    final timestamp = DateFormat('yyyy-MM-dd_HH-mm').format(DateTime.now());
    final outPath = p.join(destDir, 'lifeos-data-$timestamp.json');

    final exportedTables = <String, List<Map<String, Object?>>>{};

    for (final table in _exportTables) {
      try {
        final rows = await db.customSelect('SELECT * FROM $table').get();
        exportedTables[table] = rows.map((r) => r.data).toList();
      } catch (_) {
        // Table may not exist in older schema versions – skip silently.
      }
    }

    final json = JsonEncoder.withIndent('  ').convert({
      'version': 1,
      'exportedAt': DateTime.now().toIso8601String(),
      'tables': exportedTables,
    });

    final file = File(outPath);
    await file.writeAsString(json, encoding: utf8);
    return file;
  }

  /// Imports data from a previously exported JSON file.
  ///
  /// Uses INSERT OR REPLACE (upsert) so existing rows are overwritten and
  /// new rows are added. Rows in the current database that are NOT in the
  /// import file are kept untouched.
  static Future<ImportResult> importData(
      AppDatabase db, String jsonPath) async {
    final raw = await File(jsonPath).readAsString(encoding: utf8);
    final json = jsonDecode(raw) as Map<String, dynamic>;

    final version = json['version'] as int? ?? 0;
    if (version > 1) {
      throw FormatException(
          'Unbekannte Export-Version $version – bitte LifeOS aktualisieren.');
    }

    final tables = (json['tables'] as Map<String, dynamic>?) ?? {};
    int totalRows = 0;
    int skippedTables = 0;

    await db.customStatement('PRAGMA foreign_keys = OFF');
    try {
      await db.transaction(() async {
        for (final tableName in _exportTables) {
          final rows = tables[tableName];
          if (rows == null) continue;
          final rowList = (rows as List).cast<Map<String, dynamic>>();
          if (rowList.isEmpty) continue;

          for (final row in rowList) {
            try {
              final cols = row.keys.join(', ');
              final placeholders = row.keys.map((_) => '?').join(', ');
              final values = row.values
                  .map((v) => v is bool ? (v ? 1 : 0) : v)
                  .toList();
              await db.customStatement(
                'INSERT OR REPLACE INTO $tableName ($cols) VALUES ($placeholders)',
                values,
              );
              totalRows++;
            } catch (_) {
              skippedTables++;
            }
          }
        }
      });
    } finally {
      await db.customStatement('PRAGMA foreign_keys = ON');
    }

    return ImportResult(totalRows: totalRows, skippedRows: skippedTables);
  }
}

class ImportResult {
  final int totalRows;
  final int skippedRows;
  const ImportResult({required this.totalRows, required this.skippedRows});
}
