import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../db/database.dart';
import '../providers/nutrition_provider.dart';
import '../providers/profile_provider.dart';
import '../widgets/diary_entry_sheet.dart';

/// Phase 6.4 — Ernährungstagebuch. Shows a day-picker, per-meal-slot sections
/// and a daily macro summary. FAB and per-slot "+" buttons open
/// [DiaryEntrySheet].
class DiaryTab extends ConsumerStatefulWidget {
  const DiaryTab({super.key});

  @override
  ConsumerState<DiaryTab> createState() => _DiaryTabState();
}

class _DiaryTabState extends ConsumerState<DiaryTab> {
  DateTime _day = _today();

  static DateTime _today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  void _prevDay() => setState(() => _day = _day.subtract(const Duration(days: 1)));
  void _nextDay() {
    final next = _day.add(const Duration(days: 1));
    if (!next.isAfter(_today())) setState(() => _day = next);
  }

  bool get _isToday => _day == _today();

  @override
  Widget build(BuildContext context) {
    final logsAsync = ref.watch(nutritionLogsForDayProvider(_day));
    final totalsAsync = ref.watch(dailyTotalsProvider(_day));
    final mealTypes = ref.watch(mealTypesProvider).valueOrNull ?? [];
    final profile = ref.watch(userProfileProvider).valueOrNull;

    return Scaffold(
      body: Column(
        children: [
          // ── Day navigation ───────────────────────────────────────────────
          _DayNavBar(
            day: _day,
            isToday: _isToday,
            onPrev: _prevDay,
            onNext: _isToday ? null : _nextDay,
          ),
          // ── Content ──────────────────────────────────────────────────────
          Expanded(
            child: logsAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Fehler: $e')),
              data: (logs) => _DiaryBody(
                day: _day,
                logs: logs,
                totals: totalsAsync.valueOrNull,
                mealTypes: mealTypes,
                calorieGoal: profile?.dailyCalorieGoal?.toDouble(),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEntry(context),
        icon: const Icon(Icons.add),
        label: const Text('Hinzufügen'),
      ),
    );
  }

  void _openEntry(BuildContext context, {String? mealTypeId}) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => DiaryEntrySheet(
        initialMealTypeId: mealTypeId,
        initialLoggedAt: _isToday
            ? null
            : DateTime(_day.year, _day.month, _day.day, 12, 0),
      ),
    );
  }
}

// ─── Day navigation bar ───────────────────────────────────────────────────────

class _DayNavBar extends StatelessWidget {
  final DateTime day;
  final bool isToday;
  final VoidCallback onPrev;
  final VoidCallback? onNext;

  const _DayNavBar({
    required this.day,
    required this.isToday,
    required this.onPrev,
    this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final label = isToday
        ? 'Heute'
        : DateFormat.yMMMMd('de_DE').format(day);

    return Container(
      color: cs.surfaceContainerLow,
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: onPrev,
            tooltip: 'Vorheriger Tag',
          ),
          Expanded(
            child: GestureDetector(
              onTap: isToday
                  ? null
                  : () {
                      // nothing — could open date picker in future
                    },
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: isToday ? cs.primary : null,
                      fontWeight:
                          isToday ? FontWeight.w700 : FontWeight.normal,
                    ),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: onNext,
            tooltip: 'Nächster Tag',
          ),
        ],
      ),
    );
  }
}

// ─── Main diary body ──────────────────────────────────────────────────────────

class _DiaryBody extends ConsumerWidget {
  final DateTime day;
  final List<NutritionLog> logs;
  final DailyNutritionTotals? totals;
  final List<MealType> mealTypes;
  final double? calorieGoal;

  const _DiaryBody({
    required this.day,
    required this.logs,
    required this.totals,
    required this.mealTypes,
    this.calorieGoal,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Partition logs by meal type (null → "Sonstiges" slot)
    final byMealType = <String?, List<NutritionLog>>{};
    for (final log in logs) {
      byMealType.putIfAbsent(log.mealTypeId, () => []).add(log);
    }

    // Build sections in meal-type order, then one for unassigned
    final sections = <Widget>[];

    for (final mt in mealTypes) {
      final slotLogs = byMealType[mt.id] ?? [];
      sections.add(_MealSection(
        mealTypeId: mt.id,
        label: mt.name,
        logs: slotLogs,
        day: day,
      ));
    }

    // Entries with no meal type
    final unassigned = byMealType[null] ?? [];
    if (unassigned.isNotEmpty) {
      sections.add(_MealSection(
        mealTypeId: null,
        label: 'Weitere',
        logs: unassigned,
        day: day,
      ));
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        _DailyTotalsCard(totals: totals, calorieGoal: calorieGoal),
        const SizedBox(height: 16),
        if (logs.isEmpty)
          _EmptyDay(day: day)
        else
          ...sections,
      ],
    );
  }
}

// ─── Daily totals card ────────────────────────────────────────────────────────

class _DailyTotalsCard extends StatelessWidget {
  final DailyNutritionTotals? totals;
  final double? calorieGoal;

  const _DailyTotalsCard({required this.totals, this.calorieGoal});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fmt0 =
        NumberFormat.decimalPattern('de_DE')..maximumFractionDigits = 0;
    final fmt1 =
        NumberFormat.decimalPattern('de_DE')..maximumFractionDigits = 1;

    final kcal = totals?.kcal ?? 0;
    final protein = totals?.proteinG ?? 0;
    final carbs = totals?.carbsG ?? 0;
    final fat = totals?.fatG ?? 0;

    final pct =
        calorieGoal != null && calorieGoal! > 0 ? (kcal / calorieGoal!).clamp(0.0, 1.0) : null;

    return Card(
      color: cs.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  fmt0.format(kcal),
                  style: TextStyle(
                    fontSize: 40,
                    fontWeight: FontWeight.w700,
                    color: cs.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  calorieGoal != null
                      ? '/ ${fmt0.format(calorieGoal)} kcal'
                      : 'kcal',
                  style: TextStyle(
                      fontSize: 16, color: cs.onPrimaryContainer),
                ),
              ],
            ),
            if (pct != null) ...[
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: pct,
                  minHeight: 6,
                  backgroundColor:
                      cs.onPrimaryContainer.withValues(alpha: 0.2),
                  valueColor: AlwaysStoppedAnimation(
                    pct >= 1.0 ? cs.error : cs.onPrimaryContainer,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _MacroCell(
                    label: 'Protein',
                    value: '${fmt1.format(protein)} g',
                    cs: cs),
                _MacroCell(
                    label: 'Kohlenhydrate',
                    value: '${fmt1.format(carbs)} g',
                    cs: cs),
                _MacroCell(
                    label: 'Fett',
                    value: '${fmt1.format(fat)} g',
                    cs: cs),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MacroCell extends StatelessWidget {
  final String label;
  final String value;
  final ColorScheme cs;
  const _MacroCell(
      {required this.label, required this.value, required this.cs});

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value,
              style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: cs.onPrimaryContainer)),
          Text(label,
              style: TextStyle(
                  fontSize: 11,
                  color: cs.onPrimaryContainer.withValues(alpha: 0.8))),
        ],
      );
}

// ─── Meal section ─────────────────────────────────────────────────────────────

class _MealSection extends ConsumerWidget {
  final String? mealTypeId;
  final String label;
  final List<NutritionLog> logs;
  final DateTime day;

  const _MealSection({
    required this.mealTypeId,
    required this.label,
    required this.logs,
    required this.day,
  });

  double get _totalKcal =>
      logs.fold(0, (sum, l) => sum + (l.kcal ?? 0));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final fmt0 =
        NumberFormat.decimalPattern('de_DE')..maximumFractionDigits = 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        children: [
          // Section header
          ListTile(
            dense: true,
            title: Text(label,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (logs.isNotEmpty)
                  Text('${fmt0.format(_totalKcal)} kcal',
                      style: TextStyle(color: cs.onSurfaceVariant)),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline),
                  tooltip: 'Zu $label hinzufügen',
                  onPressed: () => _openEntry(context, mealTypeId, day),
                ),
              ],
            ),
          ),
          if (logs.isNotEmpty) ...[
            const Divider(height: 1),
            ...logs.map((l) => _LogTile(log: l)),
          ],
        ],
      ),
    );
  }

  void _openEntry(BuildContext context, String? mealTypeId, DateTime day) {
    final isToday = day == DateTime(DateTime.now().year,
        DateTime.now().month, DateTime.now().day);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => DiaryEntrySheet(
        initialMealTypeId: mealTypeId,
        initialLoggedAt:
            isToday ? null : DateTime(day.year, day.month, day.day, 12, 0),
      ),
    );
  }
}

// ─── Single log tile with swipe-to-delete ────────────────────────────────────

class _LogTile extends ConsumerWidget {
  final NutritionLog log;
  const _LogTile({required this.log});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final fmt1 =
        NumberFormat.decimalPattern('de_DE')..maximumFractionDigits = 1;

    return Dismissible(
      key: ValueKey(log.id),
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
                content: Text(
                    '„${log.productName}" wird unwiderruflich entfernt.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.of(ctx).pop(false),
                      child: const Text('Abbrechen')),
                  FilledButton(
                      onPressed: () => Navigator.of(ctx).pop(true),
                      child: const Text('Löschen')),
                ],
              ),
            ) ??
            false;
      },
      onDismissed: (_) =>
          ref.read(nutritionOpsProvider.notifier).deleteLog(log.id),
      child: ListTile(
        title: Text(log.productName),
        subtitle: Text(
          [
            '${fmt1.format(log.quantityG)} ${log.displayUnit}',
            if (log.brand != null) log.brand!,
          ].join(' · '),
          style: TextStyle(color: cs.onSurfaceVariant),
        ),
        trailing: log.kcal != null
            ? Text(
                '${fmt1.format(log.kcal!)} kcal',
                style: const TextStyle(fontWeight: FontWeight.w500),
              )
            : null,
      ),
    );
  }
}

// ─── Empty day state ──────────────────────────────────────────────────────────

class _EmptyDay extends StatelessWidget {
  final DateTime day;
  const _EmptyDay({required this.day});

  @override
  Widget build(BuildContext context) {
    final isToday = day ==
        DateTime(
            DateTime.now().year, DateTime.now().month, DateTime.now().day);
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.restaurant_menu, size: 48, color: cs.outline),
            const SizedBox(height: 12),
            Text(
              isToday ? 'Noch nichts eingetragen heute.' : 'Keine Einträge für diesen Tag.',
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
