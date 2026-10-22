/// Parser regressions from the second audit (BK-015/016/017/019/020/055/057/058).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:blackout_kit_mobile/models/config.dart';

void main() {
  group('BK-015 shadowsocks port', () {
    test('a trailing slash no longer forces the default port', () {
      // aes-256-gcm:pass
      final c = ConfigParser.parse(
        'ss://YWVzLTI1Ni1nY206cGFzcw==@example.com:1234/#Node',
      ) as ShadowsocksConfig?;
      expect(c, isNotNull);
      expect(c!.port, 1234);
      expect(c.address, 'example.com');
    });

    test('bracketed IPv6 authority keeps host and port', () {
      final c = ConfigParser.parse(
        'ss://YWVzLTI1Ni1nY206cGFzcw==@[2001:db8::1]:9999#v6',
      ) as ShadowsocksConfig?;
      expect(c, isNotNull);
      expect(c!.address, '2001:db8::1');
      expect(c.port, 9999);
    });
  });

  test('BK-016 shadowsocks plugin metadata is read', () {
    final c = ConfigParser.parse(
      'ss://YWVzLTI1Ni1nY206cGFzcw==@example.com:8388/?plugin=obfs-local%3Bobfs%3Dhttp#p',
    ) as ShadowsocksConfig?;
    expect(c, isNotNull);
    expect(c!.plugin, contains('obfs-local'));
  });

  group('BK-017 trojan', () {
    test('percent-encoded password is decoded', () {
      final c = ConfigParser.parse(
        'trojan://p%40ss%3Aword@example.com:443?sni=x.com#t',
      ) as TrojanConfig?;
      expect(c, isNotNull);
      expect(c!.password, 'p@ss:word');
    });

    test('allowInsecure=true is honoured, not just "1"', () {
      final c = ConfigParser.parse(
        'trojan://pw@example.com:443?allowInsecure=true#t',
      ) as TrojanConfig?;
      expect(c!.allowInsecure, isTrue);
    });
  });

  test('BK-019 a comment mentioning "remote " is not OpenVPN', () {
    const conf = '''
[Interface]
PrivateKey = PRIV
Address = 10.0.0.2/32
# remote server lives in Germany
[Peer]
PublicKey = PUB
Endpoint = 1.2.3.4:51820
''';
    final c = ConfigParser.parse(conf);
    expect(c, isA<WireGuardConfig>());
    expect(c, isNot(isA<OpenVpnConfig>()));
  });

  test('BK-020 AWG IPv6 endpoint keeps the whole host', () {
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
    expect(c, isNotNull);
    expect(c!.address, '2001:db8::5');
    expect(c.port, 51820);
  });

  test('BK-055 OpenVPN without a remote is rejected', () {
    const conf = '''
client
dev tun
proto udp
<ca>
CERTDATA
</ca>
''';
    expect(ConfigParser.parse(conf), isNull);
  });

  group('BK-057/058 embedded URI extraction', () {
    test('uppercase scheme in a markdown table is found', () {
      const table = '''
| Name | Link |
|------|------|
| Node | VLESS://11111111-1111-1111-1111-111111111111@example.com:443?security=none&type=tcp#Upper |
''';
      final list = ConfigParser.parseMultiple(table);
      expect(list, isNotEmpty);
      expect(list.first.displayName, contains('Upper'));
    });

    test('bracketed IPv6 link is not truncated at the bracket', () {
      final list = ConfigParser.parseMultiple(
        'see vless://11111111-1111-1111-1111-111111111111@[2001:db8::7]:443?security=none&type=tcp#V6 for details',
      );
      expect(list, hasLength(1));
      expect(list.first.address, '2001:db8::7');
      expect(list.first.port, 443);
    });
  });
}
