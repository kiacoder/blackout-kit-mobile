/// Tester service: real reachability and latency measurement for VPN configs.
///
/// ## What this used to be
///
/// The previous implementation *simulated* everything:
///
///     final seed = config.getHash().hashCode;
///     return 50 + (seed % 250).abs();          // "latency"
///     return 1.0 + (seed % 50).abs().toDouble(); // "speed"
///
/// So the "speed test" produced a deterministic number derived from the config
/// string. The same config always reported the same fake throughput, and
/// `connectFastest()` then told the user it had picked the fastest server based
/// on those invented figures. Nothing was ever contacted.
///
/// ## What it does now
///
/// It opens a real TCP connection to the config's `address:port` and times it,
/// repeated a few times to get a reliability figure. That is a genuine
/// measurement of the network path to the server.
///
/// ## What it still does not do, and why
///
/// **Throughput is not measured.** `speedMbps` is always null. Measuring
/// bandwidth properly means transferring data *through* the tunnel, which
/// requires the tunnel to be up — you cannot do it before choosing a config,
/// which is when the UI wants the number. Reporting null and letting the UI
/// show latency is honest; inventing a figure is not.
///
/// **A TCP probe is not a protocol handshake.** It proves the host answers on
/// that port; it does not prove the credentials, UUID or REALITY keys are
/// valid. A config can pass this test and still fail to connect.
library;

import 'dart:async';
import 'dart:io';

import 'package:logger/logger.dart';

import '../models/config.dart';
import '../models/test_result.dart';

typedef OnTestProgress = void Function(String configHash, TestStatus status);

/// Outcome of a single reachability probe.
class _Probe {
  final bool reachable;
  final int? latencyMs;
  final String? error;

  const _Probe({required this.reachable, this.latencyMs})
      : error = null;

  const _Probe.failed(String reason)
      : reachable = false,
        latencyMs = null,
        error = reason;
}

class TesterService {
  final Logger _log;
  OnTestProgress? onProgress;

  /// Per-attempt timeout. Deliberately short: a config that takes longer than
  /// this to answer is not one the user wants to connect to anyway.
  static const Duration defaultTimeout = Duration(seconds: 4);

  /// Probes per config, used to derive a reliability figure.
  static const int defaultAttempts = 3;

  TesterService({Logger? logger}) : _log = logger ?? Logger();

  /// Measures a single config.
  ///
  /// Returns a success result carrying the best observed latency and the
  /// success ratio, or a failure result carrying the last error seen.
  Future<TestResult> testConfig(
    Config config, {
    int attempts = defaultAttempts,
    Duration timeout = defaultTimeout,
  }) async {
    final hash = config.getHash();
    onProgress?.call(hash, TestStatus.testing);

    if (!config.validate()) {
      const reason = 'Config is incomplete';
      onProgress?.call(hash, TestStatus.failed);
      return TestResult.failed(configHash: hash, error: reason);
    }

    if (config.address.isEmpty || config.port <= 0) {
      const reason = 'Config has no usable server address';
      onProgress?.call(hash, TestStatus.failed);
      return TestResult.failed(configHash: hash, error: reason);
    }

    _log.i('Probing ${config.displayName} (${config.address}:${config.port})');

    var successes = 0;
    int? bestLatency;
    String? lastError;

    for (var attempt = 0; attempt < attempts; attempt++) {
      final probe = await _probe(config.address, config.port, timeout);
      if (probe.reachable) {
        successes++;
        final ms = probe.latencyMs;
        if (ms != null && (bestLatency == null || ms < bestLatency)) {
          bestLatency = ms;
        }
      } else {
        lastError = probe.error;
      }
    }

    if (successes == 0) {
      _log.w('${config.displayName} unreachable: ${lastError ?? "no response"}');
      onProgress?.call(hash, TestStatus.timeout);
      return TestResult.failed(
        configHash: hash,
        error: lastError ?? 'No response from ${config.address}:${config.port}',
        status: TestStatus.timeout,
      );
    }

    _log.i('${config.displayName}: ${bestLatency}ms, $successes/$attempts attempts');
    onProgress?.call(hash, TestStatus.success);

    return TestResult.success(
      configHash: hash,
      latencyMs: bestLatency,
      // Not measured on purpose - see the library doc comment.
      speedMbps: null,
      successCount: successes,
      totalCount: attempts,
    );
  }

  /// Probes each config in turn, reporting progress through [onProgress].
  Future<List<TestResult>> testConfigs(
    List<Config> configs, {
    int attempts = defaultAttempts,
    Duration timeout = defaultTimeout,
  }) async {
    final results = <TestResult>[];
    for (final config in configs) {
      results.add(await testConfig(config, attempts: attempts, timeout: timeout));
    }
    return results;
  }

  /// Probes configs concurrently.
  ///
  /// Sequential probing of 50 configs at 3 attempts and a 4s timeout could take
  /// ten minutes in the worst case; this bounds the wall-clock cost by running
  /// a limited number in flight.
  Future<List<TestResult>> testConfigsConcurrently(
    List<Config> configs, {
    int concurrency = 6,
    int attempts = defaultAttempts,
    Duration timeout = defaultTimeout,
  }) async {
    if (configs.isEmpty) return const [];

    final results = List<TestResult?>.filled(configs.length, null);
    var next = 0;

    Future<void> worker() async {
      while (true) {
        final index = next++;
        if (index >= configs.length) return;
        results[index] =
            await testConfig(configs[index], attempts: attempts, timeout: timeout);
      }
    }

    await Future.wait(
      List.generate(concurrency.clamp(1, configs.length), (_) => worker()),
    );
    return results.cast<TestResult>();
  }

  /// Opens a TCP connection to [host]:[port] and times it.
  ///
  /// A refused connection still counts as reachable: the host answered with a
  /// RST, which proves the network path works. That matters for UDP-only
  /// protocols such as WireGuard, where the port will never accept TCP but the
  /// host is plainly alive. A timeout means nothing came back at all.
  Future<_Probe> _probe(String host, int port, Duration timeout) async {
    final stopwatch = Stopwatch()..start();
    try {
      final socket = await Socket.connect(host, port, timeout: timeout);
      stopwatch.stop();
      socket.destroy();
      return _Probe(reachable: true, latencyMs: stopwatch.elapsedMilliseconds);
    } on SocketException catch (e) {
      stopwatch.stop();
      final message = e.message.toLowerCase();
      final refused = message.contains('refused') ||
          e.osError?.errorCode == 111 || // Linux/Android ECONNREFUSED
          e.osError?.errorCode == 61; // macOS ECONNREFUSED

      if (refused) {
        // Host is up, it just does not speak TCP on this port.
        return _Probe(reachable: true, latencyMs: stopwatch.elapsedMilliseconds);
      }
      return _Probe.failed(e.message);
    } on TimeoutException {
      return _Probe.failed(
        'Timed out after ${timeout.inSeconds}s - the server did not respond',
      );
    } catch (e) {
      return _Probe.failed(e.toString());
    }
  }

  /// Ranks configs, best first.
  ///
  /// Sorted by latency ascending. Speed is not a ranking input because it is
  /// not measured; latency is the only real signal we have.
  List<ConfigRanking> rankConfigs(List<TestResult> results) {
    final working = getWorkingConfigs(results);
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

  /// Working configs, fastest (lowest latency) first.
  List<TestResult> getWorkingConfigs(List<TestResult> results) {
    final working = results.where((r) => r.isWorking).toList();
    working.sort((a, b) {
      final aMs = a.latencyMs ?? 1 << 30;
      final bMs = b.latencyMs ?? 1 << 30;
      return aMs.compareTo(bMs);
    });
    return working;
  }

  /// Fastest working config, or null when none passed.
  TestResult? getFastestConfig(List<TestResult> results) {
    final working = getWorkingConfigs(results);
    return working.isEmpty ? null : working.first;
  }

  /// Average reliability percentage across all tested configs.
  double getAverageReliability(List<TestResult> results) {
    if (results.isEmpty) return 0;
    final total = results.fold(0.0, (sum, r) => sum + r.reliability);
    return total / results.length;
  }
}
