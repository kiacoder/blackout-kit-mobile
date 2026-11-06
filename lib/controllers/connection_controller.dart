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
import '../services/localization_service.dart';
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
  final RxString statusMessage = RxString('');
  final Rxn<String> connectedIP = Rxn<String>();
  final RxDouble connectionUptime = RxDouble(0.0); // seconds
  final RxBool isKillSwitchEnabled = RxBool(false);
  final RxBool isDNSLeakPreventionEnabled = RxBool(false);
  final RxBool isSplitTunnelingEnabled = RxBool(false);

  /// True while the live session only changes DNS (no routes, no engine).
  final RxBool isDnsOnly = RxBool(false);

  /// Current scan presentation model. These observables drive the connect
  /// screen's phase animation and detailed progress rather than a spinner.
  final RxString scanPhase = RxString('idle');
  final RxInt scanBatchIndex = RxInt(0);
  final RxInt scanBatchCount = RxInt(0);
  final RxInt scanItemsDone = RxInt(0);
  final RxInt scanItemsTotal = RxInt(0);
  final RxString scanCurrentConfig = RxString('');
  final RxInt scanSitesDone = RxInt(0);
  final RxInt scanSitesTotal = RxInt(0);

  /// Retained scan worklist and cursor across accepted tunnel sessions, so a
  /// later liveness failure resumes at the next untried config, not next batch.
  List<Config> _resumeQueue = const [];
  List<Config> _originalScanQueue = const [];
  List<TestResult> _resumeResults = const [];
  int _resumeCursor = 0;

  /// Start at a particular candidate when recovery resumes a partially-tested
  /// worklist; fresh scans always begin at zero.
  int? _requestedResumeCursor;
  bool _recoveryPromptPending = false;
  bool _recoveryRequested = false;

  /// Signals the UI that a connected session failed and needs a deliberate
  /// recovery choice. The controller never starts a fresh scan silently.
  final RxString recoveryReason = RxString('');
  final RxBool recoveryAvailable = RxBool(false);

  void _requestRecovery(String reason) {
    if (_recoveryPromptPending) return;
    _recoveryPromptPending = true;
    recoveryReason.value = reason;
    recoveryAvailable.value = true;
    scanPhase.value = 'recovery';
    state.value = ConnectionState.error;
  }

  /// Resume after a later tunnel failure. By default continue with the next
  /// batch; Settings can deliberately reset the cursor to the beginning.
  Future<bool> resumeScanAfterFailure({bool restart = false}) async {
    if (!_recoveryPromptPending || _operationInFlight) return false;
    final settings = Get.find<SettingsController>();
    final shouldRestart =
        restart || settings.connectFailureScanPolicy.value == 'restart';
    _requestedResumeCursor = shouldRestart ? 0 : _resumeCursor;
    if (shouldRestart) _resumeQueue = List<Config>.of(_originalScanQueue);
    _recoveryPromptPending = false;
    recoveryAvailable.value = false;
    final candidates = List<Config>.of(_resumeQueue);
    final results = List<TestResult>.of(_resumeResults);
    if (candidates.isEmpty) {
      state.value = ConnectionState.idle;
      return false;
    }
    return connectFastest(candidates,
        testResults: results.isEmpty ? null : results);
  }

  @visibleForTesting
  void debugRequestRecoveryForTest() => _requestRecovery('test recovery');

  void dismissRecovery() {
    _recoveryPromptPending = false;
    recoveryAvailable.value = false;
    scanPhase.value = 'idle';
    state.value = ConnectionState.idle;
  }

  /// Last config whose live tunnel passed the configured website gate.
  final Rx<Config?> lastKnownWorkingConfig = Rx<Config?>(null);

  /// Incremented on every connect/disconnect so in-flight lookups can tell
  /// they belong to a session that no longer exists.
  int _sessionEpoch = 0;

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
  /// of the process, so probing once is enough. It is an Rx so the library
  /// tiles' Obx rebuilds when the async probe lands — as a plain field the
  /// Connect buttons built before the answer stayed tappable forever (CON-06).
  final _engineAvailability = Rx<EngineAvailability?>(null);

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
    // Translated here rather than in the field initialiser: `.tr` needs the
    // catalogue, which is registered by the time onInit runs.
    if (statusMessage.value.isEmpty)
      statusMessage.value = LocalizationService.t('status_ready');
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
      state.value == ConnectionState.idle ||
      state.value == ConnectionState.error;

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
          final failedDuringScan = _recoveryRequested;
          state.value = ConnectionState.idle;
          statusMessage.value = LocalizationService.t('status_tunnel_ended');
          if (!failedDuringScan && lastKnownWorkingConfig.value != null) {
            _requestRecovery(LocalizationService.t('status_tunnel_ended'));
          }
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
          statusMessage.value = error ??
              LocalizationService.t(
                  'The tunnel stopped unexpectedly. Reconnect to retry.');
          if (!_recoveryRequested && lastKnownWorkingConfig.value != null) {
            _requestRecovery(statusMessage.value);
          }
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
      debugService.logAction('liveness_failed');
      // Paint the error AND close the interface. Leaving it up left the app
      // claiming failure while the system VPN stayed established, so traffic
      // kept being routed into a tunnel that carries nothing.
      await _failTunnel(
        'The tunnel is up but nothing loads — reconnect to pick another server',
      );
      _requestRecovery(statusMessage.value);
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
    debugService.logAction('liveness_failed', {'trigger': 'resume'});
    // Same reason as the watchdog: an error state with a live interface is a
    // lie the user pays for in dropped traffic - and a tunnel torn down
    // without unwinding the session is the same lie in the other direction.
    await _failTunnel(
      'The tunnel is up but nothing loads — reconnect to pick another server',
    );
    _requestRecovery(statusMessage.value);
  }

  /// Closes a tunnel that failed its liveness check and unwinds the session.
  ///
  /// The two callers used to invoke `vpnService.disconnect()` directly, which
  /// closed the interface but left the controller half-alive: selection,
  /// uptime, exit identity, the connected IP and the timers all survived, so
  /// the next connect reused stale state and the UI described a session that
  /// was not running. This runs the same teardown as a user disconnect, then
  /// keeps the failure message instead of replacing it with "Disconnected".
  Future<void> _failTunnel(String message) async {
    await _disconnectImpl();
    state.value = ConnectionState.error;
    if (message.isNotEmpty) statusMessage.value = message;
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
        // A DNS-only session has no config and no core, so the config lookup
        // below cannot match it and _fetchConnectedIP() would dial a SOCKS
        // inbound that does not exist — six retries, ~15 seconds of nothing.
        final dnsOnlySession = protocol == 'dns';
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
        if (config != null && lastKnownWorkingConfig.value == null) {
          lastKnownWorkingConfig.value = config;
        }
        isDnsOnly.value = dnsOnlySession;
        state.value = ConnectionState.connected;
        statusMessage.value = dnsOnlySession
            ? LocalizationService.t('dns_only_started')
            : config != null
                ? LocalizationService.t(
                    'Restored: @name (tunnel was already running)',
                    {'name': config.displayName})
                : LocalizationService.t(
                    'Restored connection (tunnel was already running)');

        final startedAtMs = (status['connectedAtMs'] as num?)?.toInt() ?? 0;
        _connectionStartTime = startedAtMs > 0
            ? DateTime.fromMillisecondsSinceEpoch(startedAtMs)
            : DateTime.now();
        _startUptimeCounter();
        if (config != null) {
          try {
            Get.find<ConfigController>().markConnected(config);
          } catch (_) {}
        }
        // Nothing to resolve: a DNS-only interface has no exit to describe.
        if (!dnsOnlySession) _fetchConnectedIP();

        _log.i('Adopted a running native tunnel'
            '${config != null ? " (${config.displayName})" : ""}');
        debugService.logAction('state_reconciled', {
          'adopted': true,
          'config': name ?? 'unknown',
          'protocol': protocol ?? 'unknown',
        });
      } else if (!nativeRunning && isConnected) {
        state.value = ConnectionState.idle;
        statusMessage.value = LocalizationService.t('status_tunnel_ended');
        isDnsOnly.value = false;
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
    // A failed refresh returns an empty IpInfo. Assigning it unconditionally
    // replaced a perfectly good cached identity with blanks, so one network
    // hiccup erased the "before" row until the next successful fetch.
    if (fresh.isEmpty && !(homeIpInfo.value?.isEmpty ?? true)) return;
    homeIpInfo.value = fresh;
  }

  /// Drops the identities currently on screen.
  ///
  /// Called when the user turns "Show my location" off: the service deletes
  /// its cache, but these are in-memory values that the home screen keeps
  /// rendering, so the last resolved IPs stayed visible after opting out.
  void clearIpInfo() {
    homeIpInfo.value = null;
    exitIpInfo.value = null;
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
    if (_operationInFlight) {
      _log.w('Fast connect ignored: another operation is already running');
      return false;
    }
    _operationInFlight = true;
    _cancelRequested = false;
    _recoveryRequested =
        _requestedResumeCursor != null || _recoveryPromptPending;
    try {
      return await _connectFastestImpl(availableConfigs,
          testResults: testResults);
    } finally {
      _operationInFlight = false;
      _cancelRequested = false;
      _recoveryRequested = false;
    }
  }

  Future<bool> _connectFastestImpl(
    List<Config> availableConfigs, {
    List<TestResult>? testResults,
  }) async {
    try {
      state.value = ConnectionState.selecting;
      statusMessage.value = LocalizationService.t('status_finding_fastest');

      // Honour the protocol preference instead of ignoring it: configs using
      // the preferred protocol are tried first, everything else keeps its
      // order behind them. With autoSelectFastest off the preference becomes
      // the primary order rather than latency, so "connect my vless first"
      // means something.
      final preferredProtocol =
          Get.find<SettingsController>().preferredProtocol.value.toLowerCase();
      if (preferredProtocol.isNotEmpty && preferredProtocol != 'auto') {
        availableConfigs = List<Config>.of(availableConfigs)
          ..sort((a, b) {
            final aPreferred = a.protocol.toLowerCase() == preferredProtocol;
            final bPreferred = b.protocol.toLowerCase() == preferredProtocol;
            if (aPreferred == bPreferred) return 0;
            return aPreferred ? -1 : 1;
          });
      }

      // Drop anything no bundled engine can serve, otherwise "fastest" can
      // select a config that connect() is then obliged to refuse.
      final candidates = await _servableConfigs(availableConfigs);
      if (candidates.isEmpty) {
        state.value = ConnectionState.error;
        statusMessage.value = availableConfigs.isEmpty
            ? LocalizationService.t('No configs available')
            : LocalizationService.t(
                'None of your configs use a protocol this build can serve');
        return false;
      }

      // "Auto-select fastest" off means: do not probe the whole library, just
      // take the first usable config in preference order. The switch was
      // stored, loaded, rendered and reset, but nothing ever read it - every
      // tap ran the full scan regardless of what the user chose.
      if (!Get.find<SettingsController>().autoSelectFastest.value) {
        final chosen = candidates.first;
        statusMessage.value = LocalizationService.t(
            'status_connecting_to', {'name': chosen.displayName});
        final connected = await _connectImpl(chosen);
        if (connected) lastKnownWorkingConfig.value = chosen;
        return connected;
      }

      // Cached TCP failures only influence their position within a batch; they
      // never suppress a real VPN attempt. A failed server-port probe cannot
      // rule out UDP protocols, filtering artefacts, or transient network faults.
      final cachedResults = {
        for (final result in testResults ?? const <TestResult>[])
          result.configHash: result,
      };

      // Preserve config order and full eligibility across the scan. Recovery
      // carries this exact queue and cursor forward rather than reconstructing
      // the queue from current probe results or skipping a partially tested batch.
      final settings = Get.find<SettingsController>();
      final batchSize = settings.connectScanBatchSize.value;
      final isResuming = _recoveryRequested && _requestedResumeCursor != null;
      final toScan = isResuming
          ? List<Config>.of(_resumeQueue)
          : List<Config>.of(candidates);
      if (!isResuming) {
        _resumeQueue = List<Config>.of(toScan);
        _originalScanQueue = List<Config>.of(toScan);
        _resumeCursor = 0;
      }
      final totalBatches = (toScan.length / batchSize).ceil();
      scanBatchCount.value = totalBatches;
      scanItemsTotal.value = toScan.length;
      scanItemsDone.value = 0;
      _resumeResults = List<TestResult>.of(testResults ?? const []);
      final startCursor =
          (_recoveryRequested ? (_requestedResumeCursor ?? _resumeCursor) : 0)
              .clamp(0, toScan.length);
      _resumeCursor = startCursor;
      _requestedResumeCursor = null;
      final startBatch = startCursor ~/ batchSize;
      _log.i('Batched scan: ${toScan.length} configs in $totalBatches '
          'batch(es) of $batchSize, resuming at config ${startCursor + 1}');
      debugService.logAction('scan_started', {
        'configs': toScan.length,
        'batches': totalBatches,
      });

      for (var batchIndex = startBatch;
          batchIndex < totalBatches;
          batchIndex++) {
        scanBatchIndex.value = batchIndex + 1;
        if (_cancelRequested) {
          _log.i('Scan cancelled by the user after $batchIndex batch(es)');
          statusMessage.value = LocalizationService.t('status_scan_stopped');
          state.value = ConnectionState.idle;
          return false;
        }
        final batchStart =
            batchIndex == startBatch ? startCursor : batchIndex * batchSize;
        final batch = toScan
            .skip(batchStart)
            .take(batchSize - (batchStart % batchSize))
            .toList();
        scanItemsDone.value = batchStart;
        scanPhase.value = 'ping';
        final batchHashes = batch.map((c) => c.getHash()).toSet();
        final batchLabel = 'batch ${batchIndex + 1}/$totalBatches';

        state.value = ConnectionState.selecting;
        statusMessage.value = LocalizationService.t('status_pinging',
            {'label': batchLabel, 'count': '${batch.length}'});
        var probed = 0;
        final progressToken = testerService.beginProgressRun((hash, status) {
          // onProgress fires a 'testing' event at probe start AND a terminal
          // event at the end — counting both reported double progress.
          if (status == TestStatus.testing) return;
          probed++;
          scanItemsDone.value = batchIndex * batchSize + probed;
          statusMessage.value = LocalizationService.t(
              'Pinging @label... @done/@total', {
            'label': batchLabel,
            'done': '$probed',
            'total': '${batch.length}'
          });
        });
        List<TestResult> probedResults;
        try {
          probedResults = await testerService.testConfigsConcurrently(
            batch,
            concurrency: _probeConcurrency,
            attempts: _probeAttempts,
            timeout: _probeTimeout,
          );
        } finally {
          testerService.endProgressRun(progressToken);
        }

        // A failed TCP probe is not a verdict on the VPN protocol: the port
        // may be UDP-only, filtered, or temporarily unreachable while its
        // actual outbound can still work. Keep every batch member as a real
        // connect candidate, with successful probes ordered ahead of unknown,
        // then failed probes.
        final resultsByHash = {
          for (final result in probedResults) result.configHash: result,
        };
        final working = batch
            .map((config) =>
                resultsByHash[config.getHash()] ??
                TestResult(configHash: config.getHash()))
            .toList()
          ..sort((a, b) {
            int probeRank(TestResult result) => switch (result.status) {
                  TestStatus.success => 0,
                  TestStatus.notTested => 1,
                  TestStatus.timeout || TestStatus.failed => 2,
                  TestStatus.testing => 3,
                };
            final rank = probeRank(a).compareTo(probeRank(b));
            if (rank != 0) return rank;
            final cachedA = cachedResults[a.configHash];
            final cachedB = cachedResults[b.configHash];
            return (a.latencyMs ?? cachedA?.latencyMs ?? 1 << 30)
                .compareTo(b.latencyMs ?? cachedB?.latencyMs ?? 1 << 30);
          });

        if (working.isEmpty) {
          _log.i(
              '$batchLabel: no probe results; trying configs in original order');
        }

        final verify = siteCheckService;
        final liveVerifyEnabled = verify != null &&
            verify.enabled &&
            settings.siteCheckUrls.isNotEmpty;
        final mode = settings.connectVerificationStrategy.value;
        final candidateLimit = switch (mode) {
          'all' => working.length,
          'hybrid' => settings.connectHybridCandidateCount.value,
          _ => 3,
        };
        final attemptLimit = candidateLimit.clamp(1, working.length);
        final preferred = settings.preferredProtocol.value.toLowerCase();
        working.sort((a, b) {
          int probeRank(TestResult result) => switch (result.status) {
                TestStatus.success => 0,
                TestStatus.notTested => 1,
                TestStatus.timeout || TestStatus.failed => 2,
                TestStatus.testing => 3,
              };
          final statusOrder = probeRank(a).compareTo(probeRank(b));
          if (statusOrder != 0) return statusOrder;
          final ca = batch.firstWhereOrNull((c) => c.getHash() == a.configHash);
          final cb = batch.firstWhereOrNull((c) => c.getHash() == b.configHash);
          final aPreferred = preferred.isNotEmpty &&
              preferred != 'auto' &&
              ca?.protocol.toLowerCase() == preferred;
          final bPreferred = preferred.isNotEmpty &&
              preferred != 'auto' &&
              cb?.protocol.toLowerCase() == preferred;
          if (aPreferred != bPreferred) return aPreferred ? -1 : 1;
          final latencyOrder =
              (a.latencyMs ?? 1 << 30).compareTo(b.latencyMs ?? 1 << 30);
          if (latencyOrder != 0) return latencyOrder;
          return (cachedResults[a.configHash]?.latencyMs ?? 1 << 30)
              .compareTo(cachedResults[b.configHash]?.latencyMs ?? 1 << 30);
        });

        // One VPN session at a time: each candidate is genuinely connected,
        // traffic is checked through the established tunnel, then a rejected
        // candidate is fully torn down before the next attempt.
        for (var attempt = 0; attempt < attemptLimit; attempt++) {
          if (_cancelRequested) {
            statusMessage.value = LocalizationService.t('status_scan_stopped');
            state.value = ConnectionState.idle;
            return false;
          }
          final absoluteIndex = batchStart + attempt;
          _resumeCursor = absoluteIndex;
          final result = working[attempt];
          final config =
              batch.firstWhereOrNull((c) => c.getHash() == result.configHash);
          if (config == null) continue;
          scanCurrentConfig.value = config.displayName;
          statusMessage.value = LocalizationService.t(
              'Connecting (@label, config @n)...',
              {'label': batchLabel, 'n': '${attempt + 1}'});
          scanPhase.value = 'connect';
          final connected = await _connectImpl(config, testResult: result);
          if (!connected) continue;

          var accepted = !liveVerifyEnabled;
          if (liveVerifyEnabled) {
            state.value = ConnectionState.testing;
            scanPhase.value = 'websites';
            scanSitesTotal.value = settings.siteCheckUrls.length;
            statusMessage.value = LocalizationService.t(
                'Checking websites through the tunnel (@label, config @n)...',
                {'label': batchLabel, 'n': '${attempt + 1}'});
            final outcomes = await verify.checkLiveConnection();
            scanSitesDone.value = outcomes.length;
            final passed = outcomes.where((outcome) => outcome.ok).length;
            final threshold = settings.connectWebsitePassThreshold.value;
            accepted = outcomes.isNotEmpty &&
                (threshold < 0
                    ? passed == outcomes.length
                    : passed >= threshold.clamp(1, outcomes.length));
          }

          if (accepted) {
            state.value = ConnectionState.connected;
            lastKnownWorkingConfig.value = config;
            _resumeQueue = [
              ...working.skip(attempt + 1).map((candidate) => batch
                  .firstWhere((entry) => entry.getHash() == candidate.configHash)),
              ...toScan.skip(batchStart + batch.length),
            ];
            // The retained queue now starts with the first untried config.
            _resumeCursor = 0;
            _resumeResults = List<TestResult>.of(testResults ?? const []);
            scanPhase.value = 'connected';
            statusMessage.value = LocalizationService.t(
                liveVerifyEnabled
                    ? 'status_connected_verified'
                    : 'status_connected_to',
                {'name': config.displayName});
            debugService.logAction('scan_verified', {
              'config': config.displayName,
              'attempt': attempt + 1,
              'batch': batchIndex + 1,
              'total_batches': totalBatches,
            });
            return true;
          }

          _log.w('Website threshold not met for ${config.displayName} '
              '($batchLabel: $scanSitesDone/@$scanSitesTotal passed)');
          await _disconnectImpl();
        }
        _resumeCursor = batchStart + batch.length;
        _log.i('$batchLabel exhausted: $attemptLimit candidate(s) tried');
      }

      state.value = ConnectionState.error;
      scanPhase.value = 'failed';
      final check2 = siteCheckService;
      final verificationOn =
          check2 != null && check2.enabled && settings.siteCheckUrls.isNotEmpty;
      statusMessage.value = verificationOn
          ? LocalizationService.t(
              'Scanned all @count configs but none could load websites. Refresh your sources or disable the site check to connect anyway.',
              {'count': '${toScan.length}'})
          : LocalizationService.t('No working configs found');
      debugService.logAction('scan_exhausted', {'configs': toScan.length});
      return false;
    } catch (e) {
      state.value = ConnectionState.error;
      statusMessage.value =
          LocalizationService.t('status_error', {'error': '$e'});
      _log.e('Error connecting to fastest: $e');
      return false;
    }
  }

  /// True while a connect/disconnect/scan is running.
  ///
  /// The UI only disabled the "connecting" state, so a second tap started a
  /// parallel scan, a second consent request and a second native connect
  /// while the first was still in flight. Every public entry point shares
  /// this guard; internal steps call the impl methods.
  bool _operationInFlight = false;

  /// Set by [cancelScan] and checked between batches and between connect
  /// attempts. A full scan can run for minutes over thousands of configs, and
  /// there was no way to stop it: the big button was disabled in selecting/
  /// testing and Disconnect was rejected by the single-flight guard, so the
  /// only escape was killing the app.
  bool _cancelRequested = false;

  /// Stops a running scan. Returns true when there was one to stop.
  bool cancelScan() {
    if (!_operationInFlight) return false;
    _cancelRequested = true;
    statusMessage.value = LocalizationService.t('status_stopping');
    return true;
  }

  bool get operationInFlight => _operationInFlight;

  /// Connect to specific config
  Future<bool> connect(
    Config config, {
    TestResult? testResult,
  }) async {
    if (_operationInFlight) {
      _log.w('Connect ignored: another operation is already running');
      return false;
    }
    _operationInFlight = true;
    try {
      return await _connectImpl(config, testResult: testResult);
    } finally {
      _operationInFlight = false;
    }
  }

  Future<bool> _connectImpl(
    Config config, {
    TestResult? testResult,
  }) async {
    try {
      if (!config.validate()) {
        state.value = ConnectionState.error;
        statusMessage.value = LocalizationService.t('status_invalid_config');
        return false;
      }

      // Refuse before the consent dialog: there is no point asking the user to
      // grant VPN permission for a protocol no bundled runtime can serve.
      final refusal = await _engineRefusal(config);
      if (refusal != null) {
        state.value = ConnectionState.error;
        statusMessage.value = refusal;
        debugService
            .logError('Connect refused for ${config.protocol}: $refusal');
        return false;
      }

      state.value = ConnectionState.connecting;
      // A new session starts here: anything still in flight belongs to the
      // previous one and must not write over this one's state.
      _sessionEpoch++;
      statusMessage.value = LocalizationService.t(
          'status_connecting_to', {'name': config.displayName});
      selectedConfig.value = config;
      selectedConfigResult.value = testResult;

      _log.i('Connecting to ${config.displayName}');

      // Android shows a system consent dialog before the first tunnel.
      final prepared = await vpnService.prepare();
      if (!prepared) {
        state.value = ConnectionState.error;
        statusMessage.value = vpnService.lastError ??
            LocalizationService.t('status_permission_denied');
        return false;
      }

      // Split tunneling, DNS and the kill switch are all inputs to
      // Builder.establish(), so they have to be assembled *before* connecting.
      // The old code activated them afterwards through channels that had no
      // native handler, so none of them ever took effect.
      //
      // The config is passed so its own DNS (a WireGuard profile's
      // [Interface] DNS, for one) seeds the resolver list; without it the
      // options were built with a hardcoded 1.1.1.1 and the profile's
      // resolver never reached the tunnel.
      final options = buildSessionOptions(config);
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
        statusMessage.value = LocalizationService.t(
            'status_connected_to', {'name': config.displayName});
        debugService.logAction('connected', {
          'config': config.displayName,
          'protocol': config.protocol,
        });
        _connectionStartTime = DateTime.now();
        _startUptimeCounter();
        // The tunnel is live, so this config is working by definition. Without
        // this the library badge kept whatever a failed probe had stored and
        // read "Failed" under an active tunnel.
        try {
          Get.find<ConfigController>().markConnected(config);
        } catch (_) {
          // ConfigController not registered yet (early boot) - not fatal.
        }
        _fetchConnectedIP();
        lastKnownWorkingConfig.value = config;

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
        statusMessage.value =
            vpnService.lastError ?? LocalizationService.t('Failed to connect');
        debugService.logAction('connect_failed', {
          'config': config.displayName,
          'reason': vpnService.lastError ?? 'unknown',
        });
        return false;
      }
    } catch (e) {
      state.value = ConnectionState.error;
      statusMessage.value =
          LocalizationService.t('status_connection_error', {'error': '$e'});
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
      _engineAvailability.value ??= await vpnService.getEngineInfo();
    } catch (e) {
      _log.w('Engine capability probe failed, testing all configs: $e');
      return configs;
    }

    final availability = _engineAvailability.value!;
    if (!availability.isKnown) return configs;

    final servable =
        configs.where((c) => availability.canConnect(c.protocol)).toList();
    final skipped = configs.length - servable.length;
    if (skipped > 0) {
      _log.i('Skipped $skipped config(s) with no bundled engine');
    }
    return servable;
  }

  /// True when a bundled engine can serve [protocol].
  ///
  /// Fails open: until the capability probe has answered, everything is
  /// reported as supported, because refusing a connect that might have worked
  /// is worse than letting the native layer say no.
  bool isProtocolSupported(String protocol) {
    final availability = _engineAvailability.value;
    if (availability == null || !availability.isKnown) return true;
    return availability.canConnect(protocol);
  }

  /// Runs the engine capability probe if it has not answered yet.
  ///
  /// The library calls this so its tiles can grey out protocols this build
  /// cannot run *before* the user taps Connect and gets a red error for
  /// something the app already knew.
  Future<void> ensureEngineAvailability() async {
    if (_engineAvailability.value != null) return;
    try {
      _engineAvailability.value = await vpnService.getEngineInfo();
    } catch (e) {
      _log.w('Engine capability probe failed: $e');
    }
  }

  /// Returns a human-readable refusal when no bundled engine can serve
  /// [config]'s protocol, or null when the attempt should go ahead.
  ///
  /// Fails open on purpose: if the capability probe itself errors we return
  /// null and let the native layer produce the real diagnostic, rather than
  /// blocking a connection that might have worked.
  Future<String?> _engineRefusal(Config config) async {
    try {
      _engineAvailability.value ??= await vpnService.getEngineInfo();
    } catch (e) {
      _log.w('Engine capability probe failed, continuing: $e');
      return null;
    }

    // Transports the bundled Xray core has no package for. It resolves the
    // transport by name at start-up, so a config carrying one of these fails
    // with "Xray core rejected the configuration" - after the consent dialog
    // and after a wasted probe. The core's transport/internet packages are
    // grpc, httpupgrade, hysteria, kcp, reality, splithttp, tcp, tls, udp and
    // websocket; there is no quic and no http (h2).
    // Plaintext VLESS (security: none) to a raw public IP without a domain host
    // is refused upfront because Xray-core strictly prohibits it for security
    // (it leaks the UUID in cleartext over the wire).
    if (config is VlessConfig &&
        (config.security.isEmpty || config.security.toLowerCase() == 'none')) {
      final addr = config.address.trim();
      final isIp =
          RegExp(r'^\d+\.\d+\.\d+\.\d+$').hasMatch(addr) || addr.contains(':');
      final isPrivate = addr.startsWith('10.') ||
          addr.startsWith('192.168.') ||
          addr.startsWith('127.') ||
          addr.startsWith('172.16.') ||
          addr.startsWith('172.17.') ||
          addr.startsWith('172.18.') ||
          addr.startsWith('172.19.') ||
          addr.startsWith('172.2') ||
          addr.startsWith('172.30.') ||
          addr.startsWith('172.31.') ||
          addr == 'localhost';
      final hasDomainHost = config.host != null &&
          config.host!.isNotEmpty &&
          !RegExp(r'^\d+\.\d+\.\d+\.\d+$').hasMatch(config.host!);
      if (isIp && !isPrivate && !hasDomainHost) {
        return LocalizationService.t('vless_plaintext_public_ip_refusal');
      }
    }

    final network = switch (config) {
      VlessConfig c => c.network,
      VmessConfig c => c.network,
      TrojanConfig c => c.network,
      _ => null,
    };
    if (network == 'quic' || network == 'http' || network == 'h2') {
      return "'$network' transport is not supported by the bundled core. "
          'Use a ws, grpc, httpupgrade or xhttp link instead.';
    }

    final availability = _engineAvailability.value!;
    if (!availability.isKnown) return null;
    if (availability.canConnect(config.protocol)) return null;

    final supported = availability.supportedProtocols;
    final supportedLabel = supported.isEmpty
        ? 'none'
        : supported.map((p) => p.toUpperCase()).join(', ');
    return "'${config.protocol}' cannot be dialled by this build: no engine that "
        'serves it is bundled. Supported here: $supportedLabel.';
  }

  /// Disconnect from VPN
  Future<bool> disconnect() async {
    if (_operationInFlight) {
      _log.w('Disconnect ignored: another operation is already running');
      return false;
    }
    _operationInFlight = true;
    try {
      return await _disconnectImpl();
    } finally {
      _operationInFlight = false;
    }
  }

  Future<bool> _disconnectImpl() async {
    try {
      state.value = ConnectionState.disconnecting;
      statusMessage.value = LocalizationService.t('status_disconnecting');
      // Invalidate in-flight exit-IP lookups. _fetchConnectedIP captures this
      // token and refuses to write its result if it changed - but nothing ever
      // changed it, so the only guard left was `!isConnected`, which a quick
      // reconnect defeats: the old lookup could land on the new session.
      _sessionEpoch++;

      _stopUptimeCounter();

      // Nothing to unwind here: split tunneling, DNS and the kill switch all
      // live inside the tunnel itself, so closing the interface releases them.
      // The previous code called deactivate() on three channels that had no
      // native handler.

      final success = await vpnService.disconnect();

      if (success) {
        state.value = ConnectionState.idle;
        statusMessage.value = LocalizationService.t('status_disconnected');
        selectedConfig.value = null;
        selectedConfigResult.value = null;
        connectedIP.value = null;
        exitIpInfo.value = null;
        connectionUptime.value = 0;
        _connectionStartTime = null;
        isDnsOnly.value = false;
        debugService.logInfo('VPN disconnected');
        debugService.logAction('disconnected');
        // Unawaited: the home row refreshes in the background.
        refreshHomeIpInfo();
        return true;
      } else {
        state.value = ConnectionState.error;
        statusMessage.value = LocalizationService.t('status_failed_disconnect');
        return false;
      }
    } catch (e) {
      state.value = ConnectionState.error;
      statusMessage.value =
          LocalizationService.t('status_disconnect_error', {'error': '$e'});
      _log.e('Error disconnecting: $e');
      return false;
    }
  }

  /// Reconnect to current config
  Future<bool> reconnect() async {
    // Shares the single-flight guard with connect/disconnect: a second tap
    // used to start a parallel disconnect+connect pair, and two sequences
    // fought over the tunnel and the UI state.
    if (_operationInFlight) {
      _log.w('Reconnect ignored: another operation is already running');
      return false;
    }
    _operationInFlight = true;
    try {
      // Capture the selection BEFORE disconnecting: disconnect() clears
      // selectedConfig, so reading it afterwards dereferenced null and every
      // successful disconnect-then-reconnect threw instead of reconnecting.
      final target = selectedConfig.value;
      if (target == null) {
        _log.w('No config to reconnect to');
        return false;
      }

      final success = await _disconnectImpl();
      if (!success) return false;

      await Future.delayed(const Duration(milliseconds: 500));
      return await _connectImpl(target);
    } finally {
      _operationInFlight = false;
    }
  }

  /// Test current connection
  Future<bool> testConnection() async {
    if (selectedConfig.value == null) {
      _log.w('No active connection to test');
      return false;
    }

    try {
      state.value = ConnectionState.testing;
      statusMessage.value = LocalizationService.t('status_testing_connection');

      final result = await testerService.testConfig(selectedConfig.value!);
      selectedConfigResult.value = result;

      if (result.isWorking) {
        state.value = ConnectionState.connected;
        // Report the real measured figure. Throughput is not measured by the
        // tester, so the previous "Connected (43.2Mbps)" was fabricated.
        statusMessage.value = result.latencyMs != null
            ? LocalizationService.t('Connected (@ms ms to the server)',
                {'ms': '${result.latencyMs}'})
            : LocalizationService.t('status_connected');
        return true;
      } else {
        state.value = ConnectionState.error;
        statusMessage.value =
            LocalizationService.t('status_connection_test_failed');
        return false;
      }
    } catch (e) {
      state.value = ConnectionState.error;
      statusMessage.value =
          LocalizationService.t('status_test_error', {'error': '$e'});
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

      debugService.logInfo(
          'DNS leak prevention: ${dnsLeakPreventionService.describe()}');
      if (next && isConnected) {
        statusMessage.value = LocalizationService.t('status_dns_applies');
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
        statusMessage.value = LocalizationService.t(
            'For full protection, set this app as always-on VPN and enable "Block connections without VPN" in system settings.');
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

      debugService
          .logInfo('Split tunneling: ${splitTunnelingService.describe()}');
      if (next && isConnected) {
        statusMessage.value = LocalizationService.t('status_split_applies');
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

  /// Start a DNS-only session: change the resolver, route nothing.
  ///
  /// The tunnel's DNS is otherwise a builder-time decision that requires a
  /// config and a server. Someone who only wants a different resolver had no
  /// way to get one, so this path takes the same resolvers and establishes an
  /// interface with no routes and no engine: traffic stays direct, name
  /// lookups move.
  Future<bool> connectDnsOnly() async {
    // selectedResolvers, not resolvers: the latter answers 1.1.1.1 while the
    // leak-prevention toggle is off, which is exactly the case DNS-only mode
    // exists for.
    final resolvers = dnsLeakPreventionService.selectedResolvers
        .where(VpnSessionOptions.isTunnelDns)
        .toList();
    if (resolvers.isEmpty) {
      state.value = ConnectionState.error;
      statusMessage.value = LocalizationService.t('dns_only_needs_resolver');
      return false;
    }

    state.value = ConnectionState.connecting;
    _sessionEpoch++;
    isDnsOnly.value = true;
    statusMessage.value =
        '${LocalizationService.t('connecting')} ${resolvers.join(', ')}';

    final prepared = await vpnService.prepare();
    if (!prepared) {
      state.value = ConnectionState.error;
      isDnsOnly.value = false;
      statusMessage.value = vpnService.lastError ??
          LocalizationService.t('status_permission_denied');
      return false;
    }

    final ok = await vpnService.connectDnsOnly(resolvers);
    if (!ok) {
      state.value = ConnectionState.error;
      isDnsOnly.value = false;
      statusMessage.value = vpnService.lastError ??
          LocalizationService.t('dns_only_needs_resolver');
      return false;
    }

    state.value = ConnectionState.connected;
    statusMessage.value = LocalizationService.t('dns_only_started');
    _connectionStartTime = DateTime.now();
    _startUptimeCounter();
    debugService.logInfo('DNS-only session: ${resolvers.join(", ")}');
    return true;
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

  /// Resolves the exit address through the tunnel, retrying briefly.
  ///
  /// A fresh tunnel is not instantly usable: hysteria2/TUIC still have to
  /// finish their QUIC handshake, so the very first SOCKS dial can fail. One
  /// shot at connect time left the location stuck on "resolving..." for the
  /// whole session.
  Future<void> _fetchConnectedIP() async {
    final service = ipInfoService;
    // A lookup can take seconds (QUIC handshake + HTTPS round trip). If the
    // user reconnects or disconnects meanwhile, this coroutine must not write
    // its result over the newer session's state - so every write is gated on
    // the session token captured when the lookup started.
    final epoch = _sessionEpoch;
    bool stale() => epoch != _sessionEpoch || !isConnected;

    const attempts = 6;
    for (var attempt = 1; attempt <= attempts; attempt++) {
      if (stale()) return; // torn down or superseded mid-flight
      try {
        final ip = await vpnService.getConnectedIP();
        if (stale()) return;
        if (ip != null && ip.isNotEmpty) {
          connectedIP.value = ip;
          if (service != null) {
            final info = await service.fetchExit();
            if (stale()) return;
            if (!info.isEmpty) {
              exitIpInfo.value = info;
              return;
            }
          } else {
            return;
          }
        }
      } catch (e) {
        _log.w('Exit lookup attempt $attempt/$attempts failed: $e');
      }
      // 1s, 2s, 3s, 4s, 5s - long enough for the upstream handshake.
      await Future<void>.delayed(Duration(seconds: attempt));
    }
    if (stale()) return;
    _log.w('Exit lookup gave up after $attempts attempts');
  }
}
