import 'package:blackout_kit_mobile/models/config.dart';
import 'package:blackout_kit_mobile/services/engine_capability_policy.dart';
import 'package:blackout_kit_mobile/services/vpn_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';

class _CapabilityVpn extends VPNService {
  EngineAvailability availability = const EngineAvailability.unknown();
  bool fail = false;

  @override
  Future<EngineAvailability> getEngineInfo() async {
    if (fail) throw StateError('Capability probe failed');
    return availability;
  }
}

void main() {
  test('known capability updates are visible and a failed refresh retains them', () async {
    final vpn = _CapabilityVpn();
    final policy = EngineCapabilityPolicy(vpn, Logger());
    expect(policy.isProtocolSupported('wireguard'), isTrue);
    vpn.availability = EngineAvailability.fromMap({
      'xrayAvailable': true,
      'xrayProtocols': ['vless'],
    });
    await policy.ensureEngineAvailability();
    expect(policy.isProtocolSupported('vless'), isTrue);
    expect(policy.isProtocolSupported('wireguard'), isFalse);
    vpn.fail = true;
    await policy.ensureEngineAvailability();
    expect(policy.isProtocolSupported('wireguard'), isFalse);
    expect(await policy.servableConfigs(<Config>[]), isEmpty);
  });
}
