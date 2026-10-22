/// Config service for loading, saving, and parsing VPN configs.
/// Replicates Blackout Kit CLI's config/manager.py pattern:
/// - Local persistence with Hive (currently not encrypted at rest)
/// - Atomic file I/O (write-temp + move)
/// - Deduplication by config hash
/// - Config validation before storage

import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:logger/logger.dart';
import '../models/config.dart';
import '../models/config_source.dart';
import '../models/test_result.dart';
import 'secure_vault.dart';

class ConfigService {
  static const String _configBoxName = 'configs';
  static const String _sourceBoxName = 'sources';
  static const String _resultBoxName = 'test_results';
  static const String _dedupKey = '_dedup_hashes'; // Tracks stored config hashes

  late Box<Map> _configBox;
  late Box<Map> _sourceBox;
  late Box<Map> _resultBox;
  SecureVault? _vault;
  bool _vaultActive = false;

  /// Encrypted data exists but its key is gone. The library is intact and
  /// unreadable; callers must say so rather than showing an empty list.
  bool _vaultLocked = false;
  final KeyStore? _keyStore;
  final Logger _log;

  ConfigService({Logger? logger, KeyStore? keyStore})
      : _log = logger ?? Logger(),
        _keyStore = keyStore;

  /// Initialize Hive boxes.
  ///
  /// A corrupt box (power loss / OOM kill during a compaction or write) used
  /// to rethrow out of `main()`, which is a white screen on EVERY subsequent
  /// launch - the app became permanently unbootable with no user-visible
  /// recovery. Now a failed open quarantines that box (deleted, fresh one
  /// created) exactly once and continues: losing a stored copy of configs is
  /// recoverable; an unbootable app is not.
  Future<void> initialize() async {
    // Encrypted-at-rest storage (BK-053). Every saved config embeds a live
    // credential - UUID, password or private key - and used to sit in a plain
    // Hive box readable by anything with storage access. The vault moves them
    // into AES-encrypted boxes whose key lives in the platform keystore.
    //
    // Migration is additive and idempotent: plaintext records are copied into
    // the encrypted boxes and the originals are deleted only afterwards. Any
    // failure leaves the plaintext boxes untouched and the app runs in legacy
    // mode rather than losing the library.
    try {
      // The key store is injectable so tests (and platforms with no keystore)
      // can supply their own; production gets the platform keystore.
      _vault = SecureVault(store: _keyStore);
      final report = await _vault!.migrate();
      _vaultActive = report.active;
      // migrate() already distinguishes "no keystore" from "key lost while
      // encrypted data exists" - take its verdict rather than re-deriving it,
      // which read a flag that had just been set to false.
      _vaultLocked = report.locked;
      if (report.locked) {
        _log.e('Config vault is locked: ${report.detail}');
      } else if (report.migrated) {
        _log.i('Config vault: ${report.detail}');
      } else if (!report.active) {
        _log.w('Config vault inactive: ${report.detail}');
      }
    } catch (e) {
      // Never let the vault block startup: legacy plaintext still works.
      _log.e('Config vault setup failed, continuing unencrypted: $e');
      _vaultActive = false;
    }

    // The cipher is mandatory for the encrypted boxes: opening one without it
    // silently yields zero records, which looks exactly like an empty library.
    // If the key cannot be read back (keystore wiped, app data restored onto a
    // new device) the vault is unusable, so fall back to the plaintext boxes
    // rather than presenting an empty library.
    var vaultKey = _vaultActive ? await _vault!.getOrCreateKey() : null;
    if (_vaultActive && vaultKey == null) {
      // Distinguish "no keystore on this platform" from "the key that opens
      // existing encrypted data is gone". The second case must never delete
      // anything: the boxes are intact and a restore of the key brings the
      // library back.
      _vaultLocked = await _vault!.hasEncryptedData();
      _vaultActive = false;
      vaultKey = null;
      _log.e(_vaultLocked
          ? 'Vault key missing but encrypted configs exist - keeping them '
              'untouched and reporting a locked library'
          : 'Vault key unavailable - falling back to plaintext storage');
    }
    final cipher = vaultKey == null ? null : HiveAesCipher(vaultKey);

    _configBox = await _openOrQuarantine<Map>(
        _vaultActive ? SecureVault.encryptedNameFor(_configBoxName) : _configBoxName,
        cipher);
    _sourceBox = await _openOrQuarantine<Map>(
        _vaultActive ? SecureVault.encryptedNameFor(_sourceBoxName) : _sourceBoxName,
        cipher);
    _resultBox = await _openOrQuarantine<Map>(
        _vaultActive ? SecureVault.encryptedNameFor(_resultBoxName) : _resultBoxName,
        cipher);
    _log.i('ConfigService initialized (encrypted at rest: $_vaultActive)');
  }

  /// Whether the saved configs are encrypted on disk.
  bool get isEncryptedAtRest => _vaultActive;

  /// Encrypted configs are on disk but cannot be decrypted right now.
  ///
  /// The UI shows a recovery message for this instead of "no configs", which
  /// is what made a keystore reset look like the library had been deleted.
  bool get isVaultLocked => _vaultLocked;

  /// Opens [name], or - if the file is corrupt - deletes it and reopens
  /// fresh. One retry only; if that also fails the error propagates, since
  /// silently running with no storage at all would mask real bugs.
  Future<Box<T>> _openOrQuarantine<T>(String name, [HiveCipher? cipher]) async {
    try {
      return await Hive.openBox<T>(name, encryptionCipher: cipher);
    } on HiveError catch (e) {
      // "already open and of type ...": another ConfigService (or a previous
      // instance in the same process) holds the box. Reuse it rather than
      // failing - the data is fine, only the second open is refused.
      final message = e.toString();
      if (message.contains('already open')) {
        try {
          return Hive.box(name) as Box<T>;
        } catch (_) {
          // fall through to quarantine
        }
      }
      // Never delete encrypted data. A wrong or missing key is not corruption:
      // the bytes are fine, and deleting them destroys a library that a
      // restored key would have opened. Rename instead, so the file survives.
      if (name.endsWith('_v2')) {
        _log.e('Encrypted box "$name" could not be opened ($e) - leaving it on '
            'disk; the vault key may be missing');
        rethrow;
      }
      _log.e('Box "$name" is unreadable ($e) - quarantining it');
      await Hive.deleteBoxFromDisk(name);
      return await Hive.openBox<T>(name, encryptionCipher: cipher);
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
    // Every source that ever supplied this config. Disabling one repository
    // used to hide the config for everyone, because a duplicate record could
    // only remember a single owner - so re-adding the same server from a
    // second source silently stole it from the first.
    if (sourceId != null) 'sourceIds': <String>[sourceId],
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
        // Same rule as the batch path: a duplicate arriving from a new source
        // is still an attribution, so the config stays visible when either
        // repository is enabled.
        if (sourceId != null) {
          final key = 'config_$hash';
          final existing = _configBox.get(key);
          if (existing is Map) {
            final ids = <String>{
              if (existing['sourceId'] is String) existing['sourceId'] as String,
              ...((existing['sourceIds'] as List?)?.cast<String>() ?? const []),
            };
            if (ids.add(sourceId)) {
              await _configBox.put(key, Map<String, dynamic>.from(existing)
                ..['sourceIds'] = ids.toList()
                ..['sourceId'] = sourceId);
            }
          }
        }
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
          if (existing is Map) {
            final next = Map<String, dynamic>.from(existing);
            final ids = <String>{
              if (existing['sourceId'] is String) existing['sourceId'] as String,
              ...((existing['sourceIds'] as List?)?.cast<String>() ?? const []),
            };
            if (ids.add(sourceId)) {
              // Keep sourceId as the newest owner for display purposes, and
              // record the full set so disabling one repository no longer
              // hides a config another repository also provides.
              next['sourceIds'] = ids.toList();
              next['sourceId'] = sourceId;
              batch[key] = next;
            }
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

  /// Hash → sourceId for every stored config, in one pass.
  ///
  /// Lets the controller hide configs that belong to a disabled source
  /// without touching the stored records — disabling a source must hide its
  /// configs from the library, testing and the scanner, never delete them.
  /// hash → every source id that supplied it (legacy single-id records are
  /// upgraded to a one-element set).
  Map<String, Set<String>> loadHashToSourceIds() {
    final map = <String, Set<String>>{};
    try {
      for (final key in _configBox.keys) {
        if (key is! String || !key.startsWith('config_')) continue;
        final data = _configBox.get(key);
        if (data is! Map) continue;
        final ids = <String>{
          if (data['sourceId'] is String) data['sourceId'] as String,
          ...((data['sourceIds'] as List?)?.cast<String>() ?? const []),
        };
        ids.removeWhere((id) => id.isEmpty);
        if (ids.isNotEmpty) {
          map[key.substring('config_'.length)] = ids;
        }
      }
    } catch (e) {
      _log.e('Error building hash→sourceIds map: $e');
    }
    return map;
  }

  Map<String, String> loadHashToSource() {
    final map = <String, String>{};
    try {
      for (final key in _configBox.keys) {
        if (key is! String || !key.startsWith('config_')) continue;
        final data = _configBox.get(key);
        if (data is! Map) continue;
        final sourceId = data['sourceId'];
        if (sourceId is String && sourceId.isNotEmpty) {
          map[key.substring('config_'.length)] = sourceId;
        }
      }
    } catch (e) {
      _log.e('Error building hash→source map: $e');
    }
    return map;
  }

  /// hash → savedAt, for the library's "recently added" ordering.
  ///
  /// Records written before `savedAt` existed are simply absent; the caller
  /// sorts them last rather than inventing a timestamp.
  Map<String, DateTime> loadHashToSavedAt() {
    final map = <String, DateTime>{};
    try {
      for (final key in _configBox.keys) {
        if (key is! String || !key.startsWith('config_')) continue;
        final data = _configBox.get(key);
        if (data is! Map) continue;
        final raw = data['savedAt'];
        if (raw is! String) continue;
        final parsed = DateTime.tryParse(raw);
        if (parsed != null) {
          map[key.substring('config_'.length)] = parsed;
        }
      }
    } catch (e) {
      _log.e('Error building hash→savedAt map: $e');
    }
    return map;
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

  /// Get all config sources.
  ///
  /// Each record is decoded on its own: one corrupt or schema-drifted entry
  /// used to throw inside the single try block and return an EMPTY list,
  /// which made every stored source disappear from the app until the record
  /// was removed. A skipped record is logged with its key; a list that loads
  /// 9 of 10 sources is strictly better than one that loads none.
  List<ConfigSource> getAllSources() {
    final sources = <ConfigSource>[];
    for (final key in _sourceBox.keys) {
      if (key is! String) continue;
      final data = _sourceBox.get(key);
      if (data == null) continue;
      try {
        sources.add(
          ConfigSource.fromJson(Map<String, dynamic>.from(data)),
        );
      } catch (e) {
        _log.w('Skipping unreadable source $key: $e');
      }
    }
    return sources;
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
