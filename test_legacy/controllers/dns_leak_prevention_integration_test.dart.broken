import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:logger/logger.dart';
import 'package:mockito/mockito.dart';

import 'package:blackout_kit_mobile/controllers/connection_controller.dart';
import 'package:blackout_kit_mobile/models/config.dart';
import 'package:blackout_kit_mobile/services/dns_leak_prevention_service.dart';
import 'package:blackout_kit_mobile/services/kill_switch_service.dart';
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

void main() {
  late MockVPNService vpnService;
  late MockTesterService testerService;
  late MockKillSwitchService killSwitchService;
  late MockDNSLeakPreventionService dnsService;
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

    controller = ConnectionController(
      vpnService: vpnService,
      testerService: testerService,
      killSwitchService: killSwitchService,
      dnsLeakPreventionService: dnsService,
      logger: Logger(),
    );
  });

  tearDown(() {
    controller.onClose();
  });

  group('DNS Leak Prevention Integration Tests', () {
    test('DNS leak prevention not activated if not enabled', () async {
      when(vpnService.connect(any)).thenAnswer((_) async => true);

      await controller.connect(testConfig);

      verifyNever(dnsService.activate());
    });

    test('DNS leak prevention activated on connection when enabled', () async {
      when(vpnService.connect(any)).thenAnswer((_) async => true);

      controller.isDNSLeakPreventionEnabled.value = true;

      await controller.connect(testConfig);

      verify(dnsService.activate()).called(1);
      expect(controller.state.value, ConnectionState.connected);
    });

    test('Connection succeeds if DNS activation fails', () async {
      when(vpnService.connect(any)).thenAnswer((_) async => true);
      when(dnsService.activate()).thenThrow(Exception('DNS error'));

      controller.isDNSLeakPreventionEnabled.value = true;

      final result = await controller.connect(testConfig);

      expect(result, true);
      expect(controller.state.value, ConnectionState.connected);
    });

    test('DNS leak prevention deactivated on disconnect', () async {
      when(vpnService.connect(any)).thenAnswer((_) async => true);
      when(vpnService.disconnect()).thenAnswer((_) async => true);

      controller.isDNSLeakPreventionEnabled.value = true;
      dnsService.isActive.value = true;

      await controller.connect(testConfig);
      await controller.disconnect();

      verify(dnsService.deactivate()).called(1);
      expect(controller.state.value, ConnectionState.idle);
    });

    test('Toggle DNS leak prevention enable when disabled', () async {
      controller.isDNSLeakPreventionEnabled.value = false;

      final result = await controller.toggleDNSLeakPrevention();

      expect(result, true);
      expect(controller.isDNSLeakPreventionEnabled.value, true);
      verify(dnsService.enable()).called(1);
    });

    test('Toggle DNS leak prevention disable when enabled', () async {
      controller.isDNSLeakPreventionEnabled.value = true;

      final result = await controller.toggleDNSLeakPrevention();

      expect(result, true);
      expect(controller.isDNSLeakPreventionEnabled.value, false);
      verify(dnsService.disable()).called(1);
    });

    test('Toggle DNS activates immediately if connected', () async {
      when(vpnService.connect(any)).thenAnswer((_) async => true);

      controller.isDNSLeakPreventionEnabled.value = true;
      await controller.connect(testConfig);

      reset(dnsService);
      controller.isDNSLeakPreventionEnabled.value = false;

      final result = await controller.toggleDNSLeakPrevention();

      expect(result, true);
      verify(dnsService.enable()).called(1);
      verify(dnsService.activate()).called(1);
    });

    test('DNS leak prevention cleanup called on controller close', () async {
      await controller.onClose();

      verify(dnsService.cleanup()).called(1);
    });

    test('Disconnect succeeds if DNS deactivation fails', () async {
      when(vpnService.connect(any)).thenAnswer((_) async => true);
      when(vpnService.disconnect()).thenAnswer((_) async => true);
      when(dnsService.deactivate()).thenThrow(Exception('DNS error'));

      controller.isDNSLeakPreventionEnabled.value = true;
      dnsService.isActive.value = true;

      await controller.connect(testConfig);
      final result = await controller.disconnect();

      expect(result, true);
      expect(controller.state.value, ConnectionState.idle);
    });

    test('DNS leak prevention state persists across connections', () async {
      when(vpnService.connect(any)).thenAnswer((_) async => true);
      when(vpnService.disconnect()).thenAnswer((_) async => true);

      controller.isDNSLeakPreventionEnabled.value = true;

      await controller.connect(testConfig);
      expect(controller.isDNSLeakPreventionEnabled.value, true);

      await controller.disconnect();
      expect(controller.isDNSLeakPreventionEnabled.value, true);

      await controller.connect(testConfig);
      expect(controller.isDNSLeakPreventionEnabled.value, true);
    });

    test('Both kill switch and DNS protection activate on connection', () async {
      when(vpnService.connect(any)).thenAnswer((_) async => true);

      controller.isKillSwitchEnabled.value = true;
      controller.isDNSLeakPreventionEnabled.value = true;

      await controller.connect(testConfig);

      verify(killSwitchService.activate()).called(1);
      verify(dnsService.activate()).called(1);
      expect(controller.state.value, ConnectionState.connected);
    });

    test('Both security features deactivate on disconnect', () async {
      when(vpnService.connect(any)).thenAnswer((_) async => true);
      when(vpnService.disconnect()).thenAnswer((_) async => true);

      controller.isKillSwitchEnabled.value = true;
      controller.isDNSLeakPreventionEnabled.value = true;
      killSwitchService.isActive.value = true;
      dnsService.isActive.value = true;

      await controller.connect(testConfig);
      await controller.disconnect();

      verify(killSwitchService.deactivate()).called(1);
      verify(dnsService.deactivate()).called(1);
    });
  });
}
