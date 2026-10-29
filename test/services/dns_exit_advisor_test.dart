/// The exit-aware resolver advisor.
///
/// A national resolver is the right answer when you are not tunnelling and the
/// wrong one when the tunnel exits somewhere else: geo-DNS hands back
/// country-local answers, so the destination sees an exit IP in one country
/// served from a frontend in another.
library;

import 'package:blackout_kit_mobile/models/dns_provider.dart';
import 'package:blackout_kit_mobile/services/dns_exit_advisor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('catalogue country metadata', () {
    test('the Iranian sanctions resolvers are country-local', () {
      for (final key in ['shecan', 'electro', 'begzar', 'radar', '403']) {
        expect(DnsCatalog.countryOf(key), 'IR', reason: key);
        expect(DnsCatalog.isCountryLocal(key), isTrue, reason: key);
      }
    });

    test('the Chinese domestic resolvers are country-local', () {
      for (final key in ['alibaba', 'tencent', '114dns']) {
        expect(DnsCatalog.countryOf(key), 'CN', reason: key);
      }
    });

    test('global resolvers carry no country', () {
      for (final key in ['cloudflare', 'google', 'quad9', 'adguard', 'dnssb']) {
        expect(DnsCatalog.countryOf(key), isEmpty, reason: key);
        expect(DnsCatalog.isCountryLocal(key), isFalse, reason: key);
      }
    });

    test('every country-local key exists in the catalogue', () {
      for (final key in DnsCatalog.localResolverCountries.keys) {
        expect(DnsCatalog.byKey(key), isNotNull, reason: key);
      }
    });
  });

  group('DnsExitAdvisor.evaluate', () {
    test('warns when an Iranian resolver is used from a German exit', () {
      final suggestion = DnsExitAdvisor.evaluate(
        providerKey: 'shecan',
        exitCountryCode: 'DE',
      );
      expect(suggestion, isNotNull);
      expect(suggestion!.resolverCountry, 'IR');
      expect(suggestion.exitCountry, 'DE');
      expect(suggestion.suggestedKey, 'cloudflare');
      expect(suggestion.message, contains('Shecan'));
      expect(suggestion.message, contains('DE'));
    });

    test('says nothing when the resolver matches the exit', () {
      expect(
        DnsExitAdvisor.evaluate(providerKey: 'shecan', exitCountryCode: 'IR'),
        isNull,
      );
      expect(
        DnsExitAdvisor.evaluate(providerKey: 'alibaba', exitCountryCode: 'CN'),
        isNull,
      );
    });

    test('says nothing for a global resolver anywhere', () {
      for (final exit in ['IR', 'DE', 'US', 'CN', '']) {
        expect(
          DnsExitAdvisor.evaluate(providerKey: 'cloudflare', exitCountryCode: exit),
          isNull,
          reason: exit,
        );
      }
    });

    test('says nothing when the exit is unknown', () {
      // Without a known exit there is nothing to compare against; warning here
      // would fire for every user who has not connected yet.
      expect(DnsExitAdvisor.evaluate(providerKey: 'shecan', exitCountryCode: ''), isNull);
      expect(DnsExitAdvisor.evaluate(providerKey: 'shecan', exitCountryCode: '   '), isNull);
    });

    test('says nothing for an unknown provider key', () {
      expect(
        DnsExitAdvisor.evaluate(providerKey: 'not-a-provider', exitCountryCode: 'DE'),
        isNull,
      );
    });

    test('normalises case and whitespace in the exit code', () {
      expect(
        DnsExitAdvisor.evaluate(providerKey: 'radar', exitCountryCode: ' de '),
        isNotNull,
      );
      expect(
        DnsExitAdvisor.evaluate(providerKey: 'radar', exitCountryCode: 'ir'),
        isNull,
      );
    });

    test('the custom resolver key never warns', () {
      // 'custom' is not in the catalogue, so there is no country to compare.
      expect(
        DnsExitAdvisor.evaluate(providerKey: 'custom', exitCountryCode: 'DE'),
        isNull,
      );
    });
  });

  group('DnsExitAdvisor.isLocalMatch', () {
    test('is true only when resolver country equals exit country', () {
      expect(
        DnsExitAdvisor.isLocalMatch(providerKey: 'shecan', exitCountryCode: 'IR'),
        isTrue,
      );
      expect(
        DnsExitAdvisor.isLocalMatch(providerKey: 'shecan', exitCountryCode: 'DE'),
        isFalse,
      );
      expect(
        DnsExitAdvisor.isLocalMatch(providerKey: 'cloudflare', exitCountryCode: 'DE'),
        isFalse,
      );
      expect(
        DnsExitAdvisor.isLocalMatch(providerKey: 'shecan', exitCountryCode: ''),
        isFalse,
      );
    });
  });
}
