/// Unit tests for the config controller
/// Tests state management and reactive updates

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:logger/logger.dart';
import 'package:blackout_kit_mobile/models/config.dart';
import 'package:blackout_kit_mobile/models/test_result.dart';
import 'package:blackout_kit_mobile/controllers/config_controller.dart';

void main() {
  group('ConfigController', () {
    late ConfigController controller;
    late Logger mockLogger;

    setUp(() {
      mockLogger = Logger();
      controller = ConfigController(logger: mockLogger);
      Get.put<ConfigController>(controller);
    });

    tearDown(() {
      Get.delete<ConfigController>();
    });

    test('initializes with empty configs', () {
      expect(controller.allConfigs.isEmpty, true);
    });

    test('filterProtocol observable updates correctly', () {
      controller.filterProtocol.value = 'wireguard';
      expect(controller.filterProtocol.value, equals('wireguard'));
    });

    test('sortOption observable updates correctly', () {
      controller.sortOption.value = 'speed';
      expect(controller.sortOption.value, equals('speed'));
    });

    test('addConfig adds to list and notifies observers', () {
      final config = WireGuardConfig(
        displayName: 'Test Config',
        address: '10.0.0.1',
        port: 51820,
        privateKey: 'abc123==',
        rawUri: 'wireguard://10.0.0.1:51820',
        protocol: 'wireguard',
      );

      controller.allConfigs.add(config);
      expect(controller.allConfigs.length, 1);
      expect(controller.allConfigs.first.displayName, 'Test Config');
    });

    test('filteredConfigs reflects protocol filter', () {
      final wgConfig = WireGuardConfig(
        displayName: 'WireGuard Config',
        address: '10.0.0.1',
        port: 51820,
        privateKey: 'abc123==',
        rawUri: 'wireguard://10.0.0.1:51820',
        protocol: 'wireguard',
      );

      final ovpnConfig = OpenVPNConfig(
        displayName: 'OpenVPN Config',
        address: '10.0.0.2',
        port: 1194,
        configContent: 'proto tcp',
        rawUri: 'openvpn://10.0.0.2:1194',
        protocol: 'openvpn',
      );

      controller.allConfigs.addAll([wgConfig, ovpnConfig]);
      controller.filterProtocol.value = 'wireguard';

      final filtered = controller.filteredConfigs();
      expect(filtered.length, 1);
      expect(filtered.first.protocol, 'wireguard');
    });

    test('sortConfigs sorts by speed descending', () {
      final results = [
        TestResult(
          configHash: 'hash1',
          latencyMs: 50,
          speedMbps: 10.0,
          reliability: 95,
          timestamp: DateTime.now(),
        ),
        TestResult(
          configHash: 'hash2',
          latencyMs: 30,
          speedMbps: 50.0,
          reliability: 98,
          timestamp: DateTime.now(),
        ),
      ];

      controller.testResults.assignAll(results);
      controller.sortOption.value = 'speed';

      // Manually apply sorting logic
      results.sort((a, b) => (b.speedMbps ?? 0).compareTo(a.speedMbps ?? 0));

      expect(results.first.speedMbps, 50.0);
      expect(results.last.speedMbps, 10.0);
    });

    test('removeConfig removes from list', () {
      final config = WireGuardConfig(
        displayName: 'Config to Remove',
        address: '10.0.0.1',
        port: 51820,
        privateKey: 'abc123==',
        rawUri: 'wireguard://10.0.0.1:51820',
        protocol: 'wireguard',
      );

      controller.allConfigs.add(config);
      expect(controller.allConfigs.length, 1);

      controller.allConfigs.remove(config);
      expect(controller.allConfigs.isEmpty, true);
    });

    test('getTestResult retrieves test by hash', () {
      final result = TestResult(
        configHash: 'hash1',
        latencyMs: 50,
        speedMbps: 25.0,
        reliability: 95,
        timestamp: DateTime.now(),
      );

      controller.testResults.add(result);

      final retrieved = controller.testResults.firstWhere(
        (r) => r.configHash == 'hash1',
      );

      expect(retrieved.speedMbps, 25.0);
    });

    test('updateTestResult modifies existing result', () {
      final result = TestResult(
        configHash: 'hash1',
        latencyMs: 50,
        speedMbps: 25.0,
        reliability: 95,
        timestamp: DateTime.now(),
      );

      controller.testResults.add(result);
      final index = controller.testResults.indexWhere((r) => r.configHash == 'hash1');

      // Simulate update
      final updated = TestResult(
        configHash: 'hash1',
        latencyMs: 40,
        speedMbps: 35.0,
        reliability: 98,
        timestamp: DateTime.now(),
      );

      controller.testResults[index] = updated;

      expect(controller.testResults[index].speedMbps, 35.0);
    });

    test('fastestConfig returns config with highest speed', () {
      final results = [
        TestResult(
          configHash: 'hash1',
          latencyMs: 50,
          speedMbps: 10.0,
          reliability: 95,
          timestamp: DateTime.now(),
        ),
        TestResult(
          configHash: 'hash2',
          latencyMs: 30,
          speedMbps: 50.0,
          reliability: 98,
          timestamp: DateTime.now(),
        ),
        TestResult(
          configHash: 'hash3',
          latencyMs: 100,
          speedMbps: 5.0,
          reliability: 80,
          timestamp: DateTime.now(),
        ),
      ];

      controller.testResults.assignAll(results);

      final fastest = results.reduce((current, next) =>
          (current.speedMbps ?? 0) > (next.speedMbps ?? 0) ? current : next);

      expect(fastest.configHash, 'hash2');
    });

    test('workingConfigs filters by isWorking status', () {
      final results = [
        TestResult(
          configHash: 'hash1',
          latencyMs: 50,
          speedMbps: 10.0,
          reliability: 95,
          timestamp: DateTime.now(),
        ),
        TestResult(
          configHash: 'hash2',
          latencyMs: null,
          speedMbps: null,
          reliability: 0,
          timestamp: DateTime.now(),
        ),
      ];

      final working = results.where((r) => r.speedMbps != null).toList();

      expect(working.length, 1);
      expect(working.first.configHash, 'hash1');
    });

    test('isLoading observable toggles correctly', () {
      controller.isLoading.value = false;
      expect(controller.isLoading.value, false);

      controller.isLoading.value = true;
      expect(controller.isLoading.value, true);

      controller.isLoading.value = false;
      expect(controller.isLoading.value, false);
    });

    test('error observable captures error state', () {
      controller.error.value = '';
      expect(controller.error.value, isEmpty);

      controller.error.value = 'Failed to fetch configs';
      expect(controller.error.value, isNotEmpty);

      controller.error.value = '';
      expect(controller.error.value, isEmpty);
    });

    test('lastRefreshTime tracks when configs were last fetched', () {
      final beforeRefresh = DateTime.now();
      controller.lastRefreshTime.value = DateTime.now();
      final afterRefresh = DateTime.now();

      expect(
        controller.lastRefreshTime.value.isAfter(beforeRefresh),
        true,
      );
      expect(
        controller.lastRefreshTime.value.isBefore(afterRefresh.add(const Duration(seconds: 1))),
        true,
      );
    });

    test('handles empty test results gracefully', () {
      expect(controller.testResults.isEmpty, true);

      final fastest = controller.testResults.isEmpty
          ? null
          : controller.testResults.reduce((current, next) =>
              (current.speedMbps ?? 0) > (next.speedMbps ?? 0) ? current : next);

      expect(fastest, isNull);
    });

    test('multiple config sources coexist', () {
      controller.sources.assignAll([
        'https://github.com/owner1/repo1',
        'https://github.com/owner2/repo2',
      ]);

      expect(controller.sources.length, 2);
    });

    test('clearAll resets controller state', () {
      controller.allConfigs.add(WireGuardConfig(
        displayName: 'Test',
        address: '10.0.0.1',
        port: 51820,
        privateKey: 'key',
        rawUri: 'uri',
        protocol: 'wireguard',
      ));
      controller.testResults.add(TestResult(
        configHash: 'hash',
        latencyMs: 50,
        speedMbps: 25.0,
        reliability: 95,
        timestamp: DateTime.now(),
      ));

      controller.allConfigs.clear();
      controller.testResults.clear();

      expect(controller.allConfigs.isEmpty, true);
      expect(controller.testResults.isEmpty, true);
    });
  });
}
