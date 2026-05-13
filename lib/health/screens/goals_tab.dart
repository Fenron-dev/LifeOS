import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../db/database.dart';
import '../providers/nutrition_provider.dart';
import '../providers/profile_provider.dart';
import '../providers/water_provider.dart';
import '../providers/weight_provider.dart';
import '../providers/workouts_provider.dart';

class GoalsTab extends ConsumerWidget {
  const GoalsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(userProfileProvider).valueOrNull;
    final today = _today();
    final kcalTotals = ref.watch(dailyTotalsProvider(today)).valueOrNull;
    final waterMl = ref.watch(dailyWaterTotalProvider(today));
    final latestWeight = ref.watch(latestWeightLogProvider).valueOrNull;
    final workouts = ref.watch(workoutsProvider).valueOrNull ?? [];

    // Workouts this calendar week (Mon–Sun)
    final weekStart = _weekStart();
    final weeklyWorkouts = workouts
        .where((w) => !w.startedAt.isBefore(weekStart))
        .length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        _SectionHeader(
          title: 'Meine Ziele',
          trailing: FilledButton.tonalIcon(
            onPressed: () => _showEditSheet(context, ref, profile),
            icon: const Icon(Icons.edit_outlined, size: 16),
            label: const Text('Bearbeiten'),
            style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
                textStyle: const TextStyle(fontSize: 13)),
          ),
        ),
        const SizedBox(height: 12),

        // ── Weight goal ───────────────────────────────────────────────────
        _GoalCard(
          icon: Icons.monitor_weight_outlined,
          title: 'Gewichtsziel',
          child: _WeightGoalContent(
            current: latestWeight?.weightKg,
            start: profile?.startWeightKg,
            target: profile?.targetWeightKg,
          ),
        ),
        const SizedBox(height: 12),

        // ── Calorie goal ──────────────────────────────────────────────────
        _GoalCard(
          icon: Icons.local_fire_department_outlined,
          title: 'Kalorien heute',
          child: _ProgressGoalContent(
            current: kcalTotals?.kcal ?? 0,
            goal: profile?.dailyCalorieGoal?.toDouble(),
            unit: 'kcal',
            color: Colors.orange,
            goalHint: 'Ziel nicht gesetzt – im Profil festlegen',
          ),
        ),
        const SizedBox(height: 12),

        // ── Water goal ────────────────────────────────────────────────────
        _GoalCard(
          icon: Icons.water_drop_outlined,
          title: 'Wasser heute',
          child: _ProgressGoalContent(
            current: waterMl.toDouble(),
            goal: (profile?.dailyWaterGoalMl ?? 2000).toDouble(),
            unit: 'ml',
            color: Colors.blue,
          ),
        ),
        const SizedBox(height: 12),

        // ── Macro goals ───────────────────────────────────────────────────
        if (profile != null &&
            (profile.proteinTargetG != null ||
                profile.carbsTargetG != null ||
                profile.fatTargetG != null)) ...[
          _GoalCard(
            icon: Icons.pie_chart_outline,
            title: 'Makros heute',
            child: _MacroGoalContent(
              totals: kcalTotals,
              proteinTarget: profile.proteinTargetG,
              carbsTarget: profile.carbsTargetG,
              fatTarget: profile.fatTargetG,
            ),
          ),
          const SizedBox(height: 12),
        ],

        // ── Weekly workouts ───────────────────────────────────────────────
        _GoalCard(
          icon: Icons.fitness_center_outlined,
          title: 'Workouts diese Woche',
          child: _WorkoutGoalContent(
            count: weeklyWorkouts,
            goal: profile?.workoutsPerWeekGoal ?? 3,
            streak: _computeStreak(workouts, profile?.workoutsPerWeekGoal ?? 3),
          ),
        ),
      ],
    );
  }

  DateTime _today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  DateTime _weekStart() {
    final n = DateTime.now();
    final d = DateTime(n.year, n.month, n.day);
    return d.subtract(Duration(days: d.weekday - 1));
  }

  // Returns how many consecutive past weeks met the workout goal.
  int _computeStreak(List<Workout> workouts, int goal) {
    var streak = 0;
    var weekStart = _weekStart();
    // Check up to 52 weeks back
    for (var i = 0; i < 52; i++) {
      final weekEnd = weekStart.add(const Duration(days: 7));
      final count = workouts
          .where((w) =>
              !w.startedAt.isBefore(weekStart) && w.startedAt.isBefore(weekEnd))
          .length;
      // Current week is allowed to be incomplete
      if (i == 0) {
        weekStart = weekStart.subtract(const Duration(days: 7));
        streak = 0;
        continue;
      }
      if (count >= goal) {
        streak++;
        weekStart = weekStart.subtract(const Duration(days: 7));
      } else {
        break;
      }
    }
    return streak;
  }

  void _showEditSheet(
      BuildContext context, WidgetRef ref, UserProfileData? profile) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _GoalEditSheet(profile: profile),
    );
  }
}

// ── Goal card shell ───────────────────────────────────────────────────────────

class _GoalCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget child;
  const _GoalCard(
      {required this.icon, required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(title, style: theme.textTheme.titleSmall),
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;
  const _SectionHeader({required this.title, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const Spacer(),
        ?trailing,
      ],
    );
  }
}

// ── Weight goal content ───────────────────────────────────────────────────────

class _WeightGoalContent extends StatelessWidget {
  final double? current;
  final double? start;
  final double? target;
  const _WeightGoalContent(
      {required this.current, required this.start, required this.target});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    if (target == null) {
      return Text('Kein Zielgewicht gesetzt.',
          style: theme.textTheme.bodySmall?.copyWith(color: cs.outline));
    }

    final effectiveStart = start ?? current ?? target!;
    final currentVal = current ?? effectiveStart;
    final totalDelta = (effectiveStart - target!).abs();
    final done = totalDelta > 0
        ? ((effectiveStart - currentVal).abs() / totalDelta).clamp(0.0, 1.0)
        : 1.0;
    final losing = target! < effectiveStart;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  current != null ? '${_fmt(current!)} kg' : '– kg',
                  style: theme.textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                Text('Aktuell',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: cs.outline)),
              ],
            ),
            const Spacer(),
            Icon(
              losing ? Icons.trending_down : Icons.trending_up,
              color: losing ? Colors.green : Colors.orange,
              size: 28,
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${_fmt(target!)} kg',
                  style: theme.textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                Text('Ziel',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: cs.outline)),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: done,
            minHeight: 8,
            backgroundColor: cs.surfaceContainerHighest,
            valueColor: AlwaysStoppedAnimation(cs.primary),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '${(done * 100).toStringAsFixed(0)} % erreicht'
          '${totalDelta > 0 ? '  ·  ${_fmt((target! - currentVal).abs())} kg verbleibend' : ''}',
          style:
              theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        ),
      ],
    );
  }

  String _fmt(double v) =>
      v == v.truncateToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
}

// ── Progress goal content (kcal / water) ──────────────────────────────────────

class _ProgressGoalContent extends StatelessWidget {
  final double current;
  final double? goal;
  final String unit;
  final Color color;
  final String? goalHint;
  const _ProgressGoalContent({
    required this.current,
    required this.goal,
    required this.unit,
    required this.color,
    this.goalHint,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    if (goal == null || goal == 0) {
      return Text(
        goalHint ?? 'Ziel nicht gesetzt.',
        style: theme.textTheme.bodySmall?.copyWith(color: cs.outline),
      );
    }

    final progress = (current / goal!).clamp(0.0, 1.1);
    final over = current > goal!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              _fmt(current),
              style: theme.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            Text(
              ' / ${_fmt(goal!)} $unit',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: progress.clamp(0.0, 1.0),
            minHeight: 8,
            backgroundColor: cs.surfaceContainerHighest,
            valueColor: AlwaysStoppedAnimation(
                over ? cs.error : color),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          over
              ? '+${_fmt(current - goal!)} $unit über Ziel'
              : '${_fmt(goal! - current)} $unit verbleibend',
          style: theme.textTheme.bodySmall?.copyWith(
              color: over ? cs.error : cs.onSurfaceVariant),
        ),
      ],
    );
  }

  String _fmt(double v) =>
      v >= 1000
          ? '${(v / 1000).toStringAsFixed(1)} k'
          : v == v.truncateToDouble()
              ? v.toInt().toString()
              : v.toStringAsFixed(0);
}

// ── Macro goal content ────────────────────────────────────────────────────────

class _MacroGoalContent extends StatelessWidget {
  final DailyNutritionTotals? totals;
  final double? proteinTarget;
  final double? carbsTarget;
  final double? fatTarget;
  const _MacroGoalContent({
    required this.totals,
    required this.proteinTarget,
    required this.carbsTarget,
    required this.fatTarget,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (proteinTarget != null)
          _MacroRow(
            label: 'Eiweiß',
            current: totals?.proteinG ?? 0,
            target: proteinTarget!,
            color: Colors.red.shade400,
          ),
        if (carbsTarget != null)
          _MacroRow(
            label: 'Kohlenhydrate',
            current: totals?.carbsG ?? 0,
            target: carbsTarget!,
            color: Colors.amber.shade700,
          ),
        if (fatTarget != null)
          _MacroRow(
            label: 'Fett',
            current: totals?.fatG ?? 0,
            target: fatTarget!,
            color: Colors.blue.shade400,
          ),
      ],
    );
  }
}

class _MacroRow extends StatelessWidget {
  final String label;
  final double current;
  final double target;
  final Color color;
  const _MacroRow({
    required this.label,
    required this.current,
    required this.target,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final progress = (current / target).clamp(0.0, 1.0);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(label, style: theme.textTheme.bodyMedium),
              const Spacer(),
              Text(
                '${current.toStringAsFixed(0)} / ${target.toStringAsFixed(0)} g',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: cs.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Workout goal content ──────────────────────────────────────────────────────

class _WorkoutGoalContent extends StatelessWidget {
  final int count;
  final int goal;
  final int streak;
  const _WorkoutGoalContent(
      {required this.count, required this.goal, required this.streak});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final done = (count / goal).clamp(0.0, 1.0);
    final reached = count >= goal;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '$count / $goal',
              style: theme.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.bold, color: cs.primary),
            ),
            const SizedBox(width: 8),
            Text('Workouts diese Woche', style: theme.textTheme.bodyMedium),
            const Spacer(),
            if (streak > 0)
              Chip(
                avatar: const Icon(Icons.local_fire_department, size: 16,
                    color: Colors.deepOrange),
                label: Text('$streak ${streak == 1 ? 'Woche' : 'Wochen'}',
                    style: const TextStyle(fontSize: 12)),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                backgroundColor: Colors.deepOrange.withValues(alpha: 0.1),
              ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: done,
            minHeight: 8,
            backgroundColor: cs.surfaceContainerHighest,
            valueColor: AlwaysStoppedAnimation(reached ? Colors.green : cs.primary),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          reached
              ? 'Wochenziel erreicht!'
              : '${goal - count} ${goal - count == 1 ? 'Workout' : 'Workouts'} verbleibend',
          style: theme.textTheme.bodySmall?.copyWith(
              color: reached ? Colors.green : cs.onSurfaceVariant),
        ),
      ],
    );
  }
}

// ── Goal edit sheet ───────────────────────────────────────────────────────────

class _GoalEditSheet extends ConsumerStatefulWidget {
  final UserProfileData? profile;
  const _GoalEditSheet({required this.profile});

  @override
  ConsumerState<_GoalEditSheet> createState() => _GoalEditSheetState();
}

class _GoalEditSheetState extends ConsumerState<_GoalEditSheet> {
  late final TextEditingController _targetWeightCtrl;
  late final TextEditingController _kcalGoalCtrl;
  late final TextEditingController _waterGoalCtrl;
  late final TextEditingController _proteinCtrl;
  late final TextEditingController _carbsCtrl;
  late final TextEditingController _fatCtrl;
  late final TextEditingController _workoutsPerWeekCtrl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final p = widget.profile;
    _targetWeightCtrl = TextEditingController(
        text: p?.targetWeightKg != null ? _fmt(p!.targetWeightKg!) : '');
    _kcalGoalCtrl = TextEditingController(
        text: p?.dailyCalorieGoal?.toString() ?? '');
    _waterGoalCtrl = TextEditingController(
        text: (p?.dailyWaterGoalMl ?? 2000).toString());
    _proteinCtrl = TextEditingController(
        text: p?.proteinTargetG != null ? _fmt(p!.proteinTargetG!) : '');
    _carbsCtrl = TextEditingController(
        text: p?.carbsTargetG != null ? _fmt(p!.carbsTargetG!) : '');
    _fatCtrl = TextEditingController(
        text: p?.fatTargetG != null ? _fmt(p!.fatTargetG!) : '');
    _workoutsPerWeekCtrl = TextEditingController(
        text: (p?.workoutsPerWeekGoal ?? 3).toString());
  }

  @override
  void dispose() {
    _targetWeightCtrl.dispose();
    _kcalGoalCtrl.dispose();
    _waterGoalCtrl.dispose();
    _proteinCtrl.dispose();
    _carbsCtrl.dispose();
    _fatCtrl.dispose();
    _workoutsPerWeekCtrl.dispose();
    super.dispose();
  }

  String _fmt(double v) =>
      v == v.truncateToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

  double? _parse(TextEditingController c) =>
      c.text.trim().isEmpty ? null : double.tryParse(c.text.replaceAll(',', '.'));

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final kcal = int.tryParse(_kcalGoalCtrl.text.trim());
      final water = int.tryParse(_waterGoalCtrl.text.trim());
      final wPerWeek = int.tryParse(_workoutsPerWeekCtrl.text.trim());
      await ref.read(profileOpsProvider.notifier).save(
            targetWeightKg: Value(_parse(_targetWeightCtrl)),
            dailyCalorieGoal: Value(kcal),
            dailyWaterGoalMl:
                water != null ? Value(water) : const Value.absent(),
            proteinTargetG: Value(_parse(_proteinCtrl)),
            carbsTargetG: Value(_parse(_carbsCtrl)),
            fatTargetG: Value(_parse(_fatCtrl)),
            workoutsPerWeekGoal: wPerWeek != null
                ? Value(wPerWeek.clamp(1, 14))
                : const Value.absent(),
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
            Text('Ziele bearbeiten',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            TextFormField(
              controller: _targetWeightCtrl,
              decoration: const InputDecoration(
                labelText: 'Zielgewicht (kg)',
                prefixIcon: Icon(Icons.monitor_weight_outlined),
              ),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _kcalGoalCtrl,
              decoration: const InputDecoration(
                labelText: 'Kalorienziel (kcal/Tag)',
                prefixIcon: Icon(Icons.local_fire_department_outlined),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _waterGoalCtrl,
              decoration: const InputDecoration(
                labelText: 'Wasserziel (ml/Tag)',
                prefixIcon: Icon(Icons.water_drop_outlined),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _workoutsPerWeekCtrl,
              decoration: const InputDecoration(
                labelText: 'Trainings-Ziel (Workouts/Woche)',
                prefixIcon: Icon(Icons.fitness_center_outlined),
              ),
              keyboardType: TextInputType.number,
            ),
            const Divider(height: 24),
            Text('Makro-Ziele (g/Tag)',
                style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _proteinCtrl,
                    decoration: const InputDecoration(labelText: 'Eiweiß (g)'),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    controller: _carbsCtrl,
                    decoration:
                        const InputDecoration(labelText: 'Kohlenhydrate (g)'),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    controller: _fatCtrl,
                    decoration: const InputDecoration(labelText: 'Fett (g)'),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                  ),
                ),
              ],
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
