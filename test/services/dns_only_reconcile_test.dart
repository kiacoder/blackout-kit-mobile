/// Adopting a running DNS-only session must not look like a normal tunnel.
///
/// A DNS-only interface has no config and no core. The generic adopt path
/// matched no config, then called `_fetchConnectedIP()`, which dials the core's
/// SOCKS inbound — an inbound that does not exist in this mode. Six retries
/// with 1..5s delays meant ~15 seconds of nothing after a cold start, and the
/// UI showed a connected state it could not describe.
library;

import 'package:blackout_kit_mobile/controllers/connection_controller.dart';
import 'package:blackout_kit_mobile/services/debug_service.dart';
import 'package:blackout_kit_mobile/services/dns_leak_prevention_service.dart';
import 'package:blackout_kit_mobile/services/kill_switch_service.dart';
import 'package:blackout_kit_mobile/services/split_tunneling_service.dart';
import 'package:blackout_kit_mobile/services/tester_service.dart';
import 'package:blackout_kit_mobile/services/vpn_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _DnsOnlyVpn extends VPNService {
  int connectedIpCalls = 0;

  @override
  Future<Map<String, dynamic>> getStatus() async => {
        'isRunning': true,
        'name': 'Blackout DNS',
        'protocol': 'dns',
        'connectedAtMs': DateTime.now().millisecondsSinceEpoch,
      };

  @override
  Future<String?> getConnectedIP() async {
    connectedIpCalls++;
    return null;
  }
}

class _NormalVpn extends VPNService {
  int connectedIpCalls = 0;

  @override
  Future<Map<String, dynamic>> getStatus() async => {
        'isRunning': true,
        'name': 'Somewhere',
        'protocol': 'vless',
        'connectedAtMs': DateTime.now().millisecondsSinceEpoch,
      };

  @override
  Future<String?> getConnectedIP() async {
    connectedIpCalls++;
    return null;
  }
}

ConnectionController _controller(VPNService vpn) => ConnectionController(
      vpnService: vpn,
      testerService: TesterService(),
      killSwitchService: KillSwitchService(),
      dnsLeakPreventionService: DNSLeakPreventionService(),
      splitTunnelingService: SplitTunnelingService(),
      debugService: DebugService(),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a DNS-only session is adopted as DNS-only, with no exit lookup',
      () async {
    final vpn = _DnsOnlyVpn();
    final controller = _controller(vpn);

    await controller.reconcileWithNativeService();

    expect(controller.isConnected, isTrue);
    expect(controller.isDnsOnly.value, isTrue,
        reason: 'the session must be described as DNS-only, not as a tunnel');
    expect(controller.selectedConfig.value, isNull);
    expect(vpn.connectedIpCalls, 0,
        reason: 'a DNS-only interface has no exit to resolve');
  });

  test('a normal tunnel still resolves its exit', () async {
    final vpn = _NormalVpn();
    final controller = _controller(vpn);

    await controller.reconcileWithNativeService();

    expect(controller.isConnected, isTrue);
    expect(controller.isDnsOnly.value, isFalse);
    expect(vpn.connectedIpCalls, greaterThan(0));
  });
}
