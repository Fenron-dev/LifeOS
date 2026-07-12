import 'package:flutter_test/flutter_test.dart';
import 'package:lifeos/services/sync_auth.dart';

void main() {
  group('SyncAuth', () {
    const psk = 'TESTPSK12345';
    final now = DateTime(2026, 7, 12, 12, 0, 0);

    test('sign/verify roundtrip', () {
      final ts = now.toIso8601String();
      final sig = SyncAuth.sign(
          psk: psk,
          timestamp: ts,
          method: 'POST',
          path: '/api/v1/events',
          body: '[{"id":"e1"}]');
      expect(
        SyncAuth.verify(
          psk: psk,
          timestamp: ts,
          signature: sig,
          method: 'POST',
          path: '/api/v1/events',
          body: '[{"id":"e1"}]',
          now: now,
        ),
        isTrue,
      );
    });

    test('rejects tampered body, wrong psk, wrong path', () {
      final ts = now.toIso8601String();
      final sig = SyncAuth.sign(
          psk: psk, timestamp: ts, method: 'POST', path: '/p', body: 'a');
      expect(
          SyncAuth.verify(
              psk: psk, timestamp: ts, signature: sig,
              method: 'POST', path: '/p', body: 'b', now: now),
          isFalse);
      expect(
          SyncAuth.verify(
              psk: 'WRONG', timestamp: ts, signature: sig,
              method: 'POST', path: '/p', body: 'a', now: now),
          isFalse);
      expect(
          SyncAuth.verify(
              psk: psk, timestamp: ts, signature: sig,
              method: 'POST', path: '/other', body: 'a', now: now),
          isFalse);
    });

    test('rejects stale timestamp (replay window ±5 min)', () {
      final old = now.subtract(const Duration(minutes: 6)).toIso8601String();
      final sig = SyncAuth.sign(
          psk: psk, timestamp: old, method: 'GET', path: '/p', body: '');
      expect(
          SyncAuth.verify(
              psk: psk, timestamp: old, signature: sig,
              method: 'GET', path: '/p', body: '', now: now),
          isFalse);
    });

    test('rejects missing headers', () {
      expect(
          SyncAuth.verify(
              psk: psk, timestamp: null, signature: null,
              method: 'GET', path: '/p', body: '', now: now),
          isFalse);
    });

    test('constantTimeEquals', () {
      expect(SyncAuth.constantTimeEquals('abc', 'abc'), isTrue);
      expect(SyncAuth.constantTimeEquals('abc', 'abd'), isFalse);
      expect(SyncAuth.constantTimeEquals('abc', 'ab'), isFalse);
    });
  });

  group('SyncRateLimiter', () {
    test('locks after 5 failures, unlocks after window, resets on success',
        () {
      final rl = SyncRateLimiter();
      final t0 = DateTime(2026, 7, 12, 12, 0, 0);
      const ip = '192.168.1.50';

      for (var i = 0; i < 4; i++) {
        rl.registerFailure(ip, now: t0);
        expect(rl.isLocked(ip, now: t0), isFalse);
      }
      rl.registerFailure(ip, now: t0); // 5th
      expect(rl.isLocked(ip, now: t0), isTrue);
      // 30 s lock after the 5th failure
      expect(rl.isLocked(ip, now: t0.add(const Duration(seconds: 31))),
          isFalse);

      rl.registerSuccess(ip);
      rl.registerFailure(ip, now: t0);
      expect(rl.isLocked(ip, now: t0), isFalse); // counter was reset
    });
  });
}
