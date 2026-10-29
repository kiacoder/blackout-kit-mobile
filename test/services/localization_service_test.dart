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

    test('exactly three languages ship: English, Persian, Chinese', () {
      // A product decision, not an accident: the catalogue used to list nine
      // languages with English body text, so picking one changed almost
      // nothing. Anything added here must come with a complete table.
      expect(LocalizationService.supportedLanguages.keys.toList(),
          ['en', 'fa', 'zh']);
      expect(LocalizationService.supportedLanguages['en'], 'English');
      expect(LocalizationService.supportedLanguages['fa'], 'فارسی');
      expect(LocalizationService.supportedLanguages['zh'], '简体中文');
    });

    test('a dropped language is no longer selectable', () {
      for (final code in ['es', 'fr', 'de', 'ja', 'ru', 'ar', 'pt']) {
        expect(LocalizationService.isSupported(code), isFalse, reason: code);
      }
    });
  });

  group('translate', () {
    test('resolves a key in the requested language', () {
      expect(LocalizationService.translate('connect', language: 'en'), 'Connect');
      expect(LocalizationService.translate('connect', language: 'fa'), 'اتصال');
      expect(LocalizationService.translate('connect', language: 'zh'), '连接');
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
      expect(LocalizationService.isSupported('fa'), isTrue);
      expect(LocalizationService.isSupported('zh'), isTrue);
      expect(LocalizationService.isSupported('xx'), isFalse);
      expect(LocalizationService.isSupported(''), isFalse);
    });

    test('displayName falls back to the code', () {
      expect(LocalizationService.displayName('fa'), 'فارسی');
      expect(LocalizationService.displayName('de'), 'de');
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

  group('LocalizationService.t (non-widget callers)', () {
    test('falls back to English when no locale is active', () {
      // Controllers and services call this; in a unit test Get.locale is null,
      // and returning the raw key would leak `status_connecting_to` into a
      // subtitle that a user reads.
      expect(LocalizationService.t('status_ready'), 'Ready');
      expect(LocalizationService.t('split_desc_off'), 'Off');
    });

    test('substitutes @placeholders', () {
      expect(
        LocalizationService.t('status_connecting_to', {'name': 'Berlin'}),
        'Connecting to Berlin...',
      );
      expect(
        LocalizationService.t('status_pinging', {'label': 'batch 1', 'count': '5'}),
        'Pinging batch 1 (5 servers)...',
      );
      expect(
        LocalizationService.t('status_error', {'error': 'boom'}),
        'Error: boom',
      );
    });

    test('every status key has a translation in every language', () {
      const keys = [
        'status_ready', 'status_tunnel_ended', 'status_finding_fastest',
        'status_connecting_to', 'status_connected_to', 'status_disconnected',
        'status_disconnecting', 'status_failed_disconnect', 'status_stopping',
        'status_scan_stopped', 'status_pinging', 'status_invalid_config',
        'status_connection_error', 'status_disconnect_error',
        'status_test_error', 'status_testing_connection',
        'status_connection_test_failed', 'status_error',
        'status_permission_denied', 'status_dns_applies', 'status_split_applies',
        'split_desc_off', 'split_desc_no_apps', 'split_desc_only',
        'split_desc_except', 'ks_desc_off', 'ks_desc_full',
        'ks_desc_always_on', 'ks_desc_running', 'dns_desc_off', 'dns_desc_on',
      ];
      for (final language in LocalizationService.supportedLanguages.keys) {
        for (final key in keys) {
          final value = LocalizationService.translate(key, language: language);
          expect(value, isNot(key), reason: '$key missing from $language');
        }
      }
    });
  });
}
