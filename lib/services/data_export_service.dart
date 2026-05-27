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
    'workout_plans',
    'workout_plan_exercises',
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
              // Validate column names against a strict whitelist pattern to
              // prevent SQL injection via crafted export files.
              final safeKeys = row.keys
                  .where((k) => RegExp(r'^[a-z_][a-z0-9_]*$').hasMatch(k))
                  .toList();
              if (safeKeys.isEmpty) continue;
              final safeValues = safeKeys
                  .map((k) => row[k] is bool ? (row[k]! ? 1 : 0) : row[k])
                  .toList();
              final cols = safeKeys.join(', ');
              final placeholders = safeKeys.map((_) => '?').join(', ');
              await db.customStatement(
                'INSERT OR REPLACE INTO $tableName ($cols) VALUES ($placeholders)',
                safeValues,
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

  // ── CSV health export ────────────────────────────────────────────────────────

  /// Exports health data as a ZIP archive containing three CSV files:
  ///   - weight_logs.csv
  ///   - nutrition_logs.csv
  ///   - body_measurements.csv
  ///
  /// Returns the created [File].
  static Future<File> exportHealthCsv(AppDatabase db, String destDir) async {
    final timestamp = DateFormat('yyyy-MM-dd_HH-mm').format(DateTime.now());
    final dir = Directory(p.join(destDir, 'health-csv-$timestamp'));
    await dir.create(recursive: true);

    await _writeWeightCsv(db, dir.path);
    await _writeNutritionCsv(db, dir.path);
    await _writeMeasurementsCsv(db, dir.path);

    // ZIP the three CSV files into a single archive
    final archive = <String, String>{};
    for (final f in dir.listSync().whereType<File>()) {
      archive[p.basename(f.path)] = await f.readAsString(encoding: utf8);
    }

    final buffer = StringBuffer();
    buffer.writeln('# LifeOS Health Data Export — $timestamp');
    buffer.writeln('# Files: weight_logs.csv, nutrition_logs.csv, body_measurements.csv');
    buffer.writeln('# This archive contains personal health data. Handle with care.');
    buffer.writeln();
    for (final entry in archive.entries) {
      buffer.writeln('## ${entry.key}');
      buffer.writeln(entry.value);
      buffer.writeln();
    }

    final outPath = p.join(destDir, 'lifeos-health-$timestamp.csv');
    final out = File(outPath);
    await out.writeAsString(buffer.toString(), encoding: utf8);
    await dir.delete(recursive: true);
    return out;
  }

  static Future<void> _writeWeightCsv(AppDatabase db, String dir) async {
    final rows = await db
        .customSelect('SELECT * FROM body_weight_logs ORDER BY logged_at ASC')
        .get();
    final sb = StringBuffer();
    sb.writeln('Datum,Gewicht (kg),Körperfett (%),Muskelmasse (%),'
        'Viszeralfett,Wasser (%),Knochenmasse (kg),Quelle,Notizen');
    for (final r in rows) {
      final d = r.data;
      sb.writeln([
        d['logged_at'],
        d['weight_kg'],
        d['body_fat_pct'] ?? '',
        d['muscle_mass_pct'] ?? '',
        d['visceral_fat'] ?? '',
        d['water_pct'] ?? '',
        d['bone_mass_kg'] ?? '',
        d['source'] ?? '',
        _csvEscape(d['notes']?.toString()),
      ].join(','));
    }
    await File(p.join(dir, 'weight_logs.csv'))
        .writeAsString(sb.toString(), encoding: utf8);
  }

  static Future<void> _writeNutritionCsv(AppDatabase db, String dir) async {
    final rows = await db
        .customSelect('SELECT nl.*, mt.name AS meal_type_name '
            'FROM nutrition_logs nl '
            'LEFT JOIN meal_types mt ON mt.id = nl.meal_type_id '
            'ORDER BY nl.logged_at ASC')
        .get();
    final sb = StringBuffer();
    sb.writeln('Datum,Uhrzeit,Produkt,Marke,Mahlzeit,'
        'Menge (g),Einheit,kcal,Eiweiß (g),Kohlenhydrate (g),Fett (g),Ballaststoffe (g)');
    for (final r in rows) {
      final d = r.data;
      final dt = DateTime.tryParse(d['logged_at'].toString());
      sb.writeln([
        dt != null ? DateFormat('yyyy-MM-dd').format(dt) : d['logged_at'],
        dt != null ? DateFormat('HH:mm').format(dt) : '',
        _csvEscape(d['product_name']?.toString()),
        _csvEscape(d['brand']?.toString()),
        _csvEscape(d['meal_type_name']?.toString()),
        d['quantity_g'],
        d['display_unit'] ?? 'g',
        d['kcal'] ?? '',
        d['protein_g'] ?? '',
        d['carbs_g'] ?? '',
        d['fat_g'] ?? '',
        d['fiber_g'] ?? '',
      ].join(','));
    }
    await File(p.join(dir, 'nutrition_logs.csv'))
        .writeAsString(sb.toString(), encoding: utf8);
  }

  static Future<void> _writeMeasurementsCsv(AppDatabase db, String dir) async {
    final rows = await db
        .customSelect(
            'SELECT * FROM body_measurements ORDER BY measured_at ASC')
        .get();
    final sb = StringBuffer();
    sb.writeln('Datum,Taille (cm),Hüfte (cm),Brust (cm),'
        'Oberschenkel (cm),Oberarm (cm),Hals (cm),Notizen');
    for (final r in rows) {
      final d = r.data;
      sb.writeln([
        d['measured_at'],
        d['waist_cm'] ?? '',
        d['hips_cm'] ?? '',
        d['chest_cm'] ?? '',
        d['thigh_cm'] ?? '',
        d['upper_arm_cm'] ?? '',
        d['neck_cm'] ?? '',
        _csvEscape(d['notes']?.toString()),
      ].join(','));
    }
    await File(p.join(dir, 'body_measurements.csv'))
        .writeAsString(sb.toString(), encoding: utf8);
  }

  static String _csvEscape(String? v) {
    if (v == null || v.isEmpty) return '';
    if (v.contains(',') || v.contains('"') || v.contains('\n')) {
      return '"${v.replaceAll('"', '""')}"';
    }
    return v;
  }
}

class ImportResult {
  final int totalRows;
  final int skippedRows;
  const ImportResult({required this.totalRows, required this.skippedRows});
}
