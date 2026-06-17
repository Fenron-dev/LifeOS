import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

const _channelId = 'lifeos_expiry';
const _channelName = 'Ablaufdatum';
const _channelDescription =
    'Benachrichtigungen, bevor Lebensmittel ablaufen.';

const _waterChannelId = 'lifeos_water';
const _waterChannelName = 'Wasserreminder';
const _waterChannelDescription = 'Erinnerungen zum Trinken von Wasser.';

/// Stable id range for scheduled expiry notifications. `show()` calls that
/// bypass the scheduler use ids >= 1000 to avoid collisions.
const _scheduledIdOffset = 100000;

/// Stable id range for water reminder notifications (200000–200349).
const _waterIdOffset = 200000;

/// Builds the localized notification body for an entry.
typedef ExpiryBodyBuilder = String Function(String itemName, int daysLeft);

/// Plain data model for a pending expiry — kept decoupled from Drift so the
/// service does not depend on the database layer.
class ExpiryNotice {
  /// Stable unique id (e.g. inventory entry id).
  final String id;
  final String itemName;
  final DateTime expiryDate;

  const ExpiryNotice({
    required this.id,
    required this.itemName,
    required this.expiryDate,
  });
}

class NotificationService {
  NotificationService._();

  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static Future<void> initialize() async {
    if (_initialized) return;

    // Desktop platforms (Linux, Windows) don't need notification init.
    // macOS: skip blocking init here — permission dialog is deferred so the
    // Flutter window renders first (avoids black-screen-before-runApp issue).
    if (Platform.isLinux || Platform.isWindows) {
      _initialized = true;
      return;
    }

    tz_data.initializeTimeZones();
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    // On macOS: don't request permissions here — dialog is shown later via
    // requestMacOSPermission() so it appears over rendered UI, not black screen.
    final darwin = DarwinInitializationSettings(
      requestAlertPermission: !Platform.isMacOS,
      requestBadgePermission: !Platform.isMacOS,
      requestSoundPermission: !Platform.isMacOS,
    );
    await _plugin.initialize(
      InitializationSettings(
        android: android,
        iOS: Platform.isIOS ? darwin : null,
        macOS: Platform.isMacOS ? darwin : null,
      ),
    );
    _initialized = true;
  }

  /// Requests macOS notification permission explicitly (call after runApp).
  static Future<void> requestMacOSPermission() async {
    if (!Platform.isMacOS) return;
    await _plugin.resolvePlatformSpecificImplementation<
        MacOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);
  }

  /// Shows an instant notification. Used for in-app alerts.
  static Future<void> showExpiryWarning({
    required int id,
    required String title,
    required String body,
  }) async {
    if (!_initialized) await initialize();
    await _plugin.show(
      id,
      title,
      body,
      _details(),
    );
  }

  /// Replaces all previously scheduled expiry notifications with a fresh set
  /// for [notices]. Each notice fires at 9:00 local time on the day that is
  /// [warningDays] before the expiry date (or immediately if that day already
  /// passed). Call this whenever inventory changes.
  static Future<void> scheduleExpiryNotifications({
    required List<ExpiryNotice> notices,
    required String title,
    required ExpiryBodyBuilder buildBody,
    int warningDays = 3,
    int hourOfDay = 9,
  }) async {
    if (!_initialized) await initialize();
    await cancelAllScheduledExpiries();

    final now = tz.TZDateTime.now(tz.local);
    for (var i = 0; i < notices.length; i++) {
      final notice = notices[i];
      final warnDate = notice.expiryDate.subtract(Duration(days: warningDays));
      var scheduled = tz.TZDateTime(
        tz.local,
        warnDate.year,
        warnDate.month,
        warnDate.day,
        hourOfDay,
      );
      // Never schedule in the past — fall back to "in 1 minute" so the user
      // still sees overdue items on next launch, without duplicating logic.
      if (!scheduled.isAfter(now)) {
        scheduled = now.add(const Duration(minutes: 1));
      }

      final daysLeft = notice.expiryDate.difference(DateTime.now()).inDays;
      try {
        await _plugin.zonedSchedule(
          _scheduledIdOffset + i,
          title,
          buildBody(notice.itemName, daysLeft),
          scheduled,
          _details(),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          payload: notice.id,
        );
      } catch (e) {
        debugPrint('scheduleExpiryNotifications: $e');
      }
    }
  }

  /// Cancels every notification previously created by
  /// [scheduleExpiryNotifications]. Uses the reserved id range so [show]
  /// notifications and water reminders are untouched.
  static Future<void> cancelAllScheduledExpiries() async {
    final pending = await _plugin.pendingNotificationRequests();
    for (final req in pending) {
      if (req.id >= _scheduledIdOffset && req.id < _waterIdOffset) {
        await _plugin.cancel(req.id);
      }
    }
  }

  /// Schedules daily water reminder notifications for the next [days] days.
  /// Fires at every [intervalMinutes] starting from [fromHour]:00 up to
  /// [toHour]:00 (inclusive). Cancels all previous water notifications first.
  static Future<void> scheduleWaterReminders({
    required int fromHour,
    required int toHour,
    required int intervalMinutes,
    int days = 7,
  }) async {
    if (!_initialized) await initialize();
    await cancelWaterReminders();
    if (intervalMinutes <= 0) return;

    final now = tz.TZDateTime.now(tz.local);
    int notifId = _waterIdOffset;

    for (int d = 0; d < days; d++) {
      final baseDate = now.add(Duration(days: d));
      int slotMinutes = fromHour * 60;
      final endMinutes = toHour * 60;

      while (slotMinutes <= endMinutes) {
        final hour = slotMinutes ~/ 60;
        final minute = slotMinutes % 60;
        final scheduled = tz.TZDateTime(
          tz.local,
          baseDate.year,
          baseDate.month,
          baseDate.day,
          hour,
          minute,
        );
        if (scheduled.isAfter(now)) {
          try {
            await _plugin.zonedSchedule(
              notifId,
              'Wasser trinken 💧',
              'Denk daran, dein Wasserziel zu erreichen!',
              scheduled,
              _waterDetails(),
              androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
              uiLocalNotificationDateInterpretation:
                  UILocalNotificationDateInterpretation.absoluteTime,
            );
          } catch (e) {
            debugPrint('scheduleWaterReminders: $e');
          }
          notifId++;
        }
        slotMinutes += intervalMinutes;
      }
    }
  }

  /// Cancels all pending water reminder notifications (id range 200000–200349).
  static Future<void> cancelWaterReminders() async {
    final pending = await _plugin.pendingNotificationRequests();
    for (final req in pending) {
      if (req.id >= _waterIdOffset && req.id < _waterIdOffset + 350) {
        await _plugin.cancel(req.id);
      }
    }
  }

  static NotificationDetails _details() => const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDescription,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: DarwinNotificationDetails(),
      );

  static NotificationDetails _waterDetails() => const NotificationDetails(
        android: AndroidNotificationDetails(
          _waterChannelId,
          _waterChannelName,
          channelDescription: _waterChannelDescription,
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: DarwinNotificationDetails(),
      );
}
