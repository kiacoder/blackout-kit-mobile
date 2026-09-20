import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:logger/logger.dart';
import 'package:mockito/mockito.dart';

import 'package:blackout_kit_mobile/controllers/connection_controller.dart';
import 'package:blackout_kit_mobile/models/config.dart';
import 'package:blackout_kit_mobile/services/dns_leak_prevention_service.dart';
import 'package:blackout_kit_mobile/services/kill_switch_service.dart';
import 'package:blackout_kit_mobile/services/split_tunneling_service.dart';
import 'package:blackout_kit_mobile/services/tester_service.dart';
import 'package:blackout_kit_mobile/services/vpn_service.dart';

class MockVPNService extends Mock implements VPNService {}

class MockTesterService extends Mock implements TesterService {}

class MockKillSwitchService extends Mock implements KillSwitchService {
  @override
  final isEnabled = false.obs;

  @override
  final isActive = false.obs;

  @override
  Future<void> cleanup() async {}
}

class MockDNSLeakPreventionService extends Mock
    implements DNSLeakPreventionService {
  @override
  final isEnabled = false.obs;

  @override
  final isActive = false.obs;

  @override
  final currentDNS = Rxn<String>();

  @override
  Future<bool> enable({String? customDNS}) async {
    isEnabled.value = true;
    return true;
  }

  @override
  Future<bool> disable() async {
    isEnabled.value = false;
    isActive.value = false;
    return true;
  }

  @override
  Future<void> activate() async {
    isActive.value = true;
  }

  @override
  Future<void> deactivate() async {
    isActive.value = false;
  }

  @override
  Future<void> cleanup() async {}
}

class MockSplitTunnelingService extends Mock implements SplitTunnelingService {
  @override
  final isEnabled = false.obs;

  @override
  final isActive = false.obs;

  @override
  final mode = Rxn<String>();

  @override
  final installedApps = RxList<TunnelApp>();

  @override
  final selectedApps = RxSet<String>();

  @override
  Future<bool> enable({String mode = 'whitelist'}) async {
    isEnabled.value = true;
    this.mode.value = mode;
    return true;
  }

  @override
  Future<bool> disable() async {
    isEnabled.value = false;
    isActive.value = false;
    selectedApps.clear();
    return true;
  }

  @override
  Future<bool> addApp(String packageName) async {
    if (!selectedApps.contains(packageName)) {
      selectedApps.add(packageName);
    }
    return true;
  }

  @override
  Future<bool> removeApp(String packageName) async {
    selectedApps.remove(packageName);
    return true;
  }

  @override
  Future<void> activate() async {
    isActive.value = true;
  }

  @override
  Future<void> deactivate() async {
    isActive.value = false;
  }

  @override
  Future<bool> changeMode(String newMode) async {
    mode.value = newMode;
    return true;
  }

  @override
  Future<void> cleanup() async {}
}

void main() {
  late MockVPNService vpnService;
  late MockTesterService testerService;
  late MockKillSwitchService killSwitchService;
  late MockDNSLeakPreventionService dnsService;
  late MockSplitTunnelingService splitTunnelingService;
  late ConnectionController controller;

  final testConfig = Config(
    protocol: 'wireguard',
    displayName: 'Test Config',
    uri: 'wireguard://example.com',
  );

  setUp(() {
    vpnService = MockVPNService();
    testerService = MockTesterService();
    killSwitchService = MockKillSwitchService();
    dnsService = MockDNSLeakPreventionService();
    splitTunnelingService = MockSplitTunnelingService();

    controller = ConnectionController(
      vpnService: vpnService,
      testerService: testerService,
      killSwitchService: killSwitchService,
      dnsLeakPreventionService: dnsService,
      splitTunnelingService: splitTunnelingService,
      logger: Logger(),
    );
  });

  tearDown(() {
    controller.onClose();
  });

  group('Split Tunneling Integration Tests', () {
    test('Split tunneling not activated if not enabled', () async {
      when(vpnService.connect(any)).thenAnswer((_) async => true);

      await controller.connect(testConfig);

      verifyNever(splitTunnelingService.activate());
    });

    test('Split tunneling activated on connection when enabled', () async {
      when(vpnService.connect(any)).thenAnswer((_) async => true);

      controller.isSplitTunnelingEnabled.value = true;

      await controller.connect(testConfig);

      verify(splitTunnelingService.activate()).called(1);
      expect(controller.state.value, ConnectionState.connected);
    });

    test('Connection succeeds if split tunneling activation fails', () async {
      when(vpnService.connect(any)).thenAnswer((_) async => true);
      when(splitTunnelingService.activate())
          .thenThrow(Exception('Split tunneling error'));

      controller.isSplitTunnelingEnabled.value = true;

      final result = await controller.connect(testConfig);

      expect(result, true);
      expect(controller.state.value, ConnectionState.connected);
    });

    test('Split tunneling deactivated on disconnect', () async {
      when(vpnService.connect(any)).thenAnswer((_) async => true);
      when(vpnService.disconnect()).thenAnswer((_) async => true);

      controller.isSplitTunnelingEnabled.value = true;
      splitTunnelingService.isActive.value = true;

      await controller.connect(testConfig);
      await controller.disconnect();

      verify(splitTunnelingService.deactivate()).called(1);
      expect(controller.state.value, ConnectionState.idle);
    });

    test('Toggle split tunneling enable when disabled', () async {
      controller.isSplitTunnelingEnabled.value = false;

      final result = await controller.toggleSplitTunneling();

      expect(result, true);
      expect(controller.isSplitTunnelingEnabled.value, true);
      verify(splitTunnelingService.enable(mode: anyNamed('mode'))).called(1);
    });

    test('Toggle split tunneling disable when enabled', () async {
      controller.isSplitTunnelingEnabled.value = true;

      final result = await controller.toggleSplitTunneling();

      expect(result, true);
      expect(controller.isSplitTunnelingEnabled.value, false);
      verify(splitTunnelingService.disable()).called(1);
    });

    test('Toggle split tunneling activates immediately if connected', () async {
      when(vpnService.connect(any)).thenAnswer((_) async => true);

      controller.isSplitTunnelingEnabled.value = true;
      await controller.connect(testConfig);

      reset(splitTunnelingService);
      controller.isSplitTunnelingEnabled.value = false;

      final result = await controller.toggleSplitTunneling();

      expect(result, true);
      verify(splitTunnelingService.enable(mode: anyNamed('mode'))).called(1);
      verify(splitTunnelingService.activate()).called(1);
    });

    test('Split tunneling cleanup called on controller close', () async {
      await controller.onClose();

      verify(splitTunnelingService.cleanup()).called(1);
    });

    test('Disconnect succeeds if split tunneling deactivation fails', () async {
      when(vpnService.connect(any)).thenAnswer((_) async => true);
      when(vpnService.disconnect()).thenAnswer((_) async => true);
      when(splitTunnelingService.deactivate())
          .thenThrow(Exception('Split tunneling error'));

      controller.isSplitTunnelingEnabled.value = true;
      splitTunnelingService.isActive.value = true;

      await controller.connect(testConfig);
      final result = await controller.disconnect();

      expect(result, true);
      expect(controller.state.value, ConnectionState.idle);
    });

    test('Split tunneling state persists across connections', () async {
      when(vpnService.connect(any)).thenAnswer((_) async => true);
      when(vpnService.disconnect()).thenAnswer((_) async => true);

      controller.isSplitTunnelingEnabled.value = true;

      await controller.connect(testConfig);
      expect(controller.isSplitTunnelingEnabled.value, true);

      await controller.disconnect();
      expect(controller.isSplitTunnelingEnabled.value, true);

      await controller.connect(testConfig);
      expect(controller.isSplitTunnelingEnabled.value, true);
    });

    test('All security features activate on connection', () async {
      when(vpnService.connect(any)).thenAnswer((_) async => true);

      controller.isKillSwitchEnabled.value = true;
      controller.isDNSLeakPreventionEnabled.value = true;
      controller.isSplitTunnelingEnabled.value = true;

      await controller.connect(testConfig);

      verify(killSwitchService.activate()).called(1);
      verify(dnsService.activate()).called(1);
      verify(splitTunnelingService.activate()).called(1);
      expect(controller.state.value, ConnectionState.connected);
    });

    test('All security features deactivate on disconnect', () async {
      when(vpnService.connect(any)).thenAnswer((_) async => true);
      when(vpnService.disconnect()).thenAnswer((_) async => true);

      controller.isKillSwitchEnabled.value = true;
      controller.isDNSLeakPreventionEnabled.value = true;
      controller.isSplitTunnelingEnabled.value = true;
      killSwitchService.isActive.value = true;
      dnsService.isActive.value = true;
      splitTunnelingService.isActive.value = true;

      await controller.connect(testConfig);
      await controller.disconnect();

      verify(killSwitchService.deactivate()).called(1);
      verify(dnsService.deactivate()).called(1);
      verify(splitTunnelingService.deactivate()).called(1);
    });
  });
}
