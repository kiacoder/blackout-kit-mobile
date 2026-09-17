import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controllers/config_controller.dart';
import '../controllers/connection_controller.dart';
import '../models/config.dart';

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

  Future<void> _runFullBenchmark() async {
    final configs = _configController.allConfigs;
    if (configs.isEmpty) {
      Get.snackbar(
        'No Configs',
        'Please import or fetch configs before running speed tests',
        backgroundColor: Colors.orange,
        colorText: Colors.white,
      );
      return;
    }

    setState(() {
      _isTesting = true;
      _testedCount = 0;
      _totalToTest = configs.length;
    });

    for (int i = 0; i < configs.length; i++) {
      if (!mounted) break;
      final config = configs[i];
      setState(() {
        _currentTestingConfig = config;
        _testedCount = i + 1;
      });

      await _configController.testConfig(config);
    }

    if (mounted) {
      setState(() {
        _isTesting = false;
        _currentTestingConfig = null;
      });
      Get.snackbar(
        'Benchmark Complete',
        'Tested $_totalToTest configurations successfully!',
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
                            '${result.speedMbps?.toStringAsFixed(1)} Mbps • ${result.latencyMs}ms ping',
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
              final configs = _configController.allConfigs;
              if (configs.isEmpty) {
                return Center(
                  child: Text('No configs to benchmark', style: TextStyle(color: theme.hintColor)),
                );
              }

              final sorted = _configController.getFilteredConfigs();

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
                              Text(
                                result.speedMbps != null
                                    ? '${result.speedMbps!.toStringAsFixed(1)} Mbps'
                                    : 'Failed',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: result.isWorking ? Colors.green : Colors.red,
                                ),
                              ),
                              Text(
                                result.latencyMs != null ? '${result.latencyMs}ms' : 'Timeout',
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
