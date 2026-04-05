import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../db/database.dart';
import 'vault_provider.dart';

final allLocationsProvider = StreamProvider<List<Location>>((ref) {
  final db = ref.watch(databaseProvider);
  if (db == null) return const Stream.empty();
  return db.watchAllLocations();
});

final locationsNotifierProvider =
    AsyncNotifierProvider<LocationsNotifier, void>(LocationsNotifier.new);

class LocationsNotifier extends AsyncNotifier<void> {
  static const _uuid = Uuid();

  @override
  Future<void> build() async {}

  AppDatabase get _db => ref.read(databaseProvider)!;

  Future<String> createLocation({
    required String name,
    String? parentId,
    String? notes,
  }) async {
    final id = _uuid.v4();
    await _db.insertLocation(LocationsCompanion.insert(
      id: id,
      name: name,
      parentId: Value(parentId),
      notes: Value(notes),
    ));
    return id;
  }

  Future<void> updateLocation({
    required String id,
    required String name,
    String? parentId,
    String? notes,
  }) async {
    await _db.updateLocation(LocationsCompanion(
      id: Value(id),
      name: Value(name),
      parentId: Value(parentId),
      notes: Value(notes),
    ));
  }

  Future<void> deleteLocation(String id) => _db.deleteLocation(id);
}
