/// Encrypted-at-rest storage for the saved configs.
///
/// Everything the app keeps on disk - every proxy URI, with its UUID,
/// password or private key embedded - used to sit in a plain Hive box: any
/// app with storage access, or anyone with the device unlocked in a recovery
/// tool, could read the whole library. The CLI already solved this with a
/// machine-bound AES vault; this is the mobile equivalent.
///
/// Design:
///   * The AES-256 key lives in the platform keystore (Android Keystore /
///     iOS Keychain) via flutter_secure_storage - never in the Hive box and
///     never derived from anything guessable.
///   * Hive encrypts each box with `HiveAesCipher`, so the bytes on disk are
///     ciphertext.
///   * Migration is additive: the plaintext boxes are read, copied into new
///     encrypted boxes, and only then deleted. Any failure leaves the original
///     boxes untouched and the app running in legacy mode - losing an existing
///     library to a failed upgrade is not acceptable.
///   * The key store is injectable so the migration can be exercised in tests
///     (there is no platform channel on the Dart VM).
library;

import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// Minimal key/value contract for the vault key.
abstract class KeyStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}

/// Production store: the platform keystore.
class SecureKeyStore implements KeyStore {
  final FlutterSecureStorage _storage;
  SecureKeyStore({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);
}

/// In-memory store for tests and for platforms with no keystore.
class MemoryKeyStore implements KeyStore {
  final Map<String, String> _values = <String, String>{};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async => _values[key] = value;
}

/// What the vault can do right now.
enum VaultState {
  /// A key exists and encrypted boxes are readable.
  active,

  /// Encrypted data exists but the key is gone (keystore reset, app data
  /// restored onto another device). The data is intact and unreadable; the
  /// app must say so instead of deleting it.
  locked,

  /// No encrypted data yet - a key will be created on first write.
  absent,
}

class MigrationReport {
  final bool active;
  final bool migrated;
  final String detail;
  final int recordsMoved;

  /// Encrypted data is on disk but the key is missing. Nothing was deleted.
  final bool locked;

  const MigrationReport({
    required this.active,
    required this.migrated,
    required this.detail,
    this.recordsMoved = 0,
    this.locked = false,
  });
}

class SecureVault {
  static const String _keyName = 'blackout_config_vault_key';

  /// Boxes that hold config material, and their encrypted replacements.
  static const Map<String, String> _encryptedBoxNames = {
    'configs': 'configs_v2',
    'sources': 'sources_v2',
    'test_results': 'test_results_v2',
  };

  final KeyStore _store;

  SecureVault({KeyStore? store}) : _store = store ?? SecureKeyStore();

  /// True when a key exists, i.e. the app is running on encrypted boxes.
  Future<bool> isActive() async {
    try {
      final key = await _store.read(_keyName);
      return key != null && key.isNotEmpty;
    } catch (_) {
      // No keystore (some emulators, stripped devices): stay on plaintext
      // rather than failing to boot.
      return false;
    }
  }

  /// Returns the vault key, creating it on first use.
  ///
  /// Returns null when the key cannot be produced. That is deliberately NOT
  /// the same as "create a new one": minting a fresh key while encrypted boxes
  /// still exist on disk produces a key that cannot open them, and the caller
  /// then sees an unreadable box and deletes it - which silently wiped the
  /// whole saved library on a keystore reset or a restore onto a new device.
  /// See [VaultState.locked].
  Future<Uint8List?> getOrCreateKey() async {
    try {
      final existing = await _store.read(_keyName);
      if (existing != null && existing.isNotEmpty) {
        final decoded = _decode(existing);
        if (decoded != null) return decoded;
      }

      // No usable key. If encrypted data is already on disk, creating a new
      // key would make that data permanently unreadable - refuse instead and
      // let the caller surface a recoverable state.
      if (await hasEncryptedData()) {
        return null;
      }

      final key = _randomKey();
      await _store.write(_keyName, _encode(key));
      return key;
    } catch (_) {
      return null;
    }
  }

  /// True when any encrypted box exists on disk.
  Future<bool> hasEncryptedData() async {
    for (final encrypted in _encryptedBoxNames.values) {
      try {
        if (Hive.isBoxOpen(encrypted) || await Hive.boxExists(encrypted)) {
          return true;
        }
      } catch (_) {
        // An unreadable check is not evidence of absence.
        return true;
      }
    }
    return false;
  }

  /// Whether the vault is usable, locked, or absent.
  Future<VaultState> state() async {
    try {
      final stored = await _store.read(_keyName);
      final hasKey = stored != null && stored.isNotEmpty;
      final hasData = await hasEncryptedData();
      if (hasKey && hasData) return VaultState.active;
      if (!hasKey && hasData) return VaultState.locked;
      return VaultState.absent;
    } catch (_) {
      return VaultState.absent;
    }
  }

  /// The box name to use for [legacyName] once the vault is active.
  static String encryptedNameFor(String legacyName) =>
      _encryptedBoxNames[legacyName] ?? '${legacyName}_v2';

  /// Copies every plaintext box into its encrypted replacement, then deletes
  /// the plaintext one. Idempotent: running it twice is a no-op.
  ///
  /// Returns a report; `active` is false when the store is unavailable.
  Future<MigrationReport> migrate() async {
    final key = await getOrCreateKey();
    if (key == null) {
      final locked = await state() == VaultState.locked;
      return MigrationReport(
        active: false,
        migrated: false,
        locked: locked,
        detail: locked
            ? 'Encrypted configs exist but the vault key is gone. The data is '
                'kept on disk; it cannot be read until the key is restored.'
            : 'Platform keystore unavailable - configs stay in plain text',
      );
    }

    var moved = 0;
    for (final entry in _encryptedBoxNames.entries) {
      final legacyName = entry.key;
      final encryptedName = entry.value;

      // Already migrated (on disk or currently open): nothing to do.
      if (await _boxExists(encryptedName)) continue;
      if (!await _boxExists(legacyName)) continue;

      try {
        final plain = await Hive.openBox<dynamic>(legacyName);
        final records = <dynamic, dynamic>{};
        for (final boxKey in plain.keys) {
          records[boxKey] = plain.get(boxKey);
        }
        await plain.close();

        final encrypted = await Hive.openBox<dynamic>(
          encryptedName,
          encryptionCipher: HiveAesCipher(key),
        );
        await encrypted.putAll(records);
        await encrypted.close();

        // Only now that the encrypted copy is durable is the plaintext box
        // removed. A crash anywhere above leaves both on disk, and the next
        // run finds the encrypted one and skips the migration.
        await Hive.deleteBoxFromDisk(legacyName);
        moved += records.length;
      } catch (e) {
        // Leave the plaintext box alone and keep running from it.
        return MigrationReport(
          active: false,
          migrated: false,
          detail: 'Migration of $legacyName failed: $e',
          recordsMoved: moved,
        );
      }
    }

    return MigrationReport(
      active: true,
      migrated: moved > 0,
      detail: moved > 0
          ? '$moved records moved into encrypted storage'
          : 'Encrypted storage already in use',
      recordsMoved: moved,
    );
  }

  /// True when a box exists on disk OR is already open.
  ///
  /// Never opens a box to find out: `Hive.openBox` CREATES the box if it is
  /// missing, so probing that way left an empty `*_v2` file behind and made
  /// the migration below believe it had already run - the real plaintext box
  /// was then never copied or removed.
  Future<bool> _boxExists(String name) async {
    if (Hive.isBoxOpen(name)) return true;
    try {
      return await Hive.boxExists(name);
    } catch (_) {
      return false;
    }
  }

  Uint8List _randomKey() {
    // Random.secure() reads from the platform CSPRNG (CryptGenRandom on
    // Windows, /dev/urandom elsewhere) - never seed it from the clock.
    final random = Random.secure();
    return Uint8List.fromList(
        List<int>.generate(32, (_) => random.nextInt(256)));
  }

  Uint8List? _decode(String value) {
    try {
      final bytes = <int>[];
      for (var i = 0; i < value.length; i += 2) {
        bytes.add(int.parse(value.substring(i, i + 2), radix: 16));
      }
      return Uint8List.fromList(bytes);
    } catch (_) {
      return null;
    }
  }

  String _encode(Uint8List key) =>
      key.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}
