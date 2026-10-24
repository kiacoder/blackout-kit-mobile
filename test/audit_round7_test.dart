/// Regression tests for the third mobile audit round.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:blackout_kit_mobile/models/config.dart';
import 'package:blackout_kit_mobile/services/update_service.dart';

String _source(String relative) =>
    File('${Directory.current.path}/$relative').readAsStringSync();

void main() {
  group('BKM-020 WireGuard needs a local address', () {
    test('a profile without Address is rejected', () {
      // The Xray outbound omits `address` when this list is empty and the core
      // then refuses the whole config, so it must not validate as ready.
      final noAddress = WireGuardConfig(
        name: 'wg',
        rawUri: '',
        privateKey: 'priv',
        peers: [
          WireGuardPeer(publicKey: 'pub', endpoint: 'wg.example.com:51820'),
        ],
      );
      expect(noAddress.validate(), isFalse);
    });

    test('a profile with an address still validates', () {
      final ok = WireGuardConfig(
        name: 'wg',
        rawUri: '',
        privateKey: 'priv',
        localAddresses: ['10.0.0.2/32'],
        peers: [
          WireGuardPeer(publicKey: 'pub', endpoint: 'wg.example.com:51820'),
        ],
      );
      expect(ok.validate(), isTrue);
    });
  });

  group('BKM-019 readiness polls until the deadline', () {
    test('the probe retries instead of making a single attempt', () {
      final kt = _source(
        'android/app/src/main/kotlin/com/blackoutkit/vpn/LocalSocksReadiness.kt',
      );
      expect(kt.contains('deadline'), isTrue);
      expect(kt.contains('Thread.sleep'), isTrue);
    });
  });

  group('BKM-022 allowed and disallowed lists stay exclusive', () {
    test('self-exclusion is skipped in allowed-list mode', () {
      final kt = _source(
        'android/app/src/main/kotlin/com/blackoutkit/vpn/BlackoutVpnService.kt',
      );
      final idx = kt.indexOf('builder.addDisallowedApplication(packageName)');
      expect(idx, greaterThan(-1));
      final before = kt.substring((idx - 400).clamp(0, idx), idx);
      expect(
        before.contains('if (!useAllowedList)'),
        isTrue,
        reason: 'mixing the two lists throws on stock Android',
      );
    });
  });

  group('BKM-024 the device gets its own split APK', () {
    Map<String, dynamic> asset(String name) => {
          'name': name,
          'browser_download_url': 'https://example.com/$name',
          'size': 60 * 1024 * 1024,
        };

    Map<String, dynamic> release(List<String> names) => {
          'tag_name': 'v1.12.4',
          'body': '',
          'assets': names.map(asset).toList(),
        };

    test('an arm64 phone prefers the arm64 split over universal', () {
      // Universal is listed first on purpose: the old fallback took the first
      // .apk that was universal OR matched, so this order won.
      final update = AppUpdate.fromReleaseJson(
        release([
          'blackout-kit-v1.12.4-universal.apk',
          'blackout-kit-v1.12.4-arm64-v8a.apk',
          'blackout-kit-v1.12.4-armeabi-v7a.apk',
        ]),
        abi: 'arm64-v8a',
      );
      expect(update, isNotNull);
      expect(update!.apkUrl, endsWith('arm64-v8a.apk'));
    });

    test('a 32-bit phone gets armeabi-v7a, never arm64', () {
      final update = AppUpdate.fromReleaseJson(
        release([
          'blackout-kit-v1.12.4-arm64-v8a.apk',
          'blackout-kit-v1.12.4-armeabi-v7a.apk',
        ]),
        abi: 'armeabi-v7a',
      );
      expect(update!.apkUrl, endsWith('armeabi-v7a.apk'));
    });

    test('universal is still the fallback when no split matches', () {
      final update = AppUpdate.fromReleaseJson(
        release(['blackout-kit-v1.12.4-universal.apk']),
        abi: 'x86_64',
      );
      expect(update!.apkUrl, endsWith('universal.apk'));
    });
  });

  group('BKM-027 DNS leak prevention is reachable from the UI', () {
    test('Settings renders a control and a resolver picker', () {
      final src = _source('lib/screens/settings_screen.dart');
      expect(src.contains('DNS leak prevention'), isTrue);
      expect(src.contains('toggleDnsLeakPrevention'), isTrue);
      expect(src.contains('_showDnsResolverDialog'), isTrue);
    });

    test('reset restores a usable resolver', () {
      final src = _source('lib/controllers/settings_controller.dart');
      expect(src.contains("customDnsServer.value = '1.1.1.1'"), isTrue);
    });
  });

  group('BKM-028/029 the speed test ranks by latency, isolated', () {
    test('it reads visible configs and sorts them itself', () {
      final src = _source('lib/screens/speed_test_screen.dart');
      expect(src.contains('_configController.visibleConfigs'), isTrue);
      expect(
        src.contains('_configController.getFilteredConfigs()'),
        isFalse,
        reason: 'that inherits the library filter/sort and resets pagination',
      );
    });

    test('getTopConfigs honours source isolation', () {
      final src = _source('lib/controllers/config_controller.dart');
      final idx = src.indexOf('List<Config> getTopConfigs');
      final body = src.substring(idx, idx + 400);
      expect(body.contains('visibleConfigs'), isTrue);
    });
  });

  group('BKM-035 deleting the active config disconnects', () {
    test('deleteConfig checks the live session', () {
      final src = _source('lib/controllers/config_controller.dart');
      expect(src.contains('connection.selectedConfig.value?.getHash()'), isTrue);
      expect(src.contains('await connection.disconnect()'), isTrue);
    });
  });

  group('site check probes every protocol family', () {
    test('the probe document is chosen by protocol family', () {
      final src = _source('lib/services/site_check_service.dart');
      expect(src.contains('isXrayProtocol(config.protocol)'), isTrue);
      expect(src.contains('isSingboxProtocol(config.protocol)'), isTrue);
      expect(src.contains('SingboxConfigBuilder'), isTrue);
    });

    test('the platform channel accepts a sing-box document', () {
      final src = _source('lib/services/vpn_service.dart');
      expect(src.contains("'singboxConfig': singboxConfig"), isTrue);
    });

    test('the native side runs sing-box when given one', () {
      final kt = _source(
        'android/app/src/main/kotlin/com/blackoutkit/vpn/VpnPlugin.kt',
      );
      expect(kt.contains('startSingboxProbe'), isTrue);
      expect(kt.contains('"singboxConfig"'), isTrue);
    });
  });
}
