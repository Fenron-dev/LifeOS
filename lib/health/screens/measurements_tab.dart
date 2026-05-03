import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../db/database.dart';
import '../providers/measurements_provider.dart';
import '../widgets/measurement_entry_sheet.dart';

/// Phase 6.2 — Körpermaße tab. Shows a per-metric trend chart with chip
/// selector, a summary card with the latest value for every metric, and a
/// swipe-to-delete log list. FAB opens the measurement entry sheet.
class MeasurementsTab extends ConsumerStatefulWidget {
  const MeasurementsTab({super.key});

  @override
  ConsumerState<MeasurementsTab> createState() => _MeasurementsTabState();
}

/// Descriptor for each metric that can be charted / displayed.
class _Metric {
  final String label;
  final double? Function(BodyMeasurement) extract;

  const _Metric({required this.label, required this.extract});
}

final _metrics = <_Metric>[
  _Metric(label: 'Brust', extract: (m) => m.chestCm),
  _Metric(label: 'Taille', extract: (m) => m.waistCm),
  _Metric(label: 'Hüfte', extract: (m) => m.hipCm),
  _Metric(label: 'Oberschenkel', extract: (m) => m.thighCm),
  _Metric(label: 'Arm', extract: (m) => m.armCm),
  _Metric(label: 'Nacken', extract: (m) => m.neckCm),
];

class _MeasurementsTabState extends ConsumerState<MeasurementsTab> {
  int _selectedMetricIndex = 0;

  @override
  Widget build(BuildContext context) {
    final logsAsync = ref.watch(bodyMeasurementsProvider(180));
    final latestAsync = ref.watch(latestBodyMeasurementProvider);

    return Scaffold(
      body: logsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Fehler: $e')),
        data: (logs) {
          if (logs.isEmpty) {
            return _EmptyState(onAdd: () => _openEntry(context));
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              _SummaryCard(latest: latestAsync.valueOrNull),
              const SizedBox(height: 16),
              _MetricChips(
                selectedIndex: _selectedMetricIndex,
                onSelected: (i) => setState(() => _selectedMetricIndex = i),
              ),
              const SizedBox(height: 8),
              _ChartCard(
                logs: logs,
                metric: _metrics[_selectedMetricIndex],
              ),
              const SizedBox(height: 16),
              _LogList(logs: logs.take(20).toList()),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEntry(context),
        icon: const Icon(Icons.add),
        label: const Text('Messen'),
      ),
    );
  }

  void _openEntry(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const MeasurementEntrySheet(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

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
            Icon(Icons.straighten, size: 56, color: cs.outline),
            const SizedBox(height: 12),
            const Text('Noch keine Maße erfasst',
                style: TextStyle(fontSize: 18)),
            const SizedBox(height: 4),
            Text(
              'Tippe auf „Messen", um den ersten Eintrag hinzuzufügen.',
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: const Text('Erste Messung'),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _SummaryCard extends StatelessWidget {
  final BodyMeasurement? latest;
  const _SummaryCard({required this.latest});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fmt = NumberFormat.decimalPattern('de_DE')
      ..maximumFractionDigits = 1;

    String fmtCm(double? v) => v == null ? '—' : '${fmt.format(v)} cm';

    return Card(
      color: cs.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.straighten, color: cs.onSecondaryContainer),
                const SizedBox(width: 8),
                Text(
                  'Aktuelle Maße',
                  style: TextStyle(
                      color: cs.onSecondaryContainer,
                      fontWeight: FontWeight.w600,
                      fontSize: 16),
                ),
                if (latest != null) ...[
                  const Spacer(),
                  Text(
                    DateFormat.yMMMd('de_DE').format(latest!.loggedAt),
                    style: TextStyle(
                        color: cs.onSecondaryContainer.withValues(alpha: 0.7),
                        fontSize: 12),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                    child: _MetaItem(
                        label: 'Brust',
                        value: fmtCm(latest?.chestCm),
                        cs: cs)),
                Expanded(
                    child: _MetaItem(
                        label: 'Taille',
                        value: fmtCm(latest?.waistCm),
                        cs: cs)),
                Expanded(
                    child: _MetaItem(
                        label: 'Hüfte',
                        value: fmtCm(latest?.hipCm),
                        cs: cs)),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                    child: _MetaItem(
                        label: 'Oberschenkel',
                        value: fmtCm(latest?.thighCm),
                        cs: cs)),
                Expanded(
                    child: _MetaItem(
                        label: 'Arm',
                        value: fmtCm(latest?.armCm),
                        cs: cs)),
                Expanded(
                    child: _MetaItem(
                        label: 'Nacken',
                        value: fmtCm(latest?.neckCm),
                        cs: cs)),
              ],
            ),
            if (latest == null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Noch keine Messung erfasst.',
                  style: TextStyle(
                      color: cs.onSecondaryContainer.withValues(alpha: 0.7),
                      fontSize: 12),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MetaItem extends StatelessWidget {
  final String label;
  final String value;
  final ColorScheme cs;
  const _MetaItem(
      {required this.label, required this.value, required this.cs});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(
                color: cs.onSecondaryContainer.withValues(alpha: 0.7),
                fontSize: 11)),
        Text(value,
            style: TextStyle(
                color: cs.onSecondaryContainer,
                fontWeight: FontWeight.w600,
                fontSize: 15)),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _MetricChips extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  const _MetricChips(
      {required this.selectedIndex, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < _metrics.length; i++)
            Padding(
              padding: EdgeInsets.only(right: i < _metrics.length - 1 ? 8 : 0),
              child: ChoiceChip(
                label: Text(_metrics[i].label),
                selected: selectedIndex == i,
                onSelected: (_) => onSelected(i),
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _ChartCard extends StatelessWidget {
  final List<BodyMeasurement> logs;
  final _Metric metric;
  const _ChartCard({required this.logs, required this.metric});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // Only entries with a value for the selected metric.
    final relevant = logs.reversed
        .where((m) => metric.extract(m) != null)
        .toList();

    if (relevant.length < 2) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            'Mindestens zwei Messungen für den ${metric.label}-Verlauf nötig.',
            style:
                TextStyle(color: cs.onSurfaceVariant),
          ),
        ),
      );
    }

    final spots = <FlSpot>[
      for (final m in relevant)
        FlSpot(m.loggedAt.millisecondsSinceEpoch.toDouble(),
            metric.extract(m)!),
    ];

    final values = relevant.map((m) => metric.extract(m)!).toList();
    var minY = values.reduce((a, b) => a < b ? a : b);
    var maxY = values.reduce((a, b) => a > b ? a : b);
    final pad = ((maxY - minY).abs() * 0.1).clamp(0.5, 10.0);
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
            Text('${metric.label}-Verlauf',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            SizedBox(
              height: 200,
              child: LineChart(
                LineChartData(
                  minY: minY,
                  maxY: maxY,
                  minX: minX,
                  maxX: maxX,
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval:
                        ((maxY - minY) / 4).clamp(0.5, 50.0),
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
                        reservedSize: 42,
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
                  lineBarsData: [
                    LineChartBarData(
                      spots: spots,
                      isCurved: true,
                      curveSmoothness: 0.2,
                      color: cs.tertiary,
                      barWidth: 3,
                      dotData: FlDotData(
                        show: spots.length <= 30,
                        getDotPainter: (s, p, b, i) => FlDotCirclePainter(
                          radius: 3,
                          color: cs.tertiary,
                          strokeColor: cs.surface,
                          strokeWidth: 1,
                        ),
                      ),
                      belowBarData: BarAreaData(
                        show: true,
                        color: cs.tertiary.withValues(alpha: 0.1),
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

// ─────────────────────────────────────────────────────────────────────────────

class _LogList extends ConsumerWidget {
  final List<BodyMeasurement> logs;
  const _LogList({required this.logs});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final fmt =
        NumberFormat.decimalPattern('de_DE')..maximumFractionDigits = 1;

    String fmtVal(double? v, String unit) =>
        v == null ? '' : '${fmt.format(v)} $unit';

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
            ...logs.map((m) {
              final parts = <String>[
                if (m.chestCm != null) 'Brust ${fmtVal(m.chestCm, 'cm')}',
                if (m.waistCm != null) 'Taille ${fmtVal(m.waistCm, 'cm')}',
                if (m.hipCm != null) 'Hüfte ${fmtVal(m.hipCm, 'cm')}',
                if (m.thighCm != null) 'OS ${fmtVal(m.thighCm, 'cm')}',
                if (m.armCm != null) 'Arm ${fmtVal(m.armCm, 'cm')}',
                if (m.neckCm != null) 'Nacken ${fmtVal(m.neckCm, 'cm')}',
              ];
              return Dismissible(
                key: ValueKey(m.id),
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
                              'Diese Messung wird unwiderruflich entfernt.'),
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
                onDismissed: (_) => ref
                    .read(measurementsOpsProvider.notifier)
                    .deleteLog(m.id),
                child: ListTile(
                  title: Text(
                    DateFormat.yMMMd('de_DE').add_Hm().format(m.loggedAt),
                  ),
                  subtitle: parts.isEmpty
                      ? null
                      : Text(
                          parts.join(' · '),
                          style: TextStyle(color: cs.onSurfaceVariant),
                        ),
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
                                  'Diese Messung wird unwiderruflich entfernt.'),
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
                                .read(measurementsOpsProvider.notifier)
                                .deleteLog(m.id);
                          }
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.edit_outlined),
                        tooltip: 'Bearbeiten',
                        onPressed: () => showModalBottomSheet<void>(
                          context: context,
                          isScrollControlled: true,
                          builder: (_) => MeasurementEntrySheet(editLog: m),
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
