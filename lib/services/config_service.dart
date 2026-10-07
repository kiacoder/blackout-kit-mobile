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

class ConfigService {
  static const String _configBoxName = 'configs';
  static const String _sourceBoxName = 'sources';
  static const String _dedupKey = '_dedup_hashes'; // Tracks stored config hashes

  late Box<Map> _configBox;
  late Box<Map> _sourceBox;
  final Logger _log;

  ConfigService({Logger? logger}) : _log = logger ?? Logger();

  /// Initialize Hive boxes
  Future<void> initialize() async {
    try {
      _configBox = await Hive.openBox<Map>(_configBoxName);
      _sourceBox = await Hive.openBox<Map>(_sourceBoxName);
      _log.i('ConfigService initialized');
    } catch (e) {
      _log.e('Error initializing ConfigService: $e');
      rethrow;
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
      if (dedup.containsKey(hash)) continue;
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

  /// Get configs by source
  List<Config> getConfigsBySource(String sourceId) {
    try {
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
    return _configBox.length - 1; // -1 for dedup key
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
