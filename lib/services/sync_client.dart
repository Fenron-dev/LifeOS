import 'dart:convert';

import 'package:http/http.dart' as http;

import 'sync_auth.dart';

/// HTTP client used to push/pull the full vault dump from the desktop sync
/// server (SyncServer). Requests are HMAC-signed — the PSK never leaves the
/// device (S1).
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

  /// Pulls the server's full vault dump: `{tables: {name: [rows]}}`.
  Future<Map<String, dynamic>> pullFull() async {
    const path = '/api/v1/full';
    final res = await http
        .get(Uri.parse('$serverUrl$path'),
            headers: _signedHeaders('GET', path, ''))
        .timeout(const Duration(seconds: 60));
    if (res.statusCode != 200) {
      throw Exception('Pull failed: HTTP ${res.statusCode} — ${res.body}');
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    return (body['tables'] as Map?)?.cast<String, dynamic>() ?? {};
  }

  /// Pushes the local full dump [tables] to the server. Returns the number of
  /// rows the server applied.
  Future<int> pushFull(Map<String, dynamic> tables) async {
    const path = '/api/v1/full';
    final body = jsonEncode({'version': 1, 'tables': tables});
    final res = await http
        .post(Uri.parse('$serverUrl$path'),
            headers: _signedHeaders('POST', path, body), body: body)
        .timeout(const Duration(seconds: 60));
    if (res.statusCode != 200) {
      throw Exception('Push failed: HTTP ${res.statusCode} — ${res.body}');
    }
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    return json['applied'] as int? ?? 0;
  }
}
