/// Verification suite: every fix claimed in v1.12.0 and v1.12.1, asserted
/// against the real code paths.
///
/// The point is not to re-run the regression tests but to prove the behaviour
/// the release notes promise. Anything that fails here is a claim that is not
/// true, whatever the original tests say.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:blackout_kit_mobile/controllers/config_controller.dart';
import 'package:blackout_kit_mobile/models/config.dart';
import 'package:blackout_kit_mobile/models/config_source.dart';
import 'package:blackout_kit_mobile/models/vpn_session_options.dart';
import 'package:blackout_kit_mobile/services/config_service.dart';
import 'package:blackout_kit_mobile/models/test_result.dart';
import 'package:blackout_kit_mobile/services/github_service.dart';
import 'package:blackout_kit_mobile/services/ip_info_service.dart';
import 'package:blackout_kit_mobile/services/tester_service.dart';
import 'package:blackout_kit_mobile/services/localization_service.dart';
import 'package:blackout_kit_mobile/services/secure_vault.dart';
import 'package:blackout_kit_mobile/services/singbox_config.dart';
import 'package:blackout_kit_mobile/services/vpn_service.dart';
import 'package:blackout_kit_mobile/services/xray_config.dart';

Config vless(String host, String name, {String extra = ''}) => ConfigParser.parse(
      'vless://11111111-1111-1111-1111-111111111111@$host:443?security=none&type=tcp$extra#$name',
    )!;

Map<String, dynamic> xrayDoc(String uri, {bool dnsThroughProxy = false}) {
  final config = ConfigParser.parse(uri)!;
  return XrayConfigBuilder(routeDnsThroughProxy: dnsThroughProxy)
      .build(config);
}

Map<String, dynamic> singboxDoc(String uri, {bool dnsThroughProxy = true}) {
  final config = ConfigParser.parse(uri)!;
  return SingboxConfigBuilder(routeDnsThroughProxy: dnsThroughProxy)
      .build(config);
}

void main() {
  // ── BK-002 / BK-003: strict DNS keeps no local resolver ─────────────────
  group('DNS leak prevention (BK-002/003)', () {
    test('xray strict mode has no +local and no localhost', () {
      final doc = xrayDoc(
        'vless://11111111-1111-1111-1111-111111111111@a.com:443',
        dnsThroughProxy: true,
      );
      final servers =
          ((doc['dns'] as Map)['servers'] as List).cast<String>();
      expect(servers.any((s) => s.contains('+local')), isFalse,
          reason: 'https+local bootstraps through the device resolver');
      expect(servers.contains('localhost'), isFalse);
      expect(servers.any((s) => s.startsWith('https://')), isTrue);
    });

    test('sing-box default resolver is the proxied one', () {
      // sing-box serves its own protocol set; anytls is one of them.
      final doc = singboxDoc(
          'anytls://password@a.com:443?sni=a.com#node');
      final route = doc['route'] as Map;
      final resolver = route['default_domain_resolver'] as Map;
      expect(resolver['server'], 'remote-dns',
          reason: 'user traffic must resolve through the tunnel');

      final dns = doc['dns'] as Map;
      final servers = (dns['servers'] as List).cast<Map>();

      // No resolver may be a hostname: that would need resolving itself.
      for (final server in servers) {
        final address = server['server'] as String;
        expect(RegExp(r'^[0-9.]+$').hasMatch(address) ||
                address.contains(':'),
            isTrue,
            reason: '$address needs a resolver to reach the resolver');
      }

      // Exactly one resolver is direct, and it exists only to resolve the
      // proxy's own hostname - otherwise the tunnel can never come up.
      final bootstrap =
          servers.firstWhere((s) => s['tag'] == 'bootstrap-dns');
      expect(bootstrap['detour'], 'direct');
      expect(servers.any((s) => s['tag'] == 'local-dns'), isFalse);

      final proxy = ((doc['outbounds'] as List).first as Map);
      expect((proxy['domain_resolver'] as Map)['server'], 'bootstrap-dns');
    });
  });

  // ── BK-017: trojan password decoding ────────────────────────────────────
  group('parser claims (BK-015..BK-058)', () {
    test('trojan password is percent-decoded (BK-017)', () {
      final c = ConfigParser.parse(
        'trojan://p%40ss%3Aword@example.com:443?sni=x.com#t',
      ) as TrojanConfig?;
      expect(c!.password, 'p@ss:word');
    });

    test('shadowsocks trailing slash keeps the port (BK-015)', () {
      final c = ConfigParser.parse(
        'ss://YWVzLTI1Ni1nY206cGFzcw==@example.com:1234/#n',
      ) as ShadowsocksConfig?;
      expect(c!.port, 1234);
    });

    test('shadowsocks plugin is parsed (BK-016)', () {
      final c = ConfigParser.parse(
        'ss://YWVzLTI1Ni1nY206cGFzcw==@example.com:8388/?plugin=obfs-local%3Bobfs%3Dhttp#p',
      ) as ShadowsocksConfig?;
      expect(c!.plugin, contains('obfs-local'));
    });

    test('a comment saying "remote " is not OpenVPN (BK-019)', () {
      const conf = '''
[Interface]
PrivateKey = PRIV
Address = 10.0.0.2/32
# remote server lives in Germany
[Peer]
PublicKey = PUB
Endpoint = 1.2.3.4:51820
''';
      expect(ConfigParser.parse(conf), isA<WireGuardConfig>());
    });

    test('AmneziaWG IPv6 endpoint survives (BK-020)', () {
      const conf = '''
[Interface]
PrivateKey = PRIV
Address = 10.0.0.2/32
Jc = 4
[Peer]
PublicKey = PUB
Endpoint = [2001:db8::5]:51820
''';
      final c = ConfigParser.parse(conf) as AmneziaWGConfig?;
      expect(c!.address, '2001:db8::5');
      expect(c.port, 51820);
    });

    test('OpenVPN without a remote is rejected (BK-055)', () {
      expect(
        ConfigParser.parse('client\ndev tun\nproto udp\n<ca>\nX\n</ca>\n'),
        isNull,
      );
    });

    test('uppercase scheme and bracketed IPv6 are extracted (BK-057/058)', () {
      final list = ConfigParser.parseMultiple(
        '| Node | VLESS://11111111-1111-1111-1111-111111111111@[2001:db8::7]:443?security=none&type=tcp#V6 |',
      );
      expect(list, hasLength(1));
      expect(list.first.address, '2001:db8::7');
    });
  });

  // ── BK-021: transports emit their settings ──────────────────────────────
  group('transport settings (BK-021)', () {
    test('kcp carries header type and seed', () {
      final doc = xrayDoc(
        'vless://11111111-1111-1111-1111-111111111111@a.com:443?type=kcp&headerType=srtp&seed=s1',
      );
      final stream =
          (doc['outbounds'] as List).first['streamSettings'] as Map;
      final kcp = stream['kcpSettings'] as Map;
      expect((kcp['header'] as Map)['type'], 'srtp');
      expect(kcp['seed'], 's1');
    });

    test('quic carries security, key and header', () {
      final doc = xrayDoc(
        'vless://11111111-1111-1111-1111-111111111111@a.com:443?type=quic&quicSecurity=aes-128-gcm&key=k1&headerType=dtls',
      );
      final stream =
          (doc['outbounds'] as List).first['streamSettings'] as Map;
      final quic = stream['quicSettings'] as Map;
      expect(quic['security'], 'aes-128-gcm');
      expect(quic['key'], 'k1');
    });

    test('http carries host and path', () {
      final doc = xrayDoc(
        'vless://11111111-1111-1111-1111-111111111111@a.com:443?type=http&path=%2Fh2&host=cdn.example.com',
      );
      final stream =
          (doc['outbounds'] as List).first['streamSettings'] as Map;
      final http = stream['httpSettings'] as Map;
      expect(http['path'], '/h2');
      expect(http['host'], ['cdn.example.com']);
    });
  });

  // ── BK-024: DNS validation ──────────────────────────────────────────────
  group('DNS validation (BK-024)', () {
    test('real literals pass, colon junk does not', () {
      expect(VpnSessionOptions.looksLikeIpForTest('1.1.1.1'), isTrue);
      expect(VpnSessionOptions.looksLikeIpForTest('2001:db8::1'), isTrue);
      expect(VpnSessionOptions.looksLikeIpForTest('http://x'), isFalse);
      expect(VpnSessionOptions.looksLikeIpForTest('a:b'), isFalse);
      expect(VpnSessionOptions.looksLikeIpForTest('1:2:3'), isFalse);
    });
  });

  // ── BK-025: IP lookups are opt-in ───────────────────────────────────────
  group('IP lookup privacy (BK-025)', () {
    test('off by default: the tunnel is never asked', () async {
      final fake = _FakeVpnService();
      final service = IpInfoService(vpnService: fake);
      await service.fetchExit();
      expect(fake.lastLookupAttempted, isFalse);
      expect(service.lastLookupAttempted, isFalse);
    });

    test('on: the lookup happens', () async {
      final fake = _FakeVpnService();
      final service = IpInfoService(vpnService: fake);
      service.setLookupsEnabled(true);
      final info = await service.fetchExit();
      expect(fake.lastLookupAttempted, isTrue);
      expect(info.ip, '203.0.113.9');
    });
  });

  // ── BK-047: RTL ─────────────────────────────────────────────────────────
  group('localization (BK-047)', () {
    test('arabic is RTL and every language has a locale', () {
      expect(LocalizationService.isRtl('ar'), isTrue);
      final codes =
          LocalizationService.supportedLocales.map((l) => l.languageCode).toSet();
      for (final code in LocalizationService.supportedLanguages.keys) {
        expect(codes, contains(code));
      }
    });
  });

  // ── BK-053: encrypted at rest ───────────────────────────────────────────
  group('encrypted storage (BK-053)', () {
    late Directory tempDir;

    setUp(() async {
      await Hive.close();
      tempDir = await Directory.systemTemp.createTemp('bk_verify');
      Hive.init(tempDir.path);
    });

    tearDown(() async {
      await Hive.close();
      await tempDir.delete(recursive: true);
    });

    test('migration moves records and removes the plaintext box', () async {
      final legacy = await Hive.openBox<dynamic>('configs');
      await legacy.put('config_x', {
        'protocol': 'vless',
        'displayName': 'Legacy',
        'rawUri':
            'vless://11111111-1111-1111-1111-111111111111@legacy.example.com:443?security=none&type=tcp#Legacy',
      });
      await legacy.close();

      final service = ConfigService(keyStore: MemoryKeyStore());
      await service.initialize();

      expect(service.isEncryptedAtRest, isTrue);
      expect(await Hive.boxExists('configs'), isFalse);
      expect(service.getAllConfigs().map((c) => c.displayName),
          contains('Legacy'));
    });

    test('a restart with the same key reads the encrypted box', () async {
      final store = MemoryKeyStore();
      final first = ConfigService(keyStore: store);
      await first.initialize();
      final config = vless('rt.example.com', 'RoundTrip');
      await first.saveConfig(config);

      final second = ConfigService(keyStore: store);
      await second.initialize();
      expect(second.isEncryptedAtRest, isTrue);
      expect(second.getAllConfigs().map((c) => c.displayName),
          contains('RoundTrip'));
    });

    test('without a keystore the app still boots and reads configs', () async {
      // A platform with no keystore must degrade to plaintext, not fail.
      final legacy = await Hive.openBox<dynamic>('configs');
      await legacy.put('config_y', {
        'protocol': 'vless',
        'displayName': 'Plain',
        'rawUri':
            'vless://11111111-1111-1111-1111-111111111111@plain.example.com:443?security=none&type=tcp#Plain',
      });
      await legacy.close();

      final service = ConfigService(keyStore: _BrokenKeyStore());
      await service.initialize();

      expect(service.isEncryptedAtRest, isFalse);
      expect(service.getAllConfigs().map((c) => c.displayName),
          contains('Plain'));
    });
  });

  // ── BK-027/028: filters ─────────────────────────────────────────────────
  group('library filters (BK-027/028)', () {
    test('source filter does not leak tested configs, recently-added sorts',
        () async {
      await Hive.close();
      final dir = await Directory.systemTemp.createTemp('bk_filter_verify');
      Hive.init(dir.path);
      try {
        final service = ConfigService(keyStore: MemoryKeyStore());
        await service.initialize();
        final controller = ConfigController(
          configService: service,
          githubService: GitHubService(),
          testerService: TesterService(),
        );
        // Both sources enabled, otherwise visibleConfigs hides everything.
        controller.sources.value = const [
          ConfigSource(id: 's1', name: 'One', owner: 'a', repo: 'a'),
          ConfigSource(id: 's2', name: 'Two', owner: 'b', repo: 'b'),
        ];
        final a = vless('a.example.com', 'A');
        final b = vless('b.example.com', 'B');
        await service.saveConfig(a, sourceId: 's1');
        await service.saveConfig(b, sourceId: 's2');
        controller.allConfigs.value = [a, b];
        controller.sourceIdsByHash.value = {
          a.getHash(): {'s1'},
          b.getHash(): {'s2'},
        };
        controller.testResults[b.getHash()] = TestResult.success(
          configHash: b.getHash(),
          latencyMs: 30,
        );
        controller.filterSource.value = 's1';
        expect(controller.getFilteredConfigs().map((c) => c.displayName), ['A']);

        controller.filterSource.value = 'all';
        controller.sortBy.value = 'recently_added';
        controller.savedAtByHash.value = {
          a.getHash(): DateTime(2026, 1, 1),
          b.getHash(): DateTime(2026, 6, 1),
        };
        expect(
          controller.getFilteredConfigs().map((c) => c.displayName).toList(),
          ['B', 'A'],
        );
      } finally {
        await Hive.close();
        await dir.delete(recursive: true);
      }
    });
  });
}

// ── helpers ───────────────────────────────────────────────────────────────

class _FakeVpnService extends VPNService {
  _FakeVpnService() : super();
  bool lastLookupAttempted = false;

  @override
  Future<String?> tunnelFetch(String url,
      {Duration timeout = const Duration(seconds: 10)}) async {
    lastLookupAttempted = true;
    return '{"success":true,"ip":"203.0.113.9","country":"Testland",'
        '"country_code":"TL","city":"Nowhere"}';
  }
}

/// A key store that always fails, standing in for a device with no keystore.
class _BrokenKeyStore implements KeyStore {
  @override
  Future<String?> read(String key) async => throw Exception('no keystore');

  @override
  Future<void> write(String key, String value) async =>
      throw Exception('no keystore');
}


