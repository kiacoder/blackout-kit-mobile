import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:logger/logger.dart';
import 'package:mockito/mockito.dart';

import 'package:blackout_kit_mobile/models/config.dart';
import 'package:blackout_kit_mobile/models/test_result.dart';
import 'package:blackout_kit_mobile/services/vpn_service.dart';
import 'package:blackout_kit_mobile/services/tester_service.dart';
import 'package:blackout_kit_mobile/services/kill_switch_service.dart';
import 'package:blackout_kit_mobile/services/dns_leak_prevention_service.dart';
import 'package:blackout_kit_mobile/services/split_tunneling_service.dart';
import 'package:blackout_kit_mobile/services/debug_service.dart';
import 'package:blackout_kit_mobile/controllers/connection_controller.dart';

class MockVPNService extends Mock implements VPNService {}

class MockTesterService extends Mock implements TesterService {}

class MockKillSwitchService extends Mock implements KillSwitchService {
  @override
  final isActive = false.obs;

  @override
  Future<void> cleanup() async {}
}

class MockDNSLeakPreventionService extends Mock
    implements DNSLeakPreventionService {
  @override
  final isActive = false.obs;

  @override
  Future<void> cleanup() async {}
}

class MockSplitTunnelingService extends Mock implements SplitTunnelingService {
  @override
  final isActive = false.obs;

  @override
  Future<void> cleanup() async {}
}

class MockConfig extends Mock implements Config {
  @override
  String get displayName => 'Test Config';

  @override
  bool validate() => true;

  @override
  String getHash() => 'test-hash';
}

void main() {
  late ConnectionController connectionController;
  late MockVPNService mockVPNService;
  late MockTesterService mockTesterService;
  late MockKillSwitchService mockKillSwitchService;
  late MockDNSLeakPreventionService mockDNSLeakPreventionService;
  late MockSplitTunnelingService mockSplitTunnelingService;
  late DebugService debugService;
  late MockConfig mockConfig;

  setUp(() {
    mockVPNService = MockVPNService();
    mockTesterService = MockTesterService();
    mockKillSwitchService = MockKillSwitchService();
    mockDNSLeakPreventionService = MockDNSLeakPreventionService();
    mockSplitTunnelingService = MockSplitTunnelingService();
    debugService = DebugService();
    debugService.onInit();
    mockConfig = MockConfig();

    connectionController = ConnectionController(
      vpnService: mockVPNService,
      testerService: mockTesterService,
      killSwitchService: mockKillSwitchService,
      dnsLeakPreventionService: mockDNSLeakPreventionService,
      splitTunnelingService: mockSplitTunnelingService,
      debugService: debugService,
    );
    connectionController.onInit();
  });

  group('Debug Logging Integration', () {
    test('logs when VPN connection succeeds', () async {
      when(mockVPNService.connect(any)).thenAnswer((_) async => true);
      when(mockVPNService.getConnectedIP()).thenAnswer((_) async => '1.2.3.4');

      await connectionController.connect(mockConfig);

      expect(
        debugService.logEntries
            .any((e) => e.message.contains('connected')),
        true,
      );
    });

    test('logs when kill switch is enabled', () async {
      when(mockKillSwitchService.enable()).thenAnswer((_) async => true);

      await connectionController.toggleKillSwitch();

      expect(
        debugService.logEntries
            .any((e) => e.message.contains('Kill switch enabled')),
        true,
      );
    });

    test('logs when kill switch is disabled', () async {
      connectionController.isKillSwitchEnabled.value = true;
      when(mockKillSwitchService.disable()).thenAnswer((_) async => true);

      await connectionController.toggleKillSwitch();

      expect(
        debugService.logEntries
            .any((e) => e.message.contains('Kill switch disabled')),
        true,
      );
    });

    test('logs when DNS leak prevention is enabled', () async {
      when(mockDNSLeakPreventionService.enable())
          .thenAnswer((_) async => true);

      await connectionController.toggleDNSLeakPrevention();

      expect(
        debugService.logEntries
            .any((e) => e.message.contains('DNS leak prevention enabled')),
        true,
      );
    });

    test('logs when DNS leak prevention is disabled', () async {
      connectionController.isDNSLeakPreventionEnabled.value = true;
      when(mockDNSLeakPreventionService.disable())
          .thenAnswer((_) async => true);

      await connectionController.toggleDNSLeakPrevention();

      expect(
        debugService.logEntries
            .any((e) => e.message.contains('DNS leak prevention disabled')),
        true,
      );
    });

    test('logs when split tunneling is enabled', () async {
      when(mockSplitTunnelingService.enable())
          .thenAnswer((_) async => true);

      await connectionController.toggleSplitTunneling();

      expect(
        debugService.logEntries
            .any((e) => e.message.contains('Split tunneling enabled')),
        true,
      );
    });

    test('logs when split tunneling is disabled', () async {
      connectionController.isSplitTunnelingEnabled.value = true;
      when(mockSplitTunnelingService.disable())
          .thenAnswer((_) async => true);

      await connectionController.toggleSplitTunneling();

      expect(
        debugService.logEntries
            .any((e) => e.message.contains('Split tunneling disabled')),
        true,
      );
    });

    test('logs when VPN disconnects', () async {
      when(mockVPNService.disconnect()).thenAnswer((_) async => true);
      mockKillSwitchService.isActive.value = false;
      mockDNSLeakPreventionService.isActive.value = false;
      mockSplitTunnelingService.isActive.value = false;

      await connectionController.disconnect();

      expect(
        debugService.logEntries
            .any((e) => e.message.contains('disconnected')),
        true,
      );
    });

    test('logs security feature activations on connection', () async {
      when(mockVPNService.connect(any)).thenAnswer((_) async => true);
      when(mockVPNService.getConnectedIP()).thenAnswer((_) async => '1.2.3.4');
      when(mockKillSwitchService.activate()).thenAnswer((_) async {});
      when(mockDNSLeakPreventionService.activate()).thenAnswer((_) async {});
      when(mockSplitTunnelingService.activate()).thenAnswer((_) async {});

      connectionController.isKillSwitchEnabled.value = true;
      connectionController.isDNSLeakPreventionEnabled.value = true;
      connectionController.isSplitTunnelingEnabled.value = true;

      await connectionController.connect(mockConfig);

      expect(
        debugService.logEntries.any((e) => e.message.contains('Kill switch')),
        true,
      );
      expect(
        debugService.logEntries
            .any((e) => e.message.contains('DNS leak prevention')),
        true,
      );
      expect(
        debugService.logEntries
            .any((e) => e.message.contains('Split tunneling')),
        true,
      );
    });

    test('logs security feature deactivations on disconnect', () async {
      when(mockVPNService.disconnect()).thenAnswer((_) async => true);
      mockKillSwitchService.isActive.value = true;
      mockDNSLeakPreventionService.isActive.value = true;
      mockSplitTunnelingService.isActive.value = true;

      when(mockKillSwitchService.deactivate()).thenAnswer((_) async {});
      when(mockDNSLeakPreventionService.deactivate()).thenAnswer((_) async {});
      when(mockSplitTunnelingService.deactivate()).thenAnswer((_) async {});

      await connectionController.disconnect();

      final logsString = debugService.getLogsAsString();
      expect(logsString.contains('Kill switch'), true);
      expect(logsString.contains('DNS leak prevention'), true);
      expect(logsString.contains('Split tunneling'), true);
    });

    test('logs errors when security features fail', () async {
      when(mockKillSwitchService.enable())
          .thenThrow(Exception('Test error'));

      await connectionController.toggleKillSwitch();

      expect(
        debugService.logEntries
            .any((e) => e.level.toString().contains('ERROR')),
        true,
      );
    });

    test('maintains chronological log order', () async {
      when(mockVPNService.connect(any)).thenAnswer((_) async => true);
      when(mockVPNService.getConnectedIP()).thenAnswer((_) async => '1.2.3.4');
      when(mockKillSwitchService.enable()).thenAnswer((_) async => true);

      await connectionController.toggleKillSwitch();
      await connectionController.connect(mockConfig);

      final logs = debugService.logEntries;
      expect(logs.length > 1, true);
      for (int i = 1; i < logs.length; i++) {
        expect(
          logs[i].timestamp.isAfter(logs[i - 1].timestamp) ||
              logs[i].timestamp.isAtSameMomentAs(logs[i - 1].timestamp),
          true,
        );
      }
    });

    test('includes debug info with log count', () async {
      when(mockKillSwitchService.enable()).thenAnswer((_) async => true);
      await connectionController.toggleKillSwitch();

      final debugInfo = debugService.getDebugInfo();
      expect(debugInfo['log_count'], greaterThan(0));
      expect(debugInfo.containsKey('timestamp'), true);
    });
  });
}
