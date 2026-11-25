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
///     boxes untouched. An ambiguous migration or unreadable encrypted
///     library requires recovery rather than silently switching storage.
///   * The key store is injectable so the migration can be exercised in tests
///     (there is no platform channel on the Dart VM).
library;

import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// Hive 2.2.3 completes its internal opening future with an error as well
/// as throwing from openBox. A second same-name waiter observes that future
/// so an expected failed open does not escape as an unhandled async error.
Future<Box<T>> openPreservingBox<T>(String name, {HiveCipher? cipher}) async {
  final boxes = await Future.wait([
    Hive.openBox<T>(name, encryptionCipher: cipher, crashRecovery: false),
    Hive.openBox<T>(name, encryptionCipher: cipher, crashRecovery: false),
  ]);
  return boxes.first;
}

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
  /// Encrypted boxes exist and a syntactically valid key is available.
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

  /// True when the stored key encoding is valid; does not prove readability.
  Future<bool> isActive() async {
    try {
      final key = await _store.read(_keyName);
      return key != null && _decode(key) != null;
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
      final encoded = _encode(key);
      await _store.write(_keyName, encoded);
      // Do not encrypt anything until persistence of the key is confirmed.
      if (await _store.read(_keyName) != encoded) return null;
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
    final hasData = await hasEncryptedData();
    if (!hasData) return VaultState.absent;
    try {
      final stored = await _store.read(_keyName);
      final hasKey = stored != null && _decode(stored) != null;
      return hasKey ? VaultState.active : VaultState.locked;
    } catch (_) {
      // A temporary keystore failure is not evidence that the library is absent.
      return VaultState.locked;
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

    // Both generations may contain changes after an interrupted migration.
    // Do not guess which is authoritative or silently skip the legacy data.
    for (final entry in _encryptedBoxNames.entries) {
      if (await _boxExists(entry.key) && await _boxExists(entry.value)) {
        return const MigrationReport(
          active: false,
          migrated: false,
          locked: true,
          detail: 'Both storage generations exist. Recovery is required; '
              'neither copy has been removed.',
        );
      }
    }

    // If a previous migration completed only some boxes, validate the
    // original key against those boxes before using it for any new copy.
    var hasLegacy = false;
    for (final name in _encryptedBoxNames.keys) {
      hasLegacy = hasLegacy || await _boxExists(name);
    }
    if (hasLegacy) {
      for (final name in _encryptedBoxNames.values) {
        if (await _boxExists(name) && !Hive.isBoxOpen(name)) {
          final existing = await openPreservingBox<Map>(
            name,
            cipher: HiveAesCipher(key),
          );
          await existing.close();
        }
      }
    }

    var moved = 0;
    for (final entry in _encryptedBoxNames.entries) {
      final legacyName = entry.key;
      final encryptedName = entry.value;

      // Already migrated (on disk or currently open): nothing to do.
      if (await _boxExists(encryptedName)) continue;
      if (!await _boxExists(legacyName)) continue;

      try {
        final plain = await openPreservingBox<dynamic>(legacyName);
        final records = <dynamic, dynamic>{};
        try {
          for (final boxKey in plain.keys) {
            records[boxKey] = plain.get(boxKey);
          }
        } finally {
          await plain.close();
        }

        final encrypted = await openPreservingBox<dynamic>(
          encryptedName,
          cipher: HiveAesCipher(key),
        );
        try {
          await encrypted.putAll(records);
          await encrypted.flush();
        } finally {
          await encrypted.close();
        }

        // Only now that the encrypted copy is durable is the plaintext box
        // removed. A crash above leaves both generations for recovery.
        await Hive.deleteBoxFromDisk(legacyName);
        moved += records.length;
      } catch (_) {
        // Preserve both generations and never log configuration contents.
        return MigrationReport(
          active: false,
          migrated: false,
          locked: true,
          detail: 'Config migration failed. Existing data was preserved.',
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
    return Hive.boxExists(name);
  }

  Uint8List _randomKey() {
    // Random.secure() reads from the platform CSPRNG (CryptGenRandom on
    // Windows, /dev/urandom elsewhere) - never seed it from the clock.
    final random = Random.secure();
    return Uint8List.fromList(
        List<int>.generate(32, (_) => random.nextInt(256)));
  }

  Uint8List? _decode(String value) {
    // The persisted encoding is exactly 32 bytes of hexadecimal AES key material.
    if (value.length != 64 || !RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(value)) {
      return null;
    }
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
