/// Connection controller using GetX for state management.
/// Orchestrates config selection, VPN connection, and status updates.
/// Replicates CLI's ConnectionService state machine pattern.

import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:logger/logger.dart';
import 'config_controller.dart';
import 'settings_controller.dart';
import '../models/config.dart';
import '../models/test_result.dart';
import '../models/vpn_session_options.dart';
import '../services/vpn_service.dart';
import '../services/tester_service.dart';
import '../services/site_check_service.dart';
import '../services/ip_info_service.dart';
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

class ConnectionController extends GetxController with WidgetsBindingObserver {
  final VPNService vpnService;
  final TesterService testerService;
  final KillSwitchService killSwitchService;
  final DNSLeakPreventionService dnsLeakPreventionService;
  final SplitTunnelingService splitTunnelingService;
  final DebugService debugService;

  /// Optional site-check stage: verifies shortlisted candidates by fetching
  /// real websites through a headless core instance. Null (or a disabled
  /// service) degrades selection to pure TCP-latency ranking.
  final SiteCheckService? siteCheckService;

  /// Optional IP identity service: resolves the home (pre-tunnel) and exit
  /// addresses + locations shown on the home screen. Null keeps those rows
  /// hidden.
  final IpInfoService? ipInfoService;
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

  /// Batched full-scan: the candidate list is walked in groups of this size.
  /// Each batch is TCP-probed, its survivors site-checked and connect-verified
  /// in rank order, and only a fully exhausted batch advances to the next one.
  static const int _probeBatchSize = 50;

  /// How many of a batch's TCP-passing candidates get the (expensive)
  /// headless site check. The rest keep their TCP rank.
  static const int _siteCheckShortlistSize = 3;

  /// Per-batch connect-attempt budget. Each attempt is a full connect plus a
  /// live site fetch (~5-10 s), so 10 bounds a bad batch to a few minutes
  /// while still walking every survivor of a healthy one.
  static const int _maxConnectAttemptsPerBatch = 10;

  /// Pre-flight probe budget. The full TesterService defaults (3 attempts x
  /// 4s timeout at concurrency 6) mean 150 unreachable candidates take ~5
  /// minutes of "Finding fastest config..." — and behind censorship nearly
  /// every host IS unreachable, so almost all probes ran the full 12s. The
  /// pre-flight only needs ONE answer: does this server respond at all.
  static const int _probeAttempts = 1;
  static const Duration _probeTimeout = Duration(seconds: 3);
  static const int _probeConcurrency = 16;

  bool get isConnected => state.value == ConnectionState.connected;

  DateTime? _connectionStartTime;
  Timer? _uptimeTimer;

  /// Foreground-only liveness watchdog (see [_startLivenessWatchdog]).
  Timer? _livenessTimer;

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
    this.siteCheckService,
    this.ipInfoService,
    Logger? logger,
  }) : _log = logger ?? Logger();

  // IP identity shown on the home screen: what the address/location were
  // before the tunnel (direct lookup, cached) and what they are now
  // (fetched through the exit).
  final Rx<IpInfo?> homeIpInfo = Rx<IpInfo?>(null);
  final Rx<IpInfo?> exitIpInfo = Rx<IpInfo?>(null);

  @override
  void onInit() {
    super.onInit();
    _log.i('ConnectionController initialized');
    _initIpInfo();
    // Android may kill the Flutter process while the foreground VpnService
    // keeps the tunnel up. On a fresh start (and on every resume) the Dart
    // state must be reconciled with the native truth, or the UI shows
    // "not connected" under a live VPN notification icon.
    WidgetsBinding.instance.addObserver(this);
    // React to the native service's status pushes. Without this the UI kept
    // claiming "Connected" (with a ticking uptime) after the engine died, the
    // user revoked the VPN in system settings, or another VPN app took over.
    vpnService.onStatusChanged = _onNativeStatus;
    reconcileWithNativeService().then((_) => _maybeAutoConnect());
    _startLivenessWatchdog();
  }

  /// True when adopting a running native tunnel cannot fight an operation
  /// already in flight (a scan connects and disconnects candidates, so
  /// adoption must stay out of its way).
  bool get _canAdopt =>
      state.value == ConnectionState.idle || state.value == ConnectionState.error;

  /// Handles a status pushed by the native service.
  void _onNativeStatus(String status, String? error) {
    switch (status) {
      case 'connected':
        // A tunnel came up behind the app's back (re-attached engine, or a
        // connect that outlived the process).
        if (_canAdopt) reconcileWithNativeService();
        break;
      case 'disconnected':
        if (isConnected) {
          state.value = ConnectionState.idle;
          statusMessage.value = 'Tunnel ended';
          selectedConfig.value = null;
          connectedIP.value = null;
          exitIpInfo.value = null;
          connectionUptime.value = 0;
          _connectionStartTime = null;
          _stopUptimeCounter();
          debugService.logAction('tunnel_lost', {'reason': 'disconnected'});
        }
        break;
      case 'error':
      case 'blocked':
        // The engine died (with or without the kill switch holding the
        // interface open) or the tunnel was torn down. Say so, and stop the
        // uptime that would otherwise keep ticking over a dead tunnel.
        if (isConnected || state.value == ConnectionState.connecting) {
          state.value = ConnectionState.error;
          statusMessage.value =
              error ?? 'The tunnel stopped unexpectedly. Reconnect to retry.';
          connectedIP.value = null;
          exitIpInfo.value = null;
          connectionUptime.value = 0;
          _connectionStartTime = null;
          _stopUptimeCounter();
          debugService.logAction('tunnel_lost', {
            'reason': status,
            'detail': error ?? '',
          });
        }
        break;
    }
  }

  /// Connects on launch when the user asked for it, but only after
  /// reconciliation has had its say — adopting a tunnel that survived the
  /// process is not the same as starting a new one.
  Future<void> _maybeAutoConnect() async {
    try {
      if (isConnected || !_canAdopt) return;
      final settings = Get.find<SettingsController>();
      if (!settings.autoConnect.value) return;
      final configController = Get.find<ConfigController>();
      final configs = configController.visibleConfigs;
      if (configs.isEmpty) return;
      _log.i('Auto-connect is on — starting a scan');
      debugService.logAction('auto_connect');
      await connectFastest(configs);
    } catch (e) {
      _log.w('Auto-connect skipped: $e');
    }
  }

  /// Foreground liveness watchdog: while the app is open and connected, the
  /// tunnel is asked to fetch the check hosts periodically. A tunnel that
  /// stops carrying traffic (a common way for a long-lived connection to die)
  /// is reported instead of silently pretending to work.
  ///
  /// Foreground-only by design: a background Dart timer would be killed with
  /// the process anyway, and pretending otherwise would be a lie.
  void _startLivenessWatchdog() {
    _livenessTimer?.cancel();
    int minutes;
    try {
      minutes = Get.find<SettingsController>().autoTestIntervalMinutes.value;
    } catch (_) {
      return;
    }
    if (minutes <= 0) return;
    _livenessTimer = Timer.periodic(Duration(minutes: minutes), (_) async {
      if (!isConnected) return;
      final verify = siteCheckService;
      if (verify == null || !verify.enabled) return;
      final alive = await verify.verifyLiveConnection();
      if (alive || !isConnected) return;
      _log.w('Liveness check failed on a connected tunnel');
      state.value = ConnectionState.error;
      statusMessage.value =
          'The tunnel is up but nothing loads — reconnect to pick another '
          'server';
      debugService.logAction('liveness_failed');
    });
  }

  @override
  void onClose() {
    WidgetsBinding.instance.removeObserver(this);
    vpnService.onStatusChanged = null;
    _livenessTimer?.cancel();
    _stopUptimeCounter();
    debugService.logInfo('ConnectionController closing');
    super.onClose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Coming back to the foreground is exactly when a desync becomes visible.
    if (state == AppLifecycleState.resumed) {
      reconcileWithNativeService().then((_) {
        _startLivenessWatchdog();
        // A tunnel that is up but dead is the classic "left it running for
        // half an hour" failure; check it as soon as the user looks at it.
        _verifyTunnelAlive();
      });
    }
  }

  /// Asks the live tunnel to load a check host and reports failure honestly.
  Future<void> _verifyTunnelAlive() async {
    if (!isConnected) return;
    final verify = siteCheckService;
    if (verify == null || !verify.enabled) return;
    final alive = await verify.verifyLiveConnection();
    if (alive || !isConnected) return;
    state.value = ConnectionState.error;
    statusMessage.value =
        'The tunnel is up but nothing loads — reconnect to pick another server';
    debugService.logAction('liveness_failed', {'trigger': 'resume'});
  }

  /// Brings the Dart state in line with what the native service is actually
  /// doing, in both directions:
  ///
  /// - **Native running, Dart idle** (process was killed, tunnel survived):
  ///   adopt it — restore the selected config by name/protocol, rebuild the
  ///   uptime from the native start timestamp, and re-fetch the exit info.
  /// - **Native stopped, Dart connected** (engine died or the tunnel was
  ///   revoked): drop to idle instead of claiming a connection that is gone.
  ///
  /// Safe to call at any time; a no-op when the two already agree.
  Future<void> reconcileWithNativeService() async {
    try {
      final status = await vpnService.getStatus();
      final nativeRunning = status['isRunning'] == true;

      if (nativeRunning && _canAdopt && !isConnected) {
        final name = status['name'] as String?;
        final protocol = status['protocol'] as String?;
        Config? config;
        try {
          final configController = Get.find<ConfigController>();
          config = configController.allConfigs.firstWhereOrNull(
            (c) =>
                (name == null || c.displayName == name) &&
                (protocol == null || c.protocol == protocol),
          );
        } catch (_) {
          // ConfigController not registered yet — adopt without the object.
        }

        selectedConfig.value = config;
        state.value = ConnectionState.connected;
        statusMessage.value = config != null
            ? 'Restored: ${config.displayName} (tunnel was already running)'
            : 'Restored connection (tunnel was already running)';

        final startedAtMs = (status['connectedAtMs'] as num?)?.toInt() ?? 0;
        _connectionStartTime = startedAtMs > 0
            ? DateTime.fromMillisecondsSinceEpoch(startedAtMs)
            : DateTime.now();
        _startUptimeCounter();
        _fetchConnectedIP();

        _log.i('Adopted a running native tunnel'
            '${config != null ? " (${config.displayName})" : ""}');
        debugService.logAction('state_reconciled', {
          'adopted': true,
          'config': name ?? 'unknown',
          'protocol': protocol ?? 'unknown',
        });
      } else if (!nativeRunning && isConnected) {
        state.value = ConnectionState.idle;
        statusMessage.value = 'Tunnel ended';
        selectedConfig.value = null;
        selectedConfigResult.value = null;
        connectedIP.value = null;
        exitIpInfo.value = null;
        connectionUptime.value = 0;
        _connectionStartTime = null;
        _stopUptimeCounter();
        _log.w('Native tunnel is gone while the UI thought it was connected');
        debugService.logAction('state_reconciled', {
          'adopted': false,
          'reason': 'native tunnel gone',
        });
      }
    } catch (e) {
      // Reconciliation is a repair, never a blocker.
      _log.w('State reconciliation failed: $e');
    }
  }

  /// Loads the cached home identity first (visible immediately, even
  /// offline), then refreshes it from the network.
  Future<void> _initIpInfo() async {
    final service = ipInfoService;
    if (service == null) return;
    homeIpInfo.value = service.cachedHome();
    final fresh = await service.fetchHome();
    if (!fresh.isEmpty && isConnected) return;
    homeIpInfo.value = fresh;
  }

  /// Refreshes the home identity when the tunnel is down, so the "before"
  /// row stays current.
  Future<void> refreshHomeIpInfo() async {
    if (isConnected) return;
    final service = ipInfoService;
    if (service == null) return;
    final fresh = await service.fetchHome();
    if (!fresh.isEmpty) homeIpInfo.value = fresh;
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

      // Results handed in by the library let us skip servers that already
      // failed — re-probing thousands of them was dead air behind censorship.
      final knownFailed = <String>{};
      for (final r in testResults ?? const <TestResult>[]) {
        if (!r.isWorking && candidateHashes.contains(r.configHash)) {
          knownFailed.add(r.configHash);
        }
      }

      // Batched full-scan. The list is walked in batches of 50: probe the
      // batch, site-check and connect-verify its survivors in rank order,
      // and only when the WHOLE batch is exhausted move to the next one.
      // With 7,000 sources this scans everything eventually — slow, but it
      // does not give up, and the status line always shows where it is.
      final toScan = candidates
          .where((c) => !knownFailed.contains(c.getHash()))
          .toList();
      final totalBatches = (toScan.length / _probeBatchSize).ceil();
      _log.i('Batched scan: ${toScan.length} configs in $totalBatches '
          'batch(es) of $_probeBatchSize');
      debugService.logAction('scan_started', {
        'configs': toScan.length,
        'batches': totalBatches,
      });

      for (var batchIndex = 0; batchIndex < totalBatches; batchIndex++) {
        final batch =
            toScan.skip(batchIndex * _probeBatchSize).take(_probeBatchSize).toList();
        final batchHashes = batch.map((c) => c.getHash()).toSet();
        final batchLabel =
            'batch ${batchIndex + 1}/$totalBatches';

        state.value = ConnectionState.selecting;
        statusMessage.value = 'Pinging $batchLabel (${batch.length} servers)...';
        var probed = 0;
        testerService.onProgress = (hash, status) {
          // onProgress fires a 'testing' event at probe start AND a terminal
          // event at the end — counting both reported double progress.
          if (status == TestStatus.testing) return;
          probed++;
          statusMessage.value =
              'Pinging $batchLabel... $probed/${batch.length}';
        };
        List<TestResult> probedResults;
        try {
          probedResults = await testerService.testConfigsConcurrently(
            batch,
            concurrency: _probeConcurrency,
            attempts: _probeAttempts,
            timeout: _probeTimeout,
          );
        } finally {
          testerService.onProgress = null;
        }

        final working = testerService
            .getWorkingConfigs(probedResults)
            .where((r) => batchHashes.contains(r.configHash))
            .toList()
          ..sort((a, b) => (a.latencyMs ?? 1 << 30)
              .compareTo(b.latencyMs ?? 1 << 30));

        if (working.isEmpty) {
          _log.i('$batchLabel: no server answered');
          continue;
        }

        // Site check: the TCP probe proved the *path* to each server; the
        // headless-core check proves the config can actually carry traffic.
        // Only the batch's fastest few get this (expensive) treatment; the
        // rest keep their TCP rank. Failures degrade to TCP order.
        final check = siteCheckService;
        var reports = const <String, SiteCheckReport>{};
        if (check != null && check.enabled) {
          statusMessage.value =
              'Verifying websites, $batchLabel...';
          final shortlist = working
              .take(_siteCheckShortlistSize)
              .map((r) => batch.firstWhereOrNull(
                  (c) => c.getHash() == r.configHash))
              .whereType<Config>()
              .toList();
          try {
            reports = await check.checkConfigs(shortlist);
          } catch (e) {
            _log.w('Site check stage failed, falling back to TCP rank: $e');
            reports = const {};
          }
        }

        // Rank the batch: verified-usable first (best tunnel latency), then
        // everything else by TCP latency.
        int rank(TestResult r) {
          final report = reports[r.configHash];
          if (report == null || !report.supported) return 1;
          if (!report.isUsable) return 0;
          return 2;
        }

        working.sort((a, b) {
          final byStage = rank(a).compareTo(rank(b));
          if (byStage != 0) return byStage;
          return (a.latencyMs ?? 1 << 30).compareTo(b.latencyMs ?? 1 << 30);
        });

        // Connect loop with live verification. A config can pass every
        // pre-connect probe and still black-hole real traffic once the TUN
        // interface is up — so after each successful connect, the tunnel
        // itself is asked to fetch the check hosts through its own SOCKS
        // inbound. A tunnel that cannot do that is disconnected and the
        // next candidate in the batch gets its chance.
        final verify = siteCheckService;
        final liveVerifyEnabled =
            verify != null && verify.enabled && verify.liveCheckHosts.isNotEmpty;
        final attemptLimit = liveVerifyEnabled
            ? (working.length < _maxConnectAttemptsPerBatch
                ? working.length
                : _maxConnectAttemptsPerBatch)
            : 1;

        for (var attempt = 0; attempt < attemptLimit; attempt++) {
          final result = working[attempt];
          final config = batch.firstWhereOrNull(
            (c) => c.getHash() == result.configHash,
          );
          if (config == null) continue;

          statusMessage.value =
              'Connecting ($batchLabel, config ${attempt + 1})...';

          final connected = await connect(config, testResult: result);
          if (!connected) continue;
          if (!liveVerifyEnabled) return true;

          state.value = ConnectionState.testing;
          statusMessage.value =
              'Checking websites through the tunnel ($batchLabel, config ${attempt + 1})...';
          final alive = await verify.verifyLiveConnection();
          if (alive) {
            state.value = ConnectionState.connected;
            statusMessage.value =
                'Connected to ${config.displayName} — verified';
            _log.i('Live verification passed for ${config.displayName} '
                '($batchLabel)');
            debugService.logAction('scan_verified', {
              'config': config.displayName,
              'attempt': attempt + 1,
              'batch': batchIndex + 1,
              'total_batches': totalBatches,
            });
            return true;
          }

          _log.w('Tunnel came up but could not reach any check host '
              '(${config.displayName}, $batchLabel) — trying the next '
              'candidate');
          await disconnect();
        }
        // Whole batch exhausted — the outer loop advances to the next 50.
        _log.i('$batchLabel exhausted: $attemptLimit connect attempt(s) '
            'failed live verification');
      }

      state.value = ConnectionState.error;
      final check2 = siteCheckService;
      final verificationOn = check2 != null &&
          check2.enabled &&
          check2.liveCheckHosts.isNotEmpty;
      statusMessage.value = verificationOn
          ? 'Scanned all ${toScan.length} configs but none could load '
              'websites. Refresh your sources or disable the site check to '
              'connect anyway.'
          : 'No working configs found';
      debugService.logAction('scan_exhausted', {'configs': toScan.length});
      return false;
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
        debugService.logAction('connected', {
          'config': config.displayName,
          'protocol': config.protocol,
        });
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
        debugService.logAction('connect_failed', {
          'config': config.displayName,
          'reason': vpnService.lastError ?? 'unknown',
        });
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
        exitIpInfo.value = null;
        connectionUptime.value = 0;
        _connectionStartTime = null;
        debugService.logInfo('VPN disconnected');
        debugService.logAction('disconnected');
        // Unawaited: the home row refreshes in the background.
        refreshHomeIpInfo();
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
    // Where is the exit? Only a request that leaves THROUGH the tunnel can
    // answer that; a direct one would describe the unprotected address.
    final service = ipInfoService;
    if (service != null) {
      exitIpInfo.value = await service.fetchExit();
    }
  }
}
