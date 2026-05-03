import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../db/database.dart';
import '../providers/nutrition_provider.dart';
import '../providers/profile_provider.dart';
import '../providers/water_provider.dart';
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
    final waterTotal = ref.watch(dailyWaterTotalProvider(_day));
    final waterLogs = ref.watch(waterLogsForDayProvider(_day)).valueOrNull ?? [];

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Tagebuch'),
      ),
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
                proteinTarget: profile?.proteinTargetG,
                carbsTarget: profile?.carbsTargetG,
                fatTarget: profile?.fatTargetG,
                waterTotal: waterTotal,
                waterGoal: profile?.dailyWaterGoalMl ?? 2000,
                waterLogs: waterLogs,
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
  final double? proteinTarget;
  final double? carbsTarget;
  final double? fatTarget;
  final int waterTotal;
  final int waterGoal;
  final List<WaterLog> waterLogs;

  const _DiaryBody({
    required this.day,
    required this.logs,
    required this.totals,
    required this.mealTypes,
    this.calorieGoal,
    this.proteinTarget,
    this.carbsTarget,
    this.fatTarget,
    required this.waterTotal,
    required this.waterGoal,
    required this.waterLogs,
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
        _DailyTotalsCard(
          totals: totals,
          calorieGoal: calorieGoal,
          proteinTarget: proteinTarget,
          carbsTarget: carbsTarget,
          fatTarget: fatTarget,
        ),
        const SizedBox(height: 12),
        _WaterWidget(
          day: day,
          total: waterTotal,
          goal: waterGoal,
          logs: waterLogs,
        ),
        const SizedBox(height: 16),
        if (logs.isEmpty)
          _EmptyDay(day: day)
        else
          ...sections,
        const SizedBox(height: 8),
        const _ConsumptionHistory(),
      ],
    );
  }
}

// ─── Daily totals card ────────────────────────────────────────────────────────

class _DailyTotalsCard extends StatelessWidget {
  final DailyNutritionTotals? totals;
  final double? calorieGoal;
  final double? proteinTarget;
  final double? carbsTarget;
  final double? fatTarget;

  const _DailyTotalsCard({
    required this.totals,
    this.calorieGoal,
    this.proteinTarget,
    this.carbsTarget,
    this.fatTarget,
  });

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

    final hasData = protein + carbs + fat > 0;

    return Card(
      color: cs.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Kcal + Donut row ─────────────────────────────────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
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
                                fontSize: 16,
                                color: cs.onPrimaryContainer),
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
                    ],
                  ),
                ),
                if (hasData) ...[
                  const SizedBox(width: 12),
                  _MacroDonut(
                    protein: protein,
                    carbs: carbs,
                    fat: fat,
                    cs: cs,
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            if (proteinTarget != null || carbsTarget != null || fatTarget != null)
              Column(
                children: [
                  _MacroProgressRow(
                    label: 'Protein',
                    value: protein,
                    target: proteinTarget,
                    color: cs.tertiary,
                    onColor: cs.onPrimaryContainer,
                    fmt: fmt1,
                  ),
                  const SizedBox(height: 6),
                  _MacroProgressRow(
                    label: 'Kohlenhydrate',
                    value: carbs,
                    target: carbsTarget,
                    color: cs.secondary,
                    onColor: cs.onPrimaryContainer,
                    fmt: fmt1,
                  ),
                  const SizedBox(height: 6),
                  _MacroProgressRow(
                    label: 'Fett',
                    value: fat,
                    target: fatTarget,
                    color: cs.error,
                    onColor: cs.onPrimaryContainer,
                    fmt: fmt1,
                  ),
                ],
              )
            else
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

// ─── Macro donut chart ────────────────────────────────────────────────────────

class _MacroDonut extends StatelessWidget {
  final double protein;
  final double carbs;
  final double fat;
  final ColorScheme cs;

  const _MacroDonut({
    required this.protein,
    required this.carbs,
    required this.fat,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    final total = protein + carbs + fat;
    if (total <= 0) return const SizedBox.shrink();

    final protPct = (protein / total * 100).round();
    final carbPct = (carbs / total * 100).round();
    final fatPct = (fat / total * 100).round();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 80,
          height: 80,
          child: Stack(
            alignment: Alignment.center,
            children: [
              PieChart(
                PieChartData(
                  sectionsSpace: 2,
                  centerSpaceRadius: 26,
                  startDegreeOffset: -90,
                  sections: [
                    PieChartSectionData(
                      value: protein,
                      color: cs.tertiary,
                      radius: 14,
                      showTitle: false,
                    ),
                    PieChartSectionData(
                      value: carbs,
                      color: cs.secondary,
                      radius: 14,
                      showTitle: false,
                    ),
                    PieChartSectionData(
                      value: fat,
                      color: cs.error,
                      radius: 14,
                      showTitle: false,
                    ),
                  ],
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$carbPct%',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: cs.onPrimaryContainer),
                  ),
                  Text(
                    'KH',
                    style: TextStyle(
                        fontSize: 9,
                        color: cs.onPrimaryContainer.withValues(alpha: 0.8)),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Dot(cs.tertiary),
            const SizedBox(width: 3),
            Text('P $protPct%',
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: cs.onPrimaryContainer)),
            const SizedBox(width: 8),
            _Dot(cs.error),
            const SizedBox(width: 3),
            Text('F $fatPct%',
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: cs.onPrimaryContainer)),
          ],
        ),
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  final Color color;
  const _Dot(this.color);

  @override
  Widget build(BuildContext context) => Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
}

class _MacroProgressRow extends StatelessWidget {
  final String label;
  final double value;
  final double? target;
  final Color color;
  final Color onColor;
  final NumberFormat fmt;

  const _MacroProgressRow({
    required this.label,
    required this.value,
    required this.target,
    required this.color,
    required this.onColor,
    required this.fmt,
  });

  @override
  Widget build(BuildContext context) {
    final pct =
        target != null && target! > 0 ? (value / target!).clamp(0.0, 1.0) : 0.0;
    final targetText =
        target != null ? '/ ${fmt.format(target!)} g' : '';
    return Row(
      children: [
        SizedBox(
          width: 96,
          child: Text(
            label,
            style: TextStyle(
                color: onColor.withValues(alpha: 0.85), fontSize: 12),
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 5,
              backgroundColor: onColor.withValues(alpha: 0.15),
              valueColor: AlwaysStoppedAnimation(
                pct >= 1.0 ? color.withValues(alpha: 0.6) : color,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '${fmt.format(value)} g $targetText',
          style: TextStyle(color: onColor, fontSize: 12),
        ),
      ],
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
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (log.kcal != null)
              Text(
                '${fmt1.format(log.kcal!)} kcal',
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
            // Thumb up
            IconButton(
              icon: Icon(
                log.thumbRating == 'up' ? Icons.thumb_up : Icons.thumb_up_outlined,
                size: 18,
                color: log.thumbRating == 'up' ? cs.primary : cs.onSurfaceVariant,
              ),
              tooltip: 'Daumen hoch',
              visualDensity: VisualDensity.compact,
              onPressed: () => ref.read(nutritionOpsProvider.notifier)
                  .setThumbRating(log.id, log.thumbRating == 'up' ? null : 'up'),
            ),
            // Thumb down
            IconButton(
              icon: Icon(
                log.thumbRating == 'down' ? Icons.thumb_down : Icons.thumb_down_outlined,
                size: 18,
                color: log.thumbRating == 'down' ? cs.error : cs.onSurfaceVariant,
              ),
              tooltip: 'Daumen runter',
              visualDensity: VisualDensity.compact,
              onPressed: () => ref.read(nutritionOpsProvider.notifier)
                  .setThumbRating(log.id, log.thumbRating == 'down' ? null : 'down'),
            ),
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Bearbeiten',
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                builder: (_) => DiaryEntrySheet(editLog: log),
              ),
            ),
            IconButton(
              icon: Icon(Icons.delete_outline, color: cs.error),
              tooltip: 'Löschen',
              onPressed: () => _confirmDeleteLog(context, ref),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDeleteLog(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Eintrag löschen?'),
            content: Text('„${log.productName}" wird unwiderruflich entfernt.'),
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
    if (ok && context.mounted) {
      await ref.read(nutritionOpsProvider.notifier).deleteLog(log.id);
    }
  }
}

// ─── Water tracking widget ────────────────────────────────────────────────────

class _WaterWidget extends ConsumerStatefulWidget {
  final DateTime day;
  final int total;
  final int goal;
  final List<WaterLog> logs;

  const _WaterWidget({
    required this.day,
    required this.total,
    required this.goal,
    required this.logs,
  });

  @override
  ConsumerState<_WaterWidget> createState() => _WaterWidgetState();
}

class _WaterWidgetState extends ConsumerState<_WaterWidget> {
  bool _expanded = false;

  Future<void> _add(int ml) async {
    await ref.read(waterOpsProvider.notifier).addWater(
          DateTime.now(),
          ml,
        );
  }

  Future<void> _addCustom() async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Wasser hinzufügen'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Menge',
            suffixText: 'ml',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Abbrechen')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Hinzufügen')),
        ],
      ),
    );
    if (ok == true && mounted) {
      final ml = int.tryParse(ctrl.text.trim());
      if (ml != null && ml > 0) await _add(ml);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pct = widget.goal > 0
        ? (widget.total / widget.goal).clamp(0.0, 1.0)
        : 0.0;
    final done = widget.total >= widget.goal;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Row(
              children: [
                Icon(Icons.water_drop_outlined,
                    color: done ? cs.primary : cs.onSurfaceVariant, size: 20),
                const SizedBox(width: 8),
                Text('Wasser',
                    style: Theme.of(context).textTheme.titleSmall),
                const Spacer(),
                Text(
                  '${widget.total} / ${widget.goal} ml',
                  style: TextStyle(
                    color: done ? cs.primary : cs.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                IconButton(
                  icon: Icon(
                      _expanded ? Icons.expand_less : Icons.expand_more,
                      size: 20),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => setState(() => _expanded = !_expanded),
                ),
              ],
            ),
            // Progress bar
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: pct,
                minHeight: 5,
                backgroundColor: cs.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation(
                    done ? cs.primary : cs.secondary),
              ),
            ),
            const SizedBox(height: 10),
            // Quick-add buttons
            Row(
              children: [
                _QuickAddBtn(label: '+200 ml', onTap: () => _add(200)),
                const SizedBox(width: 6),
                _QuickAddBtn(label: '+250 ml', onTap: () => _add(250)),
                const SizedBox(width: 6),
                _QuickAddBtn(label: '+330 ml', onTap: () => _add(330)),
                const SizedBox(width: 6),
                _QuickAddBtn(label: '+500 ml', onTap: () => _add(500)),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline, size: 22),
                  tooltip: 'Andere Menge',
                  visualDensity: VisualDensity.compact,
                  onPressed: _addCustom,
                ),
              ],
            ),
            // Expanded: individual log entries
            if (_expanded && widget.logs.isNotEmpty) ...[
              const Divider(height: 16),
              ...widget.logs.map((l) => _WaterLogTile(log: l)),
            ],
          ],
        ),
      ),
    );
  }
}

class _QuickAddBtn extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _QuickAddBtn({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          textStyle: const TextStyle(fontSize: 12),
          visualDensity: VisualDensity.compact,
        ),
        child: Text(label),
      );
}

class _WaterLogTile extends ConsumerWidget {
  final WaterLog log;
  const _WaterLogTile({required this.log});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final time = TimeOfDay.fromDateTime(log.loggedAt);
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(Icons.water_drop_outlined,
          size: 18, color: cs.primary),
      title: Text('${log.amountMl} ml',
          style: const TextStyle(fontSize: 13)),
      subtitle: Text(time.format(context),
          style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
      trailing: IconButton(
        icon: Icon(Icons.delete_outline, size: 18, color: cs.error),
        visualDensity: VisualDensity.compact,
        onPressed: () =>
            ref.read(waterOpsProvider.notifier).deleteLog(log.id),
      ),
    );
  }
}

// ─── Consumption history (embedded in diary) ─────────────────────────────────

enum _HistoryPeriod { today, week, month, year, all }

enum _HistorySort {
  kcal('Kalorien'),
  protein('Protein'),
  carbs('Kohlenhydrate'),
  fat('Fett'),
  name('Name');

  final String label;
  const _HistorySort(this.label);
}

class _ConsumptionHistory extends ConsumerStatefulWidget {
  const _ConsumptionHistory();

  @override
  ConsumerState<_ConsumptionHistory> createState() =>
      _ConsumptionHistoryState();
}

class _ConsumptionHistoryState extends ConsumerState<_ConsumptionHistory> {
  _HistoryPeriod _period = _HistoryPeriod.week;
  _HistorySort _sort = _HistorySort.kcal;
  bool _expanded = true;

  (DateTime, DateTime) get _range {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return switch (_period) {
      _HistoryPeriod.today => (
          today,
          today.add(const Duration(days: 1)),
        ),
      _HistoryPeriod.week => (
          today.subtract(Duration(days: today.weekday - 1)),
          today.add(const Duration(days: 1)),
        ),
      _HistoryPeriod.month => (
          DateTime(now.year, now.month, 1),
          today.add(const Duration(days: 1)),
        ),
      _HistoryPeriod.year => (
          DateTime(now.year, 1, 1),
          today.add(const Duration(days: 1)),
        ),
      _HistoryPeriod.all => (
          DateTime(2000),
          today.add(const Duration(days: 1)),
        ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final logsAsync = ref.watch(nutritionLogsForRangeProvider(_range));

    return Card(
      margin: EdgeInsets.zero,
      child: Column(
        children: [
          // Header
          ListTile(
            dense: true,
            leading: Icon(Icons.bar_chart_outlined,
                color: cs.onSurfaceVariant, size: 20),
            title: const Text('Verlauf & Übersicht',
                style: TextStyle(fontWeight: FontWeight.w600)),
            trailing: IconButton(
              icon: Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  size: 20),
              visualDensity: VisualDensity.compact,
              onPressed: () => setState(() => _expanded = !_expanded),
            ),
          ),
          if (_expanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Period selector
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SegmentedButton<_HistoryPeriod>(
                      segments: const [
                        ButtonSegment(
                            value: _HistoryPeriod.today, label: Text('Heute')),
                        ButtonSegment(
                            value: _HistoryPeriod.week, label: Text('Woche')),
                        ButtonSegment(
                            value: _HistoryPeriod.month,
                            label: Text('Monat')),
                        ButtonSegment(
                            value: _HistoryPeriod.year, label: Text('Jahr')),
                        ButtonSegment(
                            value: _HistoryPeriod.all,
                            label: Text('Gesamt')),
                      ],
                      selected: {_period},
                      onSelectionChanged: (s) =>
                          setState(() => _period = s.first),
                    ),
                  ),
                  const SizedBox(height: 6),
                  // Sort chips (scrollable)
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        Text('Sortierung:',
                            style: Theme.of(context).textTheme.bodySmall),
                        const SizedBox(width: 8),
                        ..._HistorySort.values.map((f) => Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: ChoiceChip(
                                label: Text(f.label),
                                selected: _sort == f,
                                onSelected: (_) => setState(() => _sort = f),
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 4),
                              ),
                            )),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            logsAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.all(16),
                child: Text('Fehler: $e'),
              ),
              data: (logs) => _HistoryContent(logs: logs, sort: _sort),
            ),
          ],
        ],
      ),
    );
  }
}

class _HistoryContent extends StatelessWidget {
  final List<NutritionLog> logs;
  final _HistorySort sort;

  const _HistoryContent({required this.logs, required this.sort});

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
    }
    final list = map.values.toList();
    list.sort((a, b) => switch (sort) {
          _HistorySort.kcal => b.kcal.compareTo(a.kcal),
          _HistorySort.protein => b.protein.compareTo(a.protein),
          _HistorySort.carbs => b.carbs.compareTo(a.carbs),
          _HistorySort.fat => b.fat.compareTo(a.fat),
          _HistorySort.name => a.name.compareTo(b.name),
        });
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (logs.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: Text('Keine Einträge für diesen Zeitraum.')),
      );
    }
    final entries = _aggregate();
    final fmt0 = NumberFormat.decimalPattern('de_DE')
      ..maximumFractionDigits = 0;
    final fmt1 = NumberFormat.decimalPattern('de_DE')
      ..maximumFractionDigits = 1;

    final totalKcal = entries.fold(0.0, (s, e) => s + e.kcal);
    final totalProtein = entries.fold(0.0, (s, e) => s + e.protein);
    final totalCarbs = entries.fold(0.0, (s, e) => s + e.carbs);
    final totalFat = entries.fold(0.0, (s, e) => s + e.fat);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Summary strip
        Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: cs.primaryContainer,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _SummaryCell(
                  '${fmt0.format(totalKcal)} kcal', '${logs.length}×', cs),
              _SummaryCell('${fmt1.format(totalProtein)} g', 'Protein', cs),
              _SummaryCell('${fmt1.format(totalCarbs)} g', 'KH', cs),
              _SummaryCell('${fmt1.format(totalFat)} g', 'Fett', cs),
            ],
          ),
        ),
        // Food list
        ...entries.map((e) {
          final sortValue = switch (sort) {
            _HistorySort.kcal => '${fmt0.format(e.kcal)} kcal',
            _HistorySort.protein => '${fmt1.format(e.protein)} g Protein',
            _HistorySort.carbs => '${fmt1.format(e.carbs)} g KH',
            _HistorySort.fat => '${fmt1.format(e.fat)} g Fett',
            _HistorySort.name => '${fmt0.format(e.kcal)} kcal',
          };
          return ListTile(
            dense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
            leading: CircleAvatar(
              radius: 14,
              backgroundColor: (e.source == 'recipe' || e.source == 'meal')
                  ? cs.tertiaryContainer
                  : cs.primaryContainer,
              child: Icon(
                (e.source == 'recipe' || e.source == 'meal')
                    ? Icons.restaurant_outlined
                    : Icons.fastfood_outlined,
                size: 14,
                color: (e.source == 'recipe' || e.source == 'meal')
                    ? cs.onTertiaryContainer
                    : cs.onPrimaryContainer,
              ),
            ),
            title: Text(e.name,
                style: const TextStyle(fontSize: 13),
                overflow: TextOverflow.ellipsis),
            subtitle: e.brand != null
                ? Text(e.brand!,
                    style:
                        TextStyle(fontSize: 11, color: cs.onSurfaceVariant))
                : null,
            trailing: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(sortValue,
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600)),
                Text('${e.count}×',
                    style:
                        TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
              ],
            ),
          );
        }),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _SummaryCell extends StatelessWidget {
  final String value;
  final String label;
  final ColorScheme cs;
  const _SummaryCell(this.value, this.label, this.cs);

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value,
              style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: cs.onPrimaryContainer)),
          Text(label,
              style: TextStyle(
                  fontSize: 10,
                  color: cs.onPrimaryContainer.withValues(alpha: 0.8))),
        ],
      );
}

class _AggEntry {
  final String name;
  final String? brand;
  final String source;
  int count = 0;
  double kcal = 0, protein = 0, carbs = 0, fat = 0;
  _AggEntry({required this.name, this.brand, required this.source});
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
