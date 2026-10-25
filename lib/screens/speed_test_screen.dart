import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controllers/config_controller.dart';
import '../controllers/connection_controller.dart';
import '../models/config.dart';
import '../models/test_result.dart';

class SpeedTestScreen extends StatefulWidget {
  const SpeedTestScreen({Key? key}) : super(key: key);

  @override
  State<SpeedTestScreen> createState() => _SpeedTestScreenState();
}

class _SpeedTestScreenState extends State<SpeedTestScreen> {
  late final ConfigController _configController;
  late final ConnectionController _connectionController;

  bool _isTesting = false;
  int _testedCount = 0;
  int _totalToTest = 0;
  Config? _currentTestingConfig;

  @override
  void initState() {
    super.initState();
    _configController = Get.find<ConfigController>();
    _connectionController = Get.find<ConnectionController>();
  }

  /// How many configs one benchmark run probes, and how.
  ///
  /// "Test All" used to walk the ENTIRE library sequentially — with a real
  /// source that is thousands of configs at up to 12s each, i.e. days. The
  /// home screen already settled on a bounded concurrent sample; the benchmark
  /// uses the same budget so the two surfaces agree.
  static const int _benchmarkSample = 150;
  static const int _benchmarkConcurrency = 16;

  Future<void> _runFullBenchmark() async {
    // `visibleConfigs` honours disabled repositories; `allConfigs` does not, so
    // the benchmark used to probe (and report on) servers the user had turned
    // off in Settings.
    final configs = _configController.visibleConfigs;
    if (configs.isEmpty) {
      Get.snackbar(
        'No Configs',
        'Please import or fetch configs before running speed tests',
        backgroundColor: Colors.orange,
        colorText: Colors.white,
      );
      return;
    }

    final sample = configs.take(_benchmarkSample).toList();
    setState(() {
      _isTesting = true;
      _testedCount = 0;
      _totalToTest = sample.length;
      _currentTestingConfig = sample.first;
    });

    final progressToken =
        _configController.testerService.beginProgressRun((hash, status) {
      if (!mounted) return;
      if (status == TestStatus.testing) {
        // A probe just started on this config: label it. The old code kept
        // showing sample.first for the whole run because only the progress
        // count was ever updated.
        final started = sample
            .firstWhereOrNull((c) => c.getHash() == hash);
        if (started != null) {
          setState(() => _currentTestingConfig = started);
        }
        return;
      }
      setState(() => _testedCount++);
    });

    try {
      final results =
          await _configController.testerService.testConfigsConcurrently(
        sample,
        concurrency: _benchmarkConcurrency,
      );
      for (final result in results) {
        _configController.testResults[result.configHash] = result;
      }
    } catch (e) {
      if (mounted) {
        Get.snackbar(
          'Benchmark Failed',
          'The speed test could not finish: $e',
          backgroundColor: Colors.red,
          colorText: Colors.white,
        );
      }
    } finally {
      // Always drop the callback AND clear the testing state: an exception
      // escaping the try above used to leave the screen spinning forever.
      _configController.testerService.endProgressRun(progressToken);
      if (mounted) {
        setState(() {
          _isTesting = false;
          _currentTestingConfig = null;
        });
      }
    }

    if (mounted) {
      final working = _configController.testResults.values
          .where((r) => sample.any((c) => c.getHash() == r.configHash))
          .where((r) => r.isWorking)
          .length;
      Get.snackbar(
        'Benchmark Complete',
        '$working of ${sample.length} servers responded '
        '(library holds ${configs.length} configs)',
        backgroundColor: Colors.green,
        colorText: Colors.white,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Speed & Latency Benchmark'),
        elevation: 0,
      ),
      body: Column(
        children: [
          // Benchmark Summary Card
          Container(
            padding: const EdgeInsets.all(20),
            color: isDark ? theme.cardColor : Colors.indigo.withOpacity(0.06),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Performance Tester',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Obx(() {
                          final stats = _configController.getStats();
                          final tested = stats['tested'] ?? 0;
                          final total = stats['total'] ?? 0;
                          return Text(
                            '$tested / $total configs tested',
                            style: TextStyle(color: theme.hintColor, fontSize: 13),
                          );
                        }),
                      ],
                    ),
                    ElevatedButton.icon(
                      onPressed: _isTesting ? null : _runFullBenchmark,
                      icon: _isTesting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.speed),
                      label: Text(_isTesting ? 'Testing...' : 'Test All'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: theme.colorScheme.primary,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
                if (_isTesting) ...[
                  const SizedBox(height: 16),
                  LinearProgressIndicator(
                    value: _totalToTest > 0 ? _testedCount / _totalToTest : 0.0,
                  ),
                  const SizedBox(height: 8),
                  if (_currentTestingConfig != null)
                    Text(
                      'Testing: ${_currentTestingConfig!.displayName}',
                      style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ],
            ),
          ),

          // Connect to Fastest Banner
          Obx(() {
            final topConfigs = _configController.getTopConfigs(limit: 1);
            if (topConfigs.isEmpty) return const SizedBox.shrink();
            final fastest = topConfigs.first;
            final result = _configController.testResults[fastest.getHash()];

            return Container(
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF10B981), Color(0xFF059669)],
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.bolt, color: Colors.white, size: 36),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Fastest Configuration',
                          style: TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                        Text(
                          fastest.displayName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (result != null)
                          Text(
                            // No Mbps claim — throughput is not measured.
                            '${result.latencyMs ?? '?'}ms ping • ${result.reliability.toStringAsFixed(0)}% reliable',
                            style: const TextStyle(color: Colors.white, fontSize: 12),
                          ),
                      ],
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () async {
                      final success = await _connectionController.connect(
                        fastest,
                        testResult: result,
                      );
                      if (success) {
                        Get.snackbar(
                          'Connected',
                          'Switched to fastest: ${fastest.displayName}',
                          backgroundColor: Colors.green,
                          colorText: Colors.white,
                        );
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.green.shade900,
                    ),
                    child: const Text('Connect'),
                  ),
                ],
              ),
            );
          }),

          // Results List
          Expanded(
            child: Obx(() {
              // visibleConfigs, so configs from disabled or untrusted
              // repositories do not appear in a benchmark.
              final configs = _configController.visibleConfigs;
              if (configs.isEmpty) {
                return Center(
                  child: Text('No configs to benchmark', style: TextStyle(color: theme.hintColor)),
                );
              }

              // Rank by measured latency here instead of reusing
              // getFilteredConfigs(): that applies the Library screen's filter
              // and sort (so "Alphabetical" crowned the first name "#1
              // fastest") and resets the Library's pagination as a side effect.
              final sorted = List<Config>.of(configs)
                ..sort((a, b) {
                  final aMs = _configController.testResults[a.getHash()]
                          ?.latencyMs ??
                      1 << 30;
                  final bMs = _configController.testResults[b.getHash()]
                          ?.latencyMs ??
                      1 << 30;
                  return aMs.compareTo(bMs);
                });

              return ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: sorted.length,
                separatorBuilder: (context, index) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final config = sorted[index];
                  final result = _configController.testResults[config.getHash()];
                  final isFastest = index == 0 && (result?.isWorking ?? false);

                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: isFastest
                          ? Colors.amber
                          : (result?.isWorking == true ? Colors.green.withOpacity(0.2) : Colors.grey.withOpacity(0.2)),
                      child: Text(
                        '#${index + 1}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: isFastest ? Colors.black : (result?.isWorking == true ? Colors.green : Colors.grey),
                        ),
                      ),
                    ),
                    title: Text(config.displayName, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(
                      '${config.protocol.toUpperCase()} • ${config.address}:${config.port}',
                      style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (result != null) ...[
                          Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              // Throughput is never measured (see
                              // TesterService) — the old code rendered
                              // speedMbps, which is always null, so every
                              // WORKING server showed "Failed" in red.
                              Text(
                                result.isWorking
                                    ? 'Working'
                                    : 'Failed',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: result.isWorking ? Colors.green : Colors.red,
                                ),
                              ),
                              Text(
                                result.latencyMs != null ? '${result.latencyMs}ms' : 'No response',
                                style: TextStyle(fontSize: 11, color: theme.hintColor),
                              ),
                            ],
                          ),
                          const SizedBox(width: 8),
                        ],
                        IconButton(
                          icon: const Icon(Icons.play_arrow),
                          onPressed: () => _configController.testConfig(config),
                          tooltip: 'Test single config',
                        ),
                      ],
                    ),
                  );
                },
              );
            }),
          ),
        ],
      ),
    );
  }
}
