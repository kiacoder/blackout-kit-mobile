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

  test('a failed key request releases the initialization queue', () async {
    final failed = SecureVault(store: UnavailableKeyStore()).getOrCreateKey();
    final healthy = SecureVault(store: MemoryKeyStore()).getOrCreateKey();
    expect(await failed, isNull);
    expect(await healthy, hasLength(32));
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

}
