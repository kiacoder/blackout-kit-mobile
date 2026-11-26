import 'package:flutter_test/flutter_test.dart';
import 'package:blackout_kit_mobile/services/vpn_service.dart';

void main() {
  test('missing native flags never advertise AWG', () {
    final engines = EngineAvailability.fromMap({});
    expect(engines.nativeWireguardAvailable, isFalse);
    expect(engines.nativeAmneziawgAvailable, isFalse);
    expect(engines.canConnect('amneziawg'), isFalse);
  });

  test('native WireGuard does not imply AmneziaWG', () {
    final engines = EngineAvailability.fromMap({
      'nativeWireguardAvailable': true,
    });
    expect(engines.canConnect('wireguard'), isTrue);
    expect(engines.canConnect('amneziawg'), isFalse);
  });

  test('native AWG is separately advertised', () {
    final engines = EngineAvailability.fromMap({
      'nativeAmneziawgAvailable': true,
    });
    expect(engines.canConnect('amneziawg'), isTrue);
    expect(engines.canConnect('wireguard'), isFalse);
    expect(engines.summary, contains('experimental'));
  });

  test('legacy Xray WireGuard stays available without native libraries', () {
    final engines = EngineAvailability.fromMap({
      'xrayAvailable': true,
      'xrayProtocols': ['wireguard'],
    });
    expect(engines.canConnect('wireguard'), isTrue);
    expect(engines.nativeWireguardAvailable, isFalse);
  });
}
