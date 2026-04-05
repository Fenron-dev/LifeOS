import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../db/database.dart';
import '../../providers/vault_provider.dart';

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

final weightLogsProvider = StreamProvider<List<BodyWeightLog>>((ref) {
  final db = ref.watch(databaseProvider);
  if (db == null) return const Stream.empty();
  return db.watchWeightLogs();
});

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class StatsScreen extends ConsumerWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Statistik')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: const [
          _WeightSection(),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Weight section
// ---------------------------------------------------------------------------

class _WeightSection extends ConsumerStatefulWidget {
  const _WeightSection();

  @override
  ConsumerState<_WeightSection> createState() => _WeightSectionState();
}

class _WeightSectionState extends ConsumerState<_WeightSection> {
  final _weightCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _weightCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final kg = double.tryParse(_weightCtrl.text.replaceAll(',', '.'));
    if (kg == null || kg <= 0) return;
    setState(() => _saving = true);
    try {
      final db = ref.read(databaseProvider)!;
      await db.insertWeightLog(BodyWeightLogsCompanion.insert(
        id: const Uuid().v4(),
        loggedAt: DateTime.now(),
        weightKg: kg,
        notes: _noteCtrl.text.trim().isEmpty
            ? const Value.absent()
            : Value(_noteCtrl.text.trim()),
      ));
      _weightCtrl.clear();
      _noteCtrl.clear();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final logsAsync = ref.watch(weightLogsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Körpergewicht', style: theme.textTheme.titleMedium),
        const SizedBox(height: 12),

        // Input card
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _weightCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Gewicht (kg)',
                      suffixText: 'kg',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _noteCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Notiz (optional)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Eintragen'),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 12),

        // Chart + list
        logsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Text('Fehler: $e'),
          data: (logs) {
            if (logs.isEmpty) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 24),
                    Icon(Icons.monitor_weight_outlined,
                        size: 64,
                        color: theme.colorScheme.outline),
                    const SizedBox(height: 8),
                    Text('Noch keine Einträge',
                        style: theme.textTheme.titleSmall),
                    const SizedBox(height: 4),
                    const Text('Trage dein Gewicht oben ein.'),
                    const SizedBox(height: 24),
                  ],
                ),
              );
            }

            // Chart shows last 30 entries, oldest first
            final chartData = logs.reversed.take(30).toList();
            return Column(
              children: [
                _WeightChart(logs: chartData),
                const SizedBox(height: 12),
                _WeightStats(logs: logs),
                const SizedBox(height: 12),
                ...logs.take(20).map((l) => _WeightTile(log: l)),
              ],
            );
          },
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Summary stats row
// ---------------------------------------------------------------------------

class _WeightStats extends StatelessWidget {
  final List<BodyWeightLog> logs;
  const _WeightStats({required this.logs});

  String _fmt(double v) =>
      v == v.truncateToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final weights = logs.map((l) => l.weightKg).toList();
    final current = weights.first;
    final min = weights.reduce(math.min);
    final max = weights.reduce(math.max);
    final avg = weights.reduce((a, b) => a + b) / weights.length;

    return Card(
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _StatItem(label: 'Aktuell', value: '${_fmt(current)} kg',
                theme: theme, primary: true),
            _StatItem(label: 'Min', value: '${_fmt(min)} kg', theme: theme),
            _StatItem(label: 'Max', value: '${_fmt(max)} kg', theme: theme),
            _StatItem(label: 'Ø', value: '${_fmt(avg)} kg', theme: theme),
          ],
        ),
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final String label;
  final String value;
  final ThemeData theme;
  final bool primary;
  const _StatItem(
      {required this.label,
      required this.value,
      required this.theme,
      this.primary = false});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(value,
            style: primary
                ? theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.bold)
                : theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer)),
        Text(label,
            style: theme.textTheme.labelSmall
                ?.copyWith(color: theme.colorScheme.onPrimaryContainer)),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Simple line chart (CustomPainter — no external library)
// ---------------------------------------------------------------------------

class _WeightChart extends StatelessWidget {
  final List<BodyWeightLog> logs; // oldest first
  const _WeightChart({required this.logs});

  @override
  Widget build(BuildContext context) {
    if (logs.length < 2) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
        child: SizedBox(
          height: 160,
          child: CustomPaint(
            painter: _WeightChartPainter(
              logs: logs,
              lineColor: Theme.of(context).colorScheme.primary,
              dotColor: Theme.of(context).colorScheme.primary,
              gridColor: Theme.of(context).colorScheme.outlineVariant,
              labelStyle: Theme.of(context).textTheme.labelSmall!,
            ),
          ),
        ),
      ),
    );
  }
}

class _WeightChartPainter extends CustomPainter {
  final List<BodyWeightLog> logs;
  final Color lineColor;
  final Color dotColor;
  final Color gridColor;
  final TextStyle labelStyle;

  const _WeightChartPainter({
    required this.logs,
    required this.lineColor,
    required this.dotColor,
    required this.gridColor,
    required this.labelStyle,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final weights = logs.map((l) => l.weightKg).toList();
    final minW = weights.reduce(math.min);
    final maxW = weights.reduce(math.max);
    final range = (maxW - minW).clamp(1.0, double.infinity);

    const padL = 44.0, padR = 8.0, padT = 8.0, padB = 28.0;
    final w = size.width - padL - padR;
    final h = size.height - padT - padB;

    double xOf(int i) => padL + i / (logs.length - 1) * w;
    double yOf(double v) => padT + (1 - (v - minW) / range) * h;

    // Grid lines (3)
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 0.5;
    for (var i = 0; i <= 2; i++) {
      final y = padT + i / 2 * h;
      canvas.drawLine(Offset(padL, y), Offset(padL + w, y), gridPaint);
      final label = (maxW - i / 2 * range).toStringAsFixed(1);
      _drawText(canvas, label, Offset(0, y - 6), labelStyle);
    }

    // Line
    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < logs.length - 1; i++) {
      canvas.drawLine(
        Offset(xOf(i), yOf(weights[i])),
        Offset(xOf(i + 1), yOf(weights[i + 1])),
        linePaint,
      );
    }

    // Dots + x-labels (show first, last, every ~7th)
    final dotPaint = Paint()..color = dotColor;
    for (var i = 0; i < logs.length; i++) {
      canvas.drawCircle(Offset(xOf(i), yOf(weights[i])), 3, dotPaint);
      final showLabel = i == 0 ||
          i == logs.length - 1 ||
          (logs.length > 7 && i % (logs.length ~/ 4) == 0);
      if (showLabel) {
        final date = DateFormat('d.M').format(logs[i].loggedAt);
        _drawText(
            canvas, date, Offset(xOf(i) - 10, size.height - padB + 4), labelStyle);
      }
    }
  }

  void _drawText(Canvas canvas, String text, Offset offset, TextStyle style) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: ui.TextDirection.ltr,
    )..layout();
    tp.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(_WeightChartPainter old) => old.logs != logs;
}

// ---------------------------------------------------------------------------
// Weight log tile
// ---------------------------------------------------------------------------

class _WeightTile extends ConsumerWidget {
  final BodyWeightLog log;
  const _WeightTile({required this.log});

  String _fmt(double v) =>
      v == v.truncateToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: const EdgeInsets.only(bottom: 4),
      child: ListTile(
        dense: true,
        leading: const Icon(Icons.monitor_weight_outlined),
        title: Text('${_fmt(log.weightKg)} kg'),
        subtitle: log.notes != null ? Text(log.notes!) : null,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              DateFormat('dd.MM.yy HH:mm').format(log.loggedAt),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 18),
              tooltip: 'Löschen',
              onPressed: () async {
                final db = ref.read(databaseProvider);
                await db?.deleteWeightLog(log.id);
              },
            ),
          ],
        ),
      ),
    );
  }
}
