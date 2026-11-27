/// BK-01: losing the vault key must never delete the encrypted library.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:blackout_kit_mobile/models/config.dart';
import 'package:blackout_kit_mobile/services/config_service.dart';
import 'package:blackout_kit_mobile/services/secure_vault.dart';

Config vless(String host, String name) => ConfigParser.parse(
      'vless://11111111-1111-1111-1111-111111111111@$host:443?security=none&type=tcp#$name',
    )!;

class UnavailableKeyStore implements KeyStore {
  @override
  Future<String?> read(String key) async => throw StateError('keystore unavailable');

  @override
  Future<void> write(String key, String value) async =>
      throw StateError('keystore unavailable');
}

class NonPersistingKeyStore implements KeyStore {
  @override
  Future<String?> read(String key) async => null;

  @override
  Future<void> write(String key, String value) async {}
}

class DisappearingKeyStore implements KeyStore {
  String? value;
  int reads = 0;

  @override
  Future<String?> read(String key) async => ++reads <= 2 ? value : null;

  @override
  Future<void> write(String key, String value) async => this.value = value;
}

class DelayedKeyStore implements KeyStore {
  final writeStarted = Completer<void>();
  final allowWrite = Completer<void>();
  String? value;
  int reads = 0;
  int writes = 0;

  @override
  Future<String?> read(String key) async {
    reads++;
    return value;
  }

  @override
  Future<void> write(String key, String value) async {
    writes++;
    if (!writeStarted.isCompleted) writeStarted.complete();
    await allowWrite.future;
    this.value = value;
  }
}

// Hive 2.2.3 does not await the backend close after a failed open.
// Wait for its lock-file cleanup before deleting the synthetic directory
// or reopening a failed box. Do not suppress persistent locks or IO errors.
Future<void> awaitFixtureLocksReleased(Directory directory) async {
  final deadline = Stopwatch()..start();
  while (true) {
    final locks = await directory
        .list()
        .where((entry) => entry.path.endsWith('.lock'))
        .toList();
    if (locks.isEmpty) return;
    if (deadline.elapsed >= const Duration(seconds: 5)) {
      fail('Hive fixture still has open lock files after cleanup deadline');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  late Directory dir;

  setUp(() async {
    await Hive.close();
    dir = await Directory.systemTemp.createTemp('bk_vault_locked');
    Hive.init(dir.path);
  });

  tearDown(() async {
    await Hive.close();
    await awaitFixtureLocksReleased(dir);
    await dir.delete(recursive: true);
  });

  test('concurrent vault instances create exactly one persisted key', () async {
    final store = DelayedKeyStore();
    final first = SecureVault(store: store).getOrCreateKey();
    await store.writeStarted.future;
    final second = SecureVault(store: store).getOrCreateKey();
    // Give the second caller a turn while the first write is blocked.
    await Future<void>.delayed(Duration.zero);
    final readsBeforeRelease = store.reads;
    store.allowWrite.complete();
    final keys = await Future.wait([first, second]);
    expect(readsBeforeRelease, 1);
    expect(store.writes, 1);
    expect(keys.first, isNotNull);
    expect(keys.last, keys.first);
    expect(identical(keys.first, keys.last), isFalse);
  });

  test('unavailable keystore on fresh install never creates plaintext boxes', () async {
    final service = ConfigService(keyStore: UnavailableKeyStore());
    await service.initialize();
    expect(service.isVaultLocked, isTrue);
    expect(await service.saveConfig(vless('new.example.com', 'New')), isFalse);
    for (final name in ['configs', 'sources', 'test_results',
      'configs_v2', 'sources_v2', 'test_results_v2']) {
      expect(await Hive.boxExists(name), isFalse, reason: name);
    }
    final recovered = ConfigService(keyStore: MemoryKeyStore());
    await recovered.initialize();
    expect(recovered.isEncryptedAtRest, isTrue);
    expect(await recovered.saveConfig(vless('new.example.com', 'New')), isTrue);
  });

  test('a failed key request releases the initialization queue', () async {
    final failed = SecureVault(store: UnavailableKeyStore()).getOrCreateKey();
    final healthy = SecureVault(store: MemoryKeyStore()).getOrCreateKey();
    expect(await failed, isNull);
    expect(await healthy, hasLength(32));
  });

  test('concurrent migrations copy legacy records exactly once', () async {
    final store = MemoryKeyStore();
    final legacy = await Hive.openBox<Map>('configs');
    await legacy.put('fixture', {'value': 'preserve me'});
    await legacy.close();

    final first = SecureVault(store: store);
    final second = SecureVault(store: store);
    final reports = await Future.wait([first.migrate(), second.migrate()]);
    expect(reports.every((report) => report.active && !report.locked), isTrue);
    expect(reports.map((report) => report.recordsMoved), [1, 0]);
    expect(await Hive.boxExists('configs'), isFalse);
    final key = await first.getOrCreateKey();
    final encrypted = await openPreservingBox<Map>('configs_v2',
        cipher: HiveAesCipher(key!));
    expect(encrypted.length, 1);
    expect(encrypted.get('fixture'), {'value': 'preserve me'});
    await encrypted.close();
  });

  test('migration verifies nested records after reopening encrypted storage', () async {
    final legacy = await Hive.openBox<Map>('configs');
    final record = {
      'nested': {'tags': ['one', 'two'], 'enabled': true},
      'ports': [443, 8443],
      'optional': null,
    };
    await legacy.put('fixture', record);
    await legacy.close();
    final vault = SecureVault(store: MemoryKeyStore());
    expect((await vault.migrate()).active, isTrue);
    expect(await Hive.boxExists('configs'), isFalse);
    final key = await vault.getOrCreateKey();
    final migrated = await openPreservingBox<Map>('configs_v2',
        cipher: HiveAesCipher(key!));
    expect(migrated.get('fixture'), record);
    await migrated.close();
  });

  test('lost key during migration preserves legacy and encrypted copies', () async {
    final legacy = await Hive.openBox<Map>('configs');
    await legacy.put('fixture', {'value': 'preserve me'});
    await legacy.close();
    final file = File('${dir.path}/configs.hive');
    final before = await file.readAsBytes();
    final store = DisappearingKeyStore();
    final report = await SecureVault(store: store).migrate();
    expect(report.locked, isTrue);
    expect(report.active, isFalse);
    expect(await file.readAsBytes(), before);
    expect(await Hive.boxExists('configs_v2'), isTrue);
    expect(Hive.isBoxOpen('configs_v2'), isFalse);
  });

  test('a failed migration does not block the next migration', () async {
    final store = MemoryKeyStore();
    final reports = await Future.wait([
      SecureVault(store: UnavailableKeyStore()).migrate(),
      SecureVault(store: store).migrate(),
    ]);
    expect(reports.first.active, isFalse);
    expect(reports.last.active, isTrue);
  });

  test('migration does not close a live legacy box', () async {
    final store = MemoryKeyStore();
    final legacy = await Hive.openBox<Map>('configs');
    await legacy.put('fixture', {'value': 'live'});
    final vault = SecureVault(store: store);

    final blocked = await vault.migrate();
    expect(blocked.locked, isTrue);
    expect(legacy.isOpen, isTrue);
    expect(legacy.get('fixture'), {'value': 'live'});
    expect(await Hive.boxExists('configs_v2'), isFalse);

    await legacy.close();
    expect((await vault.migrate()).active, isTrue);
    expect(await Hive.boxExists('configs'), isFalse);
  });

  test('open encrypted box cannot bypass key validation during migration',
      () async {
    final store = MemoryKeyStore();
    final vault = SecureVault(store: store);
    final key = await vault.getOrCreateKey();
    final encrypted = await Hive.openBox<Map>('configs_v2',
        encryptionCipher: HiveAesCipher(key!));
    await encrypted.put('existing', {'value': 'encrypted'});
    final legacy = await Hive.openBox<Map>('sources');
    await legacy.put('source', {'value': 'legacy'});
    await legacy.close();

    final wrongStore = MemoryKeyStore();
    await wrongStore.write('blackout_config_vault_key', List.filled(64, '0').join());
    final blocked = await SecureVault(store: wrongStore).migrate();
    expect(blocked.locked, isTrue);
    expect(encrypted.isOpen, isTrue);
    expect(encrypted.get('existing'), {'value': 'encrypted'});
    expect(await Hive.boxExists('sources'), isTrue);
    expect(await Hive.boxExists('sources_v2'), isFalse);

    await encrypted.close();
    expect((await vault.migrate()).active, isTrue);
    final migrated = await openPreservingBox<Map>('sources_v2',
        cipher: HiveAesCipher(key));
    expect(migrated.get('source'), {'value': 'legacy'});
    await migrated.close();
  });

  test('an already-open library cannot bypass a different vault key', () async {
    final store = MemoryKeyStore();
    final owner = ConfigService(keyStore: store);
    await owner.initialize();
    expect(await owner.saveConfig(vless('owner.example.com', 'Owner')), isTrue);
    final wrong = MemoryKeyStore();
    await wrong.write('blackout_config_vault_key', List.filled(64, '0').join());
    final other = ConfigService(keyStore: wrong);
    await other.initialize();
    expect(other.isVaultLocked, isTrue);
    expect(other.isEncryptedAtRest, isFalse);
    expect(await other.saveConfig(vless('other.example.com', 'Other')), isFalse);
    expect(owner.getAllConfigs().map((c) => c.displayName), ['Owner']);
    await owner.initialize();
    expect(owner.isEncryptedAtRest, isTrue);
  });

  test('concurrent initialization admits only one library owner', () async {
    final store = MemoryKeyStore();
    final first = ConfigService(keyStore: store);
    final second = ConfigService(keyStore: store);
    await Future.wait([first.initialize(), second.initialize()]);
    expect(first.isEncryptedAtRest, isTrue);
    expect(second.isVaultLocked, isTrue);
    expect(await first.saveConfig(vless('owner.example.com', 'Owner')), isTrue);
    expect(await second.saveConfig(vless('other.example.com', 'Other')), isFalse);
    expect(first.getAllConfigs().map((c) => c.displayName), ['Owner']);
  });

  test('failed partial library open closes only its own boxes', () async {
    final store = MemoryKeyStore();
    final key = await SecureVault(store: store).getOrCreateKey();
    final good = await Hive.openBox<Map>('configs_v2',
        encryptionCipher: HiveAesCipher(key!));
    await good.put('fixture', {'value': 'preserve'});
    await good.close();
    final wrong = await Hive.openBox<Map>('sources_v2',
        encryptionCipher: HiveAesCipher(List.filled(32, 0)));
    await wrong.put('fixture', {'value': 'preserve'});
    await wrong.close();
    final sourceFile = File('${dir.path}/sources_v2.hive');
    final before = await sourceFile.readAsBytes();
    final service = ConfigService(keyStore: store);
    await service.initialize();
    expect(service.isVaultLocked, isTrue);
    expect(Hive.isBoxOpen('configs_v2'), isFalse);
    expect(await sourceFile.readAsBytes(), before);
    expect(await Hive.boxExists('test_results_v2'), isFalse);
  });

  test('a lost key keeps the data and reports a locked vault', () async {
    // First run: key created, config saved, boxes encrypted.
    final store = MemoryKeyStore();
    final first = ConfigService(keyStore: store);
    await first.initialize();
    expect(await first.saveConfig(vless('a.example.com', 'A')), isTrue);
    expect(first.getAllConfigs(), hasLength(1));
    expect(await Hive.boxExists('configs_v2'), isTrue);

    // The keystore is reset: same app data, no key.
    await Hive.close();
    Hive.init(dir.path);
    final wiped = ConfigService(keyStore: MemoryKeyStore());
    await wiped.initialize();

    expect(wiped.isVaultLocked, isTrue,
        reason: 'the app must know the library is there but unreadable');
    expect(await Hive.boxExists('configs_v2'), isTrue,
        reason: 'the encrypted box must never be deleted');
    // And no new key was minted that would have made the data unrecoverable.
    expect(await Hive.boxExists('configs'), isFalse);
    expect(await wiped.saveConfig(vless('new.example.com', 'New')), isFalse);
  });

  test('the key is not regenerated while encrypted data exists', () async {
    final store = MemoryKeyStore();
    final first = ConfigService(keyStore: store);
    await first.initialize();
    await first.saveConfig(vless('b.example.com', 'B'));
    await Hive.close();
    Hive.init(dir.path);

    final vault = SecureVault(store: MemoryKeyStore());
    expect(await vault.hasEncryptedData(), isTrue);
    expect(await vault.getOrCreateKey(), isNull,
        reason: 'a fresh key could never open the existing boxes');
    expect(await vault.state(), VaultState.locked);
  });

  test('unavailable keystore reports existing encrypted data as locked', () async {
    final first = ConfigService(keyStore: MemoryKeyStore());
    await first.initialize();
    await first.saveConfig(vless('d.example.com', 'D'));
    await Hive.close();
    Hive.init(dir.path);

    final vault = SecureVault(store: UnavailableKeyStore());
    expect(await vault.state(), VaultState.locked);
    expect(await vault.getOrCreateKey(), isNull);
    expect((await vault.migrate()).locked, isTrue);
    expect(await Hive.boxExists('configs_v2'), isTrue);
  });

  test('malformed key cannot replace a key for existing encrypted data', () async {
    final first = ConfigService(keyStore: MemoryKeyStore());
    await first.initialize();
    await first.saveConfig(vless('e.example.com', 'E'));
    await Hive.close();
    Hive.init(dir.path);

    final store = MemoryKeyStore();
    await store.write('blackout_config_vault_key', 'abcd');
    final vault = SecureVault(store: store);
    expect(await vault.getOrCreateKey(), isNull);
    expect(await vault.state(), VaultState.locked);
    expect((await vault.migrate()).locked, isTrue);
    expect(await store.read('blackout_config_vault_key'), 'abcd');
  });

  test('restoring the key brings the library back', () async {
    final store = MemoryKeyStore();
    final first = ConfigService(keyStore: store);
    await first.initialize();
    await first.saveConfig(vless('c.example.com', 'C'));
    final saved = await store.read('blackout_config_vault_key');
    await Hive.close();
    Hive.init(dir.path);

    // Same key restored (e.g. the user signed back into the same device).
    final restored = MemoryKeyStore();
    await restored.write('blackout_config_vault_key', saved!);
    final service = ConfigService(keyStore: restored);
    await service.initialize();

    expect(service.isVaultLocked, isFalse);
    expect(service.getAllConfigs().map((c) => c.displayName), contains('C'));
  });
  test('wrong but well-formed key never truncates encrypted bytes', () async {
    final store = MemoryKeyStore();
    final first = ConfigService(keyStore: store);
    await first.initialize();
    await first.saveConfig(vless('wrong-key.example.com', 'WrongKey'));
    await Hive.close();
    Hive.init(dir.path);
    final file = File('${dir.path}/configs_v2.hive');
    final before = await file.readAsBytes();
    final wrong = MemoryKeyStore();
    await wrong.write('blackout_config_vault_key', List.filled(64, '0').join());
    final service = ConfigService(keyStore: wrong);
    await service.initialize();
    expect(service.isVaultLocked, isTrue);
    expect(service.isEncryptedAtRest, isFalse);
    expect(await file.readAsBytes(), before);
    expect(await Hive.boxExists('configs'), isFalse);
    await Hive.close();
    await awaitFixtureLocksReleased(dir);
    final restored = ConfigService(keyStore: store);
    await restored.initialize();
    expect(restored.getAllConfigs().map((c) => c.displayName), contains('WrongKey'));
  });

  test('overlapping storage generations require recovery without deletion', () async {
    final store = MemoryKeyStore();
    final first = ConfigService(keyStore: store);
    await first.initialize();
    await first.saveConfig(vless('encrypted.example.com', 'Encrypted'));
    await Hive.close();
    final plain = await Hive.openBox<Map>('configs');
    await plain.put('legacy', {'rawUri': 'fixture'});
    await plain.close();
    final encrypted = File('${dir.path}/configs_v2.hive');
    final before = await encrypted.readAsBytes();
    final service = ConfigService(keyStore: store);
    await service.initialize();
    expect(service.isVaultLocked, isTrue);
    expect(await Hive.boxExists('configs'), isTrue);
    expect(await encrypted.readAsBytes(), before);
    expect(Hive.isBoxOpen('configs'), isFalse);
    expect(await service.saveConfig(vless('new.example.com', 'New')), isFalse);
  });

  test('a key that does not persist cannot be used to encrypt data', () async {
    final vault = SecureVault(store: NonPersistingKeyStore());
    expect(await vault.getOrCreateKey(), isNull);
    expect(await vault.hasEncryptedData(), isFalse);
  });

  test('wrong key cannot migrate another box after a partial migration', () async {
    final store = MemoryKeyStore();
    final first = ConfigService(keyStore: store);
    await first.initialize();
    await first.saveConfig(vless('partial.example.com', 'Partial'));
    await Hive.close();
    await Hive.deleteBoxFromDisk('sources_v2');
    final plain = await Hive.openBox<Map>('sources');
    await plain.put('source_fixture', {'id': 'fixture'});
    await plain.close();
    final wrong = MemoryKeyStore();
    await wrong.write('blackout_config_vault_key', List.filled(64, '0').join());
    final service = ConfigService(keyStore: wrong);
    await service.initialize();
    expect(service.isVaultLocked, isTrue);
    expect(await Hive.boxExists('sources'), isTrue);
    expect(await Hive.boxExists('sources_v2'), isFalse);
  });

  test('incompatible later legacy box blocks migration before any deletion',
      () async {
    final configs = await Hive.openBox<dynamic>('configs');
    await configs.put('fixture', {'value': 'keep config'});
    await configs.close();
    final sources = await Hive.openBox<dynamic>('sources');
    await sources.put('unsupported', 'not a map');
    await sources.close();
    final configFile = File('${dir.path}/configs.hive');
    final sourceFile = File('${dir.path}/sources.hive');
    final configBytes = await configFile.readAsBytes();
    final sourceBytes = await sourceFile.readAsBytes();

    final report = await SecureVault(store: MemoryKeyStore()).migrate();
    expect(report.locked, isTrue);
    expect(report.recordsMoved, 0);
    expect(await configFile.readAsBytes(), configBytes);
    expect(await sourceFile.readAsBytes(), sourceBytes);
    expect(await Hive.boxExists('configs_v2'), isFalse);
    expect(await Hive.boxExists('sources_v2'), isFalse);
    expect(Hive.isBoxOpen('sources'), isFalse);
  });

  test('incompatible existing encrypted box prevents legacy deletion', () async {
    final store = MemoryKeyStore();
    final key = await SecureVault(store: store).getOrCreateKey();
    final encrypted = await Hive.openBox<dynamic>('test_results_v2',
        encryptionCipher: HiveAesCipher(key!));
    await encrypted.put('unsupported', 42);
    await encrypted.close();
    final legacy = await Hive.openBox<Map>('configs');
    await legacy.put('fixture', {'value': 'keep'});
    await legacy.close();
    final report = await SecureVault(store: store).migrate();
    expect(report.locked, isTrue);
    expect(report.recordsMoved, 0);
    expect(await Hive.boxExists('configs'), isTrue);
    expect(await Hive.boxExists('configs_v2'), isFalse);
    expect(await Hive.boxExists('test_results_v2'), isTrue);
  });

  test('key loss after box opening keeps library locked and data intact',
      () async {
    final store = MemoryKeyStore();
    final first = ConfigService(keyStore: store);
    await first.initialize();
    expect(await first.saveConfig(vless('persist.example.com', 'Persist')), isTrue);
    final saved = await store.read('blackout_config_vault_key');
    await Hive.close();
    final disappearing = DisappearingKeyStore()..value = saved;
    final service = ConfigService(keyStore: disappearing);
    await service.initialize();
    expect(service.isVaultLocked, isTrue);
    expect(service.isEncryptedAtRest, isFalse);
    expect(await service.saveConfig(vless('new.example.com', 'New')), isFalse);
    expect(Hive.isBoxOpen('configs_v2'), isFalse);
    expect(Hive.isBoxOpen('sources_v2'), isFalse);
    expect(Hive.isBoxOpen('test_results_v2'), isFalse);
    final restored = ConfigService(keyStore: store);
    await restored.initialize();
    expect(restored.getAllConfigs().map((c) => c.displayName), ['Persist']);
  });

}
