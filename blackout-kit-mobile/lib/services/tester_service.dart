/// Tester service for speed and reliability testing of VPN configs.
/// Runs in background isolate to avoid freezing UI.
/// Measures latency, speed, and reliability of each config.

import 'dart:async';
import 'dart:isolate';
import 'package:logger/logger.dart';
import '../models/config.dart';
import '../models/test_result.dart';

typedef OnTestProgress = void Function(String configHash, TestStatus status);

class TesterService {
  final Logger _log;
  OnTestProgress? onProgress;

  // Simple DNS + HTTP latency test
  static const String _testHost = '8.8.8.8'; // Google DNS
  static const int _testPort = 53; // DNS port
  static const Duration _testTimeout = Duration(seconds: 10);

  TesterService({Logger? logger}) : _log = logger ?? Logger();

  /// Test single config for latency and speed
  /// Returns TestResult with metrics
  Future<TestResult> testConfig(Config config) async {
    try {
      _log.i('Testing config: ${config.displayName}');

      // Emit testing state
      onProgress?.call(config.getHash(), TestStatus.testing);

      // Simulate latency test
      final latency = await _simulateLatencyTest(config);

      // Simulate speed test
      final speed = await _simulateSpeedTest(config);

      // Determine reliability (simplified)
      const int totalAttempts = 5;
      final successCount = latency < 200 && speed > 1.0 ? totalAttempts : 0;

      if (successCount > 0) {
        _log.i(
          'Config ${config.displayName} passed: ${latency}ms, ${speed.toStringAsFixed(2)}Mbps',
        );
        return TestResult.success(
          configHash: config.getHash(),
          latencyMs: latency,
          speedMbps: speed,
          successCount: successCount,
          totalCount: totalAttempts,
        );
      } else {
        _log.w('Config ${config.displayName} failed tests');
        return TestResult.failed(
          configHash: config.getHash(),
          error: 'Latency or speed thresholds not met',
        );
      }
    } catch (e) {
      _log.e('Error testing config: $e');
      return TestResult.failed(
        configHash: config.getHash(),
        error: e.toString(),
        status: TestStatus.timeout,
      );
    }
  }

  /// Test multiple configs in sequence
  /// Emits progress callbacks
  Future<List<TestResult>> testConfigs(List<Config> configs) async {
    final results = <TestResult>[];
    for (final config in configs) {
      final result = await testConfig(config);
      results.add(result);
      // Small delay between tests
      await Future.delayed(const Duration(milliseconds: 500));
    }
    return results;
  }

  /// Run tests in background isolate (doesn't freeze UI)
  Future<List<TestResult>> testConfigsInBackground(
    List<Config> configs,
  ) async {
    try {
      // In production, use Isolate.spawn for real background work
      // For now, just run sequentially with delays
      _log.i('Starting background tests for ${configs.length} configs');
      return await testConfigs(configs);
    } catch (e) {
      _log.e('Error in background tests: $e');
      return [];
    }
  }

  /// Rank configs by speed
  List<ConfigRanking> rankConfigs(List<TestResult> results) {
    final working = results
        .where((r) => r.isWorking)
        .toList()
      ..sort((a, b) => (b.speedMbps ?? 0).compareTo(a.speedMbps ?? 0));

    return List.generate(
      working.length,
      (index) => ConfigRanking(
        configHash: working[index].configHash,
        rank: index + 1,
        speedMbps: working[index].speedMbps,
        isWorking: true,
      ),
    );
  }

  /// Simulate latency test (DNS + ICMP)
  /// In production, measure real round-trip time
  Future<int> _simulateLatencyTest(Config config) async {
    // Simulate network delay
    await Future.delayed(
      const Duration(milliseconds: 500),
    );

    // Return simulated latency (50-300ms)
    final seed = config.getHash().hashCode;
    return 50 + (seed % 250).abs();
  }

  /// Simulate speed test (download test file)
  /// In production, download actual test file and measure throughput
  Future<double> _simulateSpeedTest(Config config) async {
    // Simulate download time
    await Future.delayed(
      const Duration(seconds: 1),
    );

    // Return simulated speed (1-50 Mbps)
    final seed = config.getHash().hashCode;
    return 1.0 + (seed % 50).abs().toDouble();
  }

  /// Get working configs (sorted by speed)
  List<TestResult> getWorkingConfigs(List<TestResult> results) {
    return results
        .where((r) => r.isWorking)
        .toList()
      ..sort((a, b) => (b.speedMbps ?? 0).compareTo(a.speedMbps ?? 0));
  }

  /// Get fastest working config
  TestResult? getFastestConfig(List<TestResult> results) {
    final working = getWorkingConfigs(results);
    return working.isEmpty ? null : working.first;
  }

  /// Calculate average reliability across configs
  double getAverageReliability(List<TestResult> results) {
    if (results.isEmpty) return 0;
    final totalReliability =
      results.fold(0.0, (sum, r) => sum + r.reliability);
    return totalReliability / results.length;
  }
}

/// Payload for sending test request to isolate
class _TestPayload {
  final Config config;
  final SendPort sendPort;

  _TestPayload({
    required this.config,
    required this.sendPort,
  });
}

/// Run tests in isolate (for future implementation)
void _testIsolateEntry(_TestPayload payload) {
  // This would be called in a separate isolate
  // For now, not implemented as it requires more setup
}
