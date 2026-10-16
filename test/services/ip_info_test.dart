/// Tests for the IP identity parser: the home screen shows "before vs now"
/// addresses and places, and a malformed lookup response must degrade to
/// "unavailable", never to a wrong location.

import 'package:flutter_test/flutter_test.dart';

import 'package:blackout_kit_mobile/services/ip_info_service.dart';

void main() {
  group('IpInfo.fromJson', () {
    test('parses a successful ipwho.is response', () {
      final info = IpInfo.fromJson({
        'success': true,
        'ip': '104.28.5.9',
        'city': 'Amsterdam',
        'country': 'Netherlands',
        'country_code': 'NL',
      });
      expect(info.ok, isTrue);
      expect(info.ip, '104.28.5.9');
      expect(info.placeLabel, 'Amsterdam, Netherlands 🇳🇱');
      expect(info.isEmpty, isFalse);
    });

    test('a failed lookup resolves to unresolved', () {
      final info = IpInfo.fromJson({'success': false, 'ip': ''});
      expect(info.isEmpty, isTrue);
    });

    test('missing fields degrade gracefully', () {
      final info = IpInfo.fromJson({'success': true, 'ip': '1.2.3.4'});
      expect(info.ok, isTrue);
      expect(info.placeLabel, ''); // no city/country known
      expect(info.flag, '');
    });
  });

  group('IpInfo.flag', () {
    test('builds a flag emoji from an ISO code', () {
      expect(IpInfo(ip: '1.2.3.4', countryCode: 'DE').flag, '🇩🇪');
      expect(IpInfo(ip: '1.2.3.4', countryCode: 'ir').flag, '🇮🇷');
    });

    test('bad codes yield no flag', () {
      expect(IpInfo(ip: '1.2.3.4', countryCode: 'X').flag, '');
      expect(IpInfo(ip: '1.2.3.4', countryCode: '').flag, '');
    });
  });

  group('IpInfo cache round trip', () {
    test('toCache/fromCached preserve the identity', () {
      final original = IpInfo(
        ip: '5.125.1.2',
        city: 'Tehran',
        country: 'Iran',
        countryCode: 'IR',
        ok: true,
      );
      final restored = IpInfo.fromCached(original.toCache());
      expect(restored.ip, original.ip);
      expect(restored.placeLabel, original.placeLabel);
      expect(restored.isEmpty, isFalse);
    });
  });
}
