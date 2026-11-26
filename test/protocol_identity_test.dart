import 'package:flutter_test/flutter_test.dart';
import 'package:blackout_kit_mobile/models/config.dart';
import 'package:blackout_kit_mobile/services/singbox_config.dart';

void main() {
  test('Hysteria v1 is never silently upgraded to Hysteria2', () {
    const uri = 'hysteria://secret@example.com:443';
    expect(Hysteria2Config.fromUri(uri), isNull);
    expect(ConfigParser.parse(uri), isNull);
    expect(ConfigParser.parseMultiple(uri), isEmpty);
  });

  for (final key in ['S3', 'S4', 'I1', 'I2', 'I3', 'I4', 'I5']) {
    test('$key alone identifies AWG and preserves the source', () {
      final raw = '''[Interface]
PrivateKey = K
Address = 10.0.0.2/32
$key = 42
[Peer]
PublicKey = P
Endpoint = example.com:51820
''';
      final profile = ConfigParser.parse(raw);
      expect(profile, isA<AmneziaWGConfig>());
      expect(profile!.rawUri, raw.trim());
      expect(ConfigParser.parseMultiple(raw).single, isA<AmneziaWGConfig>());
      expect(ConfigParser.parse(raw.replaceAll(key, key.toLowerCase())),
          isA<AmneziaWGConfig>());
      expect(() => const SingboxConfigBuilder().build(profile),
          throwsArgumentError);
    });
  }
}
