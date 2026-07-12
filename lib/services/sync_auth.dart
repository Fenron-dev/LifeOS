import 'dart:convert';

import 'package:crypto/crypto.dart';

/// HMAC request signing shared by SyncServer and SyncClient (S1).
///
/// The PSK never travels over the wire: the client signs
/// `timestamp\nmethod\npath\nbody` with HMAC-SHA256(psk) and sends only the
/// signature. Replays are limited by a ±5-minute timestamp window.
class SyncAuth {
  static const timestampHeader = 'x-sync-timestamp';
  static const signatureHeader = 'x-sync-signature';
  static const maxClockSkew = Duration(minutes: 5);

  static String sign({
    required String psk,
    required String timestamp,
    required String method,
    required String path,
    required String body,
  }) {
    final mac = Hmac(sha256, utf8.encode(psk));
    return mac
        .convert(utf8.encode('$timestamp\n$method\n$path\n$body'))
        .toString();
  }

  /// Verifies signature + timestamp window. Constant-time comparison (S4).
  static bool verify({
    required String psk,
    required String? timestamp,
    required String? signature,
    required String method,
    required String path,
    required String body,
    DateTime? now,
  }) {
    if (timestamp == null || signature == null) return false;
    final ts = DateTime.tryParse(timestamp);
    if (ts == null) return false;
    final skew = (now ?? DateTime.now()).difference(ts).abs();
    if (skew > maxClockSkew) return false;
    final expected = sign(
        psk: psk, timestamp: timestamp, method: method, path: path, body: body);
    return constantTimeEquals(expected, signature);
  }

  /// Timing-safe string comparison — never early-exits on mismatch.
  static bool constantTimeEquals(String a, String b) {
    final ab = utf8.encode(a);
    final bb = utf8.encode(b);
    if (ab.length != bb.length) return false;
    var diff = 0;
    for (var i = 0; i < ab.length; i++) {
      diff |= ab[i] ^ bb[i];
    }
    return diff == 0;
  }
}

/// Per-IP brute-force lockout (S3): after 5 failed auth attempts the IP is
/// locked for 30 s, doubling per further failure (capped at 10 min).
class SyncRateLimiter {
  final Map<String, ({int failures, DateTime lockedUntil})> _state = {};

  bool isLocked(String ip, {DateTime? now}) {
    final s = _state[ip];
    if (s == null) return false;
    return (now ?? DateTime.now()).isBefore(s.lockedUntil);
  }

  void registerFailure(String ip, {DateTime? now}) {
    final n = (now ?? DateTime.now());
    final failures = (_state[ip]?.failures ?? 0) + 1;
    var lockedUntil = _state[ip]?.lockedUntil ?? n;
    if (failures >= 5) {
      final lockSeconds =
          (30 * (1 << (failures - 5))).clamp(30, 600);
      lockedUntil = n.add(Duration(seconds: lockSeconds));
    }
    _state[ip] = (failures: failures, lockedUntil: lockedUntil);
  }

  void registerSuccess(String ip) => _state.remove(ip);
}
