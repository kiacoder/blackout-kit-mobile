/// Config controller using GetX for state management.
/// Manages loading, filtering, testing, and ranking of VPN configs.

import 'dart:async';

import 'package:get/get.dart';
import 'package:logger/logger.dart';
import '../models/config.dart';
import '../models/config_source.dart';
import '../models/test_result.dart';
import '../services/config_service.dart';
import '../services/github_service.dart';
import 'connection_controller.dart';
import '../services/tester_service.dart';
import '../services/debug_service.dart';

class ConfigController extends GetxController {
  final ConfigService configService;
  final GitHubService githubService;
  final TesterService testerService;
  final Logger _log;

  // Observable state
  final RxList<Config> allConfigs = RxList<Config>();

  /// Hash → sourceId for every stored config. Lets [visibleConfigs] hide
  /// configs whose source is disabled without touching stored records.
  final RxMap<String, String> sourceIdByHash = RxMap<String, String>();

  /// hash -> every source that supplied it. A config stays visible while ANY
  /// of its sources is enabled; the single-id map remains for display.
  final RxMap<String, Set<String>> sourceIdsByHash = <String, Set<String>>{}.obs;

  /// hash → savedAt, for the "recently added" ordering.
  final RxMap<String, DateTime> savedAtByHash = <String, DateTime>{}.obs;

  /// Configs currently being single-tested (hashes), for progress states.
  final RxSet<String> testingHashes = RxSet<String>();
  final RxList<ConfigSource> sources = RxList<ConfigSource>();
  final RxMap<String, TestResult> testResults = RxMap<String, TestResult>();
  final RxList<ConfigRanking> rankings = RxList<ConfigRanking>();

  final RxBool isLoading = RxBool(false);

  /// Network refresh / testing in flight. Kept apart from [isLoading] on
  /// purpose: the library used to show a full-screen "Loading repositories &
  /// configs..." spinner whenever ANY network work ran — including the startup
  /// refresh and the reachability tests — so opening the Library mid-startup
  /// hid the whole stored list behind a spinner for minutes. The list should
  /// render stored configs immediately; refresh progress is a banner.
  final RxBool isRefreshing = RxBool(false);
  final RxString refreshStatus = RxString('');

  /// Refcount under [isRefreshing]: several sources fetch concurrently and
  /// each one would otherwise clear the flag the moment it finishes.
  int _refreshCount = 0;

  void _refreshBegin([String? status]) {
    _refreshCount++;
    isRefreshing.value = true;
    if (status != null) refreshStatus.value = status;
  }

  void _refreshEnd() {
    _refreshCount = (_refreshCount - 1).clamp(0, 1 << 30);
    if (_refreshCount == 0) {
      isRefreshing.value = false;
      refreshStatus.value = '';
    }
  }
  final RxString filterProtocol = RxString('all');
  final RxString filterSource = RxString('all');
  final RxString sortBy = RxString('speed'); // speed, name, recently_added

  /// How many rows the library renders at a time.
  ///
  /// A real source returns thousands of configs. `ListView.builder` is lazy, but
  /// the *list* it is handed still had to be produced in full, and the screen
  /// rebuilt it on every Obx tick — including a full sort. The library now
  /// renders a window and grows it on demand.
  static const int configPageSize = 50;
  final RxInt visibleConfigLimit = RxInt(configPageSize);

  /// Cache for [getFilteredConfigs]. Bumped whenever the inputs that are not
  /// observables change (the config list itself, or the test results that drive
  /// the "speed" ordering).
  int _filterEpoch = 0;
  String? _filteredCacheKey;
  List<Config> _filteredCache = const [];

  void _invalidateFilterCache() => _filterEpoch++;

  /// Last `testedAt` written per config hash, so a persist pass only touches
  /// rows that actually changed. Also what makes the write pass idempotent.
  final Map<String, DateTime?> _persistedTestedAt = {};

  /// Hashes changed since the last flush.
  final Set<String> _pendingPersist = {};

  Timer? _persistTimer;

  /// Coalesces a burst of result changes (a scan updates one per config) into
  /// a single write pass. Without the delay each measurement triggered a pass.
  void _scheduleResultPersist() {
    _persistTimer?.cancel();
    _persistTimer = Timer(const Duration(milliseconds: 750), _flushResultPersist);
  }

  void _flushResultPersist() {
    final hashes = _pendingPersist.toList(growable: false);
    _pendingPersist.clear();
    for (final hash in hashes) {
      final result = testResults[hash];
      if (result == null) continue;
      _persistedTestedAt[hash] = result.testedAt;
      configService.saveTestResult(result);
    }
  }

  @override
  void onClose() {
    // Anything still queued must reach disk: the app may be closing.
    _persistTimer?.cancel();
    _flushResultPersist();
    super.onClose();
  }

  /// Marks [config] as working because the tunnel carrying it came up.
  ///
  /// The library badge is fed by [testResults], and nothing used to write a
  /// result on connect - so a config whose probe had failed once kept showing
  /// "✗ Failed" while it was actively carrying traffic. Existing latency and
  /// speed measurements are preserved; only the status is upgraded.
  void markConnected(Config config) {
    final hash = config.getHash();
    final existing = testResults[hash];
    testResults[hash] = existing == null
        ? TestResult.success(configHash: hash)
        : TestResult(
            configHash: hash,
            status: TestStatus.success,
            testedAt: DateTime.now(),
            latencyMs: existing.latencyMs,
            speedMbps: existing.speedMbps,
            successCount: existing.successCount,
            totalCount: existing.totalCount,
          );
    _invalidateFilterCache();
    _log.i('Marked ${config.displayName} as working (connected)');
  }

  /// Grows the visible window of the library list.
  void showMoreConfigs() => visibleConfigLimit.value += configPageSize;

  ConfigController({
    required this.configService,
    required this.githubService,
    required this.testerService,
    Logger? logger,
  }) : _log = logger ?? Logger();

  @override
  Future<void> onInit() async {
    super.onInit();

    // Anything that changes the config list or the measurements behind the
    // "speed" ordering invalidates the memoised filtered list. Watching the
    // observables covers every write path — loadConfigs, the testers, deletes —
    // without each of them having to remember to invalidate by hand.
    ever(allConfigs, (_) => _invalidateFilterCache());
    ever(testResults, (_) => _invalidateFilterCache());
    // visibleConfigs also depends on which sources are enabled, and toggling a
    // source replaces the list without touching allConfigs - so the cached
    // filter result kept showing a disabled repository's configs until some
    // unrelated change happened to invalidate it.
    ever(sources, (_) => _invalidateFilterCache());

    // Persist measurements so a restart does not wipe the tester back to
    // "Untested" for thousands of servers (and connectFastest back to probing
    // blind).
    //
    // This used to write EVERY result on EVERY change. A scan updates one
    // result per config, so with thousands of configs that is one full Hive
    // write pass per measurement - quadratic, and it made the scan crawl. Now
    // only results whose testedAt actually changed are written, and bursts are
    // coalesced into a single pass.
    ever(testResults, (Map<String, TestResult> results) {
      var dirty = false;
      for (final entry in results.entries) {
        final saved = _persistedTestedAt[entry.key];
        if (saved != entry.value.testedAt) {
          _pendingPersist.add(entry.key);
          dirty = true;
        }
      }
      if (dirty) _scheduleResultPersist();
    });

    _log.i('ConfigController initialized');

    // Hydrate stored measurements before the config list so the UI renders
    // with results on the very first frame.
    final stored = configService.loadTestResults();
    if (stored.isNotEmpty) {
      // Mark them as persisted up front, otherwise the first change would
      // rewrite every restored row.
      for (final entry in stored.entries) {
        _persistedTestedAt[entry.key] = entry.value.testedAt;
      }
      testResults.addAll(stored);
      _log.i('Restored ${stored.length} stored test results');
    }

    // Load existing data
    await loadConfigs();
    await loadSources();
  }

  /// Load all configs from storage
  Future<void> loadConfigs() async {
    try {
      isLoading.value = true;
      final configs = configService.getAllConfigs();
      allConfigs.value = configs;
      sourceIdByHash.value = configService.loadHashToSource();
      sourceIdsByHash.value = configService.loadHashToSourceIds();
      savedAtByHash.value = configService.loadHashToSavedAt();
      _log.i('Loaded ${configs.length} configs');
    } catch (e) {
      _log.e('Error loading configs: $e');
    } finally {
      isLoading.value = false;
    }
  }

  /// Configs whose source is currently enabled (manual configs — no source —
  /// are always visible).
  ///
  /// Disabling a repository in Settings hides its configs from the library,
  /// the scanner and all testing, but the stored records are untouched:
  /// re-enabling the source brings every config straight back.
  List<Config> get visibleConfigs {
    final enabled = sources.where((s) => s.isEnabled).map((s) => s.id).toSet();
    return allConfigs.where((c) {
      final hash = c.getHash();
      final ids = sourceIdsByHash[hash];
      if (ids == null || ids.isEmpty) return true;
      return ids.any(enabled.contains);
    }).toList();
  }

  /// Load all sources
  ///
  /// Stored state must win over the built-in defaults. The old code merged
  /// `[...trusted, ...stored]` and then de-duplicated keeping the *first*
  /// occurrence, so the hardcoded default — which always has `isEnabled: true`
  /// — silently overwrote whatever the user had saved. Turning a repository off
  /// in Settings therefore did nothing: the toggle snapped back on the next
  /// load. Built-in sources are still listed when disabled (they used to vanish
  /// entirely, because `TrustedSources.getEnabled()` filtered them out), so the
  /// switch has something to render in its off position.
  Future<void> loadSources() async {
    try {
      // `trusted-1` / `trusted-2` were the original placeholder sources and
      // point at repositories that have never existed. They were persisted to
      // storage by the first fetch, so an upgraded install would otherwise keep
      // showing two permanently dead entries alongside the real ones.
      const retiredIds = {'trusted-1', 'trusted-2'};

      final stored = <String, ConfigSource>{};
      for (final s in configService.getAllSources()) {
        if (retiredIds.contains(s.id)) {
          await configService.deleteSource(s.id);
          continue;
        }
        stored[s.id] = s;
      }

      final merged = <ConfigSource>[
        // Built-in sources, with the user's own state substituted where it
        // exists.
        for (final defaultSource in TrustedSources.sources)
          stored[defaultSource.id] ?? defaultSource,
        // Anything the user added themselves.
        ...stored.values.where((s) => !TrustedSources.ids.contains(s.id)),
      ];

      sources.value = merged;
      _log.i('Loaded ${merged.length} sources');
    } catch (e) {
      _log.e('Error loading sources: $e');
    }
  }

  /// Enable or disable a source and persist the choice.
  ///
  /// The rebuild assigns a new list to `sources.value` rather than mutating in
  /// place, so the `Obx` around the switch is guaranteed to repaint.
  Future<void> toggleSource(String sourceId, bool enabled) async {
    final index = sources.indexWhere((s) => s.id == sourceId);
    if (index == -1) {
      _log.w('toggleSource: no source with id $sourceId');
      return;
    }

    final updated = sources[index].copyWith(isEnabled: enabled);
    final next = List<ConfigSource>.of(sources);
    next[index] = updated;
    sources.value = next;

    await configService.saveSource(updated);
    _log.i('${enabled ? 'Enabled' : 'Disabled'} source: ${updated.name}');
    _action(
      enabled ? 'source_enabled' : 'source_disabled',
      {'source': updated.name},
    );
  }

  /// Best-effort action logging: ConfigController has no injected
  /// DebugService, and logging must never break the action itself.
  void _action(String action, [Map<String, dynamic>? details]) {
    try {
      final debug = Get.find<DebugService>();
      debug.logAction(action, details);
    } catch (_) {}
  }

  /// Fetch configs from a source and save to local storage
  Future<int> fetchFromSource(ConfigSource source) async {
    try {
      _refreshBegin('Fetching ${source.name}...');
      _log.i('Fetching from ${source.name}');

      final configs = await githubService.fetchConfigsFromSource(source);
      final saved = await configService.saveConfigs(
        configs,
        sourceId: source.id,
      );

      // Update source with config count (and clear any previous failure).
      final updated = source.copyWith(
        configCount: saved,
        lastFetched: DateTime.now(),
        clearError: true,
      );
      await configService.saveSource(updated);
      // Keep the in-memory list in step with the saved source, so a source
      // that just failed does not keep showing its old error afterwards.
      final sourceIndex = sources.indexWhere((s) => s.id == source.id);
      if (sourceIndex != -1) {
        final nextSources = List<ConfigSource>.of(sources);
        nextSources[sourceIndex] = updated;
        sources.value = nextSources;
      }

      // Reload configs
      await loadConfigs();

      // An honest update message: `saved` counts only NEW configs (duplicates
      // are coalesced by hash), so "saved 0" is a normal no-change refresh,
      // not a failure — and the old UI either said nothing or implied a big
      // update had landed.
      refreshStatus.value = saved > 0
          ? '${source.name}: +$saved new config(s)'
          : '${source.name}: up to date (no new configs)';
      _action('source_fetched', {
        'source': source.name,
        'fetched': configs.length,
        'new': saved,
      });

      _log.i('Saved $saved configs from ${source.name}');
      return saved;
    } catch (e) {
      _log.e('Error fetching from source: $e');
      // Record the failure on the source so the Library can tell "every fetch
      // failed" apart from "there are no configs" — the screen used to render
      // the same empty state for both and the user had no way to see why the
      // list was blank (or that a retry might help).
      final reason = e.toString();
      final failed = source.copyWith(
        error: reason.length > 120 ? '${reason.substring(0, 120)}…' : reason,
      );
      await configService.saveSource(failed);
      final index = sources.indexWhere((s) => s.id == source.id);
      if (index != -1) {
        final next = List<ConfigSource>.of(sources);
        next[index] = failed;
        sources.value = next;
      }
      return 0;
    } finally {
      _refreshEnd();
    }
  }

  /// Fetch from all enabled sources.
  ///
  /// Sources run concurrently: each one costs up to a couple of dozen HTTP
  /// round-trips when its candidate filenames miss, and running them one after
  /// another turned a single slow/unreachable host into minutes of loading.
  Future<int> fetchFromAllSources({bool force = false}) async {
    final targets = sources
        .where((s) => s.isEnabled && (force || s.needsRefresh))
        .toList();
    if (targets.isEmpty) return 0;

    _refreshBegin('Updating ${targets.length} source(s)...');
    try {
      final saved = await Future.wait(
        targets.map((source) => fetchFromSource(source)),
      );
      return saved.fold<int>(0, (sum, n) => sum + n);
    } finally {
      _refreshEnd();
    }
  }

  /// Test configs, bounded and concurrent.
  ///
  /// `TesterService.testConfigs` probes strictly one at a time, at up to
  /// 4s x 3 attempts = 12s for an unreachable host. While the built-in sources
  /// 404'd that never mattered because there was nothing to test. With a real
  /// source the first fetch yields ~7.6k configs, so a cold start would have
  /// blocked for hours on the home screen. `testConfigsConcurrently` was
  /// written for this case but never wired up; [limit] additionally bounds the
  /// sample so startup stays responsive.
  Future<void> testAllConfigs({int limit = 150, int concurrency = 8}) async {
    try {
      _refreshBegin('Testing configs...');
      final toTest = visibleConfigs.take(limit).toList();
      _log.i('Testing ${toTest.length} of ${allConfigs.length} configs '
          '(${visibleConfigs.length} visible)');
      _action('batch_test_started', {'configs': toTest.length});

      final results = await testerService.testConfigsConcurrently(
        toTest,
        concurrency: concurrency,
      );

      // Store results in ONE mutation: the persistence watcher below saves
      // on every map change, so per-result puts would trigger O(n²) Hive
      // writes across the batch.
      testResults.addAll({for (final r in results) r.configHash: r});

      // Calculate rankings
      final rankings = testerService.rankConfigs(results);
      this.rankings.value = rankings;

      _log.i('Tested ${results.length} configs');
    } catch (e) {
      _log.e('Error testing configs: $e');
    } finally {
      _refreshEnd();
    }
  }

  /// Test single config
  Future<void> testConfig(Config config) async {
    try {
      final result = await testerService.testConfig(config);
      testResults[config.getHash()] = result;
      _log.i('Tested ${config.displayName}');
    } catch (e) {
      _log.e('Error testing config: $e');
    }
  }

  /// Get filtered configs based on active filters.
  ///
  /// Memoised: this runs inside an `Obx` build, so it used to re-copy, re-filter
  /// and re-sort the entire list on every rebuild — thousands of entries, on
  /// every tick of `isLoading`, every stored test result, every filter change.
  /// The result only actually changes when the config list, the test results or
  /// a filter does, so it is cached against those and invalidated explicitly.
  List<Config> getFilteredConfigs() {
    final key = '${filterProtocol.value}|${filterSource.value}|'
        '${sortBy.value}|$_filterEpoch';
    if (key == _filteredCacheKey) return _filteredCache;

    final filtered = _computeFilteredConfigs();
    _filteredCacheKey = key;
    _filteredCache = filtered;
    // A new result set starts at the first page again, otherwise switching
    // filters would leave you scrolled into a window sized for the old list.
    // Guarded because this runs during a build: writing an Rx unconditionally
    // here would schedule a rebuild on every frame.
    if (visibleConfigLimit.value != configPageSize) {
      visibleConfigLimit.value = configPageSize;
    }
    return filtered;
  }

  List<Config> _computeFilteredConfigs() {
    var filtered = visibleConfigs.toList();

    // Filter by protocol
    if (filterProtocol.value != 'all') {
      filtered = filtered
          .where((c) => c.protocol == filterProtocol.value)
          .toList();
    }

    // Filter by source.
    //
    // `getConfigsBySource` re-reads the whole Hive box, so calling it per
    // config was O(n^2) — 7.6k configs meant tens of millions of comparisons
    // plus a full box scan for each one. Resolve the source's hashes once.
    if (filterSource.value != 'all') {
      final sourceHashes = configService
          .getConfigsBySource(filterSource.value)
          .map((c) => c.getHash())
          .toSet();
      // Only configs that actually belong to the chosen source. The previous
      // predicate also kept every config with a stored test result, so picking
      // one repository still listed configs from every other source.
      filtered = filtered
          .where((c) => sourceHashes.contains(c.getHash()))
          .toList();
    }

    // Sort
    filtered.sort((a, b) {
      switch (sortBy.value) {
        case 'speed':
          // Throughput is not measured (see TesterService), so "speed" ranks by
          // latency: lower is better. Untested configs sort last rather than
          // being treated as 0 ms, which would put them at the top.
          final aMs = testResults[a.getHash()]?.latencyMs;
          final bMs = testResults[b.getHash()]?.latencyMs;
          if (aMs == null && bMs == null) return 0;
          if (aMs == null) return 1;
          if (bMs == null) return -1;
          return aMs.compareTo(bMs);
        case 'name':
          return a.displayName.compareTo(b.displayName);
        case 'recently_added':
          // Newest first. savedAt is written with every stored record; configs
          // from before that field existed sort last instead of jittering.
          final aAt = savedAtByHash[a.getHash()];
          final bAt = savedAtByHash[b.getHash()];
          if (aAt == null && bAt == null) return 0;
          if (aAt == null) return 1;
          if (bAt == null) return -1;
          return bAt.compareTo(aAt);
        default:
          return 0;
      }
    });

    return filtered;
  }

  /// Get top N working configs, lowest latency first
  List<Config> getTopConfigs({int limit = 5}) {
    // visibleConfigs, not allConfigs: this feeds the "Fastest Configuration"
    // banner and the speed test, so reading the raw list surfaced configs from
    // disabled or untrusted repositories - the exact isolation the source
    // toggles are supposed to provide.
    final working = visibleConfigs
        .where((c) => testResults[c.getHash()]?.isWorking ?? false)
        .toList()
      ..sort((a, b) {
        final aMs = testResults[a.getHash()]?.latencyMs ?? 1 << 30;
        final bMs = testResults[b.getHash()]?.latencyMs ?? 1 << 30;
        return aMs.compareTo(bMs);
      });

    return working.take(limit).toList();
  }

  /// Add custom source
  /// Returns the created source, or null when the add failed.
  ///
  /// Returning a bool pushed the "which source was just added?" question onto
  /// the caller, which guessed `sources.last` — a list that is neither sorted
  /// nor guaranteed to end with the new entry, so adding a repository could
  /// fetch (and attribute configs to) a completely different source.
  Future<ConfigSource?> addCustomSource({
    required String name,
    required String owner,
    required String repo,
    String? branch,
  }) async {
    try {
      final source = ConfigSource(
        id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
        name: name,
        owner: owner,
        repo: repo,
        branch: branch ?? 'main',
        type: SourceType.userAdded,
        isEnabled: true,
      );

      await configService.saveSource(source);
      await loadSources();

      _log.i('Added custom source: $name');
      return source;
    } catch (e) {
      _log.e('Error adding source: $e');
      return null;
    }
  }

  /// Remove source
  Future<bool> removeSource(String sourceId) async {
    try {
      // Deleting from storage is what actually removes it: dropping it from the
      // in-memory list alone means the next loadSource() brings it back.
      final name = sources.firstWhereOrNull((s) => s.id == sourceId)?.name;
      sources.removeWhere((s) => s.id == sourceId);
      await configService.deleteSource(sourceId);
      _log.i('Removed source: $sourceId');
      _action('source_removed', {'source': name ?? sourceId});
      return true;
    } catch (e) {
      _log.e('Error removing source: $e');
      return false;
    }
  }

  /// Tests ONE config on demand (config detail sheet).
  ///
  /// States exposed through [testingHashes] and [testResults]: the sheet can
  /// show idle → testing (animated bar) → OK (latency) / Failed (reason).
  /// The result is stored through the same path as batch tests, so it is
  /// persisted and feeds the rankings and stats.
  Future<TestResult?> testSingleConfig(Config config) async {
    final hash = config.getHash();
    if (testingHashes.contains(hash)) return null;
    testingHashes.add(hash);
    try {
      final result = await testerService.testConfig(config);
      testResults[hash] = result;
      _action('config_tested', {
        'config': config.displayName,
        'ok': result.isWorking,
        'latency': result.latencyMs,
      });
      return result;
    } catch (e) {
      _log.e('Single test failed for ${config.displayName}: $e');
      return null;
    } finally {
      testingHashes.remove(hash);
    }
  }

  /// Delete config
  Future<bool> deleteConfig(Config config) async {
    _action('config_deleted', {'config': config.displayName});
    try {
      // The service reports whether the record was actually removed; this
      // method used to discard that and return true regardless, so the
      // Library said "removed" even when the delete had failed.
      final removed = await configService.deleteConfig(config.getHash());
      if (!removed) {
        _log.w('Storage did not delete config: ${config.displayName}');
        return false;
      }
      allConfigs.remove(config);
      testResults.remove(config.getHash());

      // A deleted config must not stay "connected". The tunnel kept running
      // with no library record behind it, so the UI showed a live session for
      // a config the user had just removed - and reconnecting was impossible
      // because the selection pointed at something that no longer existed.
      try {
        final connection = Get.find<ConnectionController>();
        if (connection.isConnected &&
            connection.selectedConfig.value?.getHash() == config.getHash()) {
          _log.i('Deleting the active config - disconnecting first');
          await connection.disconnect();
        }
      } catch (_) {
        // No connection controller (tests, or startup ordering): nothing to do.
      }

      _log.i('Deleted config: ${config.displayName}');
      return true;
    } catch (e) {
      _log.e('Error deleting config: $e');
      return false;
    }
  }

  /// Get config statistics
  Map<String, dynamic> getStats() {
    final visible = visibleConfigs;
    final working = visible
        .where((c) => testResults[c.getHash()]?.isWorking ?? false)
        .length;
    final tested = visible
        .where((c) => testResults.containsKey(c.getHash()))
        .length;

    final protocols = visible.map((c) => c.protocol).toSet().toList();

    return {
      // What the user can see and use right now — NOT the raw stored count,
      // which includes configs from disabled sources.
      'total': visible.length,
      'stored': allConfigs.length,
      'tested': tested,
      'working': working,
      'protocols': protocols,
      'sources': sources.where((s) => s.isEnabled).length,
      'average_reliability':
        testerService.getAverageReliability(testResults.values.toList()),
    };
  }
}
