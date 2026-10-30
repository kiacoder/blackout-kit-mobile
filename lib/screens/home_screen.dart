/// Home screen - Main UI for Blackout Kit VPN app
/// Features:
/// - Big connect/disconnect button (one-tap VPN)
/// - Real-time connection status and IP
/// - Quick stats (latency, reliability, uptime)
/// - Quick access to Library and Settings

import 'package:flutter/material.dart' hide ConnectionState;
import 'package:get/get.dart';

import '../controllers/config_controller.dart';
import 'guide_screen.dart';
import '../controllers/settings_controller.dart';
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
  late final SettingsController _settingsController;

  @override
  void initState() {
    super.initState();
    _configController = Get.find<ConfigController>();
    _connectionController = Get.find<ConnectionController>();
    _settingsController = Get.find<SettingsController>();

    // Do NOT fetch and probe the whole library on every launch.
    _initializeApp();
  }

  /// First-run setup only.
  ///
  /// This used to run `fetchFromAllSources()` followed by `testAllConfigs()`
  /// on EVERY cold start and every return to this tab: with a few thousand
  /// configs that is a full refresh plus a 150-server probe before the user
  /// has touched anything - data, battery, and a slow first frame. The
  /// library is already persisted, so there is nothing to fetch unless it is
  /// empty; probing is something the user asks for (Scan) or that happens
  /// when they connect.
  Future<void> _initializeApp() async {
    if (_configController.allConfigs.isNotEmpty) return;
    await _configController.fetchFromAllSources();
  }

  Future<void> _handleConnectDisconnect() async {
    if (_connectionController.isConnected) {
      await _connectionController.disconnect();
      return;
    }

    // A scan in progress: this tap means "stop", not "start another one".
    // The button used to be disabled only while connecting, so during a
    // minutes-long scan a tap did nothing at all.
    if (_connectionController.operationInFlight) {
      _connectionController.cancelScan();
      return;
    }

    // "Change DNS only": no config, no server, no routes. This is the whole
    // point of the mode - someone who only wants a different resolver must not
    // be told to go find a config first.
    if (_settingsController.dnsOnlyMode.value) {
      final ok = await _connectionController.connectDnsOnly();
      if (!ok) {
        _showSnackbar(_connectionController.statusMessage.value, Colors.red);
      }
      return;
    }

    // Get available configs (only from enabled sources)
    final configs = _configController.visibleConfigs;
    if (configs.isEmpty) {
      _showSnackbar('No configs available'.tr, Colors.orange);
      return;
    }

    // Hand over every measurement the library already has. The previous code
    // passed the connection controller's single cached result, or an empty list
    // on a cold start — and an empty (non-null) list short-circuits the tester
    // inside connectFastest, so the very first tap on Connect always failed
    // with "No working configs found" without testing a single config.
    final results = _configController.testResults.values.toList();

    final success = await _connectionController.connectFastest(
      configs,
      testResults: results.isEmpty ? null : results,
    );

    if (!success) {
      // Surface the real reason (e.g. "no bundled engine for this protocol")
      // instead of a generic failure string.
      _showSnackbar(_connectionController.statusMessage.value, Colors.red);
    }
  }

  void _showSnackbar(String message, Color color) {
    Get.snackbar(
      'Blackout Kit'.tr,
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
        actions: [
          // The guide is one tap from the first screen on purpose: a new user
          // who does not know what a "config" is will not go looking in
          // Settings for help.
          IconButton(
            icon: const Icon(Icons.help_outline),
            tooltip: 'guide'.tr,
            onPressed: () => Get.to(() => const GuideScreen()),
          ),
        ],
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
                    _connectionController.getStateLabelKey().tr,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // A DNS-only session has no config, so this row used to read
              // "Not connected" under a button that said connected.
              if (_connectionController.isDnsOnly.value)
                Text(
                  'dns_only_connected'.tr,
                  style: const TextStyle(fontSize: 14),
                )
              else if (config != null)
                Text(
                  '${'connected_to'.tr}: ${config.displayName}',
                  style: const TextStyle(fontSize: 14),
                )
              else
                Text(
                  'not_connected'.tr,
                  style: const TextStyle(fontSize: 14),
                ),
              if (ip != null) ...[
                const SizedBox(height: 8),
                Text(
                  'IP: $ip',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
              if (config != null) ...[
                const SizedBox(height: 8),
                _buildIpIdentityRow(),
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

  /// Before / now identity card: the address and place the user had before
  /// the tunnel, and the exit address + location fetched through it. Rows
  /// hide themselves when their lookup has not resolved — showing nothing is
  /// more honest than showing the wrong place.
  Widget _buildIpIdentityRow() {
    final home = _connectionController.homeIpInfo.value;
    final exit = _connectionController.exitIpInfo.value;

    final homeLabel = (home == null || home.isEmpty)
        ? null
        : '${home.ip} — ${home.placeLabel.isEmpty ? 'location unknown'.tr : home.placeLabel}'.tr;
    final exitLabel = (exit == null || exit.isEmpty)
        ? null
        : '${exit.ip} — ${exit.placeLabel.isEmpty ? 'location unknown'.tr : exit.placeLabel}'.tr;

    TextStyle rowStyle(bool accent) => TextStyle(
          fontSize: 12,
          color: accent ? Colors.lightBlueAccent : Colors.grey,
        );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.grey.withAlpha(26),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.home_outlined,
                  size: 14, color: Colors.grey),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  homeLabel ?? 'Your real IP: unavailable'.tr,
                  style: rowStyle(false),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(Icons.shield_outlined,
                  size: 14, color: Colors.lightBlueAccent),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  exitLabel ?? 'Exit location: resolving…'.tr,
                  style: rowStyle(true),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildConnectButton() {    return Obx(() {
      final isConnected = _connectionController.isConnected;
      final isConnecting = _connectionController.state.value ==
          ConnectionState.connecting;
      // During a scan the button is live again, as a Cancel action.
      final isScanning = _connectionController.state.value ==
              ConnectionState.selecting ||
          _connectionController.state.value == ConnectionState.testing;

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
                        // During a scan the same button stops it, so say so.
                        (isScanning
                                ? 'cancel'
                                : (isConnected ? 'connected' : 'connect'))
                            .tr
                            .toUpperCase(),
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
              // Throughput is never measured (the tester only opens a socket),
              // so a "Speed" card could only ever read "Not tested" forever.
              // Latency is the figure that is actually measured.
              'Latency',
              result?.latencyMs != null ? '${result!.latencyMs} ms' : 'Not tested'.tr,
              Icons.speed,
            ),
            _buildStatCard(
              'Configs (visible/stored)'.tr,
              '${stats['total']}/${stats['stored']}',
              Icons.settings,
            ),
            _buildStatCard(
              'Working',
              '${stats['working']}',
              Icons.check_circle,
            ),
            _buildStatCard(
              'Reliability',
              '${(stats['average_reliability'] as double).toStringAsFixed(0)}%'.tr,
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
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Configuration Info'.tr,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Visible: ${_configController.visibleConfigs.length} configs '
                  '(stored: ${_configController.allConfigs.length}) — '
                  'disabled sources stay saved but are hidden and untested'.tr,
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
                        label: Text('refresh'.tr),
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
                        label: Text('test_all'.tr),
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
