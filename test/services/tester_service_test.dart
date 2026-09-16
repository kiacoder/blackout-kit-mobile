/// Unit tests for the tester service
/// Tests speed testing, ranking, and reliability calculations

import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:blackout_kit_mobile/models/config.dart';
import 'package:blackout_kit_mobile/models/test_result.dart';
import 'package:blackout_kit_mobile/services/tester_service.dart';

void main() {
  group('TesterService', () {
    late TesterService testerService;
    late Logger mockLogger;

    setUp(() {
      mockLogger = Logger();
      testerService = TesterService(logger: mockLogger);
    });

    test('testConfig returns valid TestResult', () async {
      final config = WireGuardConfig(
        displayName: 'Test Config',
        address: '10.0.0.1',
        port: 51820,
        privateKey: 'abc123==',
        rawUri: 'wireguard://10.0.0.1:51820',
        protocol: 'wireguard',
      );

      final result = await testerService.testConfig(config);

      expect(result, isNotNull);
      expect(result.latencyMs, isNotNull);
      expect(result.speedMbps, isNotNull);
      expect(result.reliability, greaterThanOrEqualTo(0));
      expect(result.reliability, lessThanOrEqualTo(100));
    });

    test('testConfigs returns multiple results', () async {
      final configs = [
        WireGuardConfig(
          displayName: 'Config 1',
          address: '10.0.0.1',
          port: 51820,
          privateKey: 'abc123==',
          rawUri: 'wireguard://10.0.0.1:51820',
          protocol: 'wireguard',
        ),
        WireGuardConfig(
          displayName: 'Config 2',
          address: '10.0.0.2',
          port: 51820,
          privateKey: 'abc123==',
          rawUri: 'wireguard://10.0.0.2:51820',
          protocol: 'wireguard',
        ),
      ];

      final results = await testerService.testConfigs(configs);

      expect(results.length, 2);
      expect(results.every((r) => r.latencyMs != null), true);
    });

    test('rankConfigs sorts by speed descending', () {
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

      final rankings = testerService.rankConfigs(results);

      expect(rankings[0].configHash, 'hash2');
      expect(rankings[0].rank, 1);
      expect(rankings[1].configHash, 'hash1');
      expect(rankings[1].rank, 2);
      expect(rankings[2].configHash, 'hash3');
      expect(rankings[2].rank, 3);
    });

    test('getWorkingConfigs filters by isWorking', () {
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

      final working = testerService.getWorkingConfigs(results);

      expect(working.length, 1);
      expect(working[0].configHash, 'hash1');
    });

    test('getAverageReliability calculates correctly', () {
      final results = [
        TestResult(
          configHash: 'hash1',
          latencyMs: 50,
          speedMbps: 10.0,
          reliability: 100,
          timestamp: DateTime.now(),
        ),
        TestResult(
          configHash: 'hash2',
          latencyMs: 30,
          speedMbps: 50.0,
          reliability: 80,
          timestamp: DateTime.now(),
        ),
        TestResult(
          configHash: 'hash3',
          latencyMs: 100,
          speedMbps: 5.0,
          reliability: 70,
          timestamp: DateTime.now(),
        ),
      ];

      final average = testerService.getAverageReliability(results);

      expect(average, closeTo(83.33, 0.1));
    });

    test('getFastestConfig returns fastest working', () {
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

      final fastest = testerService.getFastestConfig(results);

      expect(fastest, isNotNull);
      expect(fastest!.configHash, 'hash2');
      expect(fastest.speedMbps, 50.0);
    });

    test('handles empty results gracefully', () {
      final empty = <TestResult>[];

      expect(testerService.getAverageReliability(empty), 0);
      expect(testerService.getFastestConfig(empty), null);
      expect(testerService.getWorkingConfigs(empty), []);
    });

    test('test results have correct timestamp', () async {
      final config = WireGuardConfig(
        displayName: 'Test Config',
        address: '10.0.0.1',
        port: 51820,
        privateKey: 'abc123==',
        rawUri: 'wireguard://10.0.0.1:51820',
        protocol: 'wireguard',
      );

      final result = await testerService.testConfig(config);
      final now = DateTime.now();

      expect(result.timestamp.isBefore(now.add(const Duration(seconds: 5))), true);
      expect(result.timestamp.isAfter(now.subtract(const Duration(seconds: 5))), true);
    });
  });
}
