/// Regressions for the engine and parser findings in the third audit round.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:blackout_kit_mobile/models/config.dart';
import 'package:blackout_kit_mobile/services/xray_config.dart';

Map<String, dynamic> stream(String uri) {
  final config = ConfigParser.parse(uri)!;
  final doc = const XrayConfigBuilder().build(config);
  return (((doc['outbounds'] as List).first as Map)['streamSettings'] as Map)
      .cast<String, dynamic>();
}

const uuid = '11111111-1111-1111-1111-111111111111';

void main() {
  group('ENG-X01 Shadowsocks must not be wrapped in TLS', () {
    test('ss:// emits security none', () {
      final s = stream('ss://YWVzLTI1Ni1nY206cGFzcw==@example.com:8388#n');
      expect(s['security'], 'none',
          reason: 'a Shadowsocks server cannot answer a TLS ClientHello');
      expect(s.containsKey('tlsSettings'), isFalse);
    });

    test('every non-TLS protocol stays none', () {
      for (final uri in [
        'ss://YWVzLTI1Ni1nY206cGFzcw==@a.com:8388#a',
        'vless://$uuid@b.com:80?security=none&type=tcp#b',
      ]) {
        expect(stream(uri)['security'], 'none', reason: uri);
      }
    });

    test('trojan is still TLS by definition', () {
      expect(stream('trojan://pw@c.com:443?sni=c.com#c')['security'], 'tls');
    });
  });

  group('ENG-X05 vmess tls:none means no TLS', () {
    test('tls "none" emits security none', () {
      // {"net":"ws","tls":"none"}
      const b64 =
          'eyJ2IjoiMiIsInBzIjoidCIsImFkZCI6ImEuY29tIiwicG9ydCI6IjQ0MyIsImlkIjoiMTExMTExMTEtMTExMS0xMTExLTExMTEtMTExMTExMTExMTExIiwiYWlkIjoiMCIsInNjeSI6ImF1dG8iLCJuZXQiOiJ3cyIsInR5cGUiOiJub25lIiwiaG9zdCI6IiIsInBhdGgiOiIvIiwidGxzIjoibm9uZSJ9';
      expect(stream('vmess://$b64')['security'], 'none');
    });
  });

  group('ENG-X06 vmess gRPC service name', () {
    test('serviceName reaches grpcSettings', () {
      const b64 =
          'eyJ2IjoiMiIsInBzIjoidCIsImFkZCI6ImEuY29tIiwicG9ydCI6IjQ0MyIsImlkIjoiMTExMTExMTEtMTExMS0xMTExLTExMTEtMTExMTExMTExMTExIiwiYWlkIjoiMCIsInNjeSI6ImF1dG8iLCJuZXQiOiJncnBjIiwidHlwZSI6Im5vbmUiLCJob3N0IjoiIiwicGF0aCI6Im15c2VydmljZSIsInRscyI6InRscyJ9';
      final s = stream('vmess://$b64');
      expect(s['network'], 'grpc');
      expect((s['grpcSettings'] as Map)['serviceName'], 'myservice');
    });
  });

  group('ENG-X03 httpupgrade', () {
    test('carries path and host instead of falling back to tcp', () {
      final s = stream(
        'vless://$uuid@a.com:443?type=httpupgrade&path=%2Fup&host=cdn.example.com#u',
      );
      expect(s['network'], 'httpupgrade');
      expect((s['httpupgradeSettings'] as Map)['path'], '/up');
      expect((s['httpupgradeSettings'] as Map)['host'], 'cdn.example.com');
    });
  });

  group('ENG-X04 allowInsecure is emitted only when requested', () {
    test('a link that asks for it gets it', () {
      final s = stream('vless://$uuid@a.com:443?security=tls&allowInsecure=1#x');
      expect((s['tlsSettings'] as Map)['allowInsecure'], isTrue);
    });

    test('a link that does not ask keeps full verification', () {
      final s = stream('vless://$uuid@a.com:443?security=tls#x');
      expect((s['tlsSettings'] as Map).containsKey('allowInsecure'), isFalse);
    });
  });

  group('BK-06 every insecure spelling is honoured', () {
    test('vless accepts insecure, allow_insecure and allowInsecure', () {
      for (final flag in ['insecure', 'allow_insecure', 'allowInsecure']) {
        final c = ConfigParser.parse(
          'vless://$uuid@a.com:443?security=tls&$flag=1#x',
        ) as VlessConfig?;
        expect(c!.allowInsecure, isTrue, reason: flag);
      }
    });

    test('trojan accepts the same spellings', () {
      for (final flag in ['insecure', 'allow_insecure', 'allowInsecure']) {
        final c = ConfigParser.parse(
          'trojan://pw@a.com:443?sni=a.com&$flag=1#x',
        ) as TrojanConfig?;
        expect(c!.allowInsecure, isTrue, reason: flag);
      }
    });
  });

  group('BK-04 passwords are percent-decoded', () {
    test('hysteria2', () {
      final c = ConfigParser.parse('hy2://p%40ss%3Aword@a.com:443#h')
          as Hysteria2Config?;
      expect(c!.password, 'p@ss:word');
    });

    test('tuic splits before decoding, so an encoded colon is safe', () {
      final c = ConfigParser.parse('tuic://$uuid:p%40ss%3Aword@a.com:443#t')
          as TuicConfig?;
      expect(c!.uuid, uuid);
      expect(c.password, 'p@ss:word');
    });

    test('anytls and shadowtls', () {
      final a = ConfigParser.parse('anytls://p%40ss@a.com:443#a') as AnyTlsConfig?;
      expect(a!.password, 'p@ss');
      final s = ConfigParser.parse('shadowtls://p%40ss@a.com:443#s') as ShadowTlsConfig?;
      expect(s!.password, 'p@ss');
    });
  });
}
