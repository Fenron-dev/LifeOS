import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../db/database.dart';
import '../../providers/vault_provider.dart';

const _uuid = Uuid();

/// Stream of all water-log entries for the given calendar [day].
final waterLogsForDayProvider =
    StreamProvider.family<List<WaterLog>, DateTime>((ref, day) {
  final db = ref.watch(databaseProvider);
  if (db == null) return const Stream.empty();
  return db.watchWaterLogsForDay(day);
});

/// Sum of water intake in ml for [day] — re-fetched whenever the log changes.
final dailyWaterTotalProvider =
    Provider.family<int, DateTime>((ref, day) {
  final logs = ref.watch(waterLogsForDayProvider(day)).valueOrNull ?? [];
  return logs.fold(0, (sum, l) => sum + l.amountMl);
});

final waterOpsProvider =
    AsyncNotifierProvider<WaterOpsNotifier, void>(WaterOpsNotifier.new);

class WaterOpsNotifier extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  AppDatabase get _db => ref.read(databaseProvider)!;

  Future<void> addWater(DateTime day, int amountMl) async {
    await _db.insertWaterLog(WaterLogsCompanion.insert(
      id: _uuid.v4(),
      loggedAt: day,
      amountMl: amountMl,
    ));
  }

  Future<void> deleteLog(String id) async {
    await _db.deleteWaterLog(id);
  }
}
