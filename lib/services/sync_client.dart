import 'dart:convert';

import 'package:http/http.dart' as http;

import '../db/database.dart';
import 'sync_server.dart';

/// HTTP client used on Android to push/pull item events from the desktop
/// sync server ([SyncServer]).
class SyncClient {
  final String serverUrl; // e.g. "http://192.168.1.10:7070"
  final String psk;
  final String deviceId;

  SyncClient({
    required this.serverUrl,
    required this.psk,
    required this.deviceId,
  });

  Map<String, String> get _headers => {
        'authorization': 'Bearer $psk',
        'content-type': 'application/json',
      };

  /// Checks whether the server is reachable. Returns null on success,
  /// error message on failure.
  Future<String?> ping() async {
    try {
      final res = await http
          .get(Uri.parse('$serverUrl/api/v1/ping'))
          .timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) return null;
      return 'HTTP ${res.statusCode}';
    } catch (e) {
      return e.toString();
    }
  }

  /// Pulls events from the server created after [since], excluding this
  /// device's own events (already present locally).
  Future<List<Map<String, dynamic>>> pullEvents(DateTime since) async {
    final uri = Uri.parse('$serverUrl/api/v1/events').replace(
      queryParameters: {
        'since': since.toIso8601String(),
        'device_id': deviceId,
      },
    );
    final res = await http
        .get(uri, headers: _headers)
        .timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) {
      throw Exception('Pull failed: HTTP ${res.statusCode} — ${res.body}');
    }
    return (jsonDecode(res.body) as List<dynamic>)
        .whereType<Map<String, dynamic>>()
        .toList();
  }

  /// Pushes [events] to the server.
  Future<int> pushEvents(List<ItemEvent> events) async {
    if (events.isEmpty) return 0;
    final body = jsonEncode(events.map(SyncServer.eventToJson).toList());
    final res = await http
        .post(Uri.parse('$serverUrl/api/v1/events'),
            headers: _headers, body: body)
        .timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) {
      throw Exception('Push failed: HTTP ${res.statusCode} — ${res.body}');
    }
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    return json['inserted'] as int? ?? 0;
  }
}
