import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'inventory_provider.dart';
import 'tasks_provider.dart';
import '../services/home_widget_service.dart';

/// Side-effect provider: pushes expiry + task summary to the Android homescreen
/// widget whenever the underlying data changes. Kept alive in main.dart.
/// Non-critical — failures are silently swallowed inside [HomeWidgetService].
final homeWidgetUpdaterProvider = Provider<void>((ref) {
  final expiring = ref.watch(expiringItemsProvider);
  final tasks = ref.watch(tasksProvider);

  final expiryList = expiring.valueOrNull ?? [];
  final taskList = tasks.valueOrNull ?? [];

  final openTasks = taskList.where((t) => t.status != 'done').toList();

  final expirySummary =
      expiryList.take(3).map((r) => r.item.name).join(', ');
  final taskSummary = openTasks.take(3).map((t) => t.title).join(', ');

  HomeWidgetService.update(
    expiryCount: expiryList.length,
    expirySummary: expirySummary,
    taskCount: openTasks.length,
    taskSummary: taskSummary,
  );
});
