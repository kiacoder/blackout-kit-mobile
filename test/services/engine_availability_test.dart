/// Tests for [EngineAvailability] — the contract the UI and the connection
/// controller use to decide whether a protocol can actually be dialled.
///
/// The important property is *fail-open*: when the native layer cannot report
/// anything, nothing may be reported as broken, otherwise a working build on an
/// unknown platform would grey out every protocol.

import 'package:flutter_test/flutter_test.dart';
import 'package:blackout_kit_mobile/models/engine_capability.dart';
import 'package:blackout_kit_mobile/services/vpn_service.dart';

void main() {
  group('EngineAvailability.fromMap', () {
    test('reads the native capability report', () {
      final availability = EngineAvailability.fromMap({
        'xrayAvailable': true,
        'xrayVersion': '26.9.9',
        'xrayProtocols': ['vless', 'vmess', 'trojan', 'shadowsocks', 'wireguard'],
        'singboxAvailable': false,
        'singboxProtocols': <String>[],
        'unavailableProtocols': ['hysteria2', 'tuic', 'amneziawg', 'warp'],
      });

      expect(availability.isKnown, isTrue);
      expect(availability.xrayAvailable, isTrue);
      expect(availability.xrayVersion, '26.9.9');
      expect(availability.xrayProtocols, contains('vless'));
      expect(availability.singboxAvailable, isFalse);
      expect(availability.unavailableProtocols, contains('hysteria2'));
    });

    test('tolerates a map with missing keys', () {
      final availability = EngineAvailability.fromMap({});

      expect(availability.isKnown, isTrue);
      expect(availability.xrayAvailable, isFalse);
      expect(availability.xrayVersion, isNull);
      expect(availability.xrayProtocols, isEmpty);
      expect(availability.singboxProtocols, isEmpty);
      expect(availability.unavailableProtocols, isEmpty);
      expect(availability.supportedProtocols, isEmpty);
    });

    test('does not mistake a truthy string for a boolean', () {
      final availability = EngineAvailability.fromMap({
        'xrayAvailable': 'true',
        'singboxAvailable': 1,
      });

      expect(availability.xrayAvailable, isFalse);
      expect(availability.singboxAvailable, isFalse);
    });
  });

  group('supportedProtocols', () {
    test('is the union of the bundled engines', () {
      final availability = EngineAvailability.fromMap({
        'xrayAvailable': true,
        'xrayProtocols': ['vless', 'vmess', 'trojan', 'shadowsocks'],
        'singboxAvailable': true,
        'singboxProtocols': ['hysteria2', 'tuic'],
      });

      expect(
        availability.supportedProtocols,
        containsAll(['vless', 'vmess', 'trojan', 'shadowsocks', 'hysteria2', 'tuic']),
      );
    });

    test('excludes protocols of an engine that is not bundled', () {
      final availability = EngineAvailability.fromMap({
        'xrayAvailable': true,
        'xrayProtocols': ['vless'],
        // Claims a sing-box engine list while reporting it as unavailable —
        // a contradictory payload must not leak hysteria2 into the supported set.
        'singboxAvailable': false,
        'singboxProtocols': ['hysteria2'],
      });

      expect(availability.supportedProtocols, ['vless']);
    });
  });

  group('canConnect', () {
    test('allows a protocol served by a bundled engine', () {
      final availability = EngineAvailability.fromMap({
        'xrayAvailable': true,
        'xrayProtocols': ['vless', 'vmess', 'trojan', 'shadowsocks'],
      });

      expect(availability.canConnect('vless'), isTrue);
      expect(availability.canConnect('shadowsocks'), isTrue);
    });

    test('allows WireGuard, which the bundled Xray core serves in-process', () {
      final availability = EngineAvailability.fromMap({
        'xrayAvailable': true,
        'xrayProtocols': ['vless', 'vmess', 'trojan', 'shadowsocks', 'wireguard'],
        'singboxAvailable': false,
      });

      expect(availability.canConnect('wireguard'), isTrue);
    });

    test('refuses a protocol with no bundled engine', () {
      final availability = EngineAvailability.fromMap({
        'xrayAvailable': true,
        'xrayProtocols': ['vless', 'vmess', 'trojan', 'shadowsocks', 'wireguard'],
        'singboxAvailable': false,
      });

      // hysteria2 needs sing-box: the core carries Hysteria v1, not v2.
      expect(availability.canConnect('hysteria2'), isFalse);
      expect(availability.canConnect('tuic'), isFalse);
      expect(availability.canConnect('amneziawg'), isFalse);
      expect(availability.canConnect('warp'), isFalse);
      expect(availability.canConnect('openvpn'), isFalse);
    });

    test('fails open when the platform could not report capability', () {
      const availability = EngineAvailability.unknown();

      expect(availability.isKnown, isFalse);
      // Unknown must not mean "everything is broken".
      expect(availability.canConnect('hysteria2'), isTrue);
      expect(availability.canConnect('wireguard'), isTrue);
      expect(availability.canConnect('anything-at-all'), isTrue);
    });

    test('refuses everything when a known platform bundles no engine', () {
      final availability = EngineAvailability.fromMap({
        'xrayAvailable': false,
        'singboxAvailable': false,
      });

      expect(availability.isKnown, isTrue);
      expect(availability.supportedProtocols, isEmpty);
      expect(availability.canConnect('vless'), isFalse);
    });
  });

  group('engineIsRunnable', () {
    // The capability report the real build produces.
    EngineAvailability realBuild() => EngineAvailability.fromMap({
          'xrayAvailable': true,
          'xrayProtocols': [
            'vless',
            'vmess',
            'trojan',
            'shadowsocks',
            'wireguard',
          ],
          'singboxAvailable': false,
          'singboxProtocols': <String>[],
          'unavailableProtocols': ['hysteria2', 'tuic', 'amneziawg', 'warp'],
        });

    test('counts the three catalogue engines this build can actually serve', () {
      final availability = realBuild();
      final runnable = EngineRegistry.getAll()
          .where((e) => engineIsRunnable(e, availability.canConnect))
          .map((e) => e.key)
          .toSet();

      expect(runnable, {'xray', 'wireguard', 'shadowsocks'});
    });

    test('an engine that merely lists a servable protocol is not counted', () {
      final availability = realBuild();

      // AmneziaWG advertises ['amneziawg', 'wireguard'] and WARP advertises
      // ['warp', 'wireguard']. Under the old `any` rule both cards rendered as
      // available the moment wireguard became servable, even though neither
      // engine is bundled and neither of their own protocols can run.
      final amnezia = EngineRegistry.getEngine('amneziawg')!;
      final warp = EngineRegistry.getEngine('warp')!;

      expect(engineIsRunnable(amnezia, availability.canConnect), isFalse);
      expect(engineIsRunnable(warp, availability.canConnect), isFalse);
    });

    test('is false for an engine that advertises no protocol at all', () {
      const engine = EngineCapability(
        engine: EngineType.mhrv,
        key: 'empty',
        displayName: 'Empty',
        description: '',
        platformSupport: PlatformSupport.all,
        compatibleProtocols: [],
        requirements: [],
        category: 'Test',
      );

      expect(engineIsRunnable(engine, (_) => true), isFalse);
    });

    test('counts an engine whose protocols are all servable', () {
      final availability = realBuild();
      final xray = EngineRegistry.getEngine('xray')!;
      expect(engineIsRunnable(xray, availability.canConnect), isTrue);
    });
  });

  group('summary', () {
    test('reports the engines it actually found', () {
      final availability = EngineAvailability.fromMap({
        'xrayAvailable': true,
        'xrayVersion': '26.9.9',
        'xrayProtocols': ['vless', 'vmess', 'trojan', 'shadowsocks'],
        'singboxAvailable': false,
      });

      expect(availability.summary, contains('26.9.9'));
      expect(availability.summary, contains('vless'));
    });

    test('says so when nothing is bundled', () {
      final availability = EngineAvailability.fromMap({
        'xrayAvailable': false,
        'singboxAvailable': false,
      });

      expect(availability.summary.toLowerCase(), contains('no engine'));
    });

    test('says so when capability is unknown', () {
      const availability = EngineAvailability.unknown();

      expect(availability.summary.toLowerCase(), contains('could not be determined'));
    });
  });
}
