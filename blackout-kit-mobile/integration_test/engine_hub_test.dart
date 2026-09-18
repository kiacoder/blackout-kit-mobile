import 'package:blackout_kit_mobile/models/config.dart';
import 'package:blackout_kit_mobile/models/engine_capability.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Blackout Kit 10-Engine Integration Tests', () {
    test('All 10 Blackout CLI engines are registered in EngineRegistry', () {
      final engines = EngineRegistry.getAll();
      expect(engines.length, equals(10));

      final keys = engines.map((e) => e.key).toSet();
      expect(keys, containsAll([
        'xray',
        'singbox_proxy',
        'amneziawg',
        'wireguard',
        'openvpn',
        'shadowsocks',
        'sni',
        'warp',
        'psiphon',
        'mhrv',
      ]));
    });

    test('ConfigParser parses VLESS URI correctly (XRay engine)', () {
      const vlessUri = 'vless://12345678-1234-1234-1234-1234567890ab@example.com:443?security=reality&sni=example.com&pbk=xyz123#MyVLESS';
      final config = ConfigParser.parse(vlessUri);

      expect(config, isNotNull);
      expect(config, isA<VlessConfig>());
      final vless = config as VlessConfig;
      expect(vless.protocol, equals('vless'));
      expect(vless.address, equals('example.com'));
      expect(vless.port, equals(443));
      expect(vless.security, equals('reality'));
      expect(vless.displayName, equals('MyVLESS'));
    });

    test('ConfigParser parses Hysteria2 URI correctly (SingBox engine)', () {
      const hy2Uri = 'hy2://my-password@hy2.example.com:8443?sni=hy2.example.com&insecure=1#MyHy2';
      final config = ConfigParser.parse(hy2Uri);

      expect(config, isNotNull);
      expect(config, isA<Hysteria2Config>());
      final hy2 = config as Hysteria2Config;
      expect(hy2.protocol, equals('hysteria2'));
      expect(hy2.address, equals('hy2.example.com'));
      expect(hy2.port, equals(8443));
      expect(hy2.password, equals('my-password'));
      expect(hy2.displayName, equals('MyHy2'));
    });

    test('ConfigParser parses TUIC v5 URI correctly (SingBox engine)', () {
      const tuicUri = 'tuic://my-uuid:my-pass@tuic.example.com:8443?sni=tuic.example.com#MyTUIC';
      final config = ConfigParser.parse(tuicUri);

      expect(config, isNotNull);
      expect(config, isA<TuicConfig>());
      final tuic = config as TuicConfig;
      expect(tuic.protocol, equals('tuic'));
      expect(tuic.address, equals('tuic.example.com'));
      expect(tuic.port, equals(8443));
      expect(tuic.uuid, equals('my-uuid'));
      expect(tuic.password, equals('my-pass'));
      expect(tuic.displayName, equals('MyTUIC'));
    });

    test('ConfigParser parses AmneziaWG .conf content correctly (AmneziaWG engine)', () {
      const awgConf = '''
[Interface]
PrivateKey = my-private-key
Address = 10.0.0.2/32
DNS = 1.1.1.1
Jc = 4
Jmin = 40
Jmax = 70

[Peer]
PublicKey = my-public-key
Endpoint = 198.51.100.1:51820
''';
      final config = ConfigParser.parse(awgConf);

      expect(config, isNotNull);
      expect(config, isA<AmneziaWGConfig>());
      final awg = config as AmneziaWGConfig;
      expect(awg.protocol, equals('amneziawg'));
      expect(awg.address, equals('198.51.100.1'));
      expect(awg.port, equals(51820));
      expect(awg.junkCount, equals(4));
      expect(awg.junkMin, equals(40));
      expect(awg.junkMax, equals(70));
    });
  });
}
