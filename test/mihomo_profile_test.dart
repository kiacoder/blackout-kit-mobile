import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:blackout_kit_mobile/models/config.dart';
import 'package:blackout_kit_mobile/services/profile_export_service.dart';
import 'package:blackout_kit_mobile/services/vpn_service.dart';

const document = '''proxies:
  - name: node
    type: socks5
    server: example.com
    port: 1080
proxy-groups:
  - name: selected
    type: select
    proxies: [node]
rules: ["MATCH,selected"]
''';

void main() {
  test('full YAML stays one profile and retains groups/rules', () {
    final configs = ConfigParser.parseMultiple(document);
    expect(configs, hasLength(1));
    final profile = configs.single as MihomoConfig;
    expect(profile.rawUri, document.trim());
    expect(profile.document['proxy-groups'], hasLength(1));
    expect(profile.document['rules'], ['MATCH,selected']);
  });
  test('JSON document is also accepted without pretending it is a URI', () {
    expect(ConfigParser.parse('{"proxies":[]}'), isA<MihomoConfig>());
  });
  test('runtime uses loopback SOCKS and disables competing TUN/listeners', () {
    final profile = MihomoConfig.fromDocument('''${document}allow-lan: true
socks-port: 9999
external-controller: 0.0.0.0:9090
tun: {enable: true}
''')!;
    final result = jsonDecode(profile.buildRuntimeJson()) as Map;
    expect(result['socks-port'], 10808);
    expect(result['allow-lan'], false);
    expect(result['bind-address'], '127.0.0.1');
    expect(result['tun'], {'enable': false});
    expect(result.containsKey('external-controller'), false);
    expect(result['proxy-groups'], profile.document['proxy-groups']);
    expect(profile.document['allow-lan'], true, reason: 'Source must not be mutated');
  });
  test('native-only TUN features and unsafe bridge inputs are refused', () {
    for (final tail in [
      'dns: {enhanced-mode: fake-ip}',
      'listeners: [{name: unsafe}]',
      'script: {code: unsafe}',
      'tunnels: []',
      'proxy-providers: {bad: {type: file, path: /private/file}}',
    ]) {
      final profile = MihomoConfig.fromDocument(document + tail)!;
      expect(() => profile.buildRuntimeJson(), throwsArgumentError);
    }
  });
  test('HTTP providers get private relative paths without losing update policy', () {
    final profile = MihomoConfig.fromDocument('''${document}proxy-providers:
  source:
    type: http
    url: https://example.com/proxies.yaml
    path: /unsafe/location
    interval: 3600
''')!;
    final result = jsonDecode(profile.buildRuntimeJson()) as Map;
    expect(result['proxy-providers']['source']['path'], matches(r'^providers/[0-9a-f]{64}\.yaml$'));
    expect(result['proxy-providers']['source']['interval'], 3600);
  });
  test('duplicate keys and cyclic alias input do not crash parser', () {
    expect(MihomoConfig.fromDocument('proxies: []\nproxies: []'), isNull);
    expect(MihomoConfig.fromDocument('proxies: &x [*x]'), isNull);
  });
  test('batch JSON export round-trips the full document; v2rayN excludes it', () {
    final profile = ConfigParser.parse(document)!;
    final archive = ProfileExportService.build([profile]);
    expect(ConfigParser.parseMultiple(archive.content).single, isA<MihomoConfig>());
    final links = ProfileExportService.build([profile], v2rayN: true);
    expect(links.included, 0);
    expect(links.omitted, 1);
  });
  test('import/catalogue entry alone does not enable runtime', () {
    expect(EngineAvailability.fromMap({}).canConnect('mihomo'), false);
    expect(EngineAvailability.fromMap({'mihomoAvailable': true}).canConnect('mihomo'), true);
  });
}
