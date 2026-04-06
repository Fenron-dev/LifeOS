import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../db/database.dart';
import 'vault_provider.dart';

/// All units, ordered by sortOrder.
final allUnitsProvider = StreamProvider<List<Unit>>((ref) {
  final db = ref.watch(databaseProvider);
  if (db == null) return const Stream.empty();
  return db.watchAllUnits();
});

/// Just the unit names as a sorted list — used everywhere units are selected.
final unitNamesProvider = Provider<List<String>>((ref) {
  return ref.watch(allUnitsProvider).valueOrNull?.map((u) => u.name).toList() ??
      ['g', 'kg', 'ml', 'l', 'Stück', 'Packung', 'Dose', 'Flasche', 'Tüte'];
});

final unitsNotifierProvider =
    AsyncNotifierProvider<UnitsNotifier, void>(UnitsNotifier.new);

class UnitsNotifier extends AsyncNotifier<void> {
  static const _uuid = Uuid();

  @override
  Future<void> build() async {}

  AppDatabase get _db => ref.read(databaseProvider)!;

  Future<void> create(String name, {String? plural, String? abbreviation}) async {
    final all = await _db.allUnitsList();
    final maxOrder =
        all.isEmpty ? 0 : all.map((u) => u.sortOrder).reduce((a, b) => a > b ? a : b);
    await _db.insertUnit(UnitsCompanion.insert(
      id: _uuid.v4(),
      name: name,
      plural: Value(plural),
      abbreviation: Value(abbreviation),
      sortOrder: Value(maxOrder + 1),
    ));
  }

  Future<void> save(Unit unit) async {
    await _db.updateUnit(UnitsCompanion(
      id: Value(unit.id),
      name: Value(unit.name),
      abbreviation: Value(unit.abbreviation),
      sortOrder: Value(unit.sortOrder),
    ));
  }

  Future<void> delete(String id) => _db.deleteUnit(id);
}
