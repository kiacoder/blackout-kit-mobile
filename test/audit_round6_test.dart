/// Regression tests for the second mobile audit round.
///
/// Parsing bugs get behavioural tests; the rest are structural, in the same
/// style as verify_structural_claims_test.dart, because they live in widget or
/// Kotlin code where a unit test is not practical.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:blackout_kit_mobile/models/config.dart';
import 'package:blackout_kit_mobile/services/singbox_config.dart';
import 'package:blackout_kit_mobile/services/xray_config.dart';

String _source(String relative) =>
    File('${Directory.current.path}/$relative').readAsStringSync();

void main() {
  group('BKM-014 plain Shadowsocks credentials are percent-decoded', () {
    test('an encoded @ in the password survives parsing', () {
      // SIP002 allows a non-base64 userinfo. This branch skipped the shared
      // decoder, so the server received "pa%40ss" instead of "pa@ss".
      final config = ConfigParser.parse('ss://aes-256-gcm:pa%40ss@d.com:8388')
          as ShadowsocksConfig;

      expect(config.method, 'aes-256-gcm');
      expect(config.password, 'pa@ss');
    });

    test('an encoded colon in the password is decoded too', () {
      final config = ConfigParser.parse('ss://aes-128-gcm:a%3Ab@d.com:8388')
          as ShadowsocksConfig;
      expect(config.password, 'a:b');
    });
  });

  group('BKM-013 VMess SNI falls back to host', () {
    test('serverName comes from host when sni is absent', () {
      // VMess links from a CDN usually carry the domain in `host` and leave
      // `sni` empty; without the fallback no serverName was emitted and the
      // handshake presented the bare IP.
      final payload = {
        'v': '2',
        'ps': 'cdn',
        'add': '104.16.0.1',
        'port': '443',
        'id': '11111111-1111-1111-1111-111111111111',
        'aid': '0',
        'net': 'ws',
        'host': 'cdn.example.com',
        'path': '/ws',
        'tls': 'tls',
      };
      final uri = 'vmess://${base64.encode(utf8.encode(jsonEncode(payload)))}';
      final config = ConfigParser.parse(uri) as VmessConfig;

      final doc = const XrayConfigBuilder().build(config);
      final stream = (doc['outbounds'] as List).first['streamSettings']
          as Map<String, dynamic>;
      final tls = stream['tlsSettings'] as Map<String, dynamic>;

      expect(tls['serverName'], 'cdn.example.com');
    });
  });

  group('BKM-001 the capability report matches what Dart can build', () {
    test('the native list advertises only buildable sing-box protocols', () {
      final kt = _source(
        'android/app/src/main/kotlin/com/blackoutkit/vpn/VpnPlugin.kt',
      );
      final advertised = RegExp(
        r'"singboxProtocols" to\s*if \(singboxAvailable\)\s*listOf\(([^)]*)\)',
      ).firstMatch(kt);
      expect(advertised, isNotNull);

      final names = RegExp(r'"([a-z0-9]+)"')
          .allMatches(advertised!.group(1)!)
          .map((m) => m.group(1)!)
          .toSet();

      // Every advertised protocol must be one kSingboxProtocols can describe,
      // otherwise connect() sends no config and the engine runs a stale file.
      expect(names.difference(kSingboxProtocols.toSet()), isEmpty);
      expect(names, kSingboxProtocols.toSet());
    });

    test('the native start path refuses a missing config document', () {
      final kt = _source(
        'android/app/src/main/kotlin/com/blackoutkit/vpn/BlackoutVpnService.kt',
      );
      expect(
        kt.contains('if (singboxConfig.isNullOrBlank())'),
        isTrue,
        reason: 'a null config must not fall through to the stale-file path',
      );
    });

    test('connect() refuses a protocol that yields no config', () {
      final dart = _source('lib/services/vpn_service.dart');
      expect(dart.contains('xrayJson == null && singboxJson == null'), isTrue);
      expect(dart.contains('cannot dial'), isTrue);
    });
  });

  group('BKM-005 notTested is not a failure', () {
    test('the auto-connect filter skips only real failures', () {
      final src = _source('lib/controllers/connection_controller.dart');
      final filter = src.indexOf('final knownFailed = <String>{};');
      expect(filter, greaterThan(-1));
      final window = src.substring(filter, filter + 900);
      expect(
        window.contains('TestStatus.notTested'),
        isTrue,
        reason: 'UDP-only protocols were blacklisted for six hours',
      );
    });
  });

  group('BKM-006 validation is not presented as parsing', () {
    test('the editor validates before saving and names the reason', () {
      final src = _source('lib/screens/config_editor_screen.dart');
      expect(src.contains('parsed.validate()'), isTrue);
      expect(src.contains('Incomplete Config'), isTrue);
      expect(src.contains('Could Not Save'), isTrue);
    });
  });

  group('BKM-012 the Paste button uses the multi-config path', () {
    test('paste does not call ConfigParser.parse directly', () {
      final src = _source('lib/screens/config_import_screen.dart');
      final pasteAt = src.indexOf("label: const Text('Paste')");
      expect(pasteAt, greaterThan(-1));
      // The handler sits just above the label.
      final window = src.substring(
        (pasteAt - 900).clamp(0, pasteAt),
        pasteAt,
      );
      expect(window.contains('_parsePayload(text)'), isTrue);
      expect(window.contains('ConfigParser.parse('), isFalse);
    });
  });

  group('BKM-016 deleting a config reports the storage result', () {
    test('the controller does not swallow a failed delete', () {
      final src = _source('lib/controllers/config_controller.dart');
      expect(src.contains('final removed = await configService.deleteConfig'), isTrue);
      expect(src.contains('if (!removed)'), isTrue);
    });
  });

  group('BKM-009 split tunneling is bound to the real connection state', () {
    test('app wiring attaches the probe', () {
      final src = _source('lib/main.dart');
      expect(src.contains('bindConnectionState('), isTrue);
    });
  });
}
