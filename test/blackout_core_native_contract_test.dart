import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:blackout_kit_mobile/models/config.dart';
import 'package:blackout_kit_mobile/services/blackout_core_bindings.dart';

void main() {
  group('BlackoutCore Native Engine Contracts', () {
    test('bindings gracefully handle missing binary in unit tests', () {
      final core = BlackoutCoreBindings();
      expect(core.isAvailable, isFalse);
      expect(core.isRunning(), isFalse);
      expect(core.getVersion(), 'unloaded');
      expect(core.init(), -99);
      expect(core.stop(), 0);
    });

    test('ShadowTLS v3 config serializes correctly for custom Rust core', () {
      final cfg = ConfigParser.parse('shadowtls://mySecretPassword@185.215.244.95:39013?sni=robohooshacademy.com&version=3') as ShadowTlsConfig?;
      expect(cfg, isNotNull);
      expect(cfg!.password, 'mySecretPassword');
      expect(cfg.address, '185.215.244.95');
      expect(cfg.port, 39013);
      expect(cfg.sni, 'robohooshacademy.com');
      expect(cfg.version, 3);

      final jsonPayload = jsonEncode({
        'protocol': 'shadowtls',
        'server': cfg.address,
        'server_port': cfg.port,
        'password': cfg.password,
        'sni': cfg.sni,
        'version': cfg.version,
      });

      final decoded = jsonDecode(jsonPayload);
      expect(decoded['protocol'], 'shadowtls');
      expect(decoded['server'], '185.215.244.95');
      expect(decoded['server_port'], 39013);
      expect(decoded['password'], 'mySecretPassword');
    });

    test('Hysteria 2 config with port hopping translates to core contract', () {
      final cfg = ConfigParser.parse('hysteria2://superSecret@185.208.172.212:39004/?sni=www.bing.com&insecure=1&mport=20000-30000') as Hysteria2Config?;
      expect(cfg, isNotNull);
      expect(cfg!.address, '185.208.172.212');
      expect(cfg.password, 'superSecret');
      expect(cfg.hopPorts, '20000-30000');

      final jsonPayload = jsonEncode({
        'protocol': 'hysteria2',
        'server': cfg.address,
        'server_port': cfg.port,
        'password': cfg.password,
        'sni': cfg.sni,
        'insecure': cfg.insecure,
        'hop_ports': cfg.hopPorts,
      });

      final decoded = jsonDecode(jsonPayload);
      expect(decoded['protocol'], 'hysteria2');
      expect(decoded['hop_ports'], '20000-30000');
    });
  });
}
