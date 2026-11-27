/// Config service for loading, saving, and parsing VPN configs.
/// Replicates Blackout Kit CLI's config/manager.py pattern:
/// - Local persistence with encrypted Hive boxes; no plaintext fallback
/// - Atomic file I/O (write-temp + move)
/// - Deduplication by config hash
/// - Config validation before storage
library;

import 'dart:async';

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

  late Box<Map> _configStorage;
  Box<Map> get _configBox {
    if (_vaultLocked) throw StateError('Storage recovery required');
    return _configStorage;
  }

  late Box<Map> _sourceStorage;
  Box<Map> get _sourceBox {
    if (_vaultLocked) throw StateError('Storage recovery required');
    return _sourceStorage;
  }

  late Box<Map> _resultStorage;
  Box<Map> get _resultBox {
    if (_vaultLocked) throw StateError('Storage recovery required');
    return _resultStorage;
  }

  bool _vaultActive = false;

  /// Encrypted storage is unavailable. Preserve all files and reject writes
  /// until a usable key and successful migration are confirmed.
  bool _vaultLocked = true;
  static Future<void> _initializationQueue = Future<void>.value();
  bool _ownsLibrary = false;
  final KeyStore? _keyStore;
  final Logger _log;

  ConfigService({Logger? logger, KeyStore? keyStore})
      : _log = logger ?? Logger(),
        _keyStore = keyStore;

  /// Initialize without opening or replacing plaintext when an existing
  /// encrypted library needs recovery.
  Future<void> initialize() async {
    final previous = _initializationQueue;
    final completion = Completer<void>();
    _initializationQueue = completion.future;
    await previous;
    try {
      await _initializeLibrary();
    } finally {
      completion.complete();
    }
  }

  Future<void> _initializeLibrary() async {
    if (_ownsLibrary &&
        _configStorage.isOpen &&
        _sourceStorage.isOpen &&
        _resultStorage.isOpen) {
      return;
    }
    _ownsLibrary = false;
    _vaultActive = false;
    _vaultLocked = true;
    final opened = <Box<Map>>[];
    final vault = SecureVault(store: _keyStore);
    try {
      final report = await vault.migrate();
      if (report.locked || !report.active) {
        _log.w('Config library requires recovery; storage left untouched');
        return;
      }
      final vaultKey = await vault.getOrCreateKey();
      if (vaultKey == null) {
        _vaultActive = false;
        _vaultLocked = true;
        return;
      }
      final names = [_configBoxName, _sourceBoxName, _resultBoxName]
          .map(SecureVault.encryptedNameFor)
          .toList();
      // Hive returns an open box without checking the supplied cipher.
      // Never borrow a box opened by another owner.
      if (names.any(Hive.isBoxOpen)) {
        throw StateError('Library already open');
      }
      final cipher = HiveAesCipher(vaultKey);
      for (final name in names) {
        opened.add(await openPreservingBox<Map>(name, cipher: cipher));
      }
      // A key may disappear or change while the boxes are being opened.
      // Never expose a writable library that cannot be reopened on restart.
      if (!await vault.isPersistedKey(vaultKey)) {
        throw StateError('Vault key unavailable during initialization');
      }
      _configStorage = opened[0];
      _sourceStorage = opened[1];
      _resultStorage = opened[2];
      _ownsLibrary = true;
      _vaultActive = true;
      _vaultLocked = false;
      _log.i('ConfigService initialized (encrypted at rest: $_vaultActive)');
    } catch (_) {
      _ownsLibrary = false;
      _vaultActive = false;
      _vaultLocked = true;
      for (final box in opened.reversed) {
        try {
          await box.close();
        } catch (_) {
          _log.w('Config storage cleanup incomplete');
        }
      }
      _log.w('Config storage could not be safely opened; recovery required');
    }
  }

  /// Whether the saved configs are encrypted on disk.
  bool get isEncryptedAtRest => _vaultActive;

  /// Saved storage needs recovery before normal access can resume.
  ///
  /// The UI shows a recovery message for this instead of "no configs", which
  /// is what made a keystore reset look like the library had been deleted.
  bool get isVaultLocked => _vaultLocked;

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
    } catch (_) {
      _log.e('Error saving test result');
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
        } catch (_) {
          _log.w('Skipping unreadable test result');
        }
      }
      return results;
    } catch (_) {
      _log.e('Error loading test results');
      return {};
    }
  }

  /// Drop the measurement for a deleted config.
  Future<void> deleteTestResult(String configHash) async {
    try {
      await _resultBox.delete(configHash);
    } catch (_) {
      _log.e('Error deleting test result');
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
    if (config is SniRelayConfig) ...{
      'transport': config.transport,
      'serverName': config.serverName,
      'username': config.username,
      'password': config.password,
      'tls': config.tls,
      'allowInsecure': config.allowInsecure,
    },
    if (config is MhrvRelayConfig) ...{
      'endpoint': config.endpoint.toString(),
      'bearerToken': config.bearerToken,
    },
  };

  /// Save config with deduplication
  /// Returns true if saved, false if duplicate
  /// The source a config was imported from, or null for a manual one.
  ///
  /// Attribution lives in the stored record, not on the [Config] object, so a
  /// caller that rewrites a config (the editor) had no way to carry it over -
  /// and the record silently became "manual".
  String? sourceIdFor(Config config) {
    try {
      final record = _configBox.get('config_${config.getHash()}');
      if (record is Map) {
        final id = record['sourceId'];
        if (id is String && id.isNotEmpty) return id;
      }
    } catch (_) {
      // A missing box is not an error here: the caller treats null as manual.
    }
    return null;
  }

  // Serialize record + dedup-index changes across concurrent imports,
  // refreshes and deletes. One failed mutation must not poison the queue.
  Future<void> _configMutationTail = Future<void>.value();

  Future<T> _mutateConfigs<T>(Future<T> Function() action) {
    final next = _configMutationTail.then((_) => action());
    _configMutationTail = next.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return next;
  }

  Future<bool> saveConfig(Config config, {String? sourceId}) =>
      _mutateConfigs(() => _saveConfig(config, sourceId: sourceId));

  Future<bool> _saveConfig(Config config, {String? sourceId}) async {
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
        _log.w('Duplicate config detected');
        return false;
      }

      // Validate config
      if (!config.validate()) {
        _log.e('Invalid config');
        return false;
      }

      await _configBox.put(
        'config_$hash',
        _configToMap(config, sourceId: sourceId),
      );

      // Update dedup tracker
      dedup[hash] = DateTime.now().toIso8601String();
      await _configBox.put(_dedupKey, dedup);

      _log.i('Saved config');
      return true;
    } catch (_) {
      _log.e('Error saving config');
      return false;
    }
  }

  /// Save many configs at once.
  ///
  /// Two batched writes instead of an await per config. A single source now
  /// returns thousands of configs, and the old loop cost two Hive writes plus a
  /// log line for every one of them — tens of thousands of awaits on the fetch
  /// path, which is what left the library stuck on "Loading repositories".
  Future<int> saveConfigs(List<Config> configs, {String? sourceId}) =>
      _mutateConfigs(() => _saveConfigs(configs, sourceId: sourceId));

  Future<int> _saveConfigs(
    List<Config> configs, {
    String? sourceId,
  }) async {
    final dedup = Map<dynamic, dynamic>.of(_configBox.get(_dedupKey) ?? {});
    final batch = <String, Map<String, dynamic>>{};
    var newCount = 0;

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
      newCount++;
    }

    if (batch.isEmpty) return 0;

    await _configBox.putAll(batch);
    await _configBox.put(_dedupKey, dedup);
    _log.i('Saved ${batch.length}/${configs.length} configs');
    return newCount;
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
    } catch (_) {
      _log.e('Error loading configs');
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
    } catch (_) {
      _log.e('Error building hash→sourceIds map');
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
    } catch (_) {
      _log.e('Error building hash→source map');
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
    } catch (_) {
      _log.e('Error building hash→savedAt map');
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
    } catch (_) {
      _log.e('Error counting configs by source');
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
    } catch (_) {
      _log.e('Error loading configs by source');
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
  Future<bool> deleteConfig(String hash) =>
      _mutateConfigs(() => _deleteConfig(hash));

  Future<bool> _deleteConfig(String hash) async {
    try {
      final key = 'config_$hash';
      await _configBox.delete(key);

      // Remove from dedup tracker
      final dedup = _configBox.get(_dedupKey) ?? {};
      dedup.remove(hash);
      await _configBox.put(_dedupKey, dedup);

      // Its measurement is meaningless without the config.
      await deleteTestResult(hash);

      _log.i('Deleted config');
      return true;
    } catch (_) {
      _log.e('Error deleting config');
      return false;
    }
  }

  /// Clear all configs (careful!)
  Future<void> clearAllConfigs() =>
      _mutateConfigs(_clearAllConfigs);

  Future<void> _clearAllConfigs() async {
    try {
      await _configBox.clear();
      await _resultBox.clear();
      _log.w('All configs cleared');
    } catch (_) {
      _log.e('Error clearing configs');
    }
  }

  /// Save config source
  Future<bool> saveSource(ConfigSource source) async {
    try {
      await _sourceBox.put(source.id, source.toJson());
      _log.i('Saved source');
      return true;
    } catch (_) {
      _log.e('Error saving source');
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
      _log.i('Deleted source');
      return true;
    } catch (_) {
      _log.e('Error deleting source');
      return false;
    }
  }

  /// Get all config sources.
  ///
  /// Each record is decoded on its own: one corrupt or schema-drifted entry
  /// used to throw inside the single try block and return an EMPTY list,
  /// which made every stored source disappear from the app until the record
  /// was removed. A skipped record is logged without its key; a list that loads
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
      } catch (_) {
        _log.w('Skipping unreadable source');
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
    } catch (_) {
      _log.e('Error loading source');
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

        case 'sni':
          return SniRelayConfig(
            name: data['displayName'] as String? ?? 'SNI Relay',
            rawUri: rawUri,
            address: data['address'] as String? ?? '',
            port: data['port'] as int? ?? 443,
            serverName: data['serverName'] as String? ?? '',
            transport: data['transport'] as String? ?? 'http-connect',
            username: data['username'] as String?,
            password: data['password'] as String?,
            tls: data['tls'] as bool? ?? true,
            allowInsecure: data['allowInsecure'] as bool? ?? false,
          );

        case 'mhrv':
          return MhrvRelayConfig(
            name: data['displayName'] as String? ?? 'MHRV Relay',
            rawUri: rawUri,
            endpoint: Uri.parse(data['endpoint'] as String? ?? ''),
            bearerToken: data['bearerToken'] as String?,
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
    } catch (_) {
      _log.e('Error converting map to config');
      return null;
    }
  }
}
