/// Connection controller using GetX for state management.
/// Orchestrates config selection, VPN connection, and status updates.
/// Replicates CLI's ConnectionService state machine pattern.

import 'dart:async';
import 'package:get/get.dart';
import 'package:logger/logger.dart';
import '../models/config.dart';
import '../models/test_result.dart';
import '../services/vpn_service.dart';
import '../services/tester_service.dart';
import '../services/kill_switch_service.dart';
import '../services/dns_leak_prevention_service.dart';
import '../services/split_tunneling_service.dart';
import '../services/debug_service.dart';

enum ConnectionState {
  idle,
  selecting,
  connecting,
  connected,
  testing,
  disconnecting,
  error,
}

class ConnectionController extends GetxController {
  final VPNService vpnService;
  final TesterService testerService;
  final KillSwitchService killSwitchService;
  final DNSLeakPreventionService dnsLeakPreventionService;
  final SplitTunnelingService splitTunnelingService;
  final DebugService debugService;
  final Logger _log;

  // Observable state
  final Rx<ConnectionState> state = ConnectionState.idle.obs;
  final Rx<Config?> selectedConfig = Rx<Config?>(null);
  final Rx<TestResult?> selectedConfigResult = Rx<TestResult?>(null);
  final RxString statusMessage = RxString('Ready');
  final Rxn<String> connectedIP = Rxn<String>();
  final RxDouble connectionUptime = RxDouble(0.0); // seconds
  final RxBool isKillSwitchEnabled = RxBool(false);
  final RxBool isDNSLeakPreventionEnabled = RxBool(false);
  final RxBool isSplitTunnelingEnabled = RxBool(false);

  bool get isConnected => state.value == ConnectionState.connected;

  DateTime? _connectionStartTime;
  int? _uptimeUpdateTimer;

  ConnectionController({
    required this.vpnService,
    required this.testerService,
    required this.killSwitchService,
    required this.dnsLeakPreventionService,
    required this.splitTunnelingService,
    required this.debugService,
    Logger? logger,
  }) : _log = logger ?? Logger();

  @override
  void onInit() {
    super.onInit();
    _log.i('ConnectionController initialized');
  }

  /// Connect with fastest available config
  /// If no result provided, will test all configs first
  Future<bool> connectFastest(
    List<Config> availableConfigs, {
    List<TestResult>? testResults,
  }) async {
    try {
      state.value = ConnectionState.selecting;
      statusMessage.value = 'Finding fastest config...';

      final results = testResults ?? await testerService.testConfigs(availableConfigs);
      final fastest = testerService.getFastestConfig(results);

      if (fastest == null) {
        state.value = ConnectionState.error;
        statusMessage.value = 'No working configs found';
        return false;
      }

      // Find the config object matching this result
      final config = availableConfigs.firstWhereOrNull(
        (c) => c.getHash() == fastest.configHash,
      );

      if (config == null) {
        state.value = ConnectionState.error;
        statusMessage.value = 'Config not found';
        return false;
      }

      return await connect(config, testResult: fastest);
    } catch (e) {
      state.value = ConnectionState.error;
      statusMessage.value = 'Error: $e';
      _log.e('Error connecting to fastest: $e');
      return false;
    }
  }

  /// Connect to specific config
  Future<bool> connect(
    Config config, {
    TestResult? testResult,
  }) async {
    try {
      if (!config.validate()) {
        state.value = ConnectionState.error;
        statusMessage.value = 'Invalid config';
        return false;
      }

      state.value = ConnectionState.connecting;
      statusMessage.value = 'Connecting to ${config.displayName}...';
      selectedConfig.value = config;
      selectedConfigResult.value = testResult;

      _log.i('Connecting to ${config.displayName}');

      // Android shows a system consent dialog before the first tunnel.
      final prepared = await vpnService.prepare();
      if (!prepared) {
        state.value = ConnectionState.error;
        statusMessage.value = vpnService.lastError ?? 'VPN permission was denied';
        return false;
      }

      final success = await vpnService.connect(config);

      if (success) {
        state.value = ConnectionState.connected;
        statusMessage.value = 'Connected to ${config.displayName}';
        _connectionStartTime = DateTime.now();
        _startUptimeCounter();
        _fetchConnectedIP();

        debugService.logInfo('VPN connected to ${config.displayName}');

        // Activate kill switch if enabled
        if (isKillSwitchEnabled.value) {
          try {
            await killSwitchService.activate();
            debugService.logInfo('Kill switch activated');
          } catch (e) {
            _log.w('Kill switch activation failed: $e');
            debugService.logWarning('Kill switch activation failed: $e');
          }
        }

        // Activate DNS leak prevention if enabled
        if (isDNSLeakPreventionEnabled.value) {
          try {
            await dnsLeakPreventionService.activate();
            debugService.logInfo('DNS leak prevention activated');
          } catch (e) {
            _log.w('DNS leak prevention activation failed: $e');
            debugService.logWarning('DNS leak prevention activation failed: $e');
          }
        }

        // Activate split tunneling if enabled
        if (isSplitTunnelingEnabled.value) {
          try {
            await splitTunnelingService.activate();
            debugService.logInfo('Split tunneling activated');
          } catch (e) {
            _log.w('Split tunneling activation failed: $e');
            debugService.logWarning('Split tunneling activation failed: $e');
          }
        }

        return true;
      } else {
        state.value = ConnectionState.error;
        statusMessage.value = 'Failed to connect';
        return false;
      }
    } catch (e) {
      state.value = ConnectionState.error;
      statusMessage.value = 'Connection error: $e';
      _log.e('Error connecting: $e');
      return false;
    }
  }

  /// Disconnect from VPN
  Future<bool> disconnect() async {
    try {
      state.value = ConnectionState.disconnecting;
      statusMessage.value = 'Disconnecting...';

      _stopUptimeCounter();

      // Deactivate security features before disconnecting
      try {
        if (killSwitchService.isActive.value) {
          await killSwitchService.deactivate();
          debugService.logInfo('Kill switch deactivated');
        }
        if (dnsLeakPreventionService.isActive.value) {
          await dnsLeakPreventionService.deactivate();
          debugService.logInfo('DNS leak prevention deactivated');
        }
        if (splitTunnelingService.isActive.value) {
          await splitTunnelingService.deactivate();
          debugService.logInfo('Split tunneling deactivated');
        }
      } catch (e) {
        _log.w('Security feature deactivation failed: $e');
        debugService.logWarning('Security feature deactivation failed: $e');
      }

      final success = await vpnService.disconnect();

      if (success) {
        state.value = ConnectionState.idle;
        statusMessage.value = 'Disconnected';
        selectedConfig.value = null;
        selectedConfigResult.value = null;
        connectedIP.value = null;
        connectionUptime.value = 0;
        _connectionStartTime = null;
        debugService.logInfo('VPN disconnected');
        return true;
      } else {
        state.value = ConnectionState.error;
        statusMessage.value = 'Failed to disconnect';
        return false;
      }
    } catch (e) {
      state.value = ConnectionState.error;
      statusMessage.value = 'Disconnect error: $e';
      _log.e('Error disconnecting: $e');
      return false;
    }
  }

  /// Reconnect to current config
  Future<bool> reconnect() async {
    if (selectedConfig.value == null) {
      _log.w('No config to reconnect to');
      return false;
    }

    final success = await disconnect();
    if (success) {
      await Future.delayed(const Duration(milliseconds: 500));
      return await connect(selectedConfig.value!);
    }
    return false;
  }

  /// Test current connection
  Future<bool> testConnection() async {
    if (selectedConfig.value == null) {
      _log.w('No active connection to test');
      return false;
    }

    try {
      state.value = ConnectionState.testing;
      statusMessage.value = 'Testing connection...';

      final result = await testerService.testConfig(selectedConfig.value!);
      selectedConfigResult.value = result;

      if (result.isWorking) {
        state.value = ConnectionState.connected;
        statusMessage.value =
          'Connected (${result.speedMbps?.toStringAsFixed(1)}Mbps)';
        return true;
      } else {
        state.value = ConnectionState.error;
        statusMessage.value = 'Connection test failed';
        return false;
      }
    } catch (e) {
      state.value = ConnectionState.error;
      statusMessage.value = 'Test error: $e';
      return false;
    }
  }

  /// Toggle DNS leak prevention on/off
  Future<bool> toggleDNSLeakPrevention() async {
    try {
      if (isDNSLeakPreventionEnabled.value) {
        // Disable DNS leak prevention
        final success = await dnsLeakPreventionService.disable();
        if (success) {
          isDNSLeakPreventionEnabled.value = false;
          _log.i('DNS leak prevention disabled');
          debugService.logInfo('DNS leak prevention disabled');
          return true;
        }
      } else {
        // Enable DNS leak prevention
        final success = await dnsLeakPreventionService.enable();
        if (success) {
          isDNSLeakPreventionEnabled.value = true;
          _log.i('DNS leak prevention enabled');
          debugService.logInfo('DNS leak prevention enabled');

          // If currently connected, activate immediately
          if (state.value == ConnectionState.connected) {
            try {
              await dnsLeakPreventionService.activate();
              debugService.logInfo('DNS leak prevention activated immediately');
            } catch (e) {
              _log.w('DNS leak prevention activation failed: $e');
              debugService.logWarning('DNS leak prevention activation failed: $e');
            }
          }
          return true;
        }
      }
      return false;
    } catch (e) {
      _log.e('Error toggling DNS leak prevention: $e');
      debugService.logError('Error toggling DNS leak prevention: $e');
      return false;
    }
  }

  /// Toggle kill switch on/off
  Future<bool> toggleKillSwitch() async {
    try {
      if (isKillSwitchEnabled.value) {
        // Disable kill switch
        final success = await killSwitchService.disable();
        if (success) {
          isKillSwitchEnabled.value = false;
          _log.i('Kill switch disabled');
          debugService.logInfo('Kill switch disabled');
          return true;
        }
      } else {
        // Enable kill switch
        final success = await killSwitchService.enable();
        if (success) {
          isKillSwitchEnabled.value = true;
          _log.i('Kill switch enabled');
          debugService.logInfo('Kill switch enabled');

          // If currently connected, activate immediately
          if (state.value == ConnectionState.connected) {
            try {
              await killSwitchService.activate();
              debugService.logInfo('Kill switch activated immediately');
            } catch (e) {
              _log.w('Kill switch activation failed: $e');
              debugService.logWarning('Kill switch activation failed: $e');
            }
          }
          return true;
        }
      }
      return false;
    } catch (e) {
      _log.e('Error toggling kill switch: $e');
      debugService.logError('Error toggling kill switch: $e');
      return false;
    }
  }

  /// Toggle split tunneling on/off
  Future<bool> toggleSplitTunneling() async {
    try {
      if (isSplitTunnelingEnabled.value) {
        // Disable split tunneling
        final success = await splitTunnelingService.disable();
        if (success) {
          isSplitTunnelingEnabled.value = false;
          _log.i('Split tunneling disabled');
          debugService.logInfo('Split tunneling disabled');
          return true;
        }
      } else {
        // Enable split tunneling
        final success = await splitTunnelingService.enable();
        if (success) {
          isSplitTunnelingEnabled.value = true;
          _log.i('Split tunneling enabled');
          debugService.logInfo('Split tunneling enabled');

          // If currently connected, activate immediately
          if (state.value == ConnectionState.connected) {
            try {
              await splitTunnelingService.activate();
              debugService.logInfo('Split tunneling activated immediately');
            } catch (e) {
              _log.w('Split tunneling activation failed: $e');
              debugService.logWarning('Split tunneling activation failed: $e');
            }
          }
          return true;
        }
      }
      return false;
    } catch (e) {
      _log.e('Error toggling split tunneling: $e');
      debugService.logError('Error toggling split tunneling: $e');
      return false;
    }
  }

  /// Get human-readable state
  String getStateLabel() {
    switch (state.value) {
      case ConnectionState.idle:
        return 'Not Connected';
      case ConnectionState.selecting:
        return 'Selecting...';
      case ConnectionState.connecting:
        return 'Connecting...';
      case ConnectionState.connected:
        return 'Connected';
      case ConnectionState.testing:
        return 'Testing...';
      case ConnectionState.disconnecting:
        return 'Disconnecting...';
      case ConnectionState.error:
        return 'Error';
    }
  }

  void _startUptimeCounter() {
    _uptimeUpdateTimer = null;
    // In production, use Timer for real uptime tracking
    // For now, update every second in UI rebuild
  }

  void _stopUptimeCounter() {
    _uptimeUpdateTimer = null;
    connectionUptime.value = 0;
  }

  Future<void> _fetchConnectedIP() async {
    try {
      final ip = await vpnService.getConnectedIP();
      connectedIP.value = ip;
    } catch (e) {
      _log.e('Error fetching connected IP: $e');
    }
  }

  @override
  void onClose() {
    _stopUptimeCounter();
    debugService.logInfo('ConnectionController closing');
    unawaited(killSwitchService.cleanup());
    unawaited(dnsLeakPreventionService.cleanup());
    unawaited(splitTunnelingService.cleanup());
    super.onClose();
  }
}
