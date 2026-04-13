import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

const _channelId = 'lifeos_expiry';
const _channelName = 'Expiry';

/// Builds the notification body for an item, given its name and the days
/// remaining until expiry (negative or zero means already expired).
typedef ExpiryBodyBuilder = String Function(String itemName, int daysLeft);

class NotificationService {
  NotificationService._();

  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static Future<void> initialize() async {
    if (_initialized) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwin = DarwinInitializationSettings();
    await _plugin.initialize(
      const InitializationSettings(android: android, iOS: darwin),
    );
    _initialized = true;
  }

  /// Shows a notification for an item expiring soon.
  ///
  /// [title] and [body] must be supplied by the caller (already localized).
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
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: const DarwinNotificationDetails(),
      ),
    );
  }

  /// Checks the vault DB for items expiring within [warningDays] and fires
  /// notifications. Localized strings are produced by [title] and [buildBody].
  static Future<void> checkExpiry({
    required Future<List<dynamic>> Function(int days) getExpiring,
    required String Function(dynamic entry) getItemName,
    required DateTime? Function(dynamic entry) getExpiryDate,
    required String title,
    required ExpiryBodyBuilder buildBody,
    int warningDays = 3,
  }) async {
    try {
      final expiring = await getExpiring(warningDays);
      for (var i = 0; i < expiring.length; i++) {
        final entry = expiring[i];
        final name = getItemName(entry);
        final expiry = getExpiryDate(entry);
        if (expiry == null) continue;
        final daysLeft = expiry.difference(DateTime.now()).inDays;
        await showExpiryWarning(
          id: i + 1000, // offset to avoid conflicts with other notifications
          title: title,
          body: buildBody(name, daysLeft),
        );
      }
    } catch (e) {
      debugPrint('NotificationService.checkExpiry error: $e');
    }
  }
}
