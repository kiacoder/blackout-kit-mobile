import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:logger/logger.dart';
import 'package:mockito/mockito.dart';

import 'package:blackout_kit_mobile/controllers/connection_controller.dart';
import 'package:blackout_kit_mobile/models/config.dart';
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
  Future<bool> enable() async {
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

    controller = ConnectionController(
      vpnService: vpnService,
      testerService: testerService,
      killSwitchService: killSwitchService,
      logger: Logger(),
    );
  });

  tearDown(() {
    controller.onClose();
  });

  group('Kill Switch Integration Tests', () {
    test('Kill switch not activated if not enabled', () async {
      when(vpnService.connect(any)).thenAnswer((_) async => true);

      await controller.connect(testConfig);

      verifyNever(killSwitchService.activate());
    });

    test('Kill switch activated on successful connection when enabled', () async {
      when(vpnService.connect(any)).thenAnswer((_) async => true);

      controller.isKillSwitchEnabled.value = true;

      await controller.connect(testConfig);

      verify(killSwitchService.activate()).called(1);
      expect(controller.state.value, ConnectionState.connected);
    });

    test('Connection succeeds even if kill switch activation fails', () async {
      when(vpnService.connect(any)).thenAnswer((_) async => true);
      when(killSwitchService.activate()).thenThrow(Exception('Kill switch error'));

      controller.isKillSwitchEnabled.value = true;

      final result = await controller.connect(testConfig);

      expect(result, true);
      expect(controller.state.value, ConnectionState.connected);
    });

    test('Kill switch deactivated on disconnect', () async {
      when(vpnService.connect(any)).thenAnswer((_) async => true);
      when(vpnService.disconnect()).thenAnswer((_) async => true);

      controller.isKillSwitchEnabled.value = true;
      killSwitchService.isActive.value = true;

      await controller.connect(testConfig);
      await controller.disconnect();

      verify(killSwitchService.deactivate()).called(1);
      expect(controller.state.value, ConnectionState.idle);
    });

    test('Toggle kill switch enable when disabled', () async {
      controller.isKillSwitchEnabled.value = false;

      final result = await controller.toggleKillSwitch();

      expect(result, true);
      expect(controller.isKillSwitchEnabled.value, true);
      verify(killSwitchService.enable()).called(1);
    });

    test('Toggle kill switch disable when enabled', () async {
      controller.isKillSwitchEnabled.value = true;

      final result = await controller.toggleKillSwitch();

      expect(result, true);
      expect(controller.isKillSwitchEnabled.value, false);
      verify(killSwitchService.disable()).called(1);
    });

    test('Toggle kill switch activates immediately if connected', () async {
      when(vpnService.connect(any)).thenAnswer((_) async => true);

      controller.isKillSwitchEnabled.value = true;
      await controller.connect(testConfig);

      reset(killSwitchService);
      controller.isKillSwitchEnabled.value = false;

      final result = await controller.toggleKillSwitch();

      expect(result, true);
      verify(killSwitchService.enable()).called(1);
      verify(killSwitchService.activate()).called(1);
    });

    test('Kill switch cleanup called on controller close', () async {
      await controller.onClose();

      verify(killSwitchService.cleanup()).called(1);
    });

    test('Disconnect succeeds even if kill switch deactivation fails', () async {
      when(vpnService.connect(any)).thenAnswer((_) async => true);
      when(vpnService.disconnect()).thenAnswer((_) async => true);
      when(killSwitchService.deactivate()).thenThrow(Exception('Kill switch error'));

      controller.isKillSwitchEnabled.value = true;
      killSwitchService.isActive.value = true;

      await controller.connect(testConfig);
      final result = await controller.disconnect();

      expect(result, true);
      expect(controller.state.value, ConnectionState.idle);
    });

    test('Kill switch state persists across connections', () async {
      when(vpnService.connect(any)).thenAnswer((_) async => true);
      when(vpnService.disconnect()).thenAnswer((_) async => true);

      controller.isKillSwitchEnabled.value = true;

      await controller.connect(testConfig);
      expect(controller.isKillSwitchEnabled.value, true);

      await controller.disconnect();
      expect(controller.isKillSwitchEnabled.value, true);

      await controller.connect(testConfig);
      expect(controller.isKillSwitchEnabled.value, true);
    });
  });
}
