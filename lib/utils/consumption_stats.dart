/// Pure statistics over the item event log (consumption rate, purchase
/// interval, suggested minimum stock). Used by the min-stock suggestion in
/// the item form; the reach badge (F1) builds on the same functions.
library;

import '../db/database.dart';

/// Average daily consumption in stock units over [window] (default 60 days).
/// Returns null with fewer than 3 consumption events — too little signal.
double? dailyConsumptionRate(
  List<ItemEvent> events, {
  Duration window = const Duration(days: 60),
  DateTime? now,
}) {
  final ref = now ?? DateTime.now();
  final since = ref.subtract(window);
  final consumptions = events
      .where((e) =>
          e.type == 'consumption' &&
          e.quantity != null &&
          e.createdAt.isAfter(since))
      .toList();
  if (consumptions.length < 3) return null;
  final total =
      consumptions.fold<double>(0, (sum, e) => sum + e.quantity!.abs());
  // Rate over the observed span (first event → now), not the full window —
  // otherwise young items are underestimated.
  consumptions.sort((a, b) => a.createdAt.compareTo(b.createdAt));
  final spanDays =
      ref.difference(consumptions.first.createdAt).inHours / 24.0;
  if (spanDays < 1) return null;
  return total / spanDays;
}

/// Average days between purchases. Null with fewer than 2 purchases.
double? avgDaysBetweenPurchases(List<ItemEvent> events, {DateTime? now}) {
  final purchases = events.where((e) => e.type == 'purchase').toList()
    ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  if (purchases.length < 2) return null;
  final span = purchases.last.createdAt.difference(purchases.first.createdAt);
  final days = span.inHours / 24.0 / (purchases.length - 1);
  return days < 0.5 ? null : days;
}

/// Suggested minimum stock: consumption between two shopping trips + 20 %
/// buffer, rounded to a sensible step. Null when either input is missing.
double? suggestedMinStock(double? dailyRate, double? purchaseIntervalDays) {
  if (dailyRate == null || purchaseIntervalDays == null) return null;
  final raw = dailyRate * purchaseIntervalDays * 1.2;
  if (raw <= 0) return null;
  // Round to a friendly step: <1 → 0.1, <10 → 0.5, <100 → 5, else 50.
  final step = raw < 1
      ? 0.1
      : raw < 10
          ? 0.5
          : raw < 100
              ? 5.0
              : 50.0;
  return (raw / step).ceil() * step;
}
