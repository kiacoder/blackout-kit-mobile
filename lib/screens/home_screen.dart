/// Home screen - Main UI for Blackout Kit VPN app
/// Features:
/// - Big connect/disconnect button (one-tap VPN)
/// - Real-time connection status and IP
/// - Quick stats (speed, reliability, uptime)
/// - Quick access to Library and Settings

import 'package:flutter/material.dart' hide ConnectionState;
import 'package:get/get.dart';

import '../controllers/config_controller.dart';
import '../controllers/connection_controller.dart';
import '../widgets/app_logo.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final ConfigController _configController;
  late final ConnectionController _connectionController;

  @override
  void initState() {
    super.initState();
    _configController = Get.find<ConfigController>();
    _connectionController = Get.find<ConnectionController>();

    // Fetch configs on first load
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    // Fetch from all enabled sources
    await _configController.fetchFromAllSources();

    // Test all configs
    await _configController.testAllConfigs();
  }

  Future<void> _handleConnectDisconnect() async {
    if (_connectionController.isConnected) {
      await _connectionController.disconnect();
    } else {
      // Get available configs
      final configs = _configController.allConfigs;
      if (configs.isEmpty) {
        _showSnackbar('No configs available', Colors.orange);
        return;
      }

      // Connect to fastest
      final testResults = _connectionController.selectedConfigResult.value;
      final success = await _connectionController.connectFastest(
        configs,
        testResults: testResults != null
            ? [testResults]
            : List.from(_connectionController.selectedConfigResult.value == null
                ? []
                : [_connectionController.selectedConfigResult.value!]),
      );

      if (!success) {
        _showSnackbar('Failed to connect', Colors.red);
      }
    }
  }

  void _showSnackbar(String message, Color color) {
    Get.snackbar(
      'Blackout Kit',
      message,
      backgroundColor: color,
      colorText: Colors.white,
      duration: const Duration(seconds: 3),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const AppLogo(size: 28, showSubtitle: false, direction: Axis.horizontal),
        centerTitle: true,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              const SizedBox(height: 24),
              // Status card
              _buildStatusCard(),
              const SizedBox(height: 32),
              // Big connect button
              _buildConnectButton(),
              const SizedBox(height: 32),
              // Quick stats
              _buildQuickStats(),
              const SizedBox(height: 32),
              // Config info
              _buildConfigInfo(),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusCard() {
    return Obx(() {
      final isConnected = _connectionController.isConnected;
      final config = _connectionController.selectedConfig.value;
      final ip = _connectionController.connectedIP.value;

      return Card(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: isConnected ? Colors.green : Colors.grey,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _connectionController.getStateLabel(),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (config != null)
                Text(
                  'Connected to: ${config.displayName}',
                  style: const TextStyle(fontSize: 14),
                )
              else
                const Text(
                  'Not connected',
                  style: TextStyle(fontSize: 14),
                ),
              if (ip != null) ...[
                const SizedBox(height: 8),
                Text(
                  'IP: $ip',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
              const SizedBox(height: 8),
              Text(
                _connectionController.statusMessage.value,
                style: const TextStyle(
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                  color: Colors.grey,
                ),
              ),
            ],
          ),
        ),
      );
    });
  }

  Widget _buildConnectButton() {
    return Obx(() {
      final isConnected = _connectionController.isConnected;
      final isConnecting = _connectionController.state.value ==
          ConnectionState.connecting;

      return Center(
        child: GestureDetector(
          onTap: isConnecting ? null : _handleConnectDisconnect,
          child: Container(
            width: 160,
            height: 160,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: isConnected
                    ? [Colors.green.shade400, Colors.green.shade600]
                    : [Colors.indigo.shade400, Colors.indigo.shade600],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: (isConnected ? Colors.green : Colors.indigo)
                      .withOpacity(0.3),
                  blurRadius: 24,
                  spreadRadius: 4,
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: isConnecting ? null : _handleConnectDisconnect,
                customBorder: const CircleBorder(),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (isConnecting)
                        const SizedBox(
                          width: 40,
                          height: 40,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      else
                        Icon(
                          isConnected ? Icons.vpn_lock : Icons.lock_open,
                          size: 56,
                          color: Colors.white,
                        ),
                      const SizedBox(height: 8),
                      Text(
                        isConnected ? 'CONNECTED' : 'CONNECT',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    });
  }

  Widget _buildQuickStats() {
    return Obx(() {
      final result = _connectionController.selectedConfigResult.value;
      final stats = _configController.getStats();

      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: GridView.count(
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            _buildStatCard(
              'Speed',
              result?.speedMbps != null
                  ? '${result!.speedMbps!.toStringAsFixed(1)} Mbps'
                  : 'Not tested',
              Icons.speed,
            ),
            _buildStatCard(
              'Total Configs',
              '${stats['total']}',
              Icons.settings,
            ),
            _buildStatCard(
              'Working',
              '${stats['working']}',
              Icons.check_circle,
            ),
            _buildStatCard(
              'Reliability',
              '${(stats['average_reliability'] as double).toStringAsFixed(0)}%',
              Icons.trending_up,
            ),
          ],
        ),
      );
    });
  }

  Widget _buildStatCard(String label, String value, IconData icon) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 28, color: Colors.indigo),
            const SizedBox(height: 8),
            Text(
              value,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConfigInfo() {
    return Obx(() {
      final configs = _configController.allConfigs;

      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Configuration Info',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Loaded: ${configs.length} configs',
                  style: const TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _configController.isLoading.value
                            ? null
                            : () async {
                              await _configController.fetchFromAllSources();
                            },
                        icon: const Icon(Icons.refresh, size: 16),
                        label: const Text('Refresh'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _configController.isLoading.value
                            ? null
                            : () async {
                              await _configController.testAllConfigs();
                            },
                        icon: const Icon(Icons.speed, size: 16),
                        label: const Text('Test All'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    });
  }
}
