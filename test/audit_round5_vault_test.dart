/// BK-01: losing the vault key must never delete the encrypted library.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:blackout_kit_mobile/models/config.dart';
import 'package:blackout_kit_mobile/services/config_service.dart';
import 'package:blackout_kit_mobile/services/secure_vault.dart';

Config vless(String host, String name) => ConfigParser.parse(
      'vless://11111111-1111-1111-1111-111111111111@$host:443?security=none&type=tcp#$name',
    )!;

void main() {
  late Directory dir;

  setUp(() async {
    await Hive.close();
    dir = await Directory.systemTemp.createTemp('bk_vault_locked');
    Hive.init(dir.path);
  });

  tearDown(() async {
    await Hive.close();
    await dir.delete(recursive: true);
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
    expect(await MemoryKeyStore().read('blackout_config_vault_key'), isNull);
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
}
