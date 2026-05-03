import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../db/database.dart';
import '../providers/workouts_provider.dart';

// ── Category labels ───────────────────────────────────────────────────────────

String _catLabel(String cat) => switch (cat) {
      'chest' => 'Brust',
      'back' => 'Rücken',
      'legs' => 'Beine',
      'shoulders' => 'Schultern',
      'arms' => 'Arme',
      'core' => 'Core',
      'cardio' => 'Kardio',
      _ => cat,
    };

String _equipLabel(String? eq) => switch (eq) {
      'barbell' => 'Langhantel',
      'dumbbell' => 'Kurzhantel',
      'machine' => 'Maschine',
      'bodyweight' => 'Körpergewicht',
      'cable' => 'Kabel',
      null => '–',
      _ => eq,
    };

const _categories = [
  'chest', 'back', 'legs', 'shoulders', 'arms', 'core', 'cardio',
];

// ── Tab root ──────────────────────────────────────────────────────────────────

class WorkoutsTab extends ConsumerWidget {
  const WorkoutsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workoutsAsync = ref.watch(workoutsProvider);
    final activeId = ref.watch(activeWorkoutIdProvider);

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Workouts'),
        actions: [
          IconButton(
            icon: const Icon(Icons.fitness_center_outlined),
            tooltip: 'Übungsbibliothek',
            onPressed: () => _openLibrary(context),
          ),
        ],
      ),
      body: workoutsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Fehler: $e')),
        data: (workouts) {
          if (workouts.isEmpty && activeId == null) {
            return _EmptyState(onStart: () => _startWorkout(context, ref));
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            itemCount: workouts.length,
            itemBuilder: (context, i) =>
                _WorkoutCard(workout: workouts[i]),
          );
        },
      ),
      floatingActionButton: activeId != null
          ? FloatingActionButton.extended(
              onPressed: () => _openActive(context, activeId),
              icon: const Icon(Icons.sports_gymnastics),
              label: const Text('Aktives Training'),
              backgroundColor: Theme.of(context).colorScheme.tertiary,
            )
          : FloatingActionButton.extended(
              onPressed: () => _startWorkout(context, ref),
              icon: const Icon(Icons.add),
              label: const Text('Neues Training'),
            ),
    );
  }

  Future<void> _startWorkout(BuildContext context, WidgetRef ref) async {
    final nameCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Training starten'),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Name (optional)',
            hintText: 'z.B. Push Day, Oberkörper…',
            border: OutlineInputBorder(),
          ),
          textCapitalization: TextCapitalization.sentences,
          onSubmitted: (_) => Navigator.of(ctx).pop(true),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Abbrechen')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Starten')),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final name = nameCtrl.text.trim().isEmpty ? null : nameCtrl.text.trim();
    final id =
        await ref.read(workoutOpsProvider.notifier).startWorkout(name: name);
    if (context.mounted) _openActive(context, id);
  }

  void _openActive(BuildContext context, String workoutId) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ActiveWorkoutScreen(workoutId: workoutId),
      ),
    );
  }

  void _openLibrary(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const ExerciseLibraryScreen(),
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final VoidCallback onStart;
  const _EmptyState({required this.onStart});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.fitness_center,
                size: 64, color: cs.onSurfaceVariant.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            Text('Noch keine Trainingseinheiten',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Starte dein erstes Training und\nerfasse deine Sätze und Gewichte.',
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onStart,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Training starten'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Workout history card ──────────────────────────────────────────────────────

class _WorkoutCard extends ConsumerWidget {
  final Workout workout;
  const _WorkoutCard({required this.workout});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final sets = ref.watch(workoutSetsProvider(workout.id)).valueOrNull ?? [];
    final fmt = DateFormat.yMMMd('de_DE').add_Hm();
    final isActive = ref.watch(activeWorkoutIdProvider) == workout.id;

    // Group sets by exerciseId to count distinct exercises
    final distinctExercises = sets.map((s) => s.exerciseId).toSet().length;
    final totalSets = sets.length;
    final dur = workout.durationMinutes;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: isActive ? cs.tertiaryContainer : null,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor:
              isActive ? cs.tertiary : cs.secondaryContainer,
          child: Icon(
            isActive ? Icons.sports_gymnastics : Icons.fitness_center,
            color: isActive ? cs.onTertiary : cs.onSecondaryContainer,
            size: 20,
          ),
        ),
        title: Text(
          workout.name ?? fmt.format(workout.startedAt),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          [
            if (workout.name != null) fmt.format(workout.startedAt),
            if (dur != null) '$dur min',
            if (distinctExercises > 0) '$distinctExercises Übungen',
            if (totalSets > 0) '$totalSets Sätze',
          ].join(' · '),
          style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
        ),
        trailing: isActive
            ? Icon(Icons.circle, color: cs.tertiary, size: 12)
            : null,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => isActive
                ? ActiveWorkoutScreen(workoutId: workout.id)
                : _WorkoutDetailScreen(workout: workout),
          ),
        ),
      ),
    );
  }
}

// ── Workout detail (read-only history) ───────────────────────────────────────

class _WorkoutDetailScreen extends ConsumerWidget {
  final Workout workout;
  const _WorkoutDetailScreen({required this.workout});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final setsAsync = ref.watch(workoutSetsProvider(workout.id));
    final exercises =
        ref.watch(exercisesProvider).valueOrNull ?? [];
    final exerciseMap = {for (final e in exercises) e.id: e};
    final fmt = DateFormat.yMMMd('de_DE').add_Hm();
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(workout.name ?? 'Training'),
        actions: [
          IconButton(
            icon: Icon(Icons.delete_outline, color: cs.error),
            tooltip: 'Löschen',
            onPressed: () => _confirmDelete(context, ref),
          ),
        ],
      ),
      body: setsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Fehler: $e')),
        data: (sets) {
          final grouped = <String, List<WorkoutSet>>{};
          for (final s in sets) {
            grouped.putIfAbsent(s.exerciseId, () => []).add(s);
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(fmt.format(workout.startedAt),
                  style: TextStyle(color: cs.onSurfaceVariant)),
              if (workout.durationMinutes != null)
                Text('${workout.durationMinutes} min',
                    style: TextStyle(color: cs.onSurfaceVariant)),
              const SizedBox(height: 16),
              ...grouped.entries.map((entry) {
                final ex = exerciseMap[entry.key];
                return _ExerciseSummaryCard(
                  exerciseName: ex?.name ?? entry.key,
                  sets: entry.value,
                );
              }),
            ],
          );
        },
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Training löschen?'),
            content: const Text(
                'Alle Sätze dieses Trainings werden unwiderruflich gelöscht.'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('Abbrechen')),
              FilledButton(
                  style: FilledButton.styleFrom(
                      backgroundColor:
                          Theme.of(context).colorScheme.error),
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: const Text('Löschen')),
            ],
          ),
        ) ??
        false;
    if (ok && context.mounted) {
      await ref
          .read(workoutOpsProvider.notifier)
          .deleteWorkout(workout.id);
      if (context.mounted) Navigator.of(context).pop();
    }
  }
}

class _ExerciseSummaryCard extends StatelessWidget {
  final String exerciseName;
  final List<WorkoutSet> sets;
  const _ExerciseSummaryCard(
      {required this.exerciseName, required this.sets});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(exerciseName,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            ...sets.map((s) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(
                    _setLabel(s),
                    style: TextStyle(
                        fontSize: 13, color: cs.onSurfaceVariant),
                  ),
                )),
          ],
        ),
      ),
    );
  }

  String _setLabel(WorkoutSet s) {
    final parts = <String>['Satz ${s.setNumber}'];
    if (s.weightKg != null) parts.add('${s.weightKg} kg');
    if (s.reps != null) parts.add('${s.reps} Wdh');
    if (s.durationSeconds != null) {
      final m = s.durationSeconds! ~/ 60;
      final sec = s.durationSeconds! % 60;
      parts.add(m > 0 ? '${m}min ${sec}s' : '${sec}s');
    }
    if (s.distanceKm != null) parts.add('${s.distanceKm} km');
    if (s.rpe != null) parts.add('RPE ${s.rpe}');
    return parts.join(' · ');
  }
}

// ── Active workout screen ─────────────────────────────────────────────────────

class ActiveWorkoutScreen extends ConsumerStatefulWidget {
  final String workoutId;
  const ActiveWorkoutScreen({super.key, required this.workoutId});

  @override
  ConsumerState<ActiveWorkoutScreen> createState() =>
      _ActiveWorkoutScreenState();
}

class _ActiveWorkoutScreenState extends ConsumerState<ActiveWorkoutScreen> {
  final _stopwatch = Stopwatch()..start();

  @override
  Widget build(BuildContext context) {
    final setsAsync = ref.watch(workoutSetsProvider(widget.workoutId));
    final exercises =
        ref.watch(exercisesProvider).valueOrNull ?? [];
    final exerciseMap = {for (final e in exercises) e.id: e};
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: _WorkoutTimer(stopwatch: _stopwatch),
        leading: IconButton(
          icon: const Icon(Icons.minimize),
          tooltip: 'Minimieren',
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          FilledButton.tonal(
            onPressed: () => _finish(context),
            child: const Text('Beenden'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: setsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Fehler: $e')),
        data: (sets) {
          // Group by exercise
          final groups = <String, List<WorkoutSet>>{};
          for (final s in sets) {
            groups.putIfAbsent(s.exerciseId, () => []).add(s);
          }

          return Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  children: [
                    ...groups.entries.map((entry) {
                      final ex = exerciseMap[entry.key];
                      return _ActiveExerciseCard(
                        exerciseId: entry.key,
                        exerciseName: ex?.name ?? entry.key,
                        isCardio: ex?.category == 'cardio',
                        sets: entry.value,
                        workoutId: widget.workoutId,
                      );
                    }),
                    if (groups.isEmpty)
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Text(
                            'Füge eine Übung hinzu,\num dein Training zu beginnen.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: cs.onSurfaceVariant),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _addExercise(context),
                    icon: const Icon(Icons.add),
                    label: const Text('Übung hinzufügen'),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _addExercise(BuildContext context) async {
    final exercises =
        ref.read(exercisesProvider).valueOrNull ?? [];
    final chosen = await showModalBottomSheet<Exercise>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _ExercisePickerSheet(exercises: exercises),
    );
    if (chosen == null || !context.mounted) return;

    // Check if already in workout
    final currentSets =
        ref.read(workoutSetsProvider(widget.workoutId)).valueOrNull ?? [];
    if (currentSets.any((s) => s.exerciseId == chosen.id)) return;

    // Add first set immediately
    await ref.read(workoutOpsProvider.notifier).addSet(
          workoutId: widget.workoutId,
          exerciseId: chosen.id,
          setNumber: 1,
        );
  }

  Future<void> _finish(BuildContext context) async {
    final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Training beenden?'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('Weiter')),
              FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: const Text('Beenden')),
            ],
          ),
        ) ??
        false;
    if (!ok || !context.mounted) return;
    await ref
        .read(workoutOpsProvider.notifier)
        .finishWorkout(widget.workoutId);
    if (context.mounted) Navigator.of(context).pop();
  }
}

class _WorkoutTimer extends StatefulWidget {
  final Stopwatch stopwatch;
  const _WorkoutTimer({required this.stopwatch});

  @override
  State<_WorkoutTimer> createState() => _WorkoutTimerState();
}

class _WorkoutTimerState extends State<_WorkoutTimer> {
  late final Stream<int> _ticks;

  @override
  void initState() {
    super.initState();
    _ticks = Stream.periodic(const Duration(seconds: 1), (i) => i);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: _ticks,
      builder: (context, _) {
        final elapsed = widget.stopwatch.elapsed;
        final h = elapsed.inHours;
        final m = elapsed.inMinutes.remainder(60).toString().padLeft(2, '0');
        final s =
            elapsed.inSeconds.remainder(60).toString().padLeft(2, '0');
        return Text(h > 0 ? '$h:$m:$s' : '$m:$s');
      },
    );
  }
}

// ── Active exercise card ──────────────────────────────────────────────────────

class _ActiveExerciseCard extends ConsumerWidget {
  final String exerciseId;
  final String exerciseName;
  final bool isCardio;
  final List<WorkoutSet> sets;
  final String workoutId;

  const _ActiveExerciseCard({
    required this.exerciseId,
    required this.exerciseName,
    required this.isCardio,
    required this.sets,
    required this.workoutId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(exerciseName,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  tooltip: 'Übung entfernen',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => _removeExercise(ref),
                ),
              ],
            ),
            const SizedBox(height: 6),
            // Header row
            _SetHeader(isCardio: isCardio),
            const Divider(height: 8),
            ...sets.map((s) => _SetRow(
                  set: s,
                  isCardio: isCardio,
                  workoutId: workoutId,
                )),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => _addSet(ref),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Satz hinzufügen'),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 4, vertical: 0),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addSet(WidgetRef ref) async {
    final nextNum = sets.isEmpty ? 1 : sets.last.setNumber + 1;
    final prev = sets.isEmpty ? null : sets.last;
    await ref.read(workoutOpsProvider.notifier).addSet(
          workoutId: workoutId,
          exerciseId: exerciseId,
          setNumber: nextNum,
          reps: prev?.reps,
          weightKg: prev?.weightKg,
          durationSeconds: prev?.durationSeconds,
          distanceKm: prev?.distanceKm,
        );
  }

  Future<void> _removeExercise(WidgetRef ref) async {
    for (final s in sets) {
      await ref
          .read(workoutOpsProvider.notifier)
          .deleteSet(s.id, workoutId);
    }
  }
}

class _SetHeader extends StatelessWidget {
  final bool isCardio;
  const _SetHeader({required this.isCardio});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final style = TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: cs.onSurfaceVariant);
    return Row(
      children: [
        SizedBox(
            width: 32,
            child: Text('Satz', style: style, textAlign: TextAlign.center)),
        if (!isCardio) ...[
          const SizedBox(width: 8),
          SizedBox(
              width: 64,
              child:
                  Text('kg', style: style, textAlign: TextAlign.center)),
          const SizedBox(width: 8),
          SizedBox(
              width: 56,
              child: Text('Wdh', style: style, textAlign: TextAlign.center)),
        ] else ...[
          const SizedBox(width: 8),
          SizedBox(
              width: 64,
              child: Text('Zeit', style: style, textAlign: TextAlign.center)),
          const SizedBox(width: 8),
          SizedBox(
              width: 56,
              child: Text('km', style: style, textAlign: TextAlign.center)),
        ],
        const SizedBox(width: 8),
        SizedBox(
            width: 44,
            child: Text('RPE', style: style, textAlign: TextAlign.center)),
      ],
    );
  }
}

// ── Inline-editable set row ───────────────────────────────────────────────────

class _SetRow extends ConsumerStatefulWidget {
  final WorkoutSet set;
  final bool isCardio;
  final String workoutId;
  const _SetRow(
      {required this.set, required this.isCardio, required this.workoutId});

  @override
  ConsumerState<_SetRow> createState() => _SetRowState();
}

class _SetRowState extends ConsumerState<_SetRow> {
  late TextEditingController _c1; // kg or minutes
  late TextEditingController _c2; // reps or km
  late TextEditingController _rpe;

  @override
  void initState() {
    super.initState();
    _c1 = TextEditingController(
        text: widget.isCardio
            ? widget.set.durationSeconds != null
                ? (widget.set.durationSeconds! ~/ 60).toString()
                : ''
            : widget.set.weightKg?.toString() ?? '');
    _c2 = TextEditingController(
        text: widget.isCardio
            ? widget.set.distanceKm?.toString() ?? ''
            : widget.set.reps?.toString() ?? '');
    _rpe = TextEditingController(
        text: widget.set.rpe?.toStringAsFixed(0) ?? '');
  }

  @override
  void dispose() {
    _c1.dispose();
    _c2.dispose();
    _rpe.dispose();
    super.dispose();
  }

  void _save() {
    final v1 = double.tryParse(_c1.text.replaceAll(',', '.'));
    final v2 = double.tryParse(_c2.text.replaceAll(',', '.'));
    final rpe = double.tryParse(_rpe.text.replaceAll(',', '.'));
    ref.read(workoutOpsProvider.notifier).updateSet(
          WorkoutSetsCompanion(
            id: drift.Value(widget.set.id),
            workoutId: drift.Value(widget.set.workoutId),
            exerciseId: drift.Value(widget.set.exerciseId),
            setNumber: drift.Value(widget.set.setNumber),
            weightKg: widget.isCardio
                ? const drift.Value(null)
                : drift.Value(v1),
            reps: widget.isCardio
                ? const drift.Value(null)
                : drift.Value(v2?.toInt()),
            durationSeconds: widget.isCardio
                ? drift.Value(v1 != null ? (v1 * 60).toInt() : null)
                : const drift.Value(null),
            distanceKm: widget.isCardio
                ? drift.Value(v2)
                : const drift.Value(null),
            rpe: drift.Value(rpe),
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 32,
            child: Text(
              '${widget.set.setNumber}',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontWeight: FontWeight.w600, color: cs.primary),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
              width: 64,
              child: _NumField(
                  ctrl: _c1,
                  hint: widget.isCardio ? 'min' : 'kg',
                  onDone: _save)),
          const SizedBox(width: 8),
          SizedBox(
              width: 56,
              child: _NumField(
                  ctrl: _c2,
                  hint: widget.isCardio ? 'km' : 'Wdh',
                  onDone: _save)),
          const SizedBox(width: 8),
          SizedBox(
              width: 44,
              child:
                  _NumField(ctrl: _rpe, hint: '–', onDone: _save)),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.close, size: 16),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: () => ref
                .read(workoutOpsProvider.notifier)
                .deleteSet(widget.set.id, widget.workoutId),
          ),
        ],
      ),
    );
  }
}

class _NumField extends StatelessWidget {
  final TextEditingController ctrl;
  final String hint;
  final VoidCallback onDone;
  const _NumField(
      {required this.ctrl, required this.hint, required this.onDone});

  @override
  Widget build(BuildContext context) => TextField(
        controller: ctrl,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 13),
        keyboardType:
            const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(fontSize: 12),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          isDense: true,
          border: const OutlineInputBorder(),
        ),
        onEditingComplete: onDone,
        onTapOutside: (_) => onDone(),
      );
}

// ── Exercise picker sheet ─────────────────────────────────────────────────────

class _ExercisePickerSheet extends StatefulWidget {
  final List<Exercise> exercises;
  const _ExercisePickerSheet({required this.exercises});

  @override
  State<_ExercisePickerSheet> createState() => _ExercisePickerSheetState();
}

class _ExercisePickerSheetState extends State<_ExercisePickerSheet> {
  String _query = '';
  String? _cat;

  List<Exercise> get _filtered => widget.exercises
      .where((e) =>
          (_cat == null || e.category == _cat) &&
          (_query.isEmpty ||
              e.name.toLowerCase().contains(_query.toLowerCase())))
      .toList();

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollCtrl) => Column(
        children: [
          const SizedBox(height: 8),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Theme.of(context)
                  .colorScheme
                  .onSurfaceVariant
                  .withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SearchBar(
              hintText: 'Übung suchen…',
              leading: const Icon(Icons.search),
              onChanged: (v) => setState(() => _query = v),
              autoFocus: true,
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                FilterChip(
                  label: const Text('Alle'),
                  selected: _cat == null,
                  onSelected: (_) => setState(() => _cat = null),
                  visualDensity: VisualDensity.compact,
                ),
                const SizedBox(width: 6),
                ..._categories.map((c) => Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: FilterChip(
                        label: Text(_catLabel(c)),
                        selected: _cat == c,
                        onSelected: (_) =>
                            setState(() => _cat = _cat == c ? null : c),
                        visualDensity: VisualDensity.compact,
                      ),
                    )),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: ListView.builder(
              controller: scrollCtrl,
              itemCount: _filtered.length,
              itemBuilder: (context, i) {
                final e = _filtered[i];
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Theme.of(context)
                        .colorScheme
                        .secondaryContainer,
                    radius: 18,
                    child: Text(
                      _catLabel(e.category).substring(0, 1),
                      style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context)
                              .colorScheme
                              .onSecondaryContainer),
                    ),
                  ),
                  title: Text(e.name),
                  subtitle: Text(
                    '${_catLabel(e.category)} · ${_equipLabel(e.equipment)}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  onTap: () => Navigator.of(context).pop(e),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ── Exercise library screen ───────────────────────────────────────────────────

class ExerciseLibraryScreen extends ConsumerStatefulWidget {
  const ExerciseLibraryScreen({super.key});

  @override
  ConsumerState<ExerciseLibraryScreen> createState() =>
      _ExerciseLibraryScreenState();
}

class _ExerciseLibraryScreenState
    extends ConsumerState<ExerciseLibraryScreen> {
  String _query = '';
  String? _cat;

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(exercisesProvider).valueOrNull ?? [];
    final filtered = all
        .where((e) =>
            (_cat == null || e.category == _cat) &&
            (_query.isEmpty ||
                e.name.toLowerCase().contains(_query.toLowerCase())))
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Übungsbibliothek'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(96),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                child: SearchBar(
                  hintText: 'Übung suchen…',
                  leading: const Icon(Icons.search),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              SizedBox(
                height: 40,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    FilterChip(
                      label: const Text('Alle'),
                      selected: _cat == null,
                      onSelected: (_) => setState(() => _cat = null),
                      visualDensity: VisualDensity.compact,
                    ),
                    const SizedBox(width: 6),
                    ..._categories.map((c) => Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: FilterChip(
                            label: Text(_catLabel(c)),
                            selected: _cat == c,
                            onSelected: (_) => setState(
                                () => _cat = _cat == c ? null : c),
                            visualDensity: VisualDensity.compact,
                          ),
                        )),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      body: ListView.builder(
        itemCount: filtered.length,
        itemBuilder: (context, i) {
          final e = filtered[i];
          return ListTile(
            leading: CircleAvatar(
              backgroundColor:
                  Theme.of(context).colorScheme.secondaryContainer,
              radius: 18,
              child: Text(
                _catLabel(e.category).substring(0, 1),
                style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context)
                        .colorScheme
                        .onSecondaryContainer),
              ),
            ),
            title: Text(e.name),
            subtitle: Text(
              '${_catLabel(e.category)} · ${_equipLabel(e.equipment)}',
              style: const TextStyle(fontSize: 12),
            ),
            trailing: e.isCustom
                ? IconButton(
                    icon: Icon(Icons.delete_outline,
                        color:
                            Theme.of(context).colorScheme.error,
                        size: 20),
                    onPressed: () => ref
                        .read(workoutOpsProvider.notifier)
                        .deleteExercise(e.id),
                  )
                : null,
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _addCustom(context),
        tooltip: 'Eigene Übung',
        child: const Icon(Icons.add),
      ),
    );
  }

  Future<void> _addCustom(BuildContext context) async {
    final nameCtrl = TextEditingController();
    String cat = 'chest';
    String? equip;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Eigene Übung'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Name *',
                  border: OutlineInputBorder(),
                ),
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                // ignore: deprecated_member_use
                value: cat,
                decoration:
                    const InputDecoration(labelText: 'Kategorie'),
                items: _categories
                    .map((c) => DropdownMenuItem(
                          value: c,
                          child: Text(_catLabel(c)),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => cat = v!),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                // ignore: deprecated_member_use
                value: equip,
                decoration:
                    const InputDecoration(labelText: 'Equipment'),
                items: const [
                  DropdownMenuItem(value: null, child: Text('–')),
                  DropdownMenuItem(
                      value: 'barbell', child: Text('Langhantel')),
                  DropdownMenuItem(
                      value: 'dumbbell', child: Text('Kurzhantel')),
                  DropdownMenuItem(
                      value: 'machine', child: Text('Maschine')),
                  DropdownMenuItem(
                      value: 'bodyweight',
                      child: Text('Körpergewicht')),
                  DropdownMenuItem(
                      value: 'cable', child: Text('Kabel')),
                  DropdownMenuItem(
                      value: 'other', child: Text('Sonstiges')),
                ],
                onChanged: (v) => setState(() => equip = v),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Abbrechen')),
            FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Erstellen')),
          ],
        ),
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final name = nameCtrl.text.trim();
    if (name.isEmpty) return;
    await ref.read(workoutOpsProvider.notifier).addCustomExercise(
          name: name,
          category: cat,
          equipment: equip,
        );
  }
}
