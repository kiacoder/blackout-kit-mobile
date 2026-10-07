/// Config controller using GetX for state management.
/// Manages loading, filtering, testing, and ranking of VPN configs.

import 'package:get/get.dart';
import 'package:logger/logger.dart';
import '../models/config.dart';
import '../models/config_source.dart';
import '../models/test_result.dart';
import '../services/config_service.dart';
import '../services/github_service.dart';
import '../services/tester_service.dart';

class ConfigController extends GetxController {
  final ConfigService configService;
  final GitHubService githubService;
  final TesterService testerService;
  final Logger _log;

  // Observable state
  final RxList<Config> allConfigs = RxList<Config>();
  final RxList<ConfigSource> sources = RxList<ConfigSource>();
  final RxMap<String, TestResult> testResults = RxMap<String, TestResult>();
  final RxList<ConfigRanking> rankings = RxList<ConfigRanking>();

  final RxBool isLoading = RxBool(false);
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

    _log.i('ConfigController initialized');

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
      _log.i('Loaded ${configs.length} configs');
    } catch (e) {
      _log.e('Error loading configs: $e');
    } finally {
      isLoading.value = false;
    }
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
  }

  /// Fetch configs from a source and save to local storage
  Future<int> fetchFromSource(ConfigSource source) async {
    try {
      isLoading.value = true;
      _log.i('Fetching from ${source.name}');

      final configs = await githubService.fetchConfigsFromSource(source);
      final saved = await configService.saveConfigs(
        configs,
        sourceId: source.id,
      );

      // Update source with config count
      final updated = source.copyWith(
        configCount: saved,
        lastFetched: DateTime.now(),
        error: null,
      );
      await configService.saveSource(updated);

      // Reload configs
      await loadConfigs();

      _log.i('Saved $saved configs from ${source.name}');
      return saved;
    } catch (e) {
      _log.e('Error fetching from source: $e');
      return 0;
    } finally {
      isLoading.value = false;
    }
  }

  /// Fetch from all enabled sources
  Future<int> fetchFromAllSources({bool force = false}) async {
    int totalSaved = 0;
    for (final source in sources.where((s) => s.isEnabled)) {
      if (force || source.needsRefresh) {
        totalSaved += await fetchFromSource(source);
      }
    }
    return totalSaved;
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
      isLoading.value = true;
      final toTest = allConfigs.take(limit).toList();
      _log.i('Testing ${toTest.length} of ${allConfigs.length} configs');

      final results = await testerService.testConfigsConcurrently(
        toTest,
        concurrency: concurrency,
      );

      // Store results
      for (final result in results) {
        testResults[result.configHash] = result;
      }

      // Calculate rankings
      final rankings = testerService.rankConfigs(results);
      this.rankings.value = rankings;

      _log.i('Tested ${results.length} configs');
    } catch (e) {
      _log.e('Error testing configs: $e');
    } finally {
      isLoading.value = false;
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
    var filtered = allConfigs.toList();

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
      filtered = filtered
          .where((c) =>
            testResults.containsKey(c.getHash()) ||
            sourceHashes.contains(c.getHash()))
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
          // Would need timestamp tracking
          return 0;
        default:
          return 0;
      }
    });

    return filtered;
  }

  /// Get top N working configs, lowest latency first
  List<Config> getTopConfigs({int limit = 5}) {
    final working = allConfigs
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
  Future<bool> addCustomSource({
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
      return true;
    } catch (e) {
      _log.e('Error adding source: $e');
      return false;
    }
  }

  /// Remove source
  Future<bool> removeSource(String sourceId) async {
    try {
      // Deleting from storage is what actually removes it: dropping it from the
      // in-memory list alone means the next loadSource() brings it back.
      sources.removeWhere((s) => s.id == sourceId);
      await configService.deleteSource(sourceId);
      _log.i('Removed source: $sourceId');
      return true;
    } catch (e) {
      _log.e('Error removing source: $e');
      return false;
    }
  }

  /// Delete config
  Future<bool> deleteConfig(Config config) async {
    try {
      await configService.deleteConfig(config.getHash());
      allConfigs.remove(config);
      testResults.remove(config.getHash());
      _log.i('Deleted config: ${config.displayName}');
      return true;
    } catch (e) {
      _log.e('Error deleting config: $e');
      return false;
    }
  }

  /// Get config statistics
  Map<String, dynamic> getStats() {
    final working = allConfigs
        .where((c) => testResults[c.getHash()]?.isWorking ?? false)
        .length;

    final protocols = allConfigs.map((c) => c.protocol).toSet().toList();

    return {
      'total': allConfigs.length,
      'working': working,
      'tested': testResults.length,
      'protocols': protocols,
      'sources': sources.length,
      'average_reliability':
        testerService.getAverageReliability(testResults.values.toList()),
    };
  }
}
