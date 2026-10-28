/// DNS catalogue: the XDNS pairs, target ordering, and lookup helpers.
///
/// These values are copied from XDNS and mirrored in the desktop CLI's
/// `blackoutkit/dns_engine.py`. A typo in an address only shows up as "DNS is
/// broken on Iranian networks" months later, so the exact pairs are pinned.
library;

import 'package:blackout_kit_mobile/models/dns_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('catalogue', () {
    test('sanctions pairs match XDNS', () {
      // Subset, not equality: the catalogue may grow, but these exact pairs
      // must never change or disappear.
      final pairs = {
        for (final p in DnsCatalog.inCategory(DnsCategory.sanctions))
          p.key: p.servers,
      };
      const expected = {
        'shecan': ['178.22.122.100', '185.51.200.2'],
        'electro': ['78.157.42.100', '78.157.42.101'],
        'begzar': ['185.55.226.26', '185.55.226.25'],
        'radar': ['10.202.10.10', '10.202.10.11'],
        'opendns': ['208.67.222.222', '208.67.220.220'],
      };
      for (final entry in expected.entries) {
        expect(pairs[entry.key], entry.value, reason: entry.key);
      }
    });

    test('speed pairs match XDNS', () {
      final pairs = {
        for (final p in DnsCatalog.inCategory(DnsCategory.speed))
          p.key: p.servers,
      };
      const expected = {
        'yandex': ['77.88.8.8', '77.88.8.1'],
        'cloudflare': ['1.1.1.1', '1.0.0.1'],
        'google': ['8.8.8.8', '8.8.4.4'],
      };
      for (final entry in expected.entries) {
        expect(pairs[entry.key], entry.value, reason: entry.key);
      }
    });

    test('the catalogue is a decent size', () {
      expect(DnsCatalog.all.length, greaterThanOrEqualTo(30));
    });

    test('keys are unique', () {
      final keys = DnsCatalog.all.map((p) => p.key).toList();
      expect(keys.toSet().length, keys.length);
    });

    test('no address is shared between providers', () {
      // Two providers claiming one address would make byAddress ambiguous.
      final seen = <String, String>{};
      for (final provider in DnsCatalog.all) {
        for (final server in provider.servers) {
          expect(seen.containsKey(server), isFalse,
              reason: '$server used by ${seen[server]} and ${provider.key}');
          seen[server] = provider.key;
        }
      }
    });

    test('every address is an IP literal', () {
      for (final provider in DnsCatalog.all) {
        for (final server in provider.servers) {
          expect(DnsCatalog.isIpLiteral(server), isTrue,
              reason: '${provider.key} -> $server');
        }
      }
    });

    test('primary comes first in servers', () {
      for (final provider in DnsCatalog.all) {
        expect(provider.servers.first, provider.primary);
      }
    });

    test('fallback is Cloudflare', () {
      expect(DnsCatalog.fallback.primary, '1.1.1.1');
      expect(DnsCatalog.fallback.servers, ['1.1.1.1', '1.0.0.1']);
    });

    test('every category has a label and at least one provider', () {
      for (final category in DnsCategory.values) {
        expect(DnsCatalog.categoryLabels[category], isNotNull);
        expect(DnsCatalog.inCategory(category), isNotEmpty);
      }
    });
  });

  group('lookup', () {
    test('byKey is case-sensitive on the key only', () {
      expect(DnsCatalog.byKey('shecan')?.name, 'Shecan');
      expect(DnsCatalog.byKey('Shecan'), isNull);
      expect(DnsCatalog.byKey(''), isNull);
      expect(DnsCatalog.byKey(null), isNull);
    });

    test('byAddress resolves the secondary too', () {
      expect(DnsCatalog.byAddress('185.51.200.2')?.key, 'shecan');
      expect(DnsCatalog.byAddress('1.0.0.1')?.key, 'cloudflare');
      expect(DnsCatalog.byAddress('203.0.113.9'), isNull);
    });

    test('activeFor matches on the primary address', () {
      expect(DnsCatalog.activeFor(['178.22.122.100', '185.51.200.2'])?.key,
          'shecan');
      expect(DnsCatalog.activeFor(['203.0.113.9']), isNull);
      expect(DnsCatalog.activeFor([]), isNull);
    });
  });

  group('address parsing', () {
    test('isIpLiteral accepts v4 and v6, rejects hostnames', () {
      expect(DnsCatalog.isIpLiteral('1.1.1.1'), isTrue);
      expect(DnsCatalog.isIpLiteral('2606:4700:4700::1111'), isTrue);
      expect(DnsCatalog.isIpLiteral('dns.example.com'), isFalse);
      expect(DnsCatalog.isIpLiteral('1.1.1'), isFalse);
      expect(DnsCatalog.isIpLiteral('1.1.1.256'), isFalse);
      expect(DnsCatalog.isIpLiteral(''), isFalse);
    });

    test('parseServers splits on comma and whitespace and drops hostnames', () {
      expect(DnsCatalog.parseServers('1.1.1.1, 1.0.0.1'),
          ['1.1.1.1', '1.0.0.1']);
      expect(DnsCatalog.parseServers('1.1.1.1 dns.example.com 8.8.8.8'),
          ['1.1.1.1', '8.8.8.8']);
    });
  });

  group('labels', () {
    test('label shows both addresses when there is a pair', () {
      expect(DnsCatalog.byKey('cloudflare')!.label,
          'Cloudflare (1.1.1.1, 1.0.0.1)');
    });

    test('toJson round-trips the fields the CLI exposes', () {
      final json = DnsCatalog.byKey('radar')!.toJson();
      expect(json['key'], 'radar');
      expect(json['primary'], '10.202.10.10');
      expect(json['secondary'], '10.202.10.11');
      expect(json['category'], 'sanctions');
    });
  });
}
