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
import '../models/config.dart';
import '../services/localization_service.dart';
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

  Future<void> _handleConnectSpecific(Config config) async {
    final result = _configController.testResults[config.getHash()];
    final ok = await _connectionController.connect(config, testResult: result);
    if (!ok)
      _showSnackbar(_connectionController.statusMessage.value, Colors.red);
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
        title: const AppLogo(
            size: 28, showSubtitle: false, direction: Axis.horizontal),
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
              const SizedBox(height: 16),
              _buildScanProgressCard(),
              const SizedBox(height: 16),
              // Big connect button
              _buildConnectButton(),
              Obx(() {
                final last = _connectionController.lastKnownWorkingConfig.value;
                if (last == null || _connectionController.isConnected) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                  child: OutlinedButton.icon(
                    onPressed: () => _handleConnectSpecific(last),
                    icon: const Icon(Icons.place_outlined),
                    label: Text('Reconnect to last working location'.tr),
                  ),
                );
              }),
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

  Widget _buildScanProgressCard() {
    return Obx(() {
      final phase = _connectionController.scanPhase.value;
      final inProgress = _connectionController.operationInFlight;
      final recovery = _connectionController.recoveryAvailable.value;
      final candidateError = _connectionController.candidateError.value;
      final candidateFailed =
          _connectionController.candidateAttemptFailed.value && !recovery;
      if (phase == 'idle' && !recovery && candidateError.isEmpty) {
        return const SizedBox.shrink();
      }

      final theme = Theme.of(context);
      final accent =
          recovery ? theme.colorScheme.error : theme.colorScheme.primary;
      final total = _connectionController.scanItemsTotal.value;
      final done = _connectionController.scanItemsDone.value;
      final progress = total == 0 ? null : (done / total).clamp(0.0, 1.0);
      final phaseLabel = switch (phase) {
        'ping' => 'Checking server reachability'.tr,
        'connect' => 'Establishing secure tunnel'.tr,
        'websites' => 'Testing your websites'.tr,
        'connected' => 'Connection verified'.tr,
        'recovery' => 'Connection needs attention'.tr,
        'failed' => 'No verified config found'.tr,
        _ => _connectionController.statusMessage.value,
      };

      return Card(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 420),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: LinearGradient(
              colors: [accent.withOpacity(0.12), theme.cardColor],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 350),
                transitionBuilder: (child, animation) => ScaleTransition(
                  scale: CurvedAnimation(
                      parent: animation, curve: Curves.easeOutBack),
                  child: FadeTransition(opacity: animation, child: child),
                ),
                child: Icon(
                  switch (phase) {
                    'ping' => Icons.radar,
                    'connect' => Icons.lock_clock,
                    'websites' => Icons.public,
                    'connected' => Icons.verified,
                    'recovery' => Icons.sync_problem,
                    'failed' => Icons.warning_amber_rounded,
                    _ => Icons.bolt,
                  },
                  key: ValueKey(phase),
                  color: accent,
                  size: 26,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(phaseLabel,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    if (recovery &&
                        _connectionController.lastKnownWorkingConfig.value !=
                            null)
                      Text(
                          _connectionController
                              .lastKnownWorkingConfig.value!.displayName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall),
                    if (candidateFailed &&
                        _connectionController.candidateError.value.isNotEmpty)
                      Text(_connectionController.candidateError.value,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.error,
                          )),
                    if (!recovery &&
                        !candidateFailed &&
                        _connectionController
                            .scanCurrentConfig.value.isNotEmpty)
                      Text(_connectionController.scanCurrentConfig.value,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall),
                  ])),
              if (inProgress)
                SizedBox(
                  width: 30,
                  height: 30,
                  child: CircularProgressIndicator(
                    value: progress,
                    strokeWidth: 3,
                    backgroundColor: accent.withOpacity(0.16),
                    color: accent,
                  ),
                ),
            ]),
            if (phase == 'ping' ||
                phase == 'connect' ||
                phase == 'websites') ...[
              const SizedBox(height: 14),
              Row(children: [
                for (final entry in const [
                  ('ping', Icons.radar),
                  ('connect', Icons.lock),
                  ('websites', Icons.public),
                ]) ...[
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    width: 36,
                    height: 5,
                    decoration: BoxDecoration(
                      color: _phaseIndex(phase) >= _phaseIndex(entry.$1)
                          ? accent
                          : theme.disabledColor.withOpacity(0.25),
                      borderRadius: BorderRadius.circular(9),
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                const Spacer(),
                if (total > 0)
                  Text('$done / $total', style: theme.textTheme.labelSmall),
                if (phase == 'websites') ...[
                  const SizedBox(width: 8),
                  Text(
                      '${_connectionController.scanSitesDone.value}/${_connectionController.scanSitesTotal.value} sites',
                      style: theme.textTheme.labelSmall),
                ],
              ]),
              if (total > 0) ...[
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: progress ?? 0),
                    duration: const Duration(milliseconds: 500),
                    builder: (context, value, _) => LinearProgressIndicator(
                      value: value,
                      minHeight: 5,
                      color: accent,
                      backgroundColor: accent.withOpacity(0.12),
                    ),
                  ),
                ),
              ],
            ],
            if (candidateError.isNotEmpty && !recovery) ...[
              const SizedBox(height: 10),
              Text(candidateError,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  )),
            ],
            if (recovery) ...[
              const SizedBox(height: 10),
              Text(_connectionController.recoveryReason.value,
                  style: theme.textTheme.bodySmall),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 6, children: [
                FilledButton.icon(
                  onPressed: () =>
                      _connectionController.resumeScanAfterFailure(),
                  icon: const Icon(Icons.skip_next),
                  label: Text(
                      _settingsController.connectFailureScanPolicy.value ==
                              'restart'
                          ? 'Restart scan'.tr
                          : 'Continue next batch'.tr),
                ),
                OutlinedButton(
                  onPressed: _connectionController.dismissRecovery,
                  child: Text('Stay disconnected'.tr),
                ),
              ]),
            ],
            if (inProgress &&
                _connectionController.scanBatchCount.value > 0) ...[
              const SizedBox(height: 6),
              Text(
                  'Batch ${_connectionController.scanBatchIndex.value} of ${_connectionController.scanBatchCount.value}',
                  style: theme.textTheme.labelSmall),
            ],
          ]),
        ),
      );
    });
  }

  int _phaseIndex(String phase) => switch (phase) {
        'ping' => 0,
        'connect' => 1,
        'websites' => 2,
        _ => -1,
      };

  Widget _buildStatusCard() {
    return Obx(() {
      final recovery = _connectionController.recoveryAvailable.value;
      final candidateFailed =
          _connectionController.candidateAttemptFailed.value && !recovery;
      final isConnected = _connectionController.isConnected && !recovery;
      final candidate = _connectionController.candidateConfig.value;
      final config = recovery
          ? _connectionController.lastKnownWorkingConfig.value
          : (candidate ?? _connectionController.selectedConfig.value);
      final ip = _connectionController.connectedIP.value;

      return Card(
        key: const ValueKey('connection-status-card'),
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
                    recovery || candidateFailed
                        ? 'error'.tr
                        : _connectionController.getStateLabelKey().tr,
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
        : LocalizationService.t('@ip — @place', {
            'ip': home.ip,
            'place': home.placeLabel.isEmpty
                ? LocalizationService.t('location unknown')
                : home.placeLabel,
          });
    final exitLabel = (exit == null || exit.isEmpty)
        ? null
        : LocalizationService.t('@ip — @place', {
            'ip': exit.ip,
            'place': exit.placeLabel.isEmpty
                ? LocalizationService.t('location unknown')
                : exit.placeLabel,
          });

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
              const Icon(Icons.home_outlined, size: 14, color: Colors.grey),
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

  Widget _buildConnectButton() {
    return Obx(() {
      final isConnected = _connectionController.isConnected;
      final isConnecting =
          _connectionController.state.value == ConnectionState.connecting;
      // During a scan the button is live again, as a Cancel action.
      final isScanning =
          _connectionController.state.value == ConnectionState.selecting ||
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
      final reliability = LocalizationService.t('@percentage%', {
        'percentage':
            (stats['average_reliability'] as double).toStringAsFixed(0),
      });

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
              'latency'.tr,
              result?.latencyMs != null
                  ? '${result!.latencyMs} ms'
                  : 'Not tested'.tr,
              Icons.speed,
            ),
            _buildStatCard(
              'Configs (visible/stored)'.tr,
              '${stats['total']}/${stats['stored']}',
              Icons.settings,
            ),
            _buildStatCard(
              'working'.tr,
              '${stats['working']}',
              Icons.check_circle,
            ),
            _buildStatCard(
              'reliability'.tr,
              reliability,
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
                          '(stored: ${_configController.allConfigs.length}) — disabled sources stay saved but are hidden and untested'
                      .tr,
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
