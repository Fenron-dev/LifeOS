import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:drift/drift.dart' as drift;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../db/database.dart';
import '../../providers/vault_provider.dart';
import '../providers/workouts_provider.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

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

String _diffLabel(String? d) => switch (d) {
      'beginner' => 'Einsteiger',
      'intermediate' => 'Fortgeschritten',
      'advanced' => 'Profi',
      _ => d ?? '–',
    };

Color _diffColor(String? d, ColorScheme cs) => switch (d) {
      'beginner' => Colors.green,
      'intermediate' => Colors.orange,
      'advanced' => cs.error,
      _ => cs.outline,
    };

String _equipLabel(String? eq) => switch (eq) {
      'barbell' => 'Langhantel',
      'dumbbell' => 'Kurzhantel',
      'machine' => 'Maschine',
      'bodyweight' => 'Körpergewicht',
      'cable' => 'Kabel',
      'other' => 'Sonstiges',
      null => 'Kein Equipment',
      _ => eq,
    };

const _categories = [
  'chest', 'back', 'legs', 'shoulders', 'arms', 'core', 'cardio',
];

const _weekDays = [
  'Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So',
];
const _weekDaysFull = [
  'Montag', 'Dienstag', 'Mittwoch', 'Donnerstag', 'Freitag', 'Samstag', 'Sonntag',
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
            icon: const Icon(Icons.calendar_month_outlined),
            tooltip: 'Trainingspläne',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                  builder: (_) => const WorkoutPlansScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.fitness_center_outlined),
            tooltip: 'Übungsbibliothek',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                  builder: (_) => const ExerciseLibraryScreen()),
            ),
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
              'Starte dein erstes Training oder\nerstelle einen Trainingsplan.',
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

    final distinctExercises = sets.map((s) => s.exerciseId).toSet().length;
    final totalSets = sets.length;
    final dur = workout.durationMinutes;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: isActive ? cs.tertiaryContainer : null,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: isActive ? cs.tertiary : cs.secondaryContainer,
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
    final exercises = ref.watch(exercisesProvider).valueOrNull ?? [];
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
                  exercise: ex,
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
  final Exercise? exercise;
  final List<WorkoutSet> sets;
  const _ExerciseSummaryCard({required this.exercise, required this.sets});

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
            Text(exercise?.name ?? '–',
                style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            ...sets.map((s) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(
                    _setLabel(s),
                    style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
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

// ── Exercise Detail Screen ────────────────────────────────────────────────────

class ExerciseDetailScreen extends ConsumerWidget {
  final Exercise exercise;
  const ExerciseDetailScreen({super.key, required this.exercise});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch for live rating/favorite updates
    final exList = ref.watch(exercisesProvider).valueOrNull ?? [];
    final exercise = exList
            .where((e) => e.id == this.exercise.id)
            .firstOrNull ??
        this.exercise;

    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final muscles = _parseJson(exercise.muscleGroups);
    final secondary = _parseJson(exercise.muscleGroupsSecondary);
    final steps = exercise.instructions
            ?.split('\n')
            .where((l) => l.trim().isNotEmpty)
            .toList() ??
        [];
    final volumeAsync = ref.watch(exerciseVolumeHistoryProvider(exercise.id));
    final bestAsync = ref.watch(bestSetForExerciseProvider(exercise.id));

    return Scaffold(
      appBar: AppBar(
        title: Text(exercise.name),
        actions: [
          IconButton(
            icon: Icon(exercise.isFavorite
                ? Icons.favorite
                : Icons.favorite_border),
            color: exercise.isFavorite ? Colors.red : null,
            tooltip: exercise.isFavorite
                ? 'Aus Favoriten entfernen'
                : 'Zu Favoriten hinzufügen',
            onPressed: () => ref
                .read(workoutOpsProvider.notifier)
                .updateExercise(ExercisesCompanion(
                  id: drift.Value(exercise.id),
                  isFavorite: drift.Value(!exercise.isFavorite),
                )),
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => _editExercise(context, ref),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          // ── Short description ────────────────────────────────────────────
          if (exercise.shortDescription != null &&
              exercise.shortDescription!.isNotEmpty) ...[
            Text(
              exercise.shortDescription!,
              style: theme.textTheme.bodyMedium?.copyWith(
                  fontStyle: FontStyle.italic,
                  color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
          ],
          // ── Ratings ──────────────────────────────────────────────────────
          _RatingRow(
            thumbRating: exercise.thumbRating,
            starRating: exercise.starRating,
            onThumb: (v) => ref
                .read(workoutOpsProvider.notifier)
                .updateExercise(ExercisesCompanion(
                  id: drift.Value(exercise.id),
                  thumbRating: drift.Value(v),
                )),
            onStar: (v) => ref
                .read(workoutOpsProvider.notifier)
                .updateExercise(ExercisesCompanion(
                  id: drift.Value(exercise.id),
                  starRating: drift.Value(v),
                )),
          ),
          const SizedBox(height: 8),
          // ── Info chips ──────────────────────────────────────────────────
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              _InfoChip(
                icon: Icons.category_outlined,
                label: _catLabel(exercise.category),
                color: cs.secondaryContainer,
                textColor: cs.onSecondaryContainer,
              ),
              if (exercise.equipment != null)
                _InfoChip(
                  icon: Icons.fitness_center_outlined,
                  label: _equipLabel(exercise.equipment),
                  color: cs.surfaceContainerHighest,
                  textColor: cs.onSurface,
                ),
              if (exercise.difficulty != null)
                _InfoChip(
                  icon: Icons.signal_cellular_alt,
                  label: _diffLabel(exercise.difficulty),
                  color: _diffColor(exercise.difficulty, cs).withValues(alpha: 0.15),
                  textColor: _diffColor(exercise.difficulty, cs),
                ),
              if (exercise.caloriesPerMinute != null)
                _InfoChip(
                  icon: Icons.local_fire_department_outlined,
                  label:
                      '~${exercise.caloriesPerMinute!.toStringAsFixed(1)} kcal/min',
                  color: Colors.orange.withValues(alpha: 0.15),
                  textColor: Colors.orange.shade700,
                ),
            ],
          ),
          const SizedBox(height: 16),

          // ── Muscles ─────────────────────────────────────────────────────
          if (muscles.isNotEmpty) ...[
            _SectionTitle('Primäre Muskeln'),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: muscles
                  .map((m) => Chip(
                        label: Text(m,
                            style: const TextStyle(fontSize: 12)),
                        backgroundColor: cs.primaryContainer,
                        labelStyle:
                            TextStyle(color: cs.onPrimaryContainer),
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 8),
          ],
          if (secondary.isNotEmpty) ...[
            _SectionTitle('Hilfsmuskel'),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: secondary
                  .map((m) => Chip(
                        label: Text(m,
                            style: const TextStyle(fontSize: 12)),
                        backgroundColor: cs.surfaceContainerHighest,
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 8),
          ],

          // ── Instructions ─────────────────────────────────────────────────
          if (steps.isNotEmpty) ...[
            const Divider(height: 24),
            _SectionTitle('Durchführung'),
            const SizedBox(height: 8),
            ...steps.asMap().entries.map((entry) {
              final stepText = entry.value.replaceFirst(
                  RegExp(r'^\d+\.\s*'), '');
              final hasNum =
                  entry.value.trimLeft().startsWith(RegExp(r'\d+\.'));
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: cs.primary,
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '${entry.key + 1}',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: cs.onPrimary),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                          hasNum ? stepText : entry.value,
                          style: theme.textTheme.bodyMedium),
                    ),
                  ],
                ),
              );
            }),
          ],

          // ── Tips ─────────────────────────────────────────────────────────
          if (exercise.tips != null && exercise.tips!.isNotEmpty) ...[
            const Divider(height: 24),
            _SectionTitle('Tipps & Sicherheit'),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: Colors.amber.withValues(alpha: 0.4)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.lightbulb_outline,
                      color: Colors.amber, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(exercise.tips!,
                        style: theme.textTheme.bodyMedium),
                  ),
                ],
              ),
            ),
          ],

          // ── Video ────────────────────────────────────────────────────────
          if (exercise.videoUrl != null &&
              exercise.videoUrl!.isNotEmpty) ...[
            const Divider(height: 24),
            _SectionTitle('Video / Demonstration'),
            const SizedBox(height: 6),
            OutlinedButton.icon(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                      content:
                          Text('Link: ${exercise.videoUrl}')),
                );
              },
              icon: const Icon(Icons.play_circle_outline),
              label: const Text('Video öffnen'),
            ),
          ],

          // ── Statistics ───────────────────────────────────────────────────
          const Divider(height: 32),
          _SectionTitle('Statistiken'),
          const SizedBox(height: 8),
          bestAsync.when(
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
            data: (best) {
              if (best == null) {
                return Text(
                  'Noch keine aufgezeichneten Sätze.',
                  style: TextStyle(color: cs.onSurfaceVariant),
                );
              }
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Icon(Icons.emoji_events_outlined,
                          color: Colors.amber.shade600),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Beste Leistung',
                                style:
                                    theme.textTheme.labelMedium),
                            Text(
                              [
                                if (best.weightKg != null)
                                  '${best.weightKg} kg',
                                if (best.reps != null)
                                  '${best.reps} Wdh',
                                if (best.durationSeconds != null)
                                  '${best.durationSeconds}s',
                              ].join(' × '),
                              style: theme.textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          volumeAsync.when(
            loading: () =>
                const Center(child: CircularProgressIndicator()),
            error: (_, _) => const SizedBox.shrink(),
            data: (history) {
              if (history.length < 2) return const SizedBox.shrink();
              return _VolumeChart(history: history);
            },
          ),
        ],
      ),
    );
  }

  List<String> _parseJson(String? json) {
    if (json == null) return [];
    try {
      return (jsonDecode(json) as List).cast<String>();
    } catch (_) {
      return [];
    }
  }

  Future<void> _editExercise(BuildContext context, WidgetRef ref) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _ExerciseEditSheet(exercise: exercise),
    );
  }
}

// ── Rating row (thumb + stars) ────────────────────────────────────────────────

class _RatingRow extends StatelessWidget {
  final int? thumbRating;
  final int? starRating;
  final void Function(int?) onThumb;
  final void Function(int?) onStar;
  const _RatingRow({
    required this.thumbRating,
    required this.starRating,
    required this.onThumb,
    required this.onStar,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
        IconButton(
          icon: Icon(Icons.thumb_up,
              color: thumbRating == 1 ? cs.primary : cs.outlineVariant),
          iconSize: 20,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          tooltip: 'Empfehlung',
          onPressed: () => onThumb(thumbRating == 1 ? null : 1),
        ),
        IconButton(
          icon: Icon(Icons.thumb_down,
              color: thumbRating == -1 ? cs.error : cs.outlineVariant),
          iconSize: 20,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          tooltip: 'Nicht empfohlen',
          onPressed: () => onThumb(thumbRating == -1 ? null : -1),
        ),
        const SizedBox(width: 12),
        ...List.generate(5, (i) {
          final star = i + 1;
          return IconButton(
            icon: Icon(
              star <= (starRating ?? 0) ? Icons.star : Icons.star_border,
              color: star <= (starRating ?? 0)
                  ? Colors.amber.shade600
                  : cs.outlineVariant,
            ),
            iconSize: 20,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            tooltip: '$star Stern${star > 1 ? 'e' : ''}',
            onPressed: () => onStar(starRating == star ? null : star),
          );
        }),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final Color textColor;
  const _InfoChip(
      {required this.icon,
      required this.label,
      required this.color,
      required this.textColor});

  @override
  Widget build(BuildContext context) => Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: textColor),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(
                    fontSize: 12,
                    color: textColor,
                    fontWeight: FontWeight.w500)),
          ],
        ),
      );
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: Theme.of(context)
            .textTheme
            .labelLarge
            ?.copyWith(color: Theme.of(context).colorScheme.primary),
      );
}

// ── Volume chart ──────────────────────────────────────────────────────────────

class _VolumeChart extends StatelessWidget {
  final List<({DateTime date, double volume, int totalSets})> history;
  const _VolumeChart({required this.history});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final spots = history
        .asMap()
        .entries
        .map((e) => FlSpot(e.key.toDouble(), e.value.volume))
        .toList();
    final maxY = history.map((h) => h.volume).fold(0.0, math.max);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Volumen-Verlauf (kg × Wdh)',
            style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 8),
        SizedBox(
          height: 140,
          child: LineChart(
            LineChartData(
              minY: 0,
              maxY: maxY * 1.15,
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                getDrawingHorizontalLine: (_) =>
                    FlLine(color: cs.outlineVariant, strokeWidth: 0.5),
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: history.length <= 8,
                    getTitlesWidget: (v, _) {
                      final i = v.toInt();
                      if (i < 0 || i >= history.length) {
                        return const SizedBox.shrink();
                      }
                      return Text(
                        DateFormat.MMMd('de_DE')
                            .format(history[i].date),
                        style: TextStyle(
                            fontSize: 9,
                            color: cs.onSurfaceVariant),
                      );
                    },
                  ),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 40,
                    getTitlesWidget: (v, _) => Text(
                      v.toInt().toString(),
                      style: TextStyle(
                          fontSize: 9, color: cs.onSurfaceVariant),
                    ),
                  ),
                ),
              ),
              lineBarsData: [
                LineChartBarData(
                  spots: spots,
                  isCurved: true,
                  color: cs.primary,
                  barWidth: 2,
                  dotData: FlDotData(
                    getDotPainter: (_, _, _, _) =>
                        FlDotCirclePainter(
                            radius: 3,
                            color: cs.primary,
                            strokeWidth: 0),
                  ),
                  belowBarData: BarAreaData(
                    show: true,
                    color: cs.primary.withValues(alpha: 0.1),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ── Exercise edit sheet (custom exercises) ────────────────────────────────────

class _ExerciseEditSheet extends ConsumerStatefulWidget {
  final Exercise exercise;
  const _ExerciseEditSheet({required this.exercise});

  @override
  ConsumerState<_ExerciseEditSheet> createState() =>
      _ExerciseEditSheetState();
}

class _ExerciseEditSheetState extends ConsumerState<_ExerciseEditSheet> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _shortDescCtrl;
  late final TextEditingController _instructionsCtrl;
  late final TextEditingController _tipsCtrl;
  late final TextEditingController _videoCtrl;
  late final TextEditingController _kcalCtrl;
  String _cat = 'chest';
  String? _equip;
  String? _diff;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.exercise;
    _nameCtrl = TextEditingController(text: e.name);
    _shortDescCtrl =
        TextEditingController(text: e.shortDescription ?? '');
    _instructionsCtrl = TextEditingController(text: e.instructions ?? '');
    _tipsCtrl = TextEditingController(text: e.tips ?? '');
    _videoCtrl = TextEditingController(text: e.videoUrl ?? '');
    _kcalCtrl = TextEditingController(
        text: e.caloriesPerMinute?.toString() ?? '');
    _cat = e.category;
    _equip = e.equipment;
    _diff = e.difficulty;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _shortDescCtrl.dispose();
    _instructionsCtrl.dispose();
    _tipsCtrl.dispose();
    _videoCtrl.dispose();
    _kcalCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty) return;
    setState(() => _saving = true);
    try {
      await ref.read(workoutOpsProvider.notifier).updateExercise(
            ExercisesCompanion(
              id: drift.Value(widget.exercise.id),
              name: drift.Value(_nameCtrl.text.trim()),
              category: drift.Value(_cat),
              equipment: drift.Value(_equip),
              difficulty: drift.Value(_diff),
              shortDescription: drift.Value(
                  _shortDescCtrl.text.trim().isEmpty
                      ? null
                      : _shortDescCtrl.text.trim()),
              instructions: drift.Value(
                  _instructionsCtrl.text.trim().isEmpty
                      ? null
                      : _instructionsCtrl.text.trim()),
              tips: drift.Value(_tipsCtrl.text.trim().isEmpty
                  ? null
                  : _tipsCtrl.text.trim()),
              videoUrl: drift.Value(_videoCtrl.text.trim().isEmpty
                  ? null
                  : _videoCtrl.text.trim()),
              caloriesPerMinute: drift.Value(
                  double.tryParse(_kcalCtrl.text.replaceAll(',', '.'))),
            ),
          );
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Übung bearbeiten',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            TextFormField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                  labelText: 'Name *', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _shortDescCtrl,
              decoration: const InputDecoration(
                labelText: 'Kurzbeschreibung',
                border: OutlineInputBorder(),
                hintText: 'z.B. „Grundübung für Brust und Trizeps"',
              ),
              maxLines: 1,
              maxLength: 100,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _cat,
              decoration:
                  const InputDecoration(labelText: 'Kategorie'),
              items: _categories
                  .map((c) => DropdownMenuItem(
                      value: c, child: Text(_catLabel(c))))
                  .toList(),
              onChanged: (v) => setState(() => _cat = v!),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              initialValue: _equip,
              decoration:
                  const InputDecoration(labelText: 'Equipment'),
              items: const [
                DropdownMenuItem(
                    value: null, child: Text('Kein Equipment')),
                DropdownMenuItem(
                    value: 'barbell', child: Text('Langhantel')),
                DropdownMenuItem(
                    value: 'dumbbell', child: Text('Kurzhantel')),
                DropdownMenuItem(
                    value: 'machine', child: Text('Maschine')),
                DropdownMenuItem(
                    value: 'bodyweight', child: Text('Körpergewicht')),
                DropdownMenuItem(
                    value: 'cable', child: Text('Kabel')),
                DropdownMenuItem(
                    value: 'other', child: Text('Sonstiges')),
              ],
              onChanged: (v) => setState(() => _equip = v),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              initialValue: _diff,
              decoration: const InputDecoration(
                  labelText: 'Schwierigkeitsgrad'),
              items: const [
                DropdownMenuItem(value: null, child: Text('–')),
                DropdownMenuItem(
                    value: 'beginner', child: Text('Einsteiger')),
                DropdownMenuItem(
                    value: 'intermediate',
                    child: Text('Fortgeschritten')),
                DropdownMenuItem(
                    value: 'advanced', child: Text('Profi')),
              ],
              onChanged: (v) => setState(() => _diff = v),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _kcalCtrl,
              decoration: const InputDecoration(
                  labelText: 'Kalorien/Minute (kcal)',
                  border: OutlineInputBorder()),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _instructionsCtrl,
              decoration: const InputDecoration(
                labelText: 'Durchführung (Schritt für Schritt)',
                border: OutlineInputBorder(),
                hintText: '1. Schritt 1\n2. Schritt 2',
              ),
              maxLines: 5,
              minLines: 3,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _tipsCtrl,
              decoration: const InputDecoration(
                  labelText: 'Tipps & Sicherheit',
                  border: OutlineInputBorder()),
              maxLines: 2,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _videoCtrl,
              decoration: const InputDecoration(
                  labelText: 'Video-URL (YouTube, GIF…)',
                  border: OutlineInputBorder()),
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Speichern'),
            ),
          ],
        ),
      ),
    );
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

class _ActiveWorkoutScreenState
    extends ConsumerState<ActiveWorkoutScreen> {

  @override
  Widget build(BuildContext context) {
    final workoutAsync =
        ref.watch(watchWorkoutByIdProvider(widget.workoutId));
    final workout = workoutAsync.valueOrNull;
    final timerStartedAt = workout?.timerStartedAt;

    final setsAsync = ref.watch(workoutSetsProvider(widget.workoutId));
    final exercises = ref.watch(exercisesProvider).valueOrNull ?? [];
    final exerciseMap = {for (final e in exercises) e.id: e};
    final cs = Theme.of(context).colorScheme;

    // Plan exercises for today (if workout is linked to a plan)
    final planId = workout?.planId;
    final allPlanExercises = planId != null
        ? (ref.watch(planExercisesProvider(planId)).valueOrNull ?? [])
        : <WorkoutPlanExercise>[];
    final today = DateTime.now().weekday - 1; // 0=Mon … 6=Sun
    final todayPlanExercises = allPlanExercises
        .where((e) => e.dayOfWeek == null || e.dayOfWeek == today)
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: timerStartedAt != null
            ? _WorkoutTimer(startedAt: timerStartedAt)
            : const Text('Bereit'),
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
                    if (todayPlanExercises.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 4, 4, 6),
                        child: Text('Heutige Übungen',
                            style: Theme.of(context)
                                .textTheme
                                .labelLarge
                                ?.copyWith(color: cs.primary)),
                      ),
                      ...todayPlanExercises.map((pe) {
                        final ex = exerciseMap[pe.exerciseId];
                        final targetDesc = [
                          if (pe.targetSets != null)
                            '${pe.targetSets} Sätze',
                          if (pe.targetReps != null)
                            '× ${pe.targetReps} Wdh',
                          if (pe.targetDurationSeconds != null)
                            '${pe.targetDurationSeconds}s',
                        ].join(' ');
                        return Card(
                          margin: const EdgeInsets.only(bottom: 6),
                          color: cs.secondaryContainer
                              .withValues(alpha: 0.4),
                          child: ListTile(
                            dense: true,
                            title: Text(ex?.name ?? pe.exerciseId,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600)),
                            subtitle: targetDesc.isNotEmpty
                                ? Text(targetDesc,
                                    style: TextStyle(
                                        color: cs.onSurfaceVariant,
                                        fontSize: 12))
                                : null,
                            trailing: OutlinedButton.icon(
                              onPressed: () => _addExerciseById(
                                  context, pe.exerciseId),
                              icon: const Icon(Icons.add, size: 14),
                              label: const Text('Satz'),
                              style: OutlinedButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8),
                              ),
                            ),
                          ),
                        );
                      }),
                      const Divider(height: 16),
                    ],
                    ...groups.entries.map((entry) {
                      final ex = exerciseMap[entry.key];
                      return _ActiveExerciseCard(
                        exercise: ex,
                        exerciseId: entry.key,
                        sets: entry.value,
                        workoutId: widget.workoutId,
                      );
                    }),
                    if (groups.isEmpty && todayPlanExercises.isEmpty)
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
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (timerStartedAt == null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: FilledButton.icon(
                          icon: const Icon(Icons.play_arrow),
                          label: const Text('Training starten'),
                          onPressed: _startTimer,
                        ),
                      ),
                    OutlinedButton.icon(
                      onPressed: () => _addExercise(context),
                      icon: const Icon(Icons.add),
                      label: const Text('Übung hinzufügen'),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _startTimer() async {
    final db = ref.read(databaseProvider)!;
    await db.setWorkoutTimerStart(widget.workoutId, DateTime.now());
  }

  Future<void> _addExerciseById(
      BuildContext context, String exerciseId) async {
    final currentSets =
        ref.read(workoutSetsProvider(widget.workoutId)).valueOrNull ?? [];
    if (currentSets.any((s) => s.exerciseId == exerciseId)) return;
    await ref.read(workoutOpsProvider.notifier).addSet(
          workoutId: widget.workoutId,
          exerciseId: exerciseId,
          setNumber: 1,
        );
  }

  Future<void> _addExercise(BuildContext context) async {
    final exercises = ref.read(exercisesProvider).valueOrNull ?? [];
    final chosen = await showModalBottomSheet<Exercise>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _ExercisePickerSheet(exercises: exercises),
    );
    if (chosen == null || !context.mounted) return;

    final currentSets =
        ref.read(workoutSetsProvider(widget.workoutId)).valueOrNull ?? [];
    if (currentSets.any((s) => s.exerciseId == chosen.id)) return;

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
  final DateTime startedAt;
  const _WorkoutTimer({required this.startedAt});

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
        final elapsed = DateTime.now().difference(widget.startedAt);
        final h = elapsed.inHours;
        final m =
            elapsed.inMinutes.remainder(60).toString().padLeft(2, '0');
        final s = elapsed.inSeconds
            .remainder(60)
            .toString()
            .padLeft(2, '0');
        return Text(h > 0 ? '$h:$m:$s' : '$m:$s');
      },
    );
  }
}

// ── Active exercise card ──────────────────────────────────────────────────────

class _ActiveExerciseCard extends ConsumerWidget {
  final Exercise? exercise;
  final String exerciseId;
  final List<WorkoutSet> sets;
  final String workoutId;

  const _ActiveExerciseCard({
    required this.exercise,
    required this.exerciseId,
    required this.sets,
    required this.workoutId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isCardio = exercise?.category == 'cardio';
    final isTimed = isCardio ||
        (exercise?.category == 'core' &&
            exercise?.equipment == 'bodyweight');

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
                  child: GestureDetector(
                    onTap: exercise != null
                        ? () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => ExerciseDetailScreen(
                                    exercise: exercise!),
                              ),
                            )
                        : null,
                    child: Text(
                      exercise?.name ?? exerciseId,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        decoration: exercise != null
                            ? TextDecoration.underline
                            : null,
                        decorationStyle: TextDecorationStyle.dotted,
                      ),
                    ),
                  ),
                ),
                if (isTimed)
                  IconButton(
                    icon: const Icon(Icons.timer_outlined, size: 18),
                    tooltip: 'Timer',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => _openTimer(context),
                  ),
                const SizedBox(width: 4),
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

  void _openTimer(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _IntervalTimerSheet(),
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

// ── Interval timer sheet ──────────────────────────────────────────────────────

class _IntervalTimerSheet extends StatefulWidget {
  const _IntervalTimerSheet();

  @override
  State<_IntervalTimerSheet> createState() => _IntervalTimerSheetState();
}

class _IntervalTimerSheetState extends State<_IntervalTimerSheet> {
  int _durationSeconds = 30;
  int _sets = 2;
  int _restSeconds = 10;
  int _currentSet = 0;
  int _remaining = 30;
  bool _running = false;
  bool _isRest = false;
  bool _done = false;
  late final AudioPlayer _player;

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();
    _remaining = _durationSeconds;
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _beep({int count = 1}) async {
    HapticFeedback.mediumImpact();
    try {
      final wav = _generateBeepWav(count: count);
      await _player.play(BytesSource(wav));
    } catch (_) {}
  }

  static Uint8List _generateBeepWav({
    int frequency = 880,
    int durationMs = 120,
    int count = 1,
  }) {
    const sampleRate = 22050;
    final numSamples = (sampleRate * durationMs / 1000).round();
    final gap = (sampleRate * 150 / 1000).round();
    final total = count * numSamples + (count - 1) * gap;
    final data = Int16List(total);

    for (int c = 0; c < count; c++) {
      final offset = c * (numSamples + gap);
      for (int i = 0; i < numSamples; i++) {
        final t = i / sampleRate;
        final env = i < 400
            ? i / 400.0
            : i > numSamples - 400
                ? (numSamples - i) / 400.0
                : 1.0;
        data[offset + i] =
            (28000 * math.sin(2 * math.pi * frequency * t) * env)
                .toInt();
      }
    }

    final dataBytes = data.buffer.asUint8List();
    final bytes = BytesBuilder();
    void w32(int v) {
      bytes.addByte(v & 0xFF);
      bytes.addByte((v >> 8) & 0xFF);
      bytes.addByte((v >> 16) & 0xFF);
      bytes.addByte((v >> 24) & 0xFF);
    }
    void w16(int v) {
      bytes.addByte(v & 0xFF);
      bytes.addByte((v >> 8) & 0xFF);
    }

    bytes.add(ascii.encode('RIFF'));
    w32(36 + dataBytes.length);
    bytes.add(ascii.encode('WAVE'));
    bytes.add(ascii.encode('fmt '));
    w32(16);
    w16(1); // PCM
    w16(1); // mono
    w32(sampleRate);
    w32(sampleRate * 2);
    w16(2);
    w16(16);
    bytes.add(ascii.encode('data'));
    w32(dataBytes.length);
    bytes.add(dataBytes);
    return bytes.toBytes();
  }

  void _startTimer() {
    _currentSet = 1;
    _remaining = _durationSeconds;
    _isRest = false;
    _done = false;
    setState(() => _running = true);
    _tick();
  }

  void _tick() {
    if (!_running || !mounted) return;
    Future.delayed(const Duration(seconds: 1), () {
      if (!mounted || !_running) return;
      setState(() => _remaining--);

      if (_remaining == 3 && !_isRest) _beep();
      if (_remaining == 0) {
        if (!_isRest && _currentSet < _sets) {
          _beep(count: 2);
          setState(() {
            _isRest = true;
            _remaining = _restSeconds;
          });
          _tick();
        } else if (_isRest) {
          _currentSet++;
          if (_currentSet <= _sets) {
            _beep(count: 1);
            setState(() {
              _isRest = false;
              _remaining = _durationSeconds;
            });
            _tick();
          } else {
            _beep(count: 3);
            setState(() {
              _running = false;
              _done = true;
            });
          }
        } else {
          _beep(count: 3);
          setState(() {
            _running = false;
            _done = true;
          });
        }
      } else {
        _tick();
      }
    });
  }

  void _stopTimer() => setState(() => _running = false);

  void _reset() => setState(() {
        _running = false;
        _done = false;
        _currentSet = 0;
        _remaining = _durationSeconds;
        _isRest = false;
      });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 24 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Intervall-Timer',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),

          if (!_running && !_done) ...[
            // Config
            Row(
              children: [
                Expanded(
                  child: _TimerInput(
                    label: 'Sek. aktiv',
                    value: _durationSeconds,
                    onChanged: (v) => setState(() {
                      _durationSeconds = v;
                      _remaining = v;
                    }),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _TimerInput(
                    label: 'Sätze',
                    value: _sets,
                    onChanged: (v) => setState(() => _sets = v),
                    min: 1,
                    max: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _TimerInput(
                    label: 'Pause (s)',
                    value: _restSeconds,
                    onChanged: (v) => setState(() => _restSeconds = v),
                    min: 0,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _startTimer,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Starten'),
            ),
          ] else if (_done) ...[
            Icon(Icons.check_circle, color: Colors.green, size: 64),
            const SizedBox(height: 8),
            Text('Fertig! $_sets Sätze absolviert.',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            FilledButton(
                onPressed: _reset, child: const Text('Neu starten')),
          ] else ...[
            // Running
            Text(
              _isRest ? 'Pause' : 'Satz $_currentSet / $_sets',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(
                      color:
                          _isRest ? cs.secondary : cs.primary),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 120,
              width: 120,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CircularProgressIndicator(
                    value: _isRest
                        ? _remaining / _restSeconds
                        : _remaining / _durationSeconds,
                    strokeWidth: 8,
                    color: _isRest ? cs.secondary : cs.primary,
                    backgroundColor: cs.surfaceContainerHighest,
                  ),
                  Text(
                    '$_remaining',
                    style: Theme.of(context)
                        .textTheme
                        .headlineLarge
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _stopTimer,
              icon: const Icon(Icons.stop),
              label: const Text('Stopp'),
            ),
          ],
        ],
      ),
    );
  }
}

class _TimerInput extends StatelessWidget {
  final String label;
  final int value;
  final int min;
  final int? max;
  final void Function(int) onChanged;
  const _TimerInput(
      {required this.label,
      required this.value,
      required this.onChanged,
      this.min = 5,
      this.max});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label,
            style: Theme.of(context).textTheme.labelSmall),
        const SizedBox(height: 4),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.remove, size: 18),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onPressed: value > min
                  ? () => onChanged(value - (label.contains('s') ? 5 : 1))
                  : null,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text('$value',
                  style:
                      const TextStyle(fontWeight: FontWeight.bold)),
            ),
            IconButton(
              icon: const Icon(Icons.add, size: 18),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onPressed:
                  (max == null || value < max!)
                      ? () => onChanged(
                          value + (label.contains('s') ? 5 : 1))
                      : null,
            ),
          ],
        ),
      ],
    );
  }
}

// ── Set header / row ──────────────────────────────────────────────────────────

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
            child:
                Text('Satz', style: style, textAlign: TextAlign.center)),
        if (!isCardio) ...[
          const SizedBox(width: 8),
          SizedBox(
              width: 64,
              child:
                  Text('kg', style: style, textAlign: TextAlign.center)),
          const SizedBox(width: 8),
          SizedBox(
              width: 56,
              child: Text('Wdh',
                  style: style, textAlign: TextAlign.center)),
        ] else ...[
          const SizedBox(width: 8),
          SizedBox(
              width: 64,
              child: Text('Zeit',
                  style: style, textAlign: TextAlign.center)),
          const SizedBox(width: 8),
          SizedBox(
              width: 56,
              child:
                  Text('km', style: style, textAlign: TextAlign.center)),
        ],
        const SizedBox(width: 8),
        SizedBox(
            width: 44,
            child:
                Text('RPE', style: style, textAlign: TextAlign.center)),
      ],
    );
  }
}

class _SetRow extends ConsumerStatefulWidget {
  final WorkoutSet set;
  final bool isCardio;
  final String workoutId;
  const _SetRow(
      {required this.set,
      required this.isCardio,
      required this.workoutId});

  @override
  ConsumerState<_SetRow> createState() => _SetRowState();
}

class _SetRowState extends ConsumerState<_SetRow> {
  late TextEditingController _c1;
  late TextEditingController _c2;
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
            child: Text('${widget.set.setNumber}',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: cs.primary)),
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
              child: _NumField(ctrl: _rpe, hint: '–', onDone: _save)),
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
  State<_ExercisePickerSheet> createState() =>
      _ExercisePickerSheetState();
}

class _ExercisePickerSheetState
    extends State<_ExercisePickerSheet> {
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
                        onSelected: (_) => setState(
                            () => _cat = _cat == c ? null : c),
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
                  trailing: const Icon(Icons.chevron_right, size: 18),
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

// ── Exercise filter sheet ─────────────────────────────────────────────────────

// Sentinel: filter for exercises that have null equipment
const _kEquipNone = '__none__';

class _ExerciseFilterSheet extends StatefulWidget {
  final String? cat;
  final String? equipFilter;
  final String? diff;
  final bool favOnly;
  final bool thumbUpOnly;
  final int? minStar;
  final void Function({
    String? cat,
    String? equipFilter,
    String? diff,
    required bool favOnly,
    required bool thumbUpOnly,
    int? minStar,
  }) onChange;

  const _ExerciseFilterSheet({
    required this.cat,
    required this.equipFilter,
    required this.diff,
    required this.favOnly,
    required this.thumbUpOnly,
    required this.minStar,
    required this.onChange,
  });

  @override
  State<_ExerciseFilterSheet> createState() =>
      _ExerciseFilterSheetState();
}

class _ExerciseFilterSheetState extends State<_ExerciseFilterSheet> {
  late String? _cat;
  late String? _equipFilter;
  late String? _diff;
  late bool _favOnly;
  late bool _thumbUpOnly;
  late int? _minStar;

  @override
  void initState() {
    super.initState();
    _cat = widget.cat;
    _equipFilter = widget.equipFilter;
    _diff = widget.diff;
    _favOnly = widget.favOnly;
    _thumbUpOnly = widget.thumbUpOnly;
    _minStar = widget.minStar;
  }

  void _notify() => widget.onChange(
        cat: _cat,
        equipFilter: _equipFilter,
        diff: _diff,
        favOnly: _favOnly,
        thumbUpOnly: _thumbUpOnly,
        minStar: _minStar,
      );

  void _reset() {
    setState(() {
      _cat = null;
      _equipFilter = null;
      _diff = null;
      _favOnly = false;
      _thumbUpOnly = false;
      _minStar = null;
    });
    _notify();
  }

  Widget _equipChip(String? value) {
    final sentinel = value ?? _kEquipNone;
    return Padding(
      padding: const EdgeInsets.only(right: 6, bottom: 4),
      child: FilterChip(
        label: Text(_equipLabel(value)),
        selected: _equipFilter == sentinel,
        onSelected: (_) {
          setState(
              () => _equipFilter = _equipFilter == sentinel ? null : sentinel);
          _notify();
        },
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
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
              color: cs.onSurfaceVariant.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 4, 0),
            child: Row(
              children: [
                Text('Filter',
                    style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                TextButton(
                  onPressed: _reset,
                  child: const Text('Zurücksetzen'),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              controller: scrollCtrl,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                _FFilterTitle('Bewertung'),
                const SizedBox(height: 8),
                Wrap(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 6, bottom: 4),
                      child: FilterChip(
                        label: const Text('❤️ Favoriten'),
                        selected: _favOnly,
                        onSelected: (v) {
                          setState(() => _favOnly = v);
                          _notify();
                        },
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: 6, bottom: 4),
                      child: FilterChip(
                        label: const Text('👍 Empfohlen'),
                        selected: _thumbUpOnly,
                        onSelected: (v) {
                          setState(() => _thumbUpOnly = v);
                          _notify();
                        },
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: 6, bottom: 4),
                      child: FilterChip(
                        label: const Text('★ 4+'),
                        selected: _minStar == 4,
                        onSelected: (v) {
                          setState(() => _minStar = v ? 4 : null);
                          _notify();
                        },
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: 6, bottom: 4),
                      child: FilterChip(
                        label: const Text('★ 3+'),
                        selected: _minStar == 3,
                        onSelected: (v) {
                          setState(() => _minStar = v ? 3 : null);
                          _notify();
                        },
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _FFilterTitle('Kategorie'),
                const SizedBox(height: 8),
                Wrap(
                  children: _categories
                      .map((c) => Padding(
                            padding:
                                const EdgeInsets.only(right: 6, bottom: 4),
                            child: FilterChip(
                              label: Text(_catLabel(c)),
                              selected: _cat == c,
                              onSelected: (_) {
                                setState(() =>
                                    _cat = _cat == c ? null : c);
                                _notify();
                              },
                              visualDensity: VisualDensity.compact,
                            ),
                          ))
                      .toList(),
                ),
                const SizedBox(height: 16),
                _FFilterTitle('Equipment'),
                const SizedBox(height: 8),
                Wrap(
                  children: [
                    _equipChip('barbell'),
                    _equipChip('dumbbell'),
                    _equipChip('machine'),
                    _equipChip('bodyweight'),
                    _equipChip('cable'),
                    _equipChip('other'),
                    _equipChip(null),
                  ],
                ),
                const SizedBox(height: 16),
                _FFilterTitle('Schwierigkeit'),
                const SizedBox(height: 8),
                Wrap(
                  children: ['beginner', 'intermediate', 'advanced']
                      .map((d) => Padding(
                            padding:
                                const EdgeInsets.only(right: 6, bottom: 4),
                            child: FilterChip(
                              label: Text(_diffLabel(d)),
                              selected: _diff == d,
                              onSelected: (_) {
                                setState(() =>
                                    _diff = _diff == d ? null : d);
                                _notify();
                              },
                              visualDensity: VisualDensity.compact,
                            ),
                          ))
                      .toList(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FFilterTitle extends StatelessWidget {
  final String text;
  const _FFilterTitle(this.text);

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
      );
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
  String? _equipFilter; // null=off; _kEquipNone=null-equipment; else=value
  String? _diff;
  bool _favOnly = false;
  bool _thumbUpOnly = false;
  int? _minStar;

  bool get _hasFilter =>
      _cat != null ||
      _equipFilter != null ||
      _diff != null ||
      _favOnly ||
      _thumbUpOnly ||
      _minStar != null;

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(exercisesProvider).valueOrNull ?? [];
    final filtered = all
        .where((e) =>
            (_cat == null || e.category == _cat) &&
            (_equipFilter == null ||
                (_equipFilter == _kEquipNone
                    ? e.equipment == null
                    : e.equipment == _equipFilter)) &&
            (_diff == null || e.difficulty == _diff) &&
            (_query.isEmpty ||
                e.name.toLowerCase().contains(_query.toLowerCase())) &&
            (!_favOnly || e.isFavorite) &&
            (!_thumbUpOnly || e.thumbRating == 1) &&
            (_minStar == null || (e.starRating ?? 0) >= _minStar!))
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Übungsbibliothek'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: SearchBar(
                    hintText: 'Übung suchen…',
                    leading: const Icon(Icons.search),
                    onChanged: (v) => setState(() => _query = v),
                  ),
                ),
                const SizedBox(width: 8),
                Badge(
                  isLabelVisible: _hasFilter,
                  smallSize: 8,
                  child: IconButton.filledTonal(
                    icon: const Icon(Icons.tune),
                    tooltip: 'Filtern',
                    onPressed: () => _showFilterSheet(context),
                  ),
                ),
              ],
            ),
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
              [
                _catLabel(e.category),
                _equipLabel(e.equipment),
                if (e.difficulty != null) _diffLabel(e.difficulty),
              ].join(' · '),
              style: const TextStyle(fontSize: 12),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.chevron_right, size: 18),
                if (e.isCustom) ...[
                  const SizedBox(width: 4),
                  IconButton(
                    icon: Icon(Icons.delete_outline,
                        color:
                            Theme.of(context).colorScheme.error,
                        size: 20),
                    onPressed: () => ref
                        .read(workoutOpsProvider.notifier)
                        .deleteExercise(e.id),
                  ),
                ],
              ],
            ),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                  builder: (_) => ExerciseDetailScreen(exercise: e)),
            ),
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

  void _showFilterSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _ExerciseFilterSheet(
        cat: _cat,
        equipFilter: _equipFilter,
        diff: _diff,
        favOnly: _favOnly,
        thumbUpOnly: _thumbUpOnly,
        minStar: _minStar,
        onChange: ({
          String? cat,
          String? equipFilter,
          String? diff,
          required bool favOnly,
          required bool thumbUpOnly,
          int? minStar,
        }) {
          setState(() {
            _cat = cat;
            _equipFilter = equipFilter;
            _diff = diff;
            _favOnly = favOnly;
            _thumbUpOnly = thumbUpOnly;
            _minStar = minStar;
          });
        },
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
                initialValue: cat,
                decoration:
                    const InputDecoration(labelText: 'Kategorie'),
                items: _categories
                    .map((c) => DropdownMenuItem(
                        value: c, child: Text(_catLabel(c))))
                    .toList(),
                onChanged: (v) => setState(() => cat = v!),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                initialValue: equip,
                decoration:
                    const InputDecoration(labelText: 'Equipment'),
                items: const [
                  DropdownMenuItem(
                      value: null, child: Text('Kein Equipment')),
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

// ── Workout Plans Screen ──────────────────────────────────────────────────────

class WorkoutPlansScreen extends ConsumerWidget {
  const WorkoutPlansScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plansAsync = ref.watch(workoutPlansProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Trainingspläne')),
      body: plansAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Fehler: $e')),
        data: (plans) {
          if (plans.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.calendar_month_outlined,
                      size: 64,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurfaceVariant
                          .withValues(alpha: 0.4)),
                  const SizedBox(height: 16),
                  const Text('Noch keine Trainingspläne'),
                  const SizedBox(height: 8),
                  const Text(
                    'Erstelle einen Plan und plane deine\nWochen-Workouts im Voraus.',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            itemCount: plans.length,
            itemBuilder: (context, i) =>
                _PlanCard(plan: plans[i]),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _createPlan(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Neuer Plan'),
      ),
    );
  }

  Future<void> _createPlan(BuildContext context, WidgetRef ref) async {
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Neuer Trainingsplan'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                  labelText: 'Name *',
                  hintText: 'z.B. Anfänger Ganzkörper',
                  border: OutlineInputBorder()),
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descCtrl,
              decoration: const InputDecoration(
                  labelText: 'Beschreibung (optional)',
                  border: OutlineInputBorder()),
              maxLines: 2,
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
    );
    if (ok != true || !context.mounted) return;
    final name = nameCtrl.text.trim();
    if (name.isEmpty) return;
    final id = await ref
        .read(workoutOpsProvider.notifier)
        .createPlan(
            name: name,
            description: descCtrl.text.trim().isEmpty
                ? null
                : descCtrl.text.trim());
    if (context.mounted) {
      final plan =
          await ref.read(databaseProvider)!.workoutPlanById(id);
      if (plan != null && context.mounted) {
        Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => WorkoutPlanDetailScreen(plan: plan)));
      }
    }
  }
}

class _PlanCard extends ConsumerWidget {
  final WorkoutPlan plan;
  const _PlanCard({required this.plan});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final exercisesAsync = ref.watch(planExercisesProvider(plan.id));
    final exercises = ref.watch(exercisesProvider).valueOrNull ?? [];
    final exerciseMap = {for (final e in exercises) e.id: e};
    final cs = Theme.of(context).colorScheme;

    final byDay = <int, List<WorkoutPlanExercise>>{};
    for (final e in exercisesAsync.valueOrNull ?? []) {
      if (e.dayOfWeek != null) {
        byDay.putIfAbsent(e.dayOfWeek!, () => []).add(e);
      }
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            title: Text(plan.name,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: plan.description != null
                ? Text(plan.description!,
                    style: TextStyle(
                        color: cs.onSurfaceVariant, fontSize: 12))
                : null,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  tooltip: 'Plan bearbeiten',
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                        builder: (_) =>
                            WorkoutPlanDetailScreen(plan: plan)),
                  ),
                ),
                FilledButton.tonal(
                  onPressed: () => _startFromPlan(context, ref),
                  child: const Text('Starten'),
                ),
              ],
            ),
          ),
          if (byDay.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: List.generate(7, (d) {
                  final dayExercises = byDay[d] ?? [];
                  final hasTraining = dayExercises.isNotEmpty;
                  return Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Tooltip(
                      message: hasTraining
                          ? '${_weekDaysFull[d]}: ${dayExercises.map((e) => exerciseMap[e.exerciseId]?.name ?? '?').take(3).join(', ')}'
                          : _weekDaysFull[d],
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: hasTraining
                              ? cs.primaryContainer
                              : cs.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          _weekDays[d],
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: hasTraining
                                ? cs.onPrimaryContainer
                                : cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
          // Equipment chips
          Builder(builder: (_) {
            final allEquipment = (exercisesAsync.valueOrNull ?? [])
                .map((pe) => exerciseMap[pe.exerciseId]?.equipment)
                .whereType<String>()
                .toSet()
                .toList();
            if (allEquipment.isEmpty) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Wrap(
                spacing: 4,
                runSpacing: 4,
                children: allEquipment
                    .map((eq) => Chip(
                          label: Text(_equipLabel(eq),
                              style: const TextStyle(fontSize: 11)),
                          backgroundColor: cs.surfaceContainerHighest,
                          visualDensity: VisualDensity.compact,
                          padding:
                              const EdgeInsets.symmetric(horizontal: 4),
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ))
                    .toList(),
              ),
            );
          }),
        ],
      ),
    );
  }

  Future<void> _startFromPlan(BuildContext context, WidgetRef ref) async {
    final id = await ref
        .read(workoutOpsProvider.notifier)
        .startWorkoutFromPlan(plan);
    if (context.mounted) {
      Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => ActiveWorkoutScreen(workoutId: id)));
    }
  }
}

// ── Workout plan detail / editor ──────────────────────────────────────────────

class WorkoutPlanDetailScreen extends ConsumerWidget {
  final WorkoutPlan plan;
  const WorkoutPlanDetailScreen({super.key, required this.plan});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch plan reactively for live rating/favorite updates
    final plans = ref.watch(workoutPlansProvider).valueOrNull ?? [];
    final plan = plans
            .where((p) => p.id == this.plan.id)
            .firstOrNull ??
        this.plan;

    final exercisesAsync = ref.watch(planExercisesProvider(plan.id));
    final allExercises = ref.watch(exercisesProvider).valueOrNull ?? [];
    final exerciseMap = {for (final e in allExercises) e.id: e};
    final cs = Theme.of(context).colorScheme;

    final byDay = <int, List<WorkoutPlanExercise>>{};
    final templateExercises = <WorkoutPlanExercise>[];
    for (final e in exercisesAsync.valueOrNull ?? []) {
      if (e.dayOfWeek == null) {
        templateExercises.add(e);
      } else {
        byDay.putIfAbsent(e.dayOfWeek!, () => []).add(e);
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(plan.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Plan bearbeiten',
            onPressed: () => _editPlanInfo(context, ref, plan),
          ),
          IconButton(
            icon: Icon(plan.isFavorite
                ? Icons.favorite
                : Icons.favorite_border),
            color: plan.isFavorite ? Colors.red : null,
            tooltip: plan.isFavorite
                ? 'Aus Favoriten entfernen'
                : 'Zu Favoriten hinzufügen',
            onPressed: () => ref
                .read(workoutOpsProvider.notifier)
                .updatePlan(WorkoutPlansCompanion(
                  id: drift.Value(plan.id),
                  isFavorite: drift.Value(!plan.isFavorite),
                )),
          ),
          IconButton(
            icon: Icon(Icons.delete_outline, color: cs.error),
            onPressed: () => _deletePlan(context, ref, plan),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: [
          // ── Info header (description + notes) ─────────────────────────
          if (plan.description != null && plan.description!.isNotEmpty) ...[
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Icon(Icons.info_outline,
                          size: 14, color: cs.primary),
                      const SizedBox(width: 6),
                      Text('Beschreibung',
                          style: Theme.of(context)
                              .textTheme
                              .labelMedium
                              ?.copyWith(color: cs.primary)),
                    ]),
                    const SizedBox(height: 6),
                    Text(plan.description!,
                        style: Theme.of(context).textTheme.bodyMedium),
                  ],
                ),
              ),
            ),
          ],
          if (plan.notes != null && plan.notes!.isNotEmpty) ...[
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              color: cs.surfaceContainerHighest,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Icon(Icons.notes_outlined,
                          size: 14, color: cs.onSurfaceVariant),
                      const SizedBox(width: 6),
                      Text('Notizen',
                          style: Theme.of(context)
                              .textTheme
                              .labelMedium
                              ?.copyWith(color: cs.onSurfaceVariant)),
                    ]),
                    const SizedBox(height: 6),
                    Text(plan.notes!,
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: cs.onSurfaceVariant)),
                  ],
                ),
              ),
            ),
          ],
          if (plan.description == null && plan.notes == null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: OutlinedButton.icon(
                onPressed: () => _editPlanInfo(context, ref, plan),
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: const Text('Beschreibung & Notizen hinzufügen'),
                style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact),
              ),
            ),
          // ── Ratings ───────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _RatingRow(
              thumbRating: plan.thumbRating,
              starRating: plan.starRating,
              onThumb: (v) => ref
                  .read(workoutOpsProvider.notifier)
                  .updatePlan(WorkoutPlansCompanion(
                    id: drift.Value(plan.id),
                    thumbRating: drift.Value(v),
                  )),
              onStar: (v) => ref
                  .read(workoutOpsProvider.notifier)
                  .updatePlan(WorkoutPlansCompanion(
                    id: drift.Value(plan.id),
                    starRating: drift.Value(v),
                  )),
            ),
          ),
          // ── Day cards ─────────────────────────────────────────────────
          ...List.generate(7, (day) {
            final dayExercises = byDay[day] ?? [];
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          _weekDaysFull[day],
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(
                                  color: dayExercises.isNotEmpty
                                      ? cs.primary
                                      : cs.onSurfaceVariant),
                        ),
                        const Spacer(),
                        TextButton.icon(
                          onPressed: () => _addExerciseToDay(
                              context, ref, day, allExercises, plan),
                          icon: const Icon(Icons.add, size: 16),
                          label: const Text('Übung'),
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8),
                          ),
                        ),
                      ],
                    ),
                    if (dayExercises.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text('Ruhetag',
                            style: TextStyle(
                                color: cs.onSurfaceVariant,
                                fontSize: 12)),
                      )
                    else
                      ...dayExercises.map((pe) => _buildPlanExerciseTile(
                          context, ref, pe, exerciseMap, cs, plan)),
                  ],
                ),
              ),
            );
          }),
          // ── Template / always ─────────────────────────────────────────
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('Immer / Template',
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(color: cs.onSurfaceVariant)),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: () => _addExerciseToDay(
                            context, ref, null, allExercises, plan),
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('Übung'),
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8),
                        ),
                      ),
                    ],
                  ),
                  if (templateExercises.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('Keine Template-Übungen',
                          style: TextStyle(
                              color: cs.onSurfaceVariant, fontSize: 12)),
                    )
                  else
                    ...templateExercises.map((pe) =>
                        _buildPlanExerciseTile(
                            context, ref, pe, exerciseMap, cs, plan)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlanExerciseTile(
      BuildContext context,
      WidgetRef ref,
      WorkoutPlanExercise pe,
      Map<String, Exercise> exerciseMap,
      ColorScheme cs,
      WorkoutPlan plan) {
    final ex = exerciseMap[pe.exerciseId];
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: CircleAvatar(
        radius: 14,
        backgroundColor: cs.secondaryContainer,
        child: Text(
          _catLabel(ex?.category ?? '').substring(0, 1),
          style: TextStyle(fontSize: 11, color: cs.onSecondaryContainer),
        ),
      ),
      title: Text(ex?.name ?? pe.exerciseId,
          style: const TextStyle(fontSize: 13)),
      subtitle: () {
        final target = [
          if (pe.targetSets != null) '${pe.targetSets} Sätze',
          if (pe.targetReps != null) '${pe.targetReps} Wdh',
          if (pe.targetDurationSeconds != null)
            '${pe.targetDurationSeconds}s',
        ].join(' × ');
        final equip =
            ex?.equipment != null ? _equipLabel(ex!.equipment) : '';
        final label = [
          if (target.isNotEmpty) target,
          if (equip.isNotEmpty) equip,
        ].join(' · ');
        return Text(label,
            style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant));
      }(),
      trailing: IconButton(
        icon: const Icon(Icons.close, size: 16),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
        onPressed: () => ref
            .read(workoutOpsProvider.notifier)
            .removePlanExercise(pe.id, plan.id),
      ),
    );
  }

  Future<void> _addExerciseToDay(
      BuildContext context,
      WidgetRef ref,
      int? day,
      List<Exercise> allExercises,
      WorkoutPlan plan) async {
    final chosen = await showModalBottomSheet<Exercise>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _ExercisePickerSheet(exercises: allExercises),
    );
    if (chosen == null || !context.mounted) return;

    int? sets = 3;
    int? reps = 10;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(chosen.name),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(children: [
                const Text('Sätze: '),
                const Spacer(),
                IconButton(
                    icon: const Icon(Icons.remove, size: 18),
                    onPressed: () => setState(
                        () => sets = ((sets ?? 3) - 1).clamp(1, 20))),
                Text('${sets ?? 3}',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                IconButton(
                    icon: const Icon(Icons.add, size: 18),
                    onPressed: () => setState(
                        () => sets = ((sets ?? 3) + 1).clamp(1, 20))),
              ]),
              Row(children: [
                const Text('Wdh: '),
                const Spacer(),
                IconButton(
                    icon: const Icon(Icons.remove, size: 18),
                    onPressed: () => setState(
                        () => reps = ((reps ?? 10) - 1).clamp(1, 50))),
                Text('${reps ?? 10}',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                IconButton(
                    icon: const Icon(Icons.add, size: 18),
                    onPressed: () => setState(
                        () => reps = ((reps ?? 10) + 1).clamp(1, 50))),
              ]),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Abbrechen')),
            FilledButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Hinzufügen')),
          ],
        ),
      ),
    );

    await ref.read(workoutOpsProvider.notifier).addPlanExercise(
          planId: plan.id,
          exerciseId: chosen.id,
          dayOfWeek: day,
          targetSets: sets,
          targetReps: reps,
        );
  }

  Future<void> _editPlanInfo(
      BuildContext context, WidgetRef ref, WorkoutPlan plan) async {
    final nameCtrl = TextEditingController(text: plan.name);
    final descCtrl = TextEditingController(text: plan.description ?? '');
    final notesCtrl = TextEditingController(text: plan.notes ?? '');
    final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Plan bearbeiten'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Name *',
                        border: OutlineInputBorder()),
                    textCapitalization: TextCapitalization.sentences,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: descCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Beschreibung',
                        hintText: 'Ziel, Fokus, Zielgruppe …',
                        border: OutlineInputBorder()),
                    maxLines: 3,
                    textCapitalization: TextCapitalization.sentences,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: notesCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Notizen',
                        hintText: 'Equipment, Hinweise, persönliche Anmerkungen …',
                        border: OutlineInputBorder()),
                    maxLines: 4,
                    textCapitalization: TextCapitalization.sentences,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('Abbrechen')),
              FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: const Text('Speichern')),
            ],
          ),
        ) ??
        false;
    final name = nameCtrl.text.trim();
    final desc = descCtrl.text.trim();
    final notes = notesCtrl.text.trim();
    nameCtrl.dispose();
    descCtrl.dispose();
    notesCtrl.dispose();
    if (!ok || !context.mounted) return;
    if (name.isEmpty) return;
    await ref.read(workoutOpsProvider.notifier).updatePlan(
          WorkoutPlansCompanion(
            id: drift.Value(plan.id),
            name: drift.Value(name),
            description: drift.Value(desc.isEmpty ? null : desc),
            notes: drift.Value(notes.isEmpty ? null : notes),
          ),
        );
  }

  Future<void> _deletePlan(
      BuildContext context, WidgetRef ref, WorkoutPlan plan) async {
    final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Plan löschen?'),
            content: const Text(
                'Der Plan und alle zugehörigen Übungs-Slots werden unwiderruflich gelöscht.'),
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
      await ref.read(workoutOpsProvider.notifier).deletePlan(plan.id);
      if (context.mounted) Navigator.of(context).pop();
    }
  }
}
