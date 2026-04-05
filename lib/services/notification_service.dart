import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

const _channelId = 'lifeos_expiry';
const _channelName = 'Ablaufdaten';

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
  static Future<void> showExpiryWarning({
    required int id,
    required String itemName,
    required DateTime expiryDate,
  }) async {
    if (!_initialized) await initialize();
    final daysLeft = expiryDate.difference(DateTime.now()).inDays;
    final body = daysLeft <= 0
        ? '$itemName ist abgelaufen!'
        : '$itemName läuft in $daysLeft Tag${daysLeft == 1 ? '' : 'en'} ab.';

    await _plugin.show(
      id,
      'Ablaufdatum',
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

  /// Checks the vault DB for items expiring within [warningDays] and fires notifications.
  static Future<void> checkExpiry({
    required Future<List<dynamic>> Function(int days) getExpiring,
    required String Function(dynamic entry) getItemName,
    required DateTime? Function(dynamic entry) getExpiryDate,
    int warningDays = 3,
  }) async {
    try {
      final expiring = await getExpiring(warningDays);
      for (var i = 0; i < expiring.length; i++) {
        final entry = expiring[i];
        final name = getItemName(entry);
        final expiry = getExpiryDate(entry);
        if (expiry == null) continue;
        await showExpiryWarning(
          id: i + 1000, // offset to avoid conflicts with other notifications
          itemName: name,
          expiryDate: expiry,
        );
      }
    } catch (e) {
      debugPrint('NotificationService.checkExpiry error: $e');
    }
  }
}
