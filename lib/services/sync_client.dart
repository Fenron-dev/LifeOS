import 'dart:convert';

import 'package:http/http.dart' as http;

import '../db/database.dart';
import 'sync_auth.dart';
import 'sync_server.dart';

/// HTTP client used on Android to push/pull item events and master data from
/// the desktop sync server ([SyncServer]). Requests are HMAC-signed — the
/// PSK never leaves the device (S1).
class SyncClient {
  final String serverUrl; // e.g. "http://192.168.1.10:7070"
  final String psk;
  final String deviceId;

  SyncClient({
    required this.serverUrl,
    required this.psk,
    required this.deviceId,
  });

  Map<String, String> _signedHeaders(
      String method, String path, String body) {
    final timestamp = DateTime.now().toIso8601String();
    return {
      'content-type': 'application/json',
      SyncAuth.timestampHeader: timestamp,
      SyncAuth.signatureHeader: SyncAuth.sign(
        psk: psk,
        timestamp: timestamp,
        method: method,
        path: path,
        body: body,
      ),
    };
  }

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
    const path = '/api/v1/events';
    final uri = Uri.parse('$serverUrl$path').replace(
      queryParameters: {
        'since': since.toIso8601String(),
        'device_id': deviceId,
      },
    );
    final res = await http
        .get(uri, headers: _signedHeaders('GET', path, ''))
        .timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) {
      throw Exception('Pull failed: HTTP ${res.statusCode} — ${res.body}');
    }
    return (jsonDecode(res.body) as List<dynamic>)
        .whereType<Map<String, dynamic>>()
        .toList();
  }

  /// Pushes [events] to the server. Returns the number of newly inserted
  /// events on the server side.
  Future<int> pushEvents(List<ItemEvent> events) async {
    if (events.isEmpty) return 0;
    const path = '/api/v1/events';
    final body = jsonEncode(events.map(SyncServer.eventToJson).toList());
    final res = await http
        .post(Uri.parse('$serverUrl$path'),
            headers: _signedHeaders('POST', path, body), body: body)
        .timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) {
      throw Exception('Push failed: HTTP ${res.statusCode} — ${res.body}');
    }
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    return json['inserted'] as int? ?? 0;
  }

  /// Pulls master data (items/locations/shops) changed since [since].
  Future<Map<String, dynamic>> pullMasterData(DateTime since) async {
    const path = '/api/v1/entities';
    final uri = Uri.parse('$serverUrl$path')
        .replace(queryParameters: {'since': since.toIso8601String()});
    final res = await http
        .get(uri, headers: _signedHeaders('GET', path, ''))
        .timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) {
      throw Exception(
          'Entities-Pull failed: HTTP ${res.statusCode} — ${res.body}');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  /// Pushes local master data changes to the server.
  Future<int> pushMasterData(Map<String, dynamic> data) async {
    const path = '/api/v1/entities';
    final body = jsonEncode(data);
    final res = await http
        .post(Uri.parse('$serverUrl$path'),
            headers: _signedHeaders('POST', path, body), body: body)
        .timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) {
      throw Exception(
          'Entities-Push failed: HTTP ${res.statusCode} — ${res.body}');
    }
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    return json['applied'] as int? ?? 0;
  }
}
