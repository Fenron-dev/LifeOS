import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../db/database.dart';
import '../../health/providers/nutrition_provider.dart';
import '../../health/providers/profile_provider.dart';
import '../../health/providers/water_provider.dart';
import '../../health/providers/workouts_provider.dart';
import '../../health/widgets/health_factor_bar.dart';
import '../../providers/groups_provider.dart';
import '../../providers/inventory_provider.dart';
import '../../providers/meal_plan_provider.dart';
import '../../providers/tasks_provider.dart';
import '../../providers/vault_provider.dart';
import '../../widgets/adaptive_shell.dart';
import '../aufgaben/aufgaben_screen.dart';

final missingStaplesProvider = StreamProvider<List<Item>>((ref) {
  final db = ref.watch(databaseProvider);
  if (db == null) return const Stream.empty();
  return db.watchMissingStapleItems();
});


class StartScreen extends ConsumerStatefulWidget {
  const StartScreen({super.key});

  @override
  ConsumerState<StartScreen> createState() => _StartScreenState();
}

class _StartScreenState extends ConsumerState<StartScreen>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Force child widgets (ExpiryCard, TodayHealthCard…) to recompute
    // DateTime.now() when the app comes back to the foreground.
    if (state == AppLifecycleState.resumed && mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Start'),
        actions: shellMenuActions(context),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
        children: const [
          _StapleWarningCard(),
          _ExpiryCard(),
          SizedBox(height: 12),
          _MealPlanCard(),
          SizedBox(height: 12),
          _WaterCard(),
          SizedBox(height: 12),
          _TodayHealthCard(),
          SizedBox(height: 12),
          _JahresstatistikCard(),
          SizedBox(height: 12),
          _RemindersCard(),
          SizedBox(height: 12),
          _QuickAccessCard(),
        ],
      ),
    );
  }
}

// ── Card 0: Fehlende Grundnahrungsmittel ─────────────────────────────────────

class _StapleWarningCard extends ConsumerWidget {
  const _StapleWarningCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final missing = ref.watch(missingStaplesProvider).valueOrNull ?? [];
    if (missing.isEmpty) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        color: cs.errorContainer,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => context.push('/haushalt/shopping'),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.warning_amber_rounded,
                    color: cs.onErrorContainer, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${missing.length} Grundnahrungsmittel fehlen',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: cs.onErrorContainer,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        missing.map((i) => i.name).take(4).join(', ') +
                            (missing.length > 4 ? ' …' : ''),
                        style: TextStyle(
                            fontSize: 12, color: cs.onErrorContainer),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right,
                    color: cs.onErrorContainer, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Card between water and reminders: Gesundheit heute ────────────────────────

class _TodayHealthCard extends ConsumerWidget {
  const _TodayHealthCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));

    final logsAsync =
        ref.watch(nutritionLogsForRangeProvider((today, tomorrow)));
    final kcal = logsAsync.valueOrNull?.fold<double>(
            0, (sum, l) => sum + (l.kcal ?? 0)) ??
        0;

    final allWorkouts = ref.watch(workoutsProvider).valueOrNull ?? [];
    final todayWorkouts = allWorkouts.where((w) {
      final d = w.startedAt;
      return d.year == now.year && d.month == now.month && d.day == now.day;
    }).length;

    final healthStats =
        ref.watch(healthFactorStatsProvider((today, tomorrow))).valueOrNull;
    final totalRated = (healthStats?.entries
            .where((e) => e.key != null)
            .fold<int>(0, (s, e) => s + e.value) ??
        0);

    final costAsync =
        ref.watch(consumedFoodCostProvider((today, tomorrow)));
    final cost = costAsync.valueOrNull;

    final cs = Theme.of(context).colorScheme;
    final euroFmt = NumberFormat.currency(locale: 'de_DE', symbol: '€', decimalDigits: 2);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.monitor_heart_outlined,
                    color: cs.primary, size: 20),
                const SizedBox(width: 8),
                Text('Gesundheit heute',
                    style: Theme.of(context).textTheme.titleSmall),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => context.go('/me'),
                    child: _HealthStatTile(
                      icon: Icons.local_fire_department_outlined,
                      label: 'kcal heute',
                      value: kcal.toStringAsFixed(0),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => context.go('/me'),
                    child: _HealthStatTile(
                      icon: Icons.fitness_center_outlined,
                      label: 'Workouts',
                      value: '$todayWorkouts',
                    ),
                  ),
                ),
                if (cost != null) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: _HealthStatTile(
                      icon: Icons.euro_outlined,
                      label: 'Kosten heute',
                      value: euroFmt.format(cost),
                    ),
                  ),
                ],
              ],
            ),
            if (totalRated > 0) ...[
              const SizedBox(height: 12),
              HealthFactorBar(stats: healthStats!),
            ],
          ],
        ),
      ),
    );
  }
}

class _HealthStatTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _HealthStatTile(
      {required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: cs.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold)),
                Text(label,
                    style: TextStyle(
                        fontSize: 11, color: cs.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Jahresstatistik ───────────────────────────────────────────────────────────

class _JahresstatistikCard extends ConsumerWidget {
  const _JahresstatistikCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final year = DateTime.now().year;
    final statsAsync = ref.watch(foodFinancialStatsProvider(year));
    final cs = Theme.of(context).colorScheme;
    final euroFmt = NumberFormat.currency(locale: 'de_DE', symbol: '€', decimalDigits: 2);

    return statsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (e, _) => const SizedBox.shrink(),
      data: (stats) {
        if (stats.consumed == 0 && stats.wasted == 0) return const SizedBox.shrink();
        final total = stats.consumed + stats.wasted;
        final consumedFlex = (stats.consumed / total * 100).round().clamp(1, 98);
        final wastedFlex = (100 - consumedFlex).clamp(1, 98);
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.bar_chart_outlined, color: cs.primary, size: 20),
                    const SizedBox(width: 8),
                    Text('Lebensmittel $year',
                        style: Theme.of(context).textTheme.titleSmall),
                  ],
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Row(
                    children: [
                      Expanded(
                        flex: consumedFlex,
                        child: Container(height: 10, color: Colors.green.shade400),
                      ),
                      Expanded(
                        flex: wastedFlex,
                        child: Container(height: 10, color: Colors.red.shade400),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Container(width: 10, height: 10,
                        decoration: BoxDecoration(color: Colors.green.shade400, shape: BoxShape.circle)),
                    const SizedBox(width: 6),
                    Text('Verbraucht: ${euroFmt.format(stats.consumed)}',
                        style: const TextStyle(fontSize: 12)),
                    const Spacer(),
                    Container(width: 10, height: 10,
                        decoration: BoxDecoration(color: Colors.red.shade400, shape: BoxShape.circle)),
                    const SizedBox(width: 6),
                    Text('Verschwendet: ${euroFmt.format(stats.wasted)}',
                        style: const TextStyle(fontSize: 12)),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ── Card 1: Ablaufende Artikel ────────────────────────────────────────────────

class _ExpiryCard extends ConsumerWidget {
  const _ExpiryCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expiringAsync = ref.watch(expiringItemsProvider);
    final cs = Theme.of(context).colorScheme;

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.push('/haushalt/shelf-life'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.event_busy_outlined, color: cs.error, size: 20),
                  const SizedBox(width: 8),
                  Text('Ablaufende Artikel',
                      style: Theme.of(context).textTheme.titleSmall),
                  const Spacer(),
                  Icon(Icons.chevron_right, color: cs.outline, size: 20),
                ],
              ),
              const SizedBox(height: 10),
              expiringAsync.when(
                loading: () => const LinearProgressIndicator(),
                error: (e, _) => Text('Fehler: $e',
                    style: TextStyle(color: cs.error, fontSize: 12)),
                data: (items) {
                  if (items.isEmpty) {
                    return Row(
                      children: [
                        Icon(Icons.check_circle_outline,
                            color: cs.primary, size: 18),
                        const SizedBox(width: 6),
                        Text('Alles frisch!',
                            style: TextStyle(color: cs.primary, fontSize: 13)),
                      ],
                    );
                  }
                  final now = DateTime.now();
                  final today = DateTime(now.year, now.month, now.day);

                  // Bucket by days remaining (floor to calendar day)
                  final urgent = items
                      .where((r) => r.effectiveExpiry
                          .difference(today)
                          .inDays <= 3)
                      .toList();
                  final soon = items
                      .where((r) {
                        final d = r.effectiveExpiry.difference(today).inDays;
                        return d > 3 && d <= 7;
                      })
                      .toList();
                  final later = items
                      .where((r) {
                        final d = r.effectiveExpiry.difference(today).inDays;
                        return d > 7 && d <= 14;
                      })
                      .toList();

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (urgent.isNotEmpty)
                        _ExpiryBucket(
                          label: '≤ 3 Tage',
                          color: cs.error,
                          items: urgent,
                        ),
                      if (soon.isNotEmpty)
                        _ExpiryBucket(
                          label: '4–7 Tage',
                          color: cs.tertiary,
                          items: soon,
                        ),
                      if (later.isNotEmpty)
                        _ExpiryBucket(
                          label: '8–14 Tage',
                          color: cs.onSurfaceVariant,
                          items: later,
                        ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: () => context.push('/haushalt/meals',
                            extra: {'filterExpiring': true}),
                        icon: const Icon(Icons.restaurant_outlined, size: 16),
                        label: const Text('Passende Gerichte'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          textStyle: const TextStyle(fontSize: 12),
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExpiryBucket extends StatelessWidget {
  final String label;
  final Color color;
  final List<({InventoryEntry entry, Item item, DateTime effectiveExpiry})> items;

  const _ExpiryBucket({
    required this.label,
    required this.color,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final shown = items.take(3).toList();
    final rest = items.length - shown.length;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(right: 6),
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
              ),
              Text(label,
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: color,
                      letterSpacing: 0.3)),
            ],
          ),
          const SizedBox(height: 4),
          ...shown.map((r) => _ExpiryRow(
                name: r.item.name,
                expiry: r.effectiveExpiry,
                color: color,
              )),
          if (rest > 0)
            Padding(
              padding: const EdgeInsets.only(top: 2, left: 14),
              child: Text('+ $rest weitere',
                  style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
            ),
        ],
      ),
    );
  }
}

class _ExpiryRow extends StatelessWidget {
  final String name;
  final DateTime expiry;
  final Color? color;
  const _ExpiryRow({required this.name, required this.expiry, this.color});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final daysLeft = expiry.difference(today).inDays;
    final isExpired = daysLeft < 0;
    final rowColor = color ?? (isExpired ? cs.error : cs.onSurfaceVariant);
    final dateStr = DateFormat('dd.MM.yy').format(expiry);
    final dayStr = isExpired
        ? 'abgelaufen'
        : daysLeft == 0
            ? 'heute'
            : 'in $daysLeft T.';

    return Padding(
      padding: const EdgeInsets.only(bottom: 3, left: 14),
      child: Row(
        children: [
          Expanded(
              child: Text(name,
                  style: const TextStyle(fontSize: 13),
                  overflow: TextOverflow.ellipsis)),
          Text('$dateStr ($dayStr)',
              style: TextStyle(fontSize: 11, color: rowColor)),
        ],
      ),
    );
  }
}

// ── Card 2: Heute geplante Mahlzeiten ─────────────────────────────────────────

class _MealPlanCard extends ConsumerWidget {
  const _MealPlanCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = DateTime.now();
    final start = DateTime(today.year, today.month, today.day);
    final end = start.add(const Duration(days: 1));
    final entriesAsync = ref.watch(mealPlanEntriesProvider((start, end)));
    final cs = Theme.of(context).colorScheme;

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.push('/haushalt/plan'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.today_outlined,
                      color: cs.primary, size: 20),
                  const SizedBox(width: 8),
                  Text('Heute geplant',
                      style: Theme.of(context).textTheme.titleSmall),
                  const Spacer(),
                  Icon(Icons.chevron_right, color: cs.outline, size: 20),
                ],
              ),
              const SizedBox(height: 10),
              entriesAsync.when(
                loading: () => const LinearProgressIndicator(),
                error: (e, _) => Text('Fehler: $e',
                    style: TextStyle(color: cs.error, fontSize: 12)),
                data: (entries) {
                  if (entries.isEmpty) {
                    return Text(
                      'Keine Mahlzeiten geplant',
                      style: TextStyle(
                          fontSize: 13, color: cs.onSurfaceVariant),
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: entries
                        .map((e) => Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Row(
                                children: [
                                  Icon(Icons.restaurant_outlined,
                                      size: 14,
                                      color: cs.onSurfaceVariant),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(e.entryName,
                                        style: const TextStyle(fontSize: 13),
                                        overflow: TextOverflow.ellipsis),
                                  ),
                                  if (e.servings != 1.0)
                                    Text('×${_fmt(e.servings)}',
                                        style: TextStyle(
                                            fontSize: 11,
                                            color: cs.onSurfaceVariant)),
                                ],
                              ),
                            ))
                        .toList(),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _fmt(double v) =>
      v % 1 == 0 ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
}

// ── Card 3: Wasser heute ──────────────────────────────────────────────────────

class _WaterCard extends ConsumerWidget {
  const _WaterCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = DateTime.now();
    final day = DateTime(today.year, today.month, today.day);
    final total = ref.watch(dailyWaterTotalProvider(day));
    final profile = ref.watch(userProfileProvider).valueOrNull;
    final goal = profile?.dailyWaterGoalMl ?? 2000;
    final cs = Theme.of(context).colorScheme;
    final pct = goal > 0 ? (total / goal).clamp(0.0, 1.0) : 0.0;
    final done = total >= goal;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.water_drop_outlined,
                    color: done ? cs.primary : cs.onSurfaceVariant,
                    size: 20),
                const SizedBox(width: 8),
                Text('Wasser',
                    style: Theme.of(context).textTheme.titleSmall),
                const Spacer(),
                Text(
                  '$total / $goal ml',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: done ? cs.primary : cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: pct,
                minHeight: 6,
                backgroundColor: cs.surfaceContainerHighest,
                valueColor:
                    AlwaysStoppedAnimation(done ? cs.primary : cs.secondary),
              ),
            ),
            const SizedBox(height: 10),
            _WaterQuickAddRow(day: day),
          ],
        ),
      ),
    );
  }
}

/// Reusable quick-add buttons row for water intake.
/// Used in both StartScreen and DiaryTab.
class WaterQuickAddRow extends ConsumerWidget {
  final DateTime day;
  const WaterQuickAddRow({super.key, required this.day});

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      _WaterQuickAddRow(day: day);
}

class _WaterQuickAddRow extends ConsumerWidget {
  final DateTime day;
  const _WaterQuickAddRow({required this.day});

  Future<void> _add(WidgetRef ref, int ml) =>
      ref.read(waterOpsProvider.notifier).addWater(day, ml);

  Future<void> _addCustom(BuildContext context, WidgetRef ref) async {
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
    if (ok == true && context.mounted) {
      final ml = int.tryParse(ctrl.text.trim());
      if (ml != null && ml > 0) await _add(ref, ml);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _QuickAddBtn(label: '+200 ml', onTap: () => _add(ref, 200)),
        _QuickAddBtn(label: '+250 ml', onTap: () => _add(ref, 250)),
        _QuickAddBtn(label: '+330 ml', onTap: () => _add(ref, 330)),
        _QuickAddBtn(label: '+500 ml', onTap: () => _add(ref, 500)),
        IconButton(
          icon: const Icon(Icons.add_circle_outline, size: 22),
          tooltip: 'Andere Menge',
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          onPressed: () => _addCustom(context, ref),
        ),
      ],
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

// ── Card 4: Erinnerungen / Status ─────────────────────────────────────────────

class _RemindersCard extends ConsumerWidget {
  const _RemindersCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasksAsync = ref.watch(tasksProvider);
    final shoppingAsync = ref.watch(shoppingNeedsProvider);
    final cs = Theme.of(context).colorScheme;

    final openTasks = tasksAsync.valueOrNull
            ?.where((t) => t.status != 'done')
            .length ??
        0;
    final shoppingCount = shoppingAsync.valueOrNull?.length ?? 0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.notifications_outlined,
                    color: cs.primary, size: 20),
                const SizedBox(width: 8),
                Text('Status',
                    style: Theme.of(context).textTheme.titleSmall),
              ],
            ),
            const SizedBox(height: 10),
            _StatusRow(
              icon: Icons.task_outlined,
              label: openTasks == 0
                  ? 'Keine offenen Aufgaben'
                  : '$openTasks Aufgabe${openTasks != 1 ? 'n' : ''} offen',
              highlight: openTasks > 0,
              onTap: () => context.push('/aufgaben'),
            ),
            const SizedBox(height: 6),
            _StatusRow(
              icon: Icons.shopping_cart_outlined,
              label: shoppingCount == 0
                  ? 'Einkaufsliste leer'
                  : '$shoppingCount Artikel einzukaufen',
              highlight: shoppingCount > 0,
              onTap: () {
                ref.read(aufgabenInitialTabProvider.notifier).state = 1;
                context.go('/aufgaben');
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool highlight;
  final VoidCallback onTap;

  const _StatusRow({
    required this.icon,
    required this.label,
    required this.highlight,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = highlight ? cs.primary : cs.onSurfaceVariant;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
        child: Row(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 8),
            Expanded(
                child: Text(label,
                    style: TextStyle(fontSize: 13, color: color))),
            Icon(Icons.chevron_right, size: 16, color: cs.outline),
          ],
        ),
      ),
    );
  }
}

// ── Card 5: Schnellzugriff ────────────────────────────────────────────────────

class _QuickAccessCard extends ConsumerWidget {
  const _QuickAccessCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.bolt_outlined, color: cs.primary, size: 20),
                const SizedBox(width: 8),
                Text('Schnellzugriff',
                    style: Theme.of(context).textTheme.titleSmall),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _QuickBtn(
                    icon: Icons.inventory_2_outlined,
                    label: 'Inventar',
                    onTap: () => context.push('/haushalt/inventory')),
                _QuickBtn(
                    icon: Icons.task_outlined,
                    label: 'Aufgaben',
                    onTap: () => context.push('/aufgaben')),
                _QuickBtn(
                    icon: Icons.category_outlined,
                    label: 'Artikel',
                    onTap: () => context.push('/haushalt/products')),
                _QuickBtn(
                    icon: Icons.menu_book_outlined,
                    label: 'Rezepte',
                    onTap: () => context.push('/haushalt/recipes')),
                _QuickBtn(
                    icon: Icons.shopping_cart_outlined,
                    label: 'Einkaufsliste',
                    onTap: () {
                      ref.read(aufgabenInitialTabProvider.notifier).state = 1;
                      context.go('/aufgaben');
                    }),
                _QuickBtn(
                    icon: Icons.restaurant_outlined,
                    label: 'Gerichte',
                    onTap: () => context.push('/haushalt/meals')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _QuickBtn(
      {required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: const TextStyle(fontSize: 12),
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}
