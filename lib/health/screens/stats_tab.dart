import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../db/database.dart';
import '../providers/nutrition_provider.dart';
import '../providers/profile_provider.dart';
import '../providers/weight_provider.dart';
import '../providers/workouts_provider.dart';
import '../utils/weekly_report.dart';

// ── Period selector ───────────────────────────────────────────────────────────

enum _Period { d30, d90, d365 }

extension _PeriodExt on _Period {
  int get days => switch (this) { _Period.d30 => 30, _Period.d90 => 90, _Period.d365 => 365 };
  String get label => switch (this) { _Period.d30 => '30 T', _Period.d90 => '90 T', _Period.d365 => '1 J' };
}

// ── Tab root ──────────────────────────────────────────────────────────────────

class StatsTab extends ConsumerStatefulWidget {
  const StatsTab({super.key});

  @override
  ConsumerState<StatsTab> createState() => _StatsTabState();
}

class _StatsTabState extends ConsumerState<StatsTab> {
  _Period _period = _Period.d30;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final weightLogs = ref.watch(weightLogsProvider(365)).valueOrNull ?? [];
    final workouts = ref.watch(workoutsProvider).valueOrNull ?? [];
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final cutoffRaw = today.subtract(Duration(days: _period.days));
    final cutoff = DateTime(cutoffRaw.year, cutoffRaw.month, cutoffRaw.day);

    final filteredWeight = weightLogs
        .where((l) => l.loggedAt.isAfter(cutoff))
        .toList()
      ..sort((a, b) => a.loggedAt.compareTo(b.loggedAt));

    final filteredWorkouts =
        workouts.where((w) => w.startedAt.isAfter(cutoff)).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        // Period selector
        Row(
          children: [
            Text('Zeitraum', style: theme.textTheme.titleMedium),
            const Spacer(),
            SegmentedButton<_Period>(
              segments: _Period.values
                  .map((p) => ButtonSegment(value: p, label: Text(p.label)))
                  .toList(),
              selected: {_period},
              onSelectionChanged: (s) => setState(() => _period = s.first),
              style: SegmentedButton.styleFrom(
                visualDensity: VisualDensity.compact,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),

        // ── Deine Woche (F7) ───────────────────────────────────────────────
        const _WeeklyReportCard(),
        const SizedBox(height: 16),

        // ── Weight trend ───────────────────────────────────────────────────
        _StatCard(
          icon: Icons.monitor_weight_outlined,
          title: 'Gewichtsverlauf',
          child: filteredWeight.length < 2
              ? _EmptyChart(
                  message: 'Noch nicht genug Daten für den gewählten Zeitraum.')
              : _WeightChart(logs: filteredWeight),
        ),
        const SizedBox(height: 16),

        // ── Workout frequency ──────────────────────────────────────────────
        _StatCard(
          icon: Icons.fitness_center_outlined,
          title: 'Trainingsfrequenz (pro Woche)',
          child: filteredWorkouts.isEmpty
              ? _EmptyChart(message: 'Keine Workouts im gewählten Zeitraum.')
              : _WorkoutFrequencyChart(
                  workouts: filteredWorkouts,
                  period: _period,
                  cutoff: cutoff,
                ),
        ),
        const SizedBox(height: 16),

        // ── Kcal trend ────────────────────────────────────────────────────
        _KcalTrendCard(cutoff: cutoff, period: _period, cs: cs),
        const SizedBox(height: 16),

        // ── Summary stats ──────────────────────────────────────────────────
        _SummaryRow(
          weightLogs: filteredWeight,
          workouts: filteredWorkouts,
          period: _period,
          cs: cs,
        ),
      ],
    );
  }
}

// ── Deine Woche (F7) ─────────────────────────────────────────────────────────

class _WeeklyReportCard extends ConsumerWidget {
  const _WeeklyReportCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final weekStart = today.subtract(const Duration(days: 6));

    final dailyTotals = <DailyNutritionTotals?>[
      for (var i = 0; i < 7; i++)
        ref
            .watch(dailyTotalsProvider(weekStart.add(Duration(days: i))))
            .valueOrNull,
    ];
    final proteinTarget =
        ref.watch(userProfileProvider).valueOrNull?.proteinTargetG;
    final weightLogs = (ref.watch(weightLogsProvider(30)).valueOrNull ?? [])
        .where((l) => !l.loggedAt.isBefore(weekStart))
        .toList();
    final workouts = (ref.watch(workoutsProvider).valueOrNull ?? [])
        .where((w) => !w.startedAt.isBefore(weekStart))
        .length;

    final report = WeeklyReport.compute(
      dailyTotals: dailyTotals,
      proteinTargetG: proteinTarget,
      weightLogsInWeek: weightLogs,
      workoutCount: workouts,
    );
    if (report.isEmpty) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;
    String fmtDelta(double d) =>
        '${d >= 0 ? '+' : ''}${d.toStringAsFixed(1)} kg';

    return _StatCard(
      icon: Icons.calendar_view_week_outlined,
      title: 'Deine Woche',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              _WeekStat(
                label: 'Ø kcal (${report.daysLogged} Tage)',
                value: report.daysLogged == 0
                    ? '—'
                    : report.avgKcal.toStringAsFixed(0),
              ),
              if (report.hasProteinTarget)
                _WeekStat(
                  label: 'Protein-Ziel',
                  value: '${report.proteinTargetHits}/${report.daysLogged}',
                ),
              _WeekStat(
                label: 'Gewicht',
                value: report.weightDeltaKg != null
                    ? fmtDelta(report.weightDeltaKg!)
                    : '—',
              ),
              _WeekStat(label: 'Workouts', value: '${report.workoutCount}'),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Letzte 7 Tage',
            style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _WeekStat extends StatelessWidget {
  final String label;
  final String value;
  const _WeekStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: Theme.of(context).textTheme.titleMedium),
        Text(label,
            style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
      ],
    );
  }
}

// ── Card shell ────────────────────────────────────────────────────────────────

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget child;
  const _StatCard({required this.icon, required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text(title, style: theme.textTheme.titleSmall),
            ]),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}

class _EmptyChart extends StatelessWidget {
  final String message;
  const _EmptyChart({required this.message});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 120,
      child: Center(
        child: Text(message,
            textAlign: TextAlign.center,
            style: TextStyle(color: Theme.of(context).colorScheme.outline)),
      ),
    );
  }
}

// ── Weight chart ──────────────────────────────────────────────────────────────

class _WeightChart extends StatelessWidget {
  final List<dynamic> logs; // BodyWeightLog
  const _WeightChart({required this.logs});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final weights = logs.map((l) => l.weightKg as double).toList();
    final minW = (weights.reduce((a, b) => a < b ? a : b) - 1).floorToDouble();
    final maxW = (weights.reduce((a, b) => a > b ? a : b) + 1).ceilToDouble();

    final spots = <FlSpot>[];
    for (var i = 0; i < logs.length; i++) {
      spots.add(FlSpot(i.toDouble(), logs[i].weightKg as double));
    }

    final fmt = DateFormat('dd.MM');

    return SizedBox(
      height: 180,
      child: LineChart(
        LineChartData(
          minY: minW,
          maxY: maxW,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (_) =>
                FlLine(color: cs.outlineVariant, strokeWidth: 0.5),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 40,
                getTitlesWidget: (v, _) => Text('${v.toStringAsFixed(0)} kg',
                    style: TextStyle(
                        fontSize: 10, color: cs.onSurfaceVariant)),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 22,
                interval: (spots.length / 4).ceilToDouble().clamp(1, 9999),
                getTitlesWidget: (v, _) {
                  final idx = v.toInt();
                  if (idx < 0 || idx >= logs.length) return const SizedBox();
                  return Text(fmt.format(logs[idx].loggedAt as DateTime),
                      style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant));
                },
              ),
            ),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              color: cs.primary,
              barWidth: 2,
              dotData: FlDotData(
                getDotPainter: (_, _, _, _) => FlDotCirclePainter(
                    radius: 3, color: cs.primary, strokeWidth: 0),
              ),
              belowBarData: BarAreaData(
                show: true,
                color: cs.primary.withValues(alpha: 0.1),
              ),
            ),
          ],
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipItems: (spots) => spots
                  .map((s) => LineTooltipItem(
                        '${s.y.toStringAsFixed(1)} kg\n${fmt.format(logs[s.x.toInt()].loggedAt as DateTime)}',
                        TextStyle(color: cs.onSurface, fontSize: 12),
                      ))
                  .toList(),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Workout frequency chart ───────────────────────────────────────────────────

class _WorkoutFrequencyChart extends StatelessWidget {
  final List<dynamic> workouts;
  final _Period period;
  final DateTime cutoff;
  const _WorkoutFrequencyChart(
      {required this.workouts, required this.period, required this.cutoff});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // Build week buckets from cutoff to now
    final now = DateTime.now();
    final weeks = <DateTime>[];
    var cursor =
        cutoff.subtract(Duration(days: cutoff.weekday - 1)); // Monday of cutoff week
    while (cursor.isBefore(now) || cursor.isAtSameMomentAs(now)) {
      weeks.add(cursor);
      cursor = cursor.add(const Duration(days: 7));
    }

    final counts = <int>[];
    for (final weekStart in weeks) {
      final weekEnd = weekStart.add(const Duration(days: 7));
      final c = workouts
          .where((w) =>
              !(w.startedAt as DateTime).isBefore(weekStart) &&
              (w.startedAt as DateTime).isBefore(weekEnd))
          .length;
      counts.add(c);
    }

    final maxCount = counts.isEmpty ? 1 : counts.reduce((a, b) => a > b ? a : b);
    final fmt = DateFormat('dd.MM');

    final bars = <BarChartGroupData>[];
    for (var i = 0; i < weeks.length; i++) {
      bars.add(BarChartGroupData(
        x: i,
        barRods: [
          BarChartRodData(
            toY: counts[i].toDouble(),
            color: counts[i] > 0 ? cs.primary : cs.surfaceContainerHighest,
            width: weeks.length > 12 ? 8 : 16,
            borderRadius: BorderRadius.circular(4),
          ),
        ],
      ));
    }

    return SizedBox(
      height: 160,
      child: BarChart(
        BarChartData(
          maxY: (maxCount + 1).toDouble(),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (_) =>
                FlLine(color: cs.outlineVariant, strokeWidth: 0.5),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 24,
                interval: 1,
                getTitlesWidget: (v, _) {
                  if (v != v.truncateToDouble()) return const SizedBox();
                  return Text(v.toInt().toString(),
                      style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant));
                },
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 22,
                interval: weeks.length <= 6
                    ? 1
                    : weeks.length <= 13
                        ? 2
                        : 4,
                getTitlesWidget: (v, _) {
                  final idx = v.toInt();
                  if (idx < 0 || idx >= weeks.length) return const SizedBox();
                  return Text(fmt.format(weeks[idx]),
                      style: TextStyle(fontSize: 9, color: cs.onSurfaceVariant));
                },
              ),
            ),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          barGroups: bars,
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipItem: (group, _, rod, _) {
                final n = rod.toY.toInt();
                return BarTooltipItem(
                  'KW ${fmt.format(weeks[group.x])}\n$n ${n == 1 ? 'Workout' : 'Workouts'}',
                  TextStyle(color: cs.onSurface, fontSize: 12),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

// ── Kcal trend card ───────────────────────────────────────────────────────────

class _KcalTrendCard extends ConsumerWidget {
  final DateTime cutoff;
  final _Period period;
  final ColorScheme cs;
  const _KcalTrendCard(
      {required this.cutoff, required this.period, required this.cs});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    final logsAsync = ref.watch(
        nutritionLogsForRangeProvider((cutoff, tomorrow)));

    return _StatCard(
      icon: Icons.local_fire_department_outlined,
      title: 'Kalorien-Verlauf',
      child: logsAsync.when(
        loading: () => const SizedBox(
            height: 120, child: Center(child: CircularProgressIndicator())),
        error: (_, _) => _EmptyChart(message: 'Fehler beim Laden.'),
        data: (logs) {
          // Group by day
          final byDay = <DateTime, double>{};
          for (final log in logs) {
            final day = DateTime(log.loggedAt.year, log.loggedAt.month,
                log.loggedAt.day);
            byDay[day] = (byDay[day] ?? 0) + (log.kcal ?? 0);
          }
          if (byDay.length < 2) {
            return _EmptyChart(
                message: 'Noch nicht genug Daten für den gewählten Zeitraum.');
          }
          final sortedDays = byDay.keys.toList()..sort();
          final spots = sortedDays
              .asMap()
              .entries
              .map((e) => FlSpot(e.key.toDouble(), byDay[e.value]!))
              .toList();
          final maxKcal =
              byDay.values.reduce((a, b) => a > b ? a : b) * 1.15;
          final fmt = DateFormat('dd.MM');

          return SizedBox(
            height: 180,
            child: LineChart(
              LineChartData(
                minY: 0,
                maxY: maxKcal,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (_) =>
                      FlLine(color: cs.outlineVariant, strokeWidth: 0.5),
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 44,
                      getTitlesWidget: (v, _) => Text(
                          '${(v / 1000).toStringAsFixed(1)}k',
                          style: TextStyle(
                              fontSize: 10, color: cs.onSurfaceVariant)),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 22,
                      interval:
                          (sortedDays.length / 5).ceilToDouble().clamp(1, 9999),
                      getTitlesWidget: (v, _) {
                        final idx = v.toInt();
                        if (idx < 0 || idx >= sortedDays.length) {
                          return const SizedBox();
                        }
                        return Text(fmt.format(sortedDays[idx]),
                            style: TextStyle(
                                fontSize: 10, color: cs.onSurfaceVariant));
                      },
                    ),
                  ),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    color: Colors.orange,
                    barWidth: 2,
                    dotData: FlDotData(
                      getDotPainter: (_, _, _, _) => FlDotCirclePainter(
                          radius: 3, color: Colors.orange, strokeWidth: 0),
                    ),
                    belowBarData: BarAreaData(
                      show: true,
                      color: Colors.orange.withValues(alpha: 0.1),
                    ),
                  ),
                ],
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipItems: (pts) => pts
                        .map((s) => LineTooltipItem(
                              '${s.y.toStringAsFixed(0)} kcal\n${fmt.format(sortedDays[s.x.toInt()])}',
                              TextStyle(color: cs.onSurface, fontSize: 12),
                            ))
                        .toList(),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ── Summary row ───────────────────────────────────────────────────────────────

class _SummaryRow extends StatelessWidget {
  final List<dynamic> weightLogs;
  final List<dynamic> workouts;
  final _Period period;
  final ColorScheme cs;
  const _SummaryRow({
    required this.weightLogs,
    required this.workouts,
    required this.period,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    double? weightDelta;
    if (weightLogs.length >= 2) {
      weightDelta = (weightLogs.last.weightKg as double) -
          (weightLogs.first.weightKg as double);
    }

    final totalWorkouts = workouts.length;
    final weeks = period.days / 7;
    final avgPerWeek = weeks > 0 ? totalWorkouts / weeks : 0.0;

    final totalMinutes = workouts.fold<int>(
        0, (sum, w) => sum + ((w.durationMinutes as int?) ?? 0));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.bar_chart, size: 18, color: cs.primary),
              const SizedBox(width: 8),
              Text('Zusammenfassung', style: theme.textTheme.titleSmall),
            ]),
            const SizedBox(height: 16),
            Row(
              children: [
                _SumTile(
                  label: 'Gewicht\nVeränderung',
                  value: weightDelta == null
                      ? '–'
                      : '${weightDelta >= 0 ? '+' : ''}${weightDelta.toStringAsFixed(1)} kg',
                  color: weightDelta == null
                      ? cs.outline
                      : weightDelta < 0
                          ? Colors.green
                          : Colors.orange,
                ),
                _SumTile(
                  label: 'Workouts\nGesamt',
                  value: '$totalWorkouts',
                  color: cs.primary,
                ),
                _SumTile(
                  label: 'Ø Workouts\npro Woche',
                  value: avgPerWeek.toStringAsFixed(1),
                  color: cs.secondary,
                ),
                _SumTile(
                  label: 'Trainings-\nzeit (min)',
                  value: '$totalMinutes',
                  color: cs.tertiary,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SumTile extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _SumTile(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        children: [
          Text(value,
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 4),
          Text(label,
              textAlign: TextAlign.center,
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}
