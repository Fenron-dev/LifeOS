import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../db/database.dart';
import '../../providers/vault_provider.dart';

const _uuid = Uuid();

/// Newest-first stream of body measurement logs. Bounded by [limit].
final bodyMeasurementsProvider =
    StreamProvider.family<List<BodyMeasurement>, int>((ref, limit) {
  final db = ref.watch(databaseProvider);
  if (db == null) return const Stream.empty();
  return db.watchBodyMeasurements(limit: limit);
});

/// Most-recent measurement row — drives the summary card.
final latestBodyMeasurementProvider =
    FutureProvider<BodyMeasurement?>((ref) async {
  ref.watch(bodyMeasurementsProvider(1));
  final db = ref.watch(databaseProvider);
  return db?.latestBodyMeasurement();
});

final measurementsOpsProvider =
    AsyncNotifierProvider<MeasurementsOpsNotifier, void>(
        MeasurementsOpsNotifier.new);

class MeasurementsOpsNotifier extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  AppDatabase get _db => ref.read(databaseProvider)!;

  Future<void> logMeasurement({
    required DateTime loggedAt,
    double? chestCm,
    double? waistCm,
    double? hipCm,
    double? thighCm,
    double? armCm,
    double? neckCm,
    String? notes,
  }) async {
    await _db.insertBodyMeasurement(BodyMeasurementsCompanion.insert(
      id: _uuid.v4(),
      loggedAt: loggedAt,
      chestCm: Value(chestCm),
      waistCm: Value(waistCm),
      hipCm: Value(hipCm),
      thighCm: Value(thighCm),
      armCm: Value(armCm),
      neckCm: Value(neckCm),
      notes: Value(notes),
    ));
  }

  Future<void> deleteLog(String id) => _db.deleteBodyMeasurement(id);
}
