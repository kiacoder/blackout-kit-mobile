/// BK-053: encrypted-at-rest storage, and the migration path that must never
/// lose an existing library.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:blackout_kit_mobile/models/config.dart';
import 'package:blackout_kit_mobile/services/config_service.dart';
import 'package:blackout_kit_mobile/services/secure_vault.dart';
import 'package:blackout_kit_mobile/services/localization_service.dart';

Config vless(String host, String name) => ConfigParser.parse(
      'vless://11111111-1111-1111-1111-111111111111@$host:443?security=none&type=tcp#$name',
    )!;

void main() {
  group('BK-053 encrypted storage', () {
    late Directory tempDir;

    // Each test gets its own Hive home: the boxes are global to the isolate,
    // so a shared directory leaks state (and open boxes) between tests.
    setUp(() async {
      await Hive.close();
      tempDir = await Directory.systemTemp.createTemp('bk_vault_test');
      Hive.init(tempDir.path);
    });

    tearDown(() async {
      await Hive.close();
      await tempDir.delete(recursive: true);
    });

    test('migrating moves plaintext records and removes the plaintext box',
        () async {
      // A pre-upgrade install: one plaintext box with a record in it.
      final legacy = await Hive.openBox<dynamic>('configs');
      final config = vless('legacy.example.com', 'Legacy');
      await legacy.put('config_${config.getHash()}', {
        'protocol': 'vless',
        'displayName': config.displayName,
        'rawUri': config.rawUri,
        'address': config.address,
        'port': config.port,
        'sourceId': null,
      });
      await legacy.close();

      // A keystore stand-in: the real one needs a platform channel.
      final service = ConfigService(keyStore: MemoryKeyStore());
      await service.initialize();

      // The service now reports encryption, and the plaintext box is gone.
      expect(service.isEncryptedAtRest, isTrue);
      expect(await Hive.boxExists('configs'), isFalse);
      expect(await Hive.boxExists('configs_v2'), isTrue);

      // The record survived the move.
      final loaded = service.getAllConfigs();
      expect(loaded.map((c) => c.displayName), contains('Legacy'));
    });

    test('a second start does not re-migrate and keeps every config', () async {
      final store = MemoryKeyStore();
      final service = ConfigService(keyStore: store);
      await service.initialize();
      final before = service.getAllConfigs().length;

      // A restart with the SAME key store: the key is still there, so the
      // encrypted boxes are readable and nothing is re-migrated.
      final again = ConfigService(keyStore: store);
      await again.initialize();
      expect(again.isEncryptedAtRest, isTrue);
      expect(again.getAllConfigs().length, before);
    });

    test('writing and reading back through the vault round-trips', () async {
      final store = MemoryKeyStore();
      final service = ConfigService(keyStore: store);
      await service.initialize();

      final config = vless('roundtrip.example.com', 'RoundTrip');
      final saved = await service.saveConfig(config);
      expect(saved, isTrue);

      final reloaded = ConfigService(keyStore: store);
      await reloaded.initialize();
      expect(
        reloaded.getAllConfigs().map((c) => c.displayName),
        contains('RoundTrip'),
      );
    });
  });

  group('BK-047 right-to-left languages', () {
    test('Arabic is RTL, English is not', () {
      expect(LocalizationService.isRtl('ar'), isTrue);
      expect(LocalizationService.isRtl('fa'), isTrue);
      expect(LocalizationService.isRtl('he'), isTrue);
      expect(LocalizationService.isRtl('en'), isFalse);
      expect(LocalizationService.isRtl('zh'), isFalse);
    });

    test('every advertised language has a locale', () {
      final codes =
          LocalizationService.supportedLocales.map((l) => l.languageCode).toSet();
      for (final code in LocalizationService.supportedLanguages.keys) {
        expect(codes, contains(code));
      }
    });

    test('the RTL list is lowercase-insensitive', () {
      expect(LocalizationService.isRtl('AR'), isTrue);
    });
  });
}
