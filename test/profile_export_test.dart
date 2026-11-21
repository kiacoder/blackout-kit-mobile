import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:blackout_kit_mobile/models/config.dart';
import 'package:blackout_kit_mobile/services/profile_export_service.dart';

void main() {
  const link = 'vless://00000000-0000-4000-8000-000000000001@example.com:443?security=tls#Test';
  const awg = '''[Interface]
PrivateKey = K
Address = 10.0.0.2/32
S4 = 12
[Peer]
PublicKey = P
Endpoint = example.com:51820''';

  test('JSON exports are reimportable raw-profile lists, with exact dedup', () {
    final profiles = [ConfigParser.parse(link)!, ConfigParser.parse(awg)!];
    final result = ProfileExportService.build([...profiles, profiles.first]);
    expect(result.included, 2);
    expect(jsonDecode(result.content), [link, awg]);
    final imported = ConfigParser.parseMultiple(result.content);
    expect(imported.length, 2);
    expect(imported.last, isA<AmneziaWGConfig>());
  });

  test('v2rayN export excludes AWG rather than converting it to WireGuard', () {
    final result = ProfileExportService.build(
      [ConfigParser.parse(link)!, ConfigParser.parse(awg)!], v2rayN: true,
    );
    expect(result.content, link);
    expect(result.included, 1);
    expect(result.omitted, 1);
  });

  test('empty library produces a valid empty JSON list', () {
    expect(ProfileExportService.build([]).content, '[]');
  });
}
