import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../db/database.dart';
import '../../providers/vault_provider.dart';

const _uuid = Uuid();

/// Newest-first stream of weight logs. `limit` keeps memory bounded; the
/// chart never needs more than ~365 points.
final weightLogsProvider =
    StreamProvider.family<List<BodyWeightLog>, int>((ref, limit) {
  final db = ref.watch(databaseProvider);
  if (db == null) return const Stream.empty();
  return db.watchWeightLogs(limit: limit);
});

/// Single most-recent log — drives the "Aktuelles Gewicht"-Karte.
final latestWeightLogProvider = FutureProvider<BodyWeightLog?>((ref) async {
  // Re-fetch when any log changes so UI stays fresh.
  ref.watch(weightLogsProvider(1));
  final db = ref.watch(databaseProvider);
  return db?.latestWeightLog();
});

/// Number of distinct days within the last [days] window that have a log.
/// Used by the Erfassungsquote display ("18 von 28 Tagen erfasst").
final weightLogDayCountProvider =
    FutureProvider.family<int, int>((ref, days) async {
  ref.watch(weightLogsProvider(days + 5));
  final db = ref.watch(databaseProvider);
  if (db == null) return 0;
  final since = DateTime.now().subtract(Duration(days: days));
  return db.weightLogDaysSince(since);
});

final weightOpsProvider =
    AsyncNotifierProvider<WeightOpsNotifier, void>(WeightOpsNotifier.new);

class WeightOpsNotifier extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  AppDatabase get _db => ref.read(databaseProvider)!;

  Future<void> logWeight({
    required DateTime loggedAt,
    required double weightKg,
    double? bodyFatPct,
    double? muscleMassPct,
    double? visceralFat,
    double? waterPct,
    double? boneMassKg,
    String source = 'manual',
    String? notes,
  }) async {
    await _db.insertWeightLog(BodyWeightLogsCompanion.insert(
      id: _uuid.v4(),
      loggedAt: loggedAt,
      weightKg: weightKg,
      bodyFatPct: Value(bodyFatPct),
      muscleMassPct: Value(muscleMassPct),
      visceralFat: Value(visceralFat),
      waterPct: Value(waterPct),
      boneMassKg: Value(boneMassKg),
      source: Value(source),
      notes: Value(notes),
    ));
  }

  Future<void> updateLog(BodyWeightLogsCompanion entry) =>
      _db.updateWeightLog(entry);

  Future<void> deleteLog(String id) => _db.deleteWeightLog(id);
}
