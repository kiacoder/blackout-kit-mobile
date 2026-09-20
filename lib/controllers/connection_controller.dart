/// Connection controller using GetX for state management.
/// Orchestrates config selection, VPN connection, and status updates.
/// Replicates CLI's ConnectionService state machine pattern.

import 'dart:async';
import 'package:get/get.dart';
import 'package:logger/logger.dart';
import '../models/config.dart';
import '../models/test_result.dart';
import '../models/vpn_session_options.dart';
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
  Timer? _uptimeTimer;

  /// Cached native capability report. Engine support is fixed for the lifetime
  /// of the process, so probing once is enough.
  EngineAvailability? _engineAvailability;

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

      // Drop anything no bundled engine can serve, otherwise "fastest" can
      // select a config that connect() is then obliged to refuse.
      final candidates = await _servableConfigs(availableConfigs);
      if (candidates.isEmpty) {
        state.value = ConnectionState.error;
        statusMessage.value = availableConfigs.isEmpty
            ? 'No configs available'
            : 'None of your configs use a protocol this build can serve';
        return false;
      }

      final candidateHashes = candidates.map((c) => c.getHash()).toSet();
      final results = (testResults ?? await testerService.testConfigs(candidates))
          .where((r) => candidateHashes.contains(r.configHash))
          .toList();
      final fastest = testerService.getFastestConfig(results);

      if (fastest == null) {
        state.value = ConnectionState.error;
        statusMessage.value = 'No working configs found';
        return false;
      }

      // Find the config object matching this result
      final config = candidates.firstWhereOrNull(
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

      // Refuse before the consent dialog: there is no point asking the user to
      // grant VPN permission for a protocol no bundled runtime can serve.
      final refusal = await _engineRefusal(config);
      if (refusal != null) {
        state.value = ConnectionState.error;
        statusMessage.value = refusal;
        debugService.logError('Connect refused for ${config.protocol}: $refusal');
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

      // Split tunneling, DNS and the kill switch are all inputs to
      // Builder.establish(), so they have to be assembled *before* connecting.
      // The old code activated them afterwards through channels that had no
      // native handler, so none of them ever took effect.
      final options = buildSessionOptions();
      final optionProblem = options.validationError;
      if (optionProblem != null) {
        state.value = ConnectionState.error;
        statusMessage.value = optionProblem;
        debugService.logError('Session options rejected: $optionProblem');
        return false;
      }

      final success = await vpnService.connect(config, options: options);

      if (success) {
        state.value = ConnectionState.connected;
        statusMessage.value = 'Connected to ${config.displayName}';
        _connectionStartTime = DateTime.now();
        _startUptimeCounter();
        _fetchConnectedIP();

        debugService.logInfo(
          'VPN connected to ${config.displayName} - '
          'split tunneling: ${splitTunnelingService.describe()}, '
          'DNS: ${dnsLeakPreventionService.describe()}, '
          'kill switch: ${killSwitchService.describe()}',
        );

        // The live tunnel now carries the current selection.
        splitTunnelingService.clearStaleFlag();

        if (killSwitchService.needsUserAction) {
          debugService.logWarning(
            'Kill switch is on, but full protection needs this app set as '
            'always-on VPN with "Block connections without VPN" enabled.',
          );
        }

        return true;
      } else {
        state.value = ConnectionState.error;
        statusMessage.value = vpnService.lastError ?? 'Failed to connect';
        return false;
      }
    } catch (e) {
      state.value = ConnectionState.error;
      statusMessage.value = 'Connection error: $e';
      _log.e('Error connecting: $e');
      return false;
    }
  }

  /// Drops configs whose protocol no bundled engine can serve.
  ///
  /// Fails open: if the capability probe errors, every config is returned and
  /// the per-connect check in [connect] still guards the actual attempt.
  Future<List<Config>> _servableConfigs(List<Config> configs) async {
    try {
      _engineAvailability ??= await vpnService.getEngineInfo();
    } catch (e) {
      _log.w('Engine capability probe failed, testing all configs: $e');
      return configs;
    }

    final availability = _engineAvailability!;
    if (!availability.isKnown) return configs;

    final servable =
        configs.where((c) => availability.canConnect(c.protocol)).toList();
    final skipped = configs.length - servable.length;
    if (skipped > 0) {
      _log.i('Skipped $skipped config(s) with no bundled engine');
    }
    return servable;
  }

  /// Returns a human-readable refusal when no bundled engine can serve
  /// [config]'s protocol, or null when the attempt should go ahead.
  ///
  /// Fails open on purpose: if the capability probe itself errors we return
  /// null and let the native layer produce the real diagnostic, rather than
  /// blocking a connection that might have worked.
  Future<String?> _engineRefusal(Config config) async {
    try {
      _engineAvailability ??= await vpnService.getEngineInfo();
    } catch (e) {
      _log.w('Engine capability probe failed, continuing: $e');
      return null;
    }

    final availability = _engineAvailability!;
    if (!availability.isKnown) return null;
    if (availability.canConnect(config.protocol)) return null;

    final supported = availability.supportedProtocols;
    final supportedLabel =
        supported.isEmpty ? 'none' : supported.map((p) => p.toUpperCase()).join(', ');
    return "'${config.protocol}' cannot be dialled by this build: no engine that "
        'serves it is bundled. Supported here: $supportedLabel.';
  }

  /// Disconnect from VPN
  Future<bool> disconnect() async {
    try {
      state.value = ConnectionState.disconnecting;
      statusMessage.value = 'Disconnecting...';

      _stopUptimeCounter();

      // Nothing to unwind here: split tunneling, DNS and the kill switch all
      // live inside the tunnel itself, so closing the interface releases them.
      // The previous code called deactivate() on three channels that had no
      // native handler.

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
        // Report the real measured figure. Throughput is not measured by the
        // tester, so the previous "Connected (43.2Mbps)" was fabricated.
        statusMessage.value = result.latencyMs != null
            ? 'Connected (${result.latencyMs}ms to the server)'
            : 'Connected';
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

  /// Toggle DNS leak prevention on/off.
  ///
  /// Takes effect on the next connect: the tunnel's DNS servers are fixed at
  /// establish() time and cannot be changed on a live interface.
  Future<bool> toggleDNSLeakPrevention() async {
    try {
      final next = !isDNSLeakPreventionEnabled.value;
      await dnsLeakPreventionService.setEnabled(next);
      isDNSLeakPreventionEnabled.value = next;

      final problem = dnsLeakPreventionService.lastError.value;
      if (problem != null) {
        statusMessage.value = problem;
        return false;
      }

      debugService.logInfo('DNS leak prevention: ${dnsLeakPreventionService.describe()}');
      if (next && isConnected) {
        statusMessage.value = 'DNS leak prevention applies after reconnecting';
      }
      return true;
    } catch (e) {
      _log.e('Error toggling DNS leak prevention: $e');
      debugService.logError('Error toggling DNS leak prevention: $e');
      return false;
    }
  }

  /// Toggle kill switch on/off.
  ///
  /// The in-app half (holding the tunnel open when the engine dies) applies on
  /// the next connect. The system half needs the user to enable always-on VPN
  /// with lockdown; [KillSwitchService.needsUserAction] reports whether they
  /// still have to.
  Future<bool> toggleKillSwitch() async {
    try {
      final next = !isKillSwitchEnabled.value;
      await killSwitchService.setEnabled(next);
      isKillSwitchEnabled.value = next;

      debugService.logInfo('Kill switch: ${killSwitchService.describe()}');
      if (next && killSwitchService.needsUserAction) {
        statusMessage.value =
            'For full protection, set this app as always-on VPN and enable '
            '"Block connections without VPN" in system settings';
      }
      return true;
    } catch (e) {
      _log.e('Error toggling kill switch: $e');
      debugService.logError('Error toggling kill switch: $e');
      return false;
    }
  }

  /// Toggle split tunneling on/off.
  ///
  /// Android freezes the per-app list into the tunnel at establish(), so a
  /// change while connected only takes effect after reconnecting.
  Future<bool> toggleSplitTunneling() async {
    try {
      final next = !isSplitTunnelingEnabled.value;
      await splitTunnelingService.setEnabled(next);
      isSplitTunnelingEnabled.value = next;

      debugService.logInfo('Split tunneling: ${splitTunnelingService.describe()}');
      if (next && isConnected) {
        statusMessage.value = 'Split tunneling applies after reconnecting';
      }
      return true;
    } catch (e) {
      _log.e('Error toggling split tunneling: $e');
      debugService.logError('Error toggling split tunneling: $e');
      return false;
    }
  }

  /// Translation key for the current state, e.g. `'connected'`.
  ///
  /// Returns a key rather than English text so this controller stays free of
  /// presentation concerns. The UI resolves it with `'key'.tr`; the tables live
  /// in `LocalizationService`. The previous `getStateLabel()` hardcoded English
  /// here, which is why the status card stayed English in every language.
  String getStateLabelKey() {
    switch (state.value) {
      case ConnectionState.idle:
        return 'not_connected';
      case ConnectionState.selecting:
        return 'selecting';
      case ConnectionState.connecting:
        return 'connecting';
      case ConnectionState.connected:
        return 'connected';
      case ConnectionState.testing:
        return 'testing';
      case ConnectionState.disconnecting:
        return 'disconnecting';
      case ConnectionState.error:
        return 'error';
    }
  }

  /// Assembles the builder-time options from the three feature services.
  ///
  /// Order matters only in that split tunneling and DNS each own a distinct
  /// field; the kill switch owns a third. None of them clobber the others.
  VpnSessionOptions buildSessionOptions([Config? config]) {
    var options = VpnSessionOptions(
      dnsServers: config == null
          ? const ['1.1.1.1']
          : VPNService.dnsServersForConfig(config),
    );
    options = splitTunnelingService.applyTo(options);
    options = dnsLeakPreventionService.applyTo(options);
    options = killSwitchService.applyTo(options);
    return options;
  }

  void _startUptimeCounter() {
    _uptimeTimer?.cancel();
    _uptimeTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final start = _connectionStartTime;
      if (start == null) return;
      connectionUptime.value =
          DateTime.now().difference(start).inMilliseconds / 1000.0;
    });
  }

  void _stopUptimeCounter() {
    _uptimeTimer?.cancel();
    _uptimeTimer = null;
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
    super.onClose();
  }
}
