/// Tests for [LocalizationService].
///
/// The important invariant is **key parity**: every language must carry exactly
/// the same key set as the fallback language. A missing key silently falls back
/// to English, which looks like a half-translated screen and is easy to miss in
/// review. These tests make it a build failure instead.

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:blackout_kit_mobile/services/localization_service.dart';

void main() {
  final service = LocalizationService();
  final englishKeys = service.keys[LocalizationService.fallbackLanguageCode]!.keys.toSet();

  group('catalogue shape', () {
    test('the fallback language is present', () {
      expect(service.keys, contains(LocalizationService.fallbackLanguageCode));
    });

    test('every supported language has a translation table', () {
      for (final code in LocalizationService.supportedLanguages.keys) {
        expect(
          service.keys,
          contains(code),
          reason: "'$code' is advertised in supportedLanguages but has no table",
        );
      }
    });

    test('every translation table belongs to a supported language', () {
      for (final code in service.keys.keys) {
        expect(
          LocalizationService.supportedLanguages,
          contains(code),
          reason: "'$code' has a table but is not in supportedLanguages, so no "
              'picker entry can ever select it',
        );
      }
    });

    test('key sets are identical across all languages', () {
      for (final entry in service.keys.entries) {
        final missing = englishKeys.difference(entry.value.keys.toSet());
        final extra = entry.value.keys.toSet().difference(englishKeys);

        expect(
          missing,
          isEmpty,
          reason: "${entry.key} is missing: ${missing.toList()..sort()}",
        );
        expect(
          extra,
          isEmpty,
          reason: "${entry.key} has keys English does not: ${extra.toList()..sort()}",
        );
      }
    });

    test('no translation is blank', () {
      for (final entry in service.keys.entries) {
        for (final translation in entry.value.entries) {
          expect(
            translation.value.trim(),
            isNotEmpty,
            reason: "${entry.key}.${translation.key} is blank",
          );
        }
      }
    });

    test('supportedLanguages is a non-trivial catalogue', () {
      expect(LocalizationService.supportedLanguages.length, greaterThanOrEqualTo(9));
      expect(LocalizationService.supportedLanguages['en'], 'English');
    });
  });

  group('translate', () {
    test('resolves a key in the requested language', () {
      expect(LocalizationService.translate('connect', language: 'en'), 'Connect');
      expect(LocalizationService.translate('connect', language: 'de'), 'Verbinden');
      expect(LocalizationService.translate('connect', language: 'zh'), '连接');
      expect(LocalizationService.translate('connect', language: 'ar'), 'اتصال');
    });

    test('defaults to the fallback language', () {
      expect(
        LocalizationService.translate('settings'),
        LocalizationService.translate(
          'settings',
          language: LocalizationService.fallbackLanguageCode,
        ),
      );
    });

    test('falls back to English for an unknown language', () {
      expect(LocalizationService.translate('connect', language: 'xx'), 'Connect');
    });

    test('returns the key itself for an unknown key, so the gap is visible', () {
      // A blank string would hide the mistake; a raw key is noticeable on screen.
      expect(
        LocalizationService.translate('no_such_key', language: 'de'),
        'no_such_key',
      );
    });

    test('the connection-state keys exist, since the status card depends on them', () {
      const stateKeys = [
        'not_connected',
        'selecting',
        'connecting',
        'connected',
        'testing',
        'disconnecting',
        'error',
      ];
      for (final key in stateKeys) {
        for (final code in LocalizationService.supportedLanguages.keys) {
          expect(
            LocalizationService.translate(key, language: code),
            isNot(key),
            reason: "'$key' is not translated into '$code'",
          );
        }
      }
    });
  });

  group('helpers', () {
    test('isSupported', () {
      expect(LocalizationService.isSupported('en'), isTrue);
      expect(LocalizationService.isSupported('ja'), isTrue);
      expect(LocalizationService.isSupported('xx'), isFalse);
      expect(LocalizationService.isSupported(''), isFalse);
    });

    test('displayName falls back to the code', () {
      expect(LocalizationService.displayName('de'), 'Deutsch');
      expect(LocalizationService.displayName('xx'), 'xx');
    });
  });

  group('GetX Translations contract', () {
    test('implements Translations and exposes keys', () {
      expect(service, isA<Translations>());
      expect(service.keys, isNotEmpty);
      // GetX looks up keys[locale.languageCode][key]; the outer keys must be
      // bare language codes or `Get.updateLocale(Locale('de'))` finds nothing.
      for (final code in service.keys.keys) {
        expect(code, matches(RegExp(r'^[a-z]{2}$')),
            reason: "'$code' is not a bare ISO-639-1 language code");
      }
    });
  });
}
