import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../db/database.dart';
import '../providers/profile_provider.dart';
import '../providers/weight_provider.dart';
import '../widgets/weight_entry_sheet.dart';

/// Phase 6.1 — weight tab. Shows current weight on top, a 90-day fl_chart
/// line plot, the Erfassungsquote (count of distinct days with a log in the
/// last 28 days) and a list of recent entries. FAB opens the entry sheet
/// where body-fat / muscle / visceral can also be captured.
class WeightTab extends ConsumerWidget {
  const WeightTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logsAsync = ref.watch(weightLogsProvider(180));
    final latestAsync = ref.watch(latestWeightLogProvider);
    final daysCountAsync = ref.watch(weightLogDayCountProvider(28));
    final profile = ref.watch(userProfileProvider).valueOrNull;

    return Scaffold(
      body: logsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Fehler: $e')),
        data: (logs) {
          if (logs.isEmpty) {
            return _EmptyState(onAdd: () => _openEntry(context, ref));
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              _CurrentWeightCard(
                latest: latestAsync.valueOrNull,
                profile: profile,
              ),
              const SizedBox(height: 16),
              _ChartCard(logs: logs, profile: profile),
              const SizedBox(height: 16),
              _QuotaCard(
                logsLast28: daysCountAsync.valueOrNull ?? 0,
              ),
              const SizedBox(height: 16),
              _LogList(logs: logs.take(20).toList()),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEntry(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Wiegen'),
      ),
    );
  }

  void _openEntry(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const WeightEntrySheet(),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.monitor_weight_outlined, size: 56, color: cs.outline),
            const SizedBox(height: 12),
            const Text('Noch keine Wiegungen erfasst',
                style: TextStyle(fontSize: 18)),
            const SizedBox(height: 4),
            Text(
              'Tippe auf „Wiegen", um den ersten Eintrag hinzuzufügen.',
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: const Text('Erste Wiegung'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CurrentWeightCard extends StatelessWidget {
  final BodyWeightLog? latest;
  final UserProfileData? profile;
  const _CurrentWeightCard({required this.latest, required this.profile});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fmtKg =
        NumberFormat.decimalPattern('de_DE')..maximumFractionDigits = 1;
    final start = profile?.startWeightKg;
    final target = profile?.targetWeightKg;
    final lost = (start != null && latest != null) ? start - latest!.weightKg : null;
    final remaining =
        (target != null && latest != null) ? latest!.weightKg - target : null;

    return Card(
      color: cs.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Aktuelles Gewicht',
                style: TextStyle(color: cs.onPrimaryContainer)),
            const SizedBox(height: 8),
            if (latest != null)
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    fmtKg.format(latest!.weightKg),
                    style: TextStyle(
                      fontSize: 56,
                      fontWeight: FontWeight.w600,
                      color: cs.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('kg',
                      style: TextStyle(
                          fontSize: 24, color: cs.onPrimaryContainer)),
                ],
              )
            else
              Text('—',
                  style: TextStyle(
                      fontSize: 56,
                      fontWeight: FontWeight.w600,
                      color: cs.onPrimaryContainer)),
            const SizedBox(height: 4),
            if (latest != null)
              Text(
                'Zuletzt: ${DateFormat.yMMMMd('de_DE').add_Hm().format(latest!.loggedAt)}',
                style: TextStyle(
                    color: cs.onPrimaryContainer.withValues(alpha: 0.8)),
              ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _MetaRow(
                    label: 'Start',
                    value: start == null ? '—' : '${fmtKg.format(start)} kg',
                    color: cs.onPrimaryContainer,
                  ),
                ),
                Expanded(
                  child: _MetaRow(
                    label: 'Ziel',
                    value: target == null ? '—' : '${fmtKg.format(target)} kg',
                    color: cs.onPrimaryContainer,
                  ),
                ),
              ],
            ),
            if (lost != null || remaining != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _MetaRow(
                      label: 'Abgenommen',
                      value: lost == null
                          ? '—'
                          : '${fmtKg.format(lost)} kg',
                      color: cs.onPrimaryContainer,
                    ),
                  ),
                  Expanded(
                    child: _MetaRow(
                      label: 'Verbleibend',
                      value: remaining == null
                          ? '—'
                          : '${fmtKg.format(remaining < 0 ? 0 : remaining)} kg',
                      color: cs.onPrimaryContainer,
                    ),
                  ),
                ],
              ),
            ],
            if (latest != null && _hasComposition(latest!)) ...[
              const Divider(height: 24),
              Wrap(
                spacing: 24,
                runSpacing: 8,
                children: [
                  if (latest!.bodyFatPct != null)
                    _CompoChip(
                      label: 'KFA',
                      value: '${fmtKg.format(latest!.bodyFatPct!)} %',
                    ),
                  if (latest!.muscleMassPct != null)
                    _CompoChip(
                      label: 'Muskel',
                      value: '${fmtKg.format(latest!.muscleMassPct!)} %',
                    ),
                  if (latest!.visceralFat != null)
                    _CompoChip(
                      label: 'Visceral',
                      value: fmtKg.format(latest!.visceralFat!),
                    ),
                  if (latest!.waterPct != null)
                    _CompoChip(
                      label: 'Wasser',
                      value: '${fmtKg.format(latest!.waterPct!)} %',
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  bool _hasComposition(BodyWeightLog l) =>
      l.bodyFatPct != null ||
      l.muscleMassPct != null ||
      l.visceralFat != null ||
      l.waterPct != null;
}

class _MetaRow extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _MetaRow(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: color.withValues(alpha: 0.7))),
        Text(value,
            style: TextStyle(
                color: color, fontWeight: FontWeight.w600, fontSize: 16)),
      ],
    );
  }
}

class _CompoChip extends StatelessWidget {
  final String label;
  final String value;
  const _CompoChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label,
            style: TextStyle(
                color: cs.onPrimaryContainer.withValues(alpha: 0.7),
                fontSize: 12)),
        Text(value,
            style: TextStyle(
                color: cs.onPrimaryContainer,
                fontWeight: FontWeight.w600,
                fontSize: 16)),
      ],
    );
  }
}

class _ChartCard extends StatelessWidget {
  final List<BodyWeightLog> logs;
  final UserProfileData? profile;
  const _ChartCard({required this.logs, required this.profile});

  @override
  Widget build(BuildContext context) {
    if (logs.length < 2) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            'Mindestens zwei Wiegungen für den Verlauf nötig.',
            style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ),
      );
    }

    final cs = Theme.of(context).colorScheme;
    // Logs come newest-first; chart needs ascending time.
    final ordered = logs.reversed.toList();
    final spots = <FlSpot>[
      for (var i = 0; i < ordered.length; i++)
        FlSpot(ordered[i].loggedAt.millisecondsSinceEpoch.toDouble(),
            ordered[i].weightKg),
    ];

    final weights = ordered.map((l) => l.weightKg).toList();
    var minY = weights.reduce((a, b) => a < b ? a : b);
    var maxY = weights.reduce((a, b) => a > b ? a : b);
    final start = profile?.startWeightKg;
    final target = profile?.targetWeightKg;
    if (start != null) {
      if (start < minY) minY = start;
      if (start > maxY) maxY = start;
    }
    if (target != null) {
      if (target < minY) minY = target;
      if (target > maxY) maxY = target;
    }
    // Comfortable padding so points don't sit on the axes.
    final pad = ((maxY - minY).abs() * 0.1).clamp(0.5, 5.0);
    minY -= pad;
    maxY += pad;

    final minX = spots.first.x;
    final maxX = spots.last.x;
    final spanDays =
        ((maxX - minX) / Duration.millisecondsPerDay).clamp(1, 365 * 10);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Verlauf', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            SizedBox(
              height: 220,
              child: LineChart(
                LineChartData(
                  minY: minY,
                  maxY: maxY,
                  minX: minX,
                  maxX: maxX,
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: ((maxY - minY) / 4).clamp(0.5, 50.0),
                    getDrawingHorizontalLine: (_) => FlLine(
                      color: cs.outlineVariant,
                      strokeWidth: 1,
                      dashArray: const [4, 4],
                    ),
                  ),
                  titlesData: FlTitlesData(
                    show: true,
                    rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 40,
                        getTitlesWidget: (v, _) => Text(
                          v.toStringAsFixed(0),
                          style: TextStyle(
                              fontSize: 11, color: cs.onSurfaceVariant),
                        ),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 28,
                        interval: (maxX - minX) / 4,
                        getTitlesWidget: (v, _) {
                          final d =
                              DateTime.fromMillisecondsSinceEpoch(v.toInt());
                          final fmt = spanDays > 90
                              ? DateFormat.MMM('de_DE')
                              : DateFormat.Md('de_DE');
                          return Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              fmt.format(d),
                              style: TextStyle(
                                  fontSize: 11,
                                  color: cs.onSurfaceVariant),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  extraLinesData: ExtraLinesData(
                    horizontalLines: [
                      if (start != null)
                        HorizontalLine(
                          y: start,
                          color: cs.error.withValues(alpha: 0.6),
                          strokeWidth: 1,
                          dashArray: const [4, 4],
                          label: HorizontalLineLabel(
                            show: true,
                            alignment: Alignment.topRight,
                            style: TextStyle(
                                color: cs.error, fontSize: 11),
                            labelResolver: (_) => 'Start',
                          ),
                        ),
                      if (target != null)
                        HorizontalLine(
                          y: target,
                          color: cs.primary.withValues(alpha: 0.6),
                          strokeWidth: 1,
                          dashArray: const [4, 4],
                          label: HorizontalLineLabel(
                            show: true,
                            alignment: Alignment.bottomRight,
                            style: TextStyle(
                                color: cs.primary, fontSize: 11),
                            labelResolver: (_) => 'Ziel',
                          ),
                        ),
                    ],
                  ),
                  lineBarsData: [
                    LineChartBarData(
                      spots: spots,
                      isCurved: true,
                      curveSmoothness: 0.2,
                      color: cs.primary,
                      barWidth: 3,
                      dotData: FlDotData(
                        show: spots.length <= 30,
                        getDotPainter: (s, p, b, i) => FlDotCirclePainter(
                          radius: 3,
                          color: cs.primary,
                          strokeColor: cs.surface,
                          strokeWidth: 1,
                        ),
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
        ),
      ),
    );
  }
}

class _QuotaCard extends StatelessWidget {
  final int logsLast28;
  const _QuotaCard({required this.logsLast28});

  @override
  Widget build(BuildContext context) {
    final pct = (logsLast28 / 28).clamp(0.0, 1.0);
    final cs = Theme.of(context).colorScheme;
    final encouragement = switch (logsLast28) {
      0 => 'Noch nichts erfasst — der erste Schritt zählt.',
      < 7 => 'Guter Anfang. Wieg dich regelmäßig für aussagekräftige Trends.',
      < 14 => 'Solide Routine. Weiter so!',
      < 21 => 'Sehr konstant — die Trendlinie wird zuverlässig.',
      _ => 'Top-Disziplin. Die Daten sind aussagekräftig.',
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.calendar_month, color: cs.primary),
                const SizedBox(width: 8),
                Text(
                  '$logsLast28 von 28 Tagen erfasst',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: pct,
                minHeight: 8,
                backgroundColor: cs.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation(cs.primary),
              ),
            ),
            const SizedBox(height: 8),
            Text(encouragement,
                style: TextStyle(color: cs.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

class _LogList extends ConsumerWidget {
  final List<BodyWeightLog> logs;
  const _LogList({required this.logs});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final fmt = NumberFormat.decimalPattern('de_DE')..maximumFractionDigits = 1;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Text('Letzte Einträge',
                  style: Theme.of(context).textTheme.titleMedium),
            ),
            const Divider(height: 1),
            ...logs.map((l) {
              final extras = <String>[
                if (l.bodyFatPct != null) 'KFA ${fmt.format(l.bodyFatPct)} %',
                if (l.muscleMassPct != null)
                  'Muskel ${fmt.format(l.muscleMassPct)} %',
                if (l.visceralFat != null)
                  'Visc ${fmt.format(l.visceralFat)}',
              ];
              return Dismissible(
                key: ValueKey(l.id),
                background: Container(
                  color: cs.error,
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Icon(Icons.delete, color: cs.onError),
                ),
                direction: DismissDirection.endToStart,
                confirmDismiss: (_) async {
                  return await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Eintrag löschen?'),
                          content: const Text(
                              'Diese Wiegung wird unwiderruflich entfernt.'),
                          actions: [
                            TextButton(
                                onPressed: () =>
                                    Navigator.of(ctx).pop(false),
                                child: const Text('Abbrechen')),
                            FilledButton(
                                onPressed: () =>
                                    Navigator.of(ctx).pop(true),
                                child: const Text('Löschen')),
                          ],
                        ),
                      ) ??
                      false;
                },
                onDismissed: (_) =>
                    ref.read(weightOpsProvider.notifier).deleteLog(l.id),
                child: ListTile(
                  title: Text('${fmt.format(l.weightKg)} kg'),
                  subtitle: Text(
                    [
                      DateFormat.yMMMd('de_DE').add_Hm().format(l.loggedAt),
                      if (extras.isNotEmpty) extras.join(' · '),
                    ].join('\n'),
                    style: TextStyle(color: cs.onSurfaceVariant),
                  ),
                  isThreeLine: extras.isNotEmpty,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        tooltip: 'Löschen',
                        onPressed: () async {
                          final ok = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('Eintrag löschen?'),
                              content: const Text(
                                  'Diese Wiegung wird unwiderruflich entfernt.'),
                              actions: [
                                TextButton(
                                    onPressed: () =>
                                        Navigator.of(ctx).pop(false),
                                    child: const Text('Abbrechen')),
                                FilledButton(
                                    onPressed: () =>
                                        Navigator.of(ctx).pop(true),
                                    child: const Text('Löschen')),
                              ],
                            ),
                          );
                          if (ok == true) {
                            ref
                                .read(weightOpsProvider.notifier)
                                .deleteLog(l.id);
                          }
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.edit_outlined),
                        tooltip: 'Bearbeiten',
                        onPressed: () => showModalBottomSheet<void>(
                          context: context,
                          isScrollControlled: true,
                          builder: (_) => WeightEntrySheet(editLog: l),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}
