import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../db/database.dart';
import '../../providers/vault_provider.dart';

const _uuid = Uuid();

// ── Exercise library ──────────────────────────────────────────────────────────

final exercisesProvider = StreamProvider<List<Exercise>>((ref) {
  final db = ref.watch(databaseProvider);
  if (db == null) return const Stream.empty();
  return db.watchAllExercises();
});

// ── Workout history ───────────────────────────────────────────────────────────

final workoutsProvider = StreamProvider<List<Workout>>((ref) {
  final db = ref.watch(databaseProvider);
  if (db == null) return const Stream.empty();
  return db.watchAllWorkouts();
});

// ── Sets for one workout ──────────────────────────────────────────────────────

final workoutSetsProvider =
    StreamProvider.family<List<WorkoutSet>, String>((ref, workoutId) {
  final db = ref.watch(databaseProvider);
  if (db == null) return const Stream.empty();
  return db.watchSetsForWorkout(workoutId);
});

// ── Active workout id ─────────────────────────────────────────────────────────

/// Null = no active workout in progress.
final activeWorkoutIdProvider = StateProvider<String?>((ref) => null);

// ── Operations ────────────────────────────────────────────────────────────────

final workoutOpsProvider =
    AsyncNotifierProvider<WorkoutOpsNotifier, void>(WorkoutOpsNotifier.new);

class WorkoutOpsNotifier extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  AppDatabase get _db => ref.read(databaseProvider)!;

  // ── Workout CRUD ────────────────────────────────────────────────────────────

  Future<String> startWorkout({String? name}) async {
    final id = _uuid.v4();
    await _db.insertWorkout(WorkoutsCompanion.insert(
      id: id,
      startedAt: DateTime.now(),
      name: Value(name),
    ));
    ref.read(activeWorkoutIdProvider.notifier).state = id;
    ref.invalidate(workoutsProvider);
    return id;
  }

  Future<void> finishWorkout(String id) async {
    final now = DateTime.now();
    final workout = await (ref.read(databaseProvider)!.select(
              ref.read(databaseProvider)!.workouts,
            )..where((w) => w.id.equals(id)))
        .getSingleOrNull();
    final started = workout?.startedAt ?? now;
    final minutes = now.difference(started).inMinutes;
    await _db.updateWorkout(WorkoutsCompanion(
      id: Value(id),
      endedAt: Value(now),
      durationMinutes: Value(minutes),
    ));
    ref.read(activeWorkoutIdProvider.notifier).state = null;
    ref.invalidate(workoutsProvider);
  }

  Future<void> deleteWorkout(String id) async {
    await _db.deleteWorkout(id);
    if (ref.read(activeWorkoutIdProvider) == id) {
      ref.read(activeWorkoutIdProvider.notifier).state = null;
    }
    ref.invalidate(workoutsProvider);
  }

  Future<void> renameWorkout(String id, String name) async {
    await _db.updateWorkout(WorkoutsCompanion(
      id: Value(id),
      name: Value(name),
    ));
    ref.invalidate(workoutsProvider);
  }

  // ── Set CRUD ────────────────────────────────────────────────────────────────

  Future<void> addSet({
    required String workoutId,
    required String exerciseId,
    required int setNumber,
    int? reps,
    double? weightKg,
    int? durationSeconds,
    double? distanceKm,
    double? rpe,
  }) async {
    await _db.insertWorkoutSet(WorkoutSetsCompanion.insert(
      id: _uuid.v4(),
      workoutId: workoutId,
      exerciseId: exerciseId,
      setNumber: setNumber,
      reps: Value(reps),
      weightKg: Value(weightKg),
      durationSeconds: Value(durationSeconds),
      distanceKm: Value(distanceKm),
      rpe: Value(rpe),
    ));
    ref.invalidate(workoutSetsProvider(workoutId));
  }

  Future<void> updateSet(WorkoutSetsCompanion entry) async {
    await _db.updateWorkoutSet(entry);
    ref.invalidate(workoutSetsProvider(entry.workoutId.value));
  }

  Future<void> deleteSet(String id, String workoutId) async {
    await _db.deleteWorkoutSet(id);
    ref.invalidate(workoutSetsProvider(workoutId));
  }

  // ── Exercise CRUD ───────────────────────────────────────────────────────────

  Future<void> addCustomExercise({
    required String name,
    required String category,
    String? equipment,
  }) async {
    await _db.insertExercise(ExercisesCompanion.insert(
      id: _uuid.v4(),
      name: name,
      category: category,
      equipment: Value(equipment),
      isCustom: const Value(true),
    ));
    ref.invalidate(exercisesProvider);
  }

  Future<void> deleteExercise(String id) async {
    await _db.deleteExercise(id);
    ref.invalidate(exercisesProvider);
  }
}
