import 'dart:io';

import 'package:home_widget/home_widget.dart';

/// Pushes expiry and task summary data to the Android homescreen widget.
/// No-op on non-Android platforms.
class HomeWidgetService {
  static const _androidProviderName = 'LifeOsWidgetProvider';

  static Future<void> update({
    required int expiryCount,
    required String expirySummary,
    required int taskCount,
    required String taskSummary,
  }) async {
    if (!Platform.isAndroid) return;
    try {
      await Future.wait([
        HomeWidget.saveWidgetData<int>('expiry_count', expiryCount),
        HomeWidget.saveWidgetData<String>('expiry_summary', expirySummary),
        HomeWidget.saveWidgetData<int>('task_count', taskCount),
        HomeWidget.saveWidgetData<String>('task_summary', taskSummary),
      ]);
      await HomeWidget.updateWidget(androidName: _androidProviderName);
    } catch (_) {
      // Widget update failure is non-critical — silently ignore
    }
  }
}
