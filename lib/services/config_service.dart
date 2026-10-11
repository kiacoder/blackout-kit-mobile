/// Config service for loading, saving, and parsing VPN configs.
/// Replicates Blackout Kit CLI's config/manager.py pattern:
/// - Local persistence with Hive (encrypted)
/// - Atomic file I/O (write-temp + move)
/// - Deduplication by config hash
/// - Config validation before storage

import 'package:hive/hive.dart';
import 'package:logger/logger.dart';
import '../models/config.dart';
import '../models/config_source.dart';
import '../models/test_result.dart';

class ConfigService {
  static const String _configBoxName = 'configs';
  static const String _sourceBoxName = 'sources';
  static const String _resultBoxName = 'test_results';
  static const String _dedupKey = '_dedup_hashes'; // Tracks stored config hashes

  late Box<Map> _configBox;
  late Box<Map> _sourceBox;
  late Box<Map> _resultBox;
  final Logger _log;

  ConfigService({Logger? logger}) : _log = logger ?? Logger();

  /// Initialize Hive boxes
  Future<void> initialize() async {
    try {
      _configBox = await Hive.openBox<Map>(_configBoxName);
      _sourceBox = await Hive.openBox<Map>(_sourceBoxName);
      _resultBox = await Hive.openBox<Map>(_resultBoxName);
      _log.i('ConfigService initialized');
    } catch (e) {
      _log.e('Error initializing ConfigService: $e');
      rethrow;
    }
  }

  // ── Test result persistence ──────────────────────────────────────────────
  //
  // The reachability measurements used to live only in memory, so every app
  // restart wiped the tester: all servers read "Untested" again, rankings and
  // the fastest-config banner vanished, and connectFastest had to re-probe
  // from scratch behind censorship.

  /// Persist one measurement, keyed by config hash.
  Future<void> saveTestResult(TestResult result) async {
    try {
      await _resultBox.put(result.configHash, result.toJson());
    } catch (e) {
      _log.e('Error saving test result: $e');
    }
  }

  /// Load every stored measurement.
  Map<String, TestResult> loadTestResults() {
    try {
      final results = <String, TestResult>{};
      for (final key in _resultBox.keys) {
        final data = _resultBox.get(key);
        if (data == null || key is! String) continue;
        try {
          results[key] =
              TestResult.fromJson(Map<String, dynamic>.from(data));
        } catch (e) {
          _log.w('Skipping unreadable test result $key: $e');
        }
      }
      return results;
    } catch (e) {
      _log.e('Error loading test results: $e');
      return {};
    }
  }

  /// Drop the measurement for a deleted config.
  Future<void> deleteTestResult(String configHash) async {
    try {
      await _resultBox.delete(configHash);
    } catch (e) {
      _log.e('Error deleting test result: $e');
    }
  }

  /// Serialises [config] for the box.
  ///
  /// Shared by the single and bulk save paths so the two cannot drift.
  Map<String, dynamic> _configToMap(Config config, {String? sourceId}) => {
    'protocol': config.protocol,
    'displayName': config.displayName,
    'address': config.address,
    'port': config.port,
    'rawUri': config.rawUri,
    'sourceId': sourceId,
    'savedAt': DateTime.now().toIso8601String(),
    // Protocol-specific fields
    if (config is WireGuardConfig) ...{
      'privateKey': config.privateKey,
      'localAddresses': config.localAddresses,
      'dns': config.dns,
      'mtu': config.mtu,
      'peers': config.peers.map((p) => p.toMap()).toList(),
    },
    if (config is OpenVpnConfig) ...{
      'configContent': config.configContent,
    },
    if (config is ShadowsocksConfig) ...{
      'method': config.method,
      'password': config.password,
      'plugin': config.plugin,
    },
  };

  /// Save config with deduplication
  /// Returns true if saved, false if duplicate
  Future<bool> saveConfig(Config config, {String? sourceId}) async {
    try {
      final hash = config.getHash();

      // Check for duplicate
      final dedup = _configBox.get(_dedupKey) ?? {};
      if (dedup.containsKey(hash)) {
        _log.w('Duplicate config detected: $hash (source: $sourceId)');
        return false;
      }

      // Validate config
      if (!config.validate()) {
        _log.e('Invalid config: ${config.displayName}');
        return false;
      }

      await _configBox.put(
        'config_$hash',
        _configToMap(config, sourceId: sourceId),
      );

      // Update dedup tracker
      dedup[hash] = DateTime.now().toIso8601String();
      await _configBox.put(_dedupKey, dedup);

      _log.i('Saved config: ${config.displayName} (hash: $hash)');
      return true;
    } catch (e) {
      _log.e('Error saving config: $e');
      return false;
    }
  }

  /// Save many configs at once.
  ///
  /// Two batched writes instead of an await per config. A single source now
  /// returns thousands of configs, and the old loop cost two Hive writes plus a
  /// log line for every one of them — tens of thousands of awaits on the fetch
  /// path, which is what left the library stuck on "Loading repositories".
  Future<int> saveConfigs(
    List<Config> configs, {
    String? sourceId,
  }) async {
    final dedup = Map<dynamic, dynamic>.of(_configBox.get(_dedupKey) ?? {});
    final batch = <String, Map<String, dynamic>>{};

    for (final config in configs) {
      final hash = config.getHash();
      if (dedup.containsKey(hash)) {
        // A duplicate under a NEW source id is still an attribution: the
        // stored record may carry a sourceId from a source that has since
        // been retired or renamed, and the Settings counters count by the
        // ids that exist today. Rewriting sourceId on the hit keeps those
        // counters honest instead of showing a permanent 0.
        if (sourceId != null) {
          final key = 'config_$hash';
          final existing = _configBox.get(key);
          if (existing is Map && existing['sourceId'] != sourceId) {
            batch[key] = Map<String, dynamic>.from(existing)
              ..['sourceId'] = sourceId;
          }
        }
        continue;
      }
      if (!config.validate()) continue;
      dedup[hash] = DateTime.now().toIso8601String();
      batch['config_$hash'] = _configToMap(config, sourceId: sourceId);
    }

    if (batch.isEmpty) return 0;

    await _configBox.putAll(batch);
    await _configBox.put(_dedupKey, dedup);
    _log.i('Saved ${batch.length}/${configs.length} configs');
    return batch.length;
  }

  /// Get all stored configs
  List<Config> getAllConfigs() {
    try {
      final configs = <Config>[];
      for (final key in _configBox.keys) {
        if (key == _dedupKey || key is! String) continue;
        final data = _configBox.get(key);
        if (data == null) continue;

        final config = _configFromMap(data);
        if (config != null) {
          configs.add(config);
        }
      }
      _log.i('Loaded ${configs.length} configs from storage');
      return configs;
    } catch (e) {
      _log.e('Error loading configs: $e');
      return [];
    }
  }

  /// Get configs by protocol
  List<Config> getConfigsByProtocol(String protocol) {
    return getAllConfigs()
        .where((c) => c.protocol == protocol)
        .toList();
  }

  /// Count stored configs per source id, in one pass.
  ///
  /// The Settings screen used to render the `configCount` stored on the
  /// source record, which is a snapshot from the last successful fetch: it
  /// reads 0 for a freshly-created source even when thousands of its configs
  /// are already in the library (e.g. fetched under an older source id, or
  /// before the counter was ever persisted). The UI now renders this live
  /// count instead.
  Map<String, int> countConfigsBySource() {
    final counts = <String, int>{};
    try {
      for (final key in _configBox.keys) {
        if (key == _dedupKey || key is! String) continue;
        final data = _configBox.get(key);
        if (data == null) continue;
        final sourceId = data['sourceId'];
        if (sourceId is String && sourceId.isNotEmpty) {
          counts[sourceId] = (counts[sourceId] ?? 0) + 1;
        }
      }
    } catch (e) {
      _log.e('Error counting configs by source: $e');
    }
    return counts;
  }

  /// Get configs by source
  List<Config> getConfigsBySource(String sourceId) {    try {
      final configs = <Config>[];
      for (final key in _configBox.keys) {
        if (key == _dedupKey || key is! String) continue;
        final data = _configBox.get(key);
        if (data == null) continue;

        if (data['sourceId'] == sourceId) {
          final config = _configFromMap(data);
          if (config != null) {
            configs.add(config);
          }
        }
      }
      return configs;
    } catch (e) {
      _log.e('Error loading configs by source: $e');
      return [];
    }
  }

  /// Get config count
  int getConfigCount() {
    // Not `_configBox.length - 1`: on a fresh box the dedup key has never
    // been written and that arithmetic returns -1. Count the real keys.
    var count = 0;
    for (final key in _configBox.keys) {
      if (key == _dedupKey || key is! String) continue;
      count++;
    }
    return count;
  }

  /// Delete config by hash
  Future<bool> deleteConfig(String hash) async {
    try {
      final key = 'config_$hash';
      await _configBox.delete(key);

      // Remove from dedup tracker
      final dedup = _configBox.get(_dedupKey) ?? {};
      dedup.remove(hash);
      await _configBox.put(_dedupKey, dedup);

      // Its measurement is meaningless without the config.
      await deleteTestResult(hash);

      _log.i('Deleted config: $hash');
      return true;
    } catch (e) {
      _log.e('Error deleting config: $e');
      return false;
    }
  }

  /// Clear all configs (careful!)
  Future<void> clearAllConfigs() async {
    try {
      await _configBox.clear();
      await _resultBox.clear();
      _log.w('All configs cleared');
    } catch (e) {
      _log.e('Error clearing configs: $e');
    }
  }

  /// Save config source
  Future<bool> saveSource(ConfigSource source) async {
    try {
      await _sourceBox.put(source.id, source.toJson());
      _log.i('Saved source: ${source.name}');
      return true;
    } catch (e) {
      _log.e('Error saving source: $e');
      return false;
    }
  }

  /// Delete config source
  ///
  /// Removing a source only from the in-memory list is not enough: the entry is
  /// still in the box, so the next load brought it straight back.
  Future<bool> deleteSource(String id) async {
    try {
      await _sourceBox.delete(id);
      _log.i('Deleted source: $id');
      return true;
    } catch (e) {
      _log.e('Error deleting source: $e');
      return false;
    }
  }

  /// Get all config sources
  List<ConfigSource> getAllSources() {
    try {
      return _sourceBox.values
          .map((data) => ConfigSource.fromJson(Map<String, dynamic>.from(data)))
          .toList();
    } catch (e) {
      _log.e('Error loading sources: $e');
      return [];
    }
  }

  /// Get source by ID
  ConfigSource? getSource(String id) {
    try {
      final data = _sourceBox.get(id);
      if (data == null) return null;
      return ConfigSource.fromJson(Map<String, dynamic>.from(data));
    } catch (e) {
      _log.e('Error loading source: $e');
      return null;
    }
  }

  /// Get statistics
  Map<String, dynamic> getStats() {
    return {
      'total_configs': getConfigCount(),
      'total_sources': _sourceBox.length,
      'protocols': getAllConfigs()
          .map((c) => c.protocol)
          .toSet()
          .toList(),
    };
  }

  /// Convert Map to Config object
  Config? _configFromMap(Map data) {
    try {
      final protocol = data['protocol'] as String?;
      final rawUri = data['rawUri'] as String?;
      if (protocol == null || rawUri == null) return null;

      switch (protocol) {
        case 'wireguard':
          return WireGuardConfig(
            name: data['displayName'] as String? ?? 'WireGuard',
            rawUri: rawUri,
            privateKey: data['privateKey'] as String? ?? '',
            localAddresses: (data['localAddresses'] as List?)
                    ?.map((e) => e.toString())
                    .toList() ??
                const [],
            dns: data['dns'] as String? ?? '',
            mtu: data['mtu'] as int?,
            peers: (data['peers'] as List?)
                    ?.whereType<Map>()
                    .map(WireGuardPeer.fromMap)
                    .toList() ??
                const [],
          );

        case 'openvpn':
          return OpenVpnConfig(
            name: data['displayName'] as String? ?? 'OpenVPN',
            rawUri: rawUri,
            configContent: data['configContent'] as String? ?? '',
            address: data['address'] as String? ?? '',
            port: data['port'] as int? ?? 1194,
          );

        case 'shadowsocks':
          return ShadowsocksConfig(
            name: data['displayName'] as String? ?? 'Shadowsocks',
            rawUri: rawUri,
            address: data['address'] as String? ?? '',
            port: data['port'] as int? ?? 8388,
            method: data['method'] as String? ?? 'aes-256-gcm',
            password: data['password'] as String? ?? '',
            plugin: data['plugin'] as String?,
          );

        default:
          // Rebuild from the raw link that was stored alongside the record.
          //
          // This branch used to `return null`, and because
          // [getAllConfigs] drops nulls, every VLESS / VMess / Trojan /
          // Hysteria2 / TUIC config was silently deleted from the library on
          // each app start — only the three protocols with an explicit branch
          // above survived a restart. VLESS is the app's primary protocol, so
          // the practical effect was that the config list emptied itself.
          //
          // Every saved record carries `rawUri`, and [ConfigParser.parse] is
          // the same code that produced the object on import, so re-parsing
          // reconstructs it faithfully.
          return ConfigParser.parse(
            rawUri,
            customName: data['displayName'] as String?,
          );
      }
    } catch (e) {
      _log.e('Error converting map to config: $e');
      return null;
    }
  }
}
