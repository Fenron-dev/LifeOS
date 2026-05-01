import 'package:flutter_test/flutter_test.dart';
import 'package:lifeos/services/mealie_service.dart';

void main() {
  group('MealieService.classifyUrl', () {
    test('flags HTTPS as secure', () {
      expect(MealieService.classifyUrl('https://recipes.example.com'),
          MealieUrlSecurity.https);
    });

    test('treats HTTP loopback / private ranges as local', () {
      const localUrls = [
        'http://localhost:9000',
        'http://127.0.0.1:9000',
        'http://10.0.0.5:9000',
        'http://192.168.1.5:9000',
        'http://172.16.0.10',
        'http://172.31.5.4',
        'http://169.254.42.42',
        'http://server.local',
        'http://nas.lan:9000',
      ];
      for (final u in localUrls) {
        expect(MealieService.classifyUrl(u), MealieUrlSecurity.httpLocal,
            reason: 'expected $u to be classified as httpLocal');
      }
    });

    test('warns on HTTP over public IP / hostname', () {
      const remoteUrls = [
        'http://example.com',
        'http://recipes.example.com:9000',
        'http://203.0.113.42',
        'http://8.8.8.8:9000',
        'http://172.32.0.1', // 172.32+ is OUTSIDE the 172.16/12 private range
      ];
      for (final u in remoteUrls) {
        expect(MealieService.classifyUrl(u),
            MealieUrlSecurity.httpRemoteInsecure,
            reason: 'expected $u to be classified as httpRemoteInsecure');
      }
    });

    test('returns invalid for malformed input', () {
      expect(MealieService.classifyUrl(''), MealieUrlSecurity.invalid);
      expect(MealieService.classifyUrl('not a url'), MealieUrlSecurity.invalid);
      expect(MealieService.classifyUrl('ftp://example.com'),
          MealieUrlSecurity.invalid);
    });
  });
}
