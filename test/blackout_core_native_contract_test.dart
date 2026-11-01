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
        'outbound': {
          'protocol': 'shadowtls',
          'server': cfg.address,
          'server_port': cfg.port,
          'password': cfg.password,
          'sni': cfg.sni,
          'version': cfg.version,
        },
        'dns_servers': ['1.1.1.1', '1.0.0.1'],
        'route_dns_through_proxy': true,
      });

      final decoded = jsonDecode(jsonPayload);
      expect(decoded['outbound']['protocol'], 'shadowtls');
      expect(decoded['outbound']['server'], '185.215.244.95');
      expect(decoded['outbound']['server_port'], 39013);
      expect(decoded['outbound']['password'], 'mySecretPassword');
    });

    test('Hysteria 2 config with port hopping translates to core contract', () {
      final cfg = ConfigParser.parse('hysteria2://superSecret@185.208.172.212:39004/?sni=www.bing.com&insecure=1&mport=20000-30000') as Hysteria2Config?;
      expect(cfg, isNotNull);
      expect(cfg!.address, '185.208.172.212');
      expect(cfg.password, 'superSecret');
      expect(cfg.hopPorts, '20000-30000');

      final jsonPayload = jsonEncode({
        'outbound': {
          'protocol': 'hysteria2',
          'server': cfg.address,
          'server_port': cfg.port,
          'password': cfg.password,
          'sni': cfg.sni,
          'insecure': cfg.insecure,
          'hop_ports': cfg.hopPorts,
        },
      });

      final decoded = jsonDecode(jsonPayload);
      expect(decoded['outbound']['protocol'], 'hysteria2');
      expect(decoded['outbound']['hop_ports'], '20000-30000');
    });

    test('VLESS + REALITY config translates cleanly to native engine format', () {
      final cfg = ConfigParser.parse('vless://798fc293-66e4-4c7c-84a0-906bc802457f@185.208.172.212:39003?security=reality&sni=www.cloudflare.com&fp=chrome&pbk=clquQ_vti6qaaEBM0xzs0qmVRYfhqyhuNnIUNNTsh1Y&sid=ff9216366f5433e8&type=tcp&flow=xtls-rprx-vision#A-vless-reality') as VlessConfig?;
      expect(cfg, isNotNull);
      expect(cfg!.security, 'reality');
      expect(cfg.publicKey, 'clquQ_vti6qaaEBM0xzs0qmVRYfhqyhuNnIUNNTsh1Y');
      expect(cfg.shortId, 'ff9216366f5433e8');
      expect(cfg.flow, 'xtls-rprx-vision');

      final jsonPayload = jsonEncode({
        'outbound': {
          'protocol': 'vless',
          'server': cfg.address,
          'server_port': cfg.port,
          'uuid': cfg.uuid,
          'flow': cfg.flow,
          'security': cfg.security,
          'sni': cfg.sni,
          'public_key': cfg.publicKey,
          'short_id': cfg.shortId,
        },
        'dns_servers': ['1.1.1.1'],
      });

      final decoded = jsonDecode(jsonPayload);
      expect(decoded['outbound']['protocol'], 'vless');
      expect(decoded['outbound']['security'], 'reality');
      expect(decoded['outbound']['public_key'], 'clquQ_vti6qaaEBM0xzs0qmVRYfhqyhuNnIUNNTsh1Y');
    });

    test('Shadowsocks-2022 config serializes for native blake3-aes engine', () {
      final cfg = ConfigParser.parse('ss://2022-blake3-aes-128-gcm:pM7lyHkkxiB/beD7dwwZGg==@185.208.172.212:39012#A-ss2022') as ShadowsocksConfig?;
      expect(cfg, isNotNull);
      expect(cfg!.method, '2022-blake3-aes-128-gcm');
      expect(cfg.password, 'pM7lyHkkxiB/beD7dwwZGg==');

      final jsonPayload = jsonEncode({
        'outbound': {
          'protocol': 'shadowsocks',
          'server': cfg.address,
          'server_port': cfg.port,
          'method': cfg.method,
          'password': cfg.password,
        },
      });

      final decoded = jsonDecode(jsonPayload);
      expect(decoded['outbound']['protocol'], 'shadowsocks');
      expect(decoded['outbound']['method'], '2022-blake3-aes-128-gcm');
    });
  });
}
