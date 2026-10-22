/// Parser and controller findings from the third audit round.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:blackout_kit_mobile/models/config.dart';

const awg = '''
[Interface]
PrivateKey = K
Address = 10.0.0.2/32
Jc = 5
Jmin = 40
Jmax = 70

[Peer]
PublicKey = P
Endpoint = awg.example.com:51820
''';

void main() {
  group('PAR-02 AmneziaWG survives multi-import', () {
    test('parseMultiple classifies the block as AWG, not WireGuard', () {
      final list = ConfigParser.parseMultiple(awg);
      expect(list, hasLength(1));
      expect(list.first, isA<AmneziaWGConfig>(),
          reason: 'the block flush hard-coded WireGuardConfig');
    });

    test('lowercase jc is still AWG', () {
      final c = ConfigParser.parse(awg.replaceAll('Jc = 5', 'jc = 5'));
      expect(c, isA<AmneziaWGConfig>());
    });

    test('a plain WireGuard block stays WireGuard', () {
      const wg = '''
[Interface]
PrivateKey = K
Address = 10.0.0.2/32

[Peer]
PublicKey = P
Endpoint = wg.example.com:51820
''';
      expect(ConfigParser.parse(wg), isA<WireGuardConfig>());
    });
  });

  group('PAR-01 a .conf mentioning a URL keeps its key case', () {
    test('the private key is not lower-cased', () {
      const conf = '''
[Interface]
PrivateKey = AbCdEfGhIjKlMnOpQrStUvWxYz0123456789ABCD=
Address = 10.0.0.2/32
# docs: https://Example.COM/guide

[Peer]
PublicKey = ZyXwVuTsRqPoNmLkJiHgFeDcBa9876543210ZYX=
Endpoint = wg.example.com:51820
''';
      final c = ConfigParser.parse(conf) as WireGuardConfig?;
      expect(c, isNotNull);
      expect(c!.privateKey, startsWith('AbCdEfGh'),
          reason: 'normalizeScheme used to lower-case everything before ://');
    });

    test('an uppercase scheme is still normalised', () {
      final c = ConfigParser.parse(
        'VLESS://11111111-1111-1111-1111-111111111111@a.com:443?security=none#x',
      );
      expect(c, isA<VlessConfig>());
    });
  });

  group('SCN-01 psiphon needs a real document', () {
    test('a line mentioning psiphon is not a config', () {
      expect(
        ConfigParser.parse('psiphon lists: vless://abc@a.com:443#x'),
        isNot(isA<PsiphonConfig>()),
      );
    });

    test('a bare JSON blob is not a psiphon config', () {
      expect(ConfigParser.parse('{"hello":"world"}'), isNull);
    });

    test('a real psiphon document is accepted', () {
      final c = ConfigParser.parse('{"region":"US","proxiedSites":[]}');
      expect(c, isA<PsiphonConfig>());
    });
  });

  group('IMP-01 pasting several links yields several configs', () {
    test('parseMultiple keeps every link', () {
      final text = [
        'vless://11111111-1111-1111-1111-111111111111@a.com:443?security=none#A',
        'trojan://pw@b.com:443?sni=b.com#B',
        'ss://YWVzLTI1Ni1nY206cGFzcw==@c.com:8388#C',
      ].join('\n');
      final list = ConfigParser.parseMultiple(text);
      expect(list.map((c) => c.displayName).toSet(), {'A', 'B', 'C'});
    });
  });
}
