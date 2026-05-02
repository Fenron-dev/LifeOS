import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../db/database.dart';
import '../providers/nutrition_provider.dart';

/// Aggregated consumption overview. Selectable period + sort field.
class NutritionHistoryScreen extends ConsumerStatefulWidget {
  const NutritionHistoryScreen({super.key});

  @override
  ConsumerState<NutritionHistoryScreen> createState() =>
      _NutritionHistoryScreenState();
}

class _NutritionHistoryScreenState
    extends ConsumerState<NutritionHistoryScreen> {
  _Period _period = _Period.week;
  _SortField _sort = _SortField.kcal;

  (DateTime, DateTime) get _range {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return switch (_period) {
      _Period.today => (today, today.add(const Duration(days: 1))),
      _Period.week => (today.subtract(Duration(days: today.weekday - 1)),
          today.add(const Duration(days: 1))),
      _Period.month => (DateTime(now.year, now.month, 1),
          today.add(const Duration(days: 1))),
      _Period.year => (DateTime(now.year, 1, 1),
          today.add(const Duration(days: 1))),
      _Period.all => (DateTime(2000), today.add(const Duration(days: 1))),
    };
  }

  @override
  Widget build(BuildContext context) {
    final range = _range;
    final logsAsync = ref.watch(nutritionLogsForRangeProvider(range));

    return Scaffold(
      appBar: AppBar(title: const Text('Verlauf & Übersicht')),
      body: Column(
        children: [
          _ControlBar(
            period: _period,
            sort: _sort,
            onPeriodChanged: (p) => setState(() => _period = p),
            onSortChanged: (s) => setState(() => _sort = s),
          ),
          Expanded(
            child: logsAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Fehler: $e')),
              data: (logs) => _HistoryList(
                logs: logs,
                sort: _sort,
                range: range,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Control bar ──────────────────────────────────────────────────────────────

class _ControlBar extends StatelessWidget {
  final _Period period;
  final _SortField sort;
  final ValueChanged<_Period> onPeriodChanged;
  final ValueChanged<_SortField> onSortChanged;

  const _ControlBar({
    required this.period,
    required this.sort,
    required this.onPeriodChanged,
    required this.onSortChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Period chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<_Period>(
              segments: const [
                ButtonSegment(value: _Period.today, label: Text('Heute')),
                ButtonSegment(value: _Period.week, label: Text('Woche')),
                ButtonSegment(value: _Period.month, label: Text('Monat')),
                ButtonSegment(value: _Period.year, label: Text('Jahr')),
                ButtonSegment(value: _Period.all, label: Text('Gesamt')),
              ],
              selected: {period},
              onSelectionChanged: (s) => onPeriodChanged(s.first),
            ),
          ),
          const SizedBox(height: 8),
          // Sort row
          Row(
            children: [
              Text('Sortieren nach:',
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(width: 8),
              ..._SortField.values.map((f) => Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(f.label),
                      selected: sort == f,
                      onSelected: (_) => onSortChanged(f),
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                    ),
                  )),
            ],
          ),
          const Divider(),
        ],
      ),
    );
  }
}

// ─── History list ─────────────────────────────────────────────────────────────

class _HistoryList extends StatelessWidget {
  final List<NutritionLog> logs;
  final _SortField sort;
  final (DateTime, DateTime) range;

  const _HistoryList({
    required this.logs,
    required this.sort,
    required this.range,
  });

  List<_AggEntry> _aggregate() {
    final map = <String, _AggEntry>{};
    for (final l in logs) {
      final key = l.itemId ?? l.productName;
      final e = map.putIfAbsent(
          key,
          () => _AggEntry(
                name: l.productName,
                brand: l.brand,
                source: l.source,
              ));
      e.count++;
      e.kcal += l.kcal ?? 0;
      e.protein += l.proteinG ?? 0;
      e.carbs += l.carbsG ?? 0;
      e.fat += l.fatG ?? 0;
      e.fiber += l.fiberG ?? 0;
    }
    final list = map.values.toList();
    list.sort((a, b) => switch (sort) {
          _SortField.kcal => b.kcal.compareTo(a.kcal),
          _SortField.protein => b.protein.compareTo(a.protein),
          _SortField.carbs => b.carbs.compareTo(a.carbs),
          _SortField.fat => b.fat.compareTo(a.fat),
          _SortField.name => a.name.compareTo(b.name),
        });
    return list;
  }

  @override
  Widget build(BuildContext context) {
    if (logs.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.restaurant_menu,
                size: 48,
                color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            const Text('Keine Einträge für diesen Zeitraum.'),
          ],
        ),
      );
    }

    final entries = _aggregate();
    final fmt0 =
        NumberFormat.decimalPattern('de_DE')..maximumFractionDigits = 0;
    final fmt1 =
        NumberFormat.decimalPattern('de_DE')..maximumFractionDigits = 1;

    // Total summary row
    final totalKcal = entries.fold(0.0, (s, e) => s + e.kcal);
    final totalProtein = entries.fold(0.0, (s, e) => s + e.protein);
    final totalCarbs = entries.fold(0.0, (s, e) => s + e.carbs);
    final totalFat = entries.fold(0.0, (s, e) => s + e.fat);

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 32),
      itemCount: entries.length + 1,
      itemBuilder: (ctx, i) {
        if (i == 0) {
          return _TotalCard(
            kcal: totalKcal,
            protein: totalProtein,
            carbs: totalCarbs,
            fat: totalFat,
            fmt0: fmt0,
            fmt1: fmt1,
            entryCount: logs.length,
            range: range,
          );
        }
        final e = entries[i - 1];
        final cs = Theme.of(ctx).colorScheme;
        final sortValue = switch (sort) {
          _SortField.kcal => '${fmt0.format(e.kcal)} kcal',
          _SortField.protein => '${fmt1.format(e.protein)} g Protein',
          _SortField.carbs => '${fmt1.format(e.carbs)} g KH',
          _SortField.fat => '${fmt1.format(e.fat)} g Fett',
          _SortField.name => '${fmt0.format(e.kcal)} kcal',
        };
        return Card(
          margin: const EdgeInsets.only(bottom: 6),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: e.source == 'recipe'
                  ? cs.tertiaryContainer
                  : cs.primaryContainer,
              child: Icon(
                e.source == 'recipe'
                    ? Icons.menu_book_outlined
                    : Icons.restaurant_outlined,
                size: 18,
                color: e.source == 'recipe'
                    ? cs.onTertiaryContainer
                    : cs.onPrimaryContainer,
              ),
            ),
            title: Text(e.name),
            subtitle: Row(
              children: [
                if (e.brand != null)
                  Text('${e.brand!} · ',
                      style: TextStyle(
                          color: cs.onSurfaceVariant, fontSize: 12)),
                Text('${e.count}×',
                    style:
                        TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
              ],
            ),
            trailing: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(sortValue,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                if (sort != _SortField.kcal && sort != _SortField.name)
                  Text('${fmt0.format(e.kcal)} kcal',
                      style: TextStyle(
                          fontSize: 11, color: cs.onSurfaceVariant)),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ─── Summary card ─────────────────────────────────────────────────────────────

class _TotalCard extends StatelessWidget {
  final double kcal, protein, carbs, fat;
  final NumberFormat fmt0, fmt1;
  final int entryCount;
  final (DateTime, DateTime) range;

  const _TotalCard({
    required this.kcal,
    required this.protein,
    required this.carbs,
    required this.fat,
    required this.fmt0,
    required this.fmt1,
    required this.entryCount,
    required this.range,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      color: cs.primaryContainer,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('${fmt0.format(kcal)} kcal',
                    style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        color: cs.onPrimaryContainer)),
                const Spacer(),
                Text('$entryCount Einträge',
                    style: TextStyle(
                        color: cs.onPrimaryContainer.withValues(alpha: 0.7),
                        fontSize: 12)),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _MacroCol('Protein', '${fmt1.format(protein)} g',
                    cs.onPrimaryContainer),
                _MacroCol('Kohlenhydrate', '${fmt1.format(carbs)} g',
                    cs.onPrimaryContainer),
                _MacroCol('Fett', '${fmt1.format(fat)} g',
                    cs.onPrimaryContainer),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MacroCol extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _MacroCol(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Text(value,
              style: TextStyle(fontWeight: FontWeight.w600, color: color)),
          Text(label,
              style: TextStyle(
                  fontSize: 11, color: color.withValues(alpha: 0.7))),
        ],
      );
}

// ─── Models ───────────────────────────────────────────────────────────────────

class _AggEntry {
  final String name;
  final String? brand;
  final String source;
  int count = 0;
  double kcal = 0, protein = 0, carbs = 0, fat = 0, fiber = 0;
  _AggEntry({required this.name, this.brand, required this.source});
}

enum _Period { today, week, month, year, all }

enum _SortField {
  kcal('Kalorien'),
  protein('Protein'),
  carbs('Kohlenhydrate'),
  fat('Fett'),
  name('Name');

  final String label;
  const _SortField(this.label);
}
