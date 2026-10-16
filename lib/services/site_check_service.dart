/// Site check: verifies a candidate config by fetching real websites
/// *through* it.
///
/// ## Why a TCP probe is not enough
///
/// `TesterService` times a TCP handshake to the config's server. That proves
/// the network path exists — it does NOT prove the config can carry traffic:
/// wrong credentials, a mangled UUID, a REALITY key mismatch or a censor
/// black-holing the exit can all leave the handshake green while every real
/// connection dies inside the core. The beta.11–beta.13 device logs were full
/// of exactly that shape.
///
/// ## How the check works
///
/// For one candidate config at a time:
///
///     XrayConfigBuilder(tunEnabled: false)  → SOCKS-only config, no tun fd
///     probeStart                            → headless core, no VpnService,
///                                             no consent dialog, no routing
///     probeSites                            → HTTPS GET each check host
///                                             through 127.0.0.1:<socksPort>
///     probeStop                             → core torn down
///
/// The device's network is never routed through the probe: it is a plain
/// local proxy, so a misbehaving candidate cannot black-hole the phone.
///
/// ## What a "pass" means
///
/// Any HTTP response through the tunnel counts as reachable — even a 403 or
/// a 302 proves the round trip to the exit and back works. Only connect
/// failures and timeouts count against the config.
///
/// ## Cost model
///
/// Spinning a core instance per candidate is expensive (~1–2 s startup plus
/// the fetches), so the check runs on a *shortlist* — the fastest few
/// configs that already passed the TCP probe — not on every config. With the
/// site check disabled in settings the flow degrades to pure TCP ranking.
library;

import 'package:logger/logger.dart';

import '../controllers/settings_controller.dart';
import '../models/config.dart';
import '../models/test_result.dart';
import 'vpn_service.dart';
import 'xray_config.dart';

/// Result of fetching one host through the probe tunnel.
class SiteCheckOutcome {
  final String host;
  final bool ok;
  final int? statusCode;
  final int? latencyMs;
  final String? error;

  const SiteCheckOutcome({
    required this.host,
    required this.ok,
    this.statusCode,
    this.latencyMs,
    this.error,
  });

  factory SiteCheckOutcome.fromMap(Map<String, dynamic> map) => SiteCheckOutcome(
        host: map['host'] as String? ?? '',
        ok: map['ok'] == true,
        statusCode: map['statusCode'] as int?,
        latencyMs: map['latencyMs'] as int?,
        error: map['error'] as String?,
      );
}

/// Aggregated result of checking one config against the host list.
class SiteCheckReport {
  final String configHash;

  /// Hosts that answered through the tunnel.
  final int reachable;

  /// Hosts attempted.
  final int total;

  /// Best observed latency across reachable hosts, null when none answered.
  final int? bestLatencyMs;

  final List<SiteCheckOutcome> outcomes;

  /// False when the check could not run at all (engine refused the config,
  /// the live tunnel was up, the platform channel is missing). A report with
  /// `supported == false` must never disqualify a config — the check is an
  /// improvement on the TCP probe, not a gate that can break connecting.
  final bool supported;

  const SiteCheckReport({
    required this.configHash,
    required this.reachable,
    required this.total,
    this.bestLatencyMs,
    this.outcomes = const [],
    this.supported = true,
  });

  /// 1.0 when every host answered, 0.0 when none did.
  double get passRatio => total == 0 ? 0 : reachable / total;

  /// True when at least half the hosts (and at least one) answered.
  bool get isUsable => reachable > 0 && passRatio >= 0.5;
}

/// Runs the site check for candidate configs through a headless core.
class SiteCheckService {
  final VPNService _vpnService;
  final SettingsController _settings;
  final Logger _log;

  /// How many TCP-passing candidates get the (expensive) site check.
  static const int defaultShortlistSize = 3;

  /// Per-URL timeout. Generous: a slow exit that answers in 8 s still works
  /// for browsing, unlike the 4 s TCP probe where a slow handshake already
  /// disqualifies the server.
  static const Duration defaultUrlTimeout = Duration(seconds: 10);

  SiteCheckService({
    required VPNService vpnService,
    required SettingsController settings,
    Logger? logger,
  })  : _vpnService = vpnService,
        _settings = settings,
        _log = logger ?? Logger();

  bool get enabled => _settings.siteCheckEnabled.value;

  /// Hosts used for live verification (empty when the stage is disabled).
  /// Capped: the live check runs on the connect critical path and four
  /// hosts are enough to distinguish "tunnel carries traffic" from
  /// "notification says connected, nothing loads".
  static const int maxLiveCheckHosts = 4;

  List<String> get liveCheckHosts =>
      _settings.siteCheckUrls.take(maxLiveCheckHosts).toList();

  /// Verifies the CURRENTLY CONNECTED tunnel by fetching [liveCheckHosts]
  /// through its loopback SOCKS inbound (port 10808).
  ///
  /// This is the missing feedback loop: a config can pass every pre-connect
  /// probe and still black-hole real traffic once the TUN interface is up.
  /// Dialing the live tunnel's own SOCKS port answers the only question that
  /// matters — does this tunnel, right now, move traffic to the wider web?
  ///
  /// Returns true when at least one host answered, and true vacuously when
  /// the site check is disabled (the user opted out of verification).
  Future<bool> verifyLiveConnection({
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final hosts = liveCheckHosts;
    if (hosts.isEmpty) return true;
    try {
      final outcomes = await _vpnService.probeSites(
        VPNService.defaultSocksPort,
        hosts,
        timeout: timeout,
      );
      final reachable = outcomes.where((o) => o['ok'] == true).length;
      _log.i('Live tunnel check: $reachable/${hosts.length} hosts reachable');
      return reachable > 0;
    } catch (e) {
      // A failed verification probe must not itself break the connection
      // flow — but it also must not bless a dead tunnel. Treat the check as
      // failed so the caller falls through to the next candidate.
      _log.w('Live tunnel check errored: $e');
      return false;
    }
  }

  /// Checks [configs] (already TCP-verified, fastest first) and returns a
  /// report per config, in input order. Returns an empty map when the check
  /// is disabled, the list is empty, or every candidate is a non-Xray
  /// protocol (the headless probe is Xray-only today).
  Future<Map<String, SiteCheckReport>> checkConfigs(
    List<Config> configs, {
    int shortlistSize = defaultShortlistSize,
    Duration urlTimeout = defaultUrlTimeout,
  }) async {
    final shortlist = configs
        .where((c) => isXrayProtocol(c.protocol))
        .take(shortlistSize)
        .toList();
    if (!enabled || shortlist.isEmpty) return const {};

    final hosts = _settings.siteCheckUrls.toList();
    if (hosts.isEmpty) return const {};

    final reports = <String, SiteCheckReport>{};
    for (final config in shortlist) {
      reports[config.getHash()] = await _checkOne(
        config,
        hosts,
        urlTimeout: urlTimeout,
      );
    }
    return reports;
  }

  Future<SiteCheckReport> _checkOne(
    Config config,
    List<String> hosts, {
    required Duration urlTimeout,
  }) async {
    final hash = config.getHash();

    // A free-ish port far from the live tunnel's 10808; if something is
    // already listening there the core fails to start and the report below
    // degrades to unsupported rather than blocking the flow.
    const probePort = 10809;

    final probeConfig = XrayConfigBuilder(
      socksPort: probePort,
      tunEnabled: false,
    ).buildJson(config);

    final started = await _vpnService.probeStart(probeConfig);
    if (!started) {
      _log.w('Site check: probe core refused config ${config.displayName}: '
          '${_vpnService.lastError}');
      return SiteCheckReport(
        configHash: hash,
        reachable: 0,
        total: hosts.length,
        supported: false,
      );
    }

    try {
      final outcomes = (await _vpnService.probeSites(
        probePort,
        hosts,
        timeout: urlTimeout,
      ))
          .map(SiteCheckOutcome.fromMap)
          .toList();
      final reachable = outcomes.where((o) => o.ok).toList();
      final best = reachable.isEmpty
          ? null
          : reachable
              .map((o) => o.latencyMs ?? 1 << 30)
              .reduce((a, b) => a < b ? a : b);
      _log.i('Site check ${config.displayName}: '
          '${reachable.length}/${hosts.length} hosts reachable');
      return SiteCheckReport(
        configHash: hash,
        reachable: reachable.length,
        total: hosts.length,
        bestLatencyMs: best == 1 << 30 ? null : best,
        outcomes: outcomes,
      );
    } finally {
      // The probe core must never outlive the check, even if the fetches
      // throw — a stray headless core holds its SOCKS port forever.
      await _vpnService.probeStop();
    }
  }

  /// Picks the best of [results] using the site-check reports as the primary
  /// signal and TCP latency as the tie-break.
  ///
  /// Order of preference:
  ///  1. checked and usable (≥ half the hosts answered), most reachable first
  ///  2. checked but poor — still ahead of unchecked, because we *know* it is
  ///     weak while unchecked is a coin flip
  ///  3. unchecked (check unsupported/disabled) — pure TCP latency order
  ///
  /// Returns the winning [TestResult], or null when [results] is empty.
  static TestResult? pickBest(
    List<TestResult> results,
    List<Config> configs,
    Map<String, SiteCheckReport> reports,
  ) {
    if (results.isEmpty) return null;

    Config? configFor(TestResult r) {
      final hash = r.configHash;
      for (final c in configs) {
        if (c.getHash() == hash) return c;
      }
      return null;
    }

    int score(TestResult r) {
      final report = reports[r.configHash];
      if (report == null || !report.supported) return 0;
      if (!report.isUsable) return 1;
      return 2;
    }

    TestResult? best;
    for (final r in results) {
      if (best == null) {
        best = r;
        continue;
      }
      final sNew = score(r);
      final sBest = score(best);
      final better = sNew != sBest
          ? sNew > sBest
          : _latencyOf(r, reports) < _latencyOf(best, reports);
      if (better) best = r;
    }

    // Guard the (theoretically impossible) case of a result whose config
    // vanished from the candidate list mid-flight.
    if (best == null || configFor(best) == null) return null;
    return best;
  }

  static int _latencyOf(
    TestResult result,
    Map<String, SiteCheckReport> reports,
  ) {
    // Prefer the site-check latency when we have one: it is measured through
    // the tunnel, which is what the user actually experiences.
    final report = reports[result.configHash];
    final checked = report?.bestLatencyMs;
    if (checked != null) return checked;
    final tcp = result.latencyMs;
    return tcp ?? 1 << 30;
  }
}
