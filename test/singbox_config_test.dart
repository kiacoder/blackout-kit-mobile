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
      expect(() => builder.build(awg), returnsNormally);
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

  group('amneziawg outbound', () {
    test('builds valid wireguard config with junk packet parameters', () {
      const builder = SingboxConfigBuilder();
      final config = ConfigParser.parse('''
[Interface]
PrivateKey = MY_PRIVATE_KEY
Jc = 4
Jmin = 50
Jmax = 90

[Peer]
PublicKey = MY_PEER_PUB_KEY
Endpoint = awg.server.com:51820
''')! as AmneziaWGConfig;

      final doc = builder.build(config);
      final outbounds = doc['outbounds'] as List;
      final proxy = outbounds.firstWhere((o) => o['tag'] == 'proxy') as Map;

      expect(proxy['type'], 'wireguard');
      expect(proxy['server'], 'awg.server.com');
      expect(proxy['server_port'], 51820);
      expect(proxy['private_key'], 'MY_PRIVATE_KEY');
      expect(proxy['peer_public_key'], 'MY_PEER_PUB_KEY');
      expect(proxy['reserved'], [4, 50, 90]);
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
}
