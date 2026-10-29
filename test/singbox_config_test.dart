import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:blackout_kit_mobile/models/config.dart';
import 'package:blackout_kit_mobile/services/singbox_config.dart';

void main() {
  group('SingboxConfigBuilder protocol support', () {
    test('accepts protocols served by the bundled sing-box core', () {
      const builder = SingboxConfigBuilder();
      final hy2 = ConfigParser.parse('hy2://pass@example.com:443?sni=example.com')!;
      final tuic = ConfigParser.parse('tuic://11111111-1111-1111-1111-111111111111:pass@example.com:443')!;
      final awg = ConfigParser.parse('''
[Interface]
PrivateKey = PRIVKEY
Jc = 5
Jmin = 40
Jmax = 70

[Peer]
PublicKey = PUBKEY
Endpoint = example.com:51820
''')!;

      expect(() => builder.build(hy2), returnsNormally);
      expect(() => builder.build(tuic), returnsNormally);
      // AmneziaWG is deliberately NOT advertised any more: the bundled core
      // contains no AmneziaWG symbols, so the `amnezia` block is rejected as
      // an unknown field and the tunnel can never come up. Refusing to build
      // is honest; the old code built it and failed at connect.
      expect(() => builder.build(awg), throwsArgumentError);
      expect(kSingboxProtocols, isNot(contains('amneziawg')));
      expect(kSingboxProtocols, isNot(contains('shadowtls')));
      expect(kSingboxProtocols, isNot(contains('warp')));
    });

    test('rejects non-singbox protocols', () {
      const builder = SingboxConfigBuilder();
      final vless = ConfigParser.parse('vless://11111111-1111-1111-1111-111111111111@example.com:443')!;

      expect(() => builder.build(vless), throwsArgumentError);
    });
  });

  group('hysteria2 outbound', () {
    test('builds valid hysteria2 config with tls and obfs', () {
      const builder = SingboxConfigBuilder();
      final config = ConfigParser.parse(
        'hy2://mypassword@hy2.server.com:8443?sni=sni.server.com&insecure=1&up=50&down=100&obfs=salamander&obfs-password=obfspass',
      )! as Hysteria2Config;

      final doc = builder.build(config);
      final outbounds = doc['outbounds'] as List;
      final proxy = outbounds.firstWhere((o) => o['tag'] == 'proxy') as Map;

      expect(proxy['type'], 'hysteria2');
      expect(proxy['server'], 'hy2.server.com');
      expect(proxy['server_port'], 8443);
      expect(proxy['password'], 'mypassword');
      expect(proxy['up_mbps'], 50);
      expect(proxy['down_mbps'], 100);
      expect(proxy['obfs'], {'type': 'salamander', 'password': 'obfspass'});

      final tls = proxy['tls'] as Map;
      expect(tls['enabled'], isTrue);
      expect(tls['server_name'], 'sni.server.com');
      expect(tls['insecure'], isTrue);
      expect(tls['alpn'], ['h3']);
    });
  });

  group('tuic outbound', () {
    test('builds valid tuic v5 config with bbr and alpn', () {
      const builder = SingboxConfigBuilder();
      final config = ConfigParser.parse(
        'tuic://my-uuid:mypwd@tuic.server.com:443?sni=tuic.server.com&congestion_control=bbr&alpn=h3,h2',
      )! as TuicConfig;

      final doc = builder.build(config);
      final outbounds = doc['outbounds'] as List;
      final proxy = outbounds.firstWhere((o) => o['tag'] == 'proxy') as Map;

      expect(proxy['type'], 'tuic');
      expect(proxy['server'], 'tuic.server.com');
      expect(proxy['server_port'], 443);
      expect(proxy['uuid'], 'my-uuid');
      expect(proxy['password'], 'mypwd');
      expect(proxy['congestion_control'], 'bbr');

      final tls = proxy['tls'] as Map;
      expect(tls['enabled'], isTrue);
      expect(tls['server_name'], 'tuic.server.com');
      expect(tls['alpn'], ['h3', 'h2']);
    });
  });

  group('amneziawg model', () {
    test('parses the full interface, not just the junk parameters', () {
      final config = ConfigParser.parse('''
[Interface]
PrivateKey = MY_PRIVATE_KEY
Address = 172.16.9.2/32, fd00::2/128
MTU = 1300
Jc = 4
Jmin = 50
Jmax = 90
S1 = 12
S2 = 34
H1 = 1111
H4 = 4444

[Peer]
PublicKey = MY_PEER_PUB_KEY
PresharedKey = MY_PSK
Endpoint = awg.server.com:51820
''')! as AmneziaWGConfig;

      // The interface address used to be overwritten by the endpoint host and
      // replaced with a hard-coded 10.0.0.2/32.
      expect(config.address, 'awg.server.com');
      expect(config.localAddresses, ['172.16.9.2/32', 'fd00::2/128']);
      expect(config.mtu, 1300);
      expect(config.presharedKey, 'MY_PSK');
      // Obfuscation beyond Jc/Jmin/Jmax was dropped entirely.
      expect(config.s1, 12);
      expect(config.s2, 34);
      expect(config.h1, 1111);
      expect(config.h4, 4444);
    });

    test('the builder refuses it rather than emitting a config that cannot run',
        () {
      final config = ConfigParser.parse('''
[Interface]
PrivateKey = K
Jc = 4

[Peer]
PublicKey = P
Endpoint = awg.server.com:51820
''')!;
      expect(() => const SingboxConfigBuilder().build(config),
          throwsArgumentError);
    });
  });

  group('inbounds and routing', () {
    test('emits mixed inbound on socksPort', () {
      const builder = SingboxConfigBuilder(socksPort: 10999);
      final config = ConfigParser.parse('hy2://pass@example.com:443')!;
      final doc = builder.build(config);

      final inbounds = doc['inbounds'] as List;
      final mixed = inbounds.first as Map;
      expect(mixed['type'], 'mixed');
      expect(mixed['listen'], '127.0.0.1');
      expect(mixed['listen_port'], 10999);
    });

    test('supports split tunneling and DNS proxying', () {
      const builder = SingboxConfigBuilder(
        routeDnsThroughProxy: true,
        bypassDomains: ['ir', 'local'],
      );
      final config = ConfigParser.parse('hy2://pass@example.com:443')!;
      final doc = builder.build(config);

      expect(doc['dns'], isNotNull);
      final rules = (doc['route'] as Map)['rules'] as List;
      expect(rules.any((r) => (r['domain_suffix'] as List?)?.contains('ir') == true), isTrue);
    });

    test('buildJson outputs valid JSON round-trippable by jsonDecode', () {
      const builder = SingboxConfigBuilder();
      final config = ConfigParser.parse('hy2://pass@example.com:443')!;
      final jsonStr = builder.buildJson(config);

      expect(jsonDecode(jsonStr), isA<Map<String, dynamic>>());
    });
  });

  group('sing-box 1.13+/1.14 field compliance', () {
    // The bundled libsingbox.so is 1.13+: any legacy field makes the whole
    // document fail to decode, which surfaced on the phone as
    // "sing-box rejected the configuration: ... inbounds[0]: legacy inbound
    // fields are deprecated in sing-box 1.11.0 and removed in sing-box 1.13.0".
    // These tests pin the modern equivalents so the regression cannot return.

    test('no legacy sniff field on the inbound; sniff is a route action', () {
      const builder = SingboxConfigBuilder();
      final config = ConfigParser.parse('hy2://pass@example.com:443?sni=example.com')!;
      final doc = builder.build(config);

      final inbounds = doc['inbounds'] as List;
      final mixed = inbounds.firstWhere((i) => i['type'] == 'mixed') as Map;
      expect(mixed.containsKey('sniff'), isFalse,
          reason: 'the `sniff` inbound field was removed in sing-box 1.13');

      final route = doc['route'] as Map;
      final rules = route['rules'] as List;
      expect(rules.any((r) => (r as Map)['action'] == 'sniff'), isTrue,
          reason: 'sniffing must be a route rule action');
    });

    test('the sniff action comes after the bypass rules', () {
      // A sniff action terminates route evaluation: first means the bypass
      // rules never fire.
      const builder = SingboxConfigBuilder(bypassDomains: ['example.org']);
      final config = ConfigParser.parse('hy2://pass@example.com:443?sni=example.com')!;
      final rules = (builder.build(config)['route'] as Map)['rules'] as List;

      final actions = rules.map((r) => (r as Map)['outbound'] ?? r['action']).toList();
      final sniffIndex = rules.indexWhere((r) => (r as Map)['action'] == 'sniff');
      final bypassIndex = rules.indexWhere((r) => (r as Map)['outbound'] == 'direct');
      expect(sniffIndex, greaterThan(bypassIndex));
      expect(actions, isNotEmpty);
    });

    test('proxied DNS uses typed servers and dial-field resolvers', () {
      const builder = SingboxConfigBuilder(routeDnsThroughProxy: true);
      final config = ConfigParser.parse('hy2://pass@example.com:443?sni=example.com')!;
      final doc = builder.build(config);

      final dns = doc['dns'] as Map;
      final servers = dns['servers'] as List;
      // legacy `address` form was removed in sing-box 1.14
      expect(servers.every((s) => !(s as Map).containsKey('address')), isTrue);
      // Plain `udp` throughout: these resolvers are addressed by IP and speak
      // port 53. A DoH endpoint on an arbitrary resolver IP does not exist.
      expect(servers.every((s) => (s as Map)['type'] == 'udp'), isTrue);
      // the outbound DNS rule item is removed; the association lives in dial fields
      expect(dns.containsKey('rules'), isFalse);

      final route = doc['route'] as Map;
      expect(route['default_domain_resolver'], isNotNull);
      final proxy = (doc['outbounds'] as List).firstWhere((o) => o['tag'] == 'proxy') as Map;
      expect(proxy['domain_resolver'], isNotNull);
    });

    test('the chosen resolver pair is what actually answers queries', () {
      // Regression: `remote-dns` was hardcoded to https://1.1.1.1 and the
      // caller's addresses went into an unreferenced `remote-dns-ip` entry, so
      // the resolver picked in Settings was never used on any sing-box
      // protocol — and the secondary was dropped entirely.
      const builder = SingboxConfigBuilder(
        routeDnsThroughProxy: true,
        dnsServers: ['178.22.122.100', '185.51.200.2'],
      );
      final config = ConfigParser.parse('hy2://pass@example.com:443?sni=example.com')!;
      final doc = builder.build(config);

      final dns = doc['dns'] as Map;
      final servers = (dns['servers'] as List).cast<Map>();
      final byTag = {for (final s in servers) s['tag']: s};

      expect(dns['final'], 'remote-dns');
      expect(byTag['remote-dns']!['server'], '178.22.122.100');
      expect(byTag['remote-dns']!['detour'], 'proxy');
      // The bootstrap resolver must also be an IP literal of the pair, or a
      // filtered 1.1.1.1 stops the tunnel from ever resolving its own host.
      expect(byTag['bootstrap-dns']!['server'], '178.22.122.100');
      expect(byTag['bootstrap-dns']!.containsKey('detour'), isFalse);
      // Both halves of the pair are present.
      expect(byTag['remote-dns-2']!['server'], '185.51.200.2');
      expect(byTag['remote-dns-2']!['detour'], 'proxy');
    });

    test('a single resolver still produces a complete DNS section', () {
      const builder = SingboxConfigBuilder(
        routeDnsThroughProxy: true,
        dnsServers: ['9.9.9.9'],
      );
      final config = ConfigParser.parse('hy2://pass@example.com:443?sni=example.com')!;
      final doc = builder.build(config);

      final servers = ((doc['dns'] as Map)['servers'] as List).cast<Map>();
      expect(servers.map((s) => s['tag']), containsAll(['bootstrap-dns', 'remote-dns']));
      expect(servers.any((s) => s['tag'] == 'remote-dns-2'), isFalse);
      expect((doc['dns'] as Map)['final'], 'remote-dns');
    });

    test('without proxied DNS there is no dns block to go stale', () {
      const builder = SingboxConfigBuilder();
      final config = ConfigParser.parse('hy2://pass@example.com:443?sni=example.com')!;
      final doc = builder.build(config);

      expect(doc.containsKey('dns'), isFalse);
      final route = doc['route'] as Map;
      expect(route.containsKey('default_domain_resolver'), isFalse);
      final proxy = (doc['outbounds'] as List).firstWhere((o) => o['tag'] == 'proxy') as Map;
      expect(proxy.containsKey('domain_resolver'), isFalse);
    });
  });


  group('Android netlink restriction', () {
    // Google's SELinux policy bans netlink sockets for normal apps, and we run
    // sing-box as a subprocess (no Android platform interface), so any field
    // that enforces the interface monitor turns the ban into a FATAL:
    //   "initialize network manager: create network monitor: netlink socket
    //    in Android is banned by Google"
    // `auto_detect_interface` is exactly that field - and is documented as
    // Linux/Windows/macOS-only, so it was never valid on Android.
    test('route never carries auto_detect_interface', () {
      const builder = SingboxConfigBuilder();
      final config = ConfigParser.parse('hy2://pass@example.com:443?sni=example.com')!;
      final doc = builder.build(config);

      final route = doc['route'] as Map;
      expect(route.containsKey('auto_detect_interface'), isFalse);
    });

    test('no field anywhere selects an interface by name', () {
      const builder = SingboxConfigBuilder(routeDnsThroughProxy: true);
      final config = ConfigParser.parse('hy2://pass@example.com:443?sni=example.com')!;
      final json = builder.buildJson(config);

      expect(json.contains('auto_detect_interface'), isFalse);
      expect(json.contains('default_interface'), isFalse);
      expect(json.contains('bind_interface'), isFalse);
    });
  });

}
