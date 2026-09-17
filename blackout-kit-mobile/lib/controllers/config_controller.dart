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

  ConfigController({
    required this.configService,
    required this.githubService,
    required this.testerService,
    Logger? logger,
  }) : _log = logger ?? Logger();

  @override
  Future<void> onInit() async {
    super.onInit();
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
  Future<void> loadSources() async {
    try {
      // Start with trusted sources
      final trustedSources = TrustedSources.getEnabled();

      // Add stored sources from config service
      final storedSources = configService.getAllSources();
      final allSources = [...trustedSources, ...storedSources];

      // Remove duplicates by ID
      final uniqueSources = <ConfigSource>[];
      final seen = <String>{};
      for (final source in allSources) {
        if (!seen.contains(source.id)) {
          uniqueSources.add(source);
          seen.add(source.id);
        }
      }

      sources.value = uniqueSources;
      _log.i('Loaded ${uniqueSources.length} sources');
    } catch (e) {
      _log.e('Error loading sources: $e');
    }
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

  /// Test all configs
  Future<void> testAllConfigs() async {
    try {
      isLoading.value = true;
      _log.i('Testing ${allConfigs.length} configs');

      final results = await testerService.testConfigs(allConfigs);

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

  /// Get filtered configs based on active filters
  List<Config> getFilteredConfigs() {
    var filtered = allConfigs.toList();

    // Filter by protocol
    if (filterProtocol.value != 'all') {
      filtered = filtered
          .where((c) => c.protocol == filterProtocol.value)
          .toList();
    }

    // Filter by source
    if (filterSource.value != 'all') {
      filtered = filtered
          .where((c) =>
            testResults[c.getHash()]?.configHash == c.getHash() ||
            configService.getConfigsBySource(filterSource.value).contains(c))
          .toList();
    }

    // Sort
    filtered.sort((a, b) {
      switch (sortBy.value) {
        case 'speed':
          final speedA = testResults[a.getHash()]?.speedMbps ?? 0;
          final speedB = testResults[b.getHash()]?.speedMbps ?? 0;
          return speedB.compareTo(speedA); // Descending
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

  /// Get top N working configs
  List<Config> getTopConfigs({int limit = 5}) {
    final working = allConfigs
        .where((c) => testResults[c.getHash()]?.isWorking ?? false)
        .toList()
      ..sort((a, b) {
        final speedA = testResults[a.getHash()]?.speedMbps ?? 0;
        final speedB = testResults[b.getHash()]?.speedMbps ?? 0;
        return speedB.compareTo(speedA);
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
      // In production, also delete associated configs
      sources.removeWhere((s) => s.id == sourceId);
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
