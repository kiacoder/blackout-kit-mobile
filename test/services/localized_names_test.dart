/// Provider and engine names follow the language too.
///
/// The first pass at localisation translated the UI chrome but left the
/// catalogue printing "Shecan" and "XRay Core" in every language. Persian
/// users know several of these services by a Persian name, so the model asks
/// the catalogue first and falls back to the service's own name.
library;

import 'package:blackout_kit_mobile/models/dns_provider.dart';
import 'package:blackout_kit_mobile/models/engine_capability.dart';
import 'package:blackout_kit_mobile/services/localization_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DNS provider names', () {
    test('every provider has a name key in all three languages', () {
      for (final provider in DnsCatalog.all) {
        for (final language in LocalizationService.supportedLanguages.keys) {
          final value = LocalizationService.translate(
            'dns_name_${provider.key}',
            language: language,
          );
          expect(value, isNot('dns_name_${provider.key}'),
              reason: '${provider.key} has no name in $language');
          expect(value.trim(), isNotEmpty);
        }
      }
    });

    test('the Iranian services use their Persian names', () {
      // These are the names the services and their users actually use.
      expect(LocalizationService.translate('dns_name_shecan', language: 'fa'),
          'شکن');
      expect(LocalizationService.translate('dns_name_begzar', language: 'fa'),
          'بگزار');
      expect(LocalizationService.translate('dns_name_radar', language: 'fa'),
          'رادار');
      expect(LocalizationService.translate('dns_name_electro', language: 'fa'),
          'الکترو');
    });

    test('localizedName falls back to the catalogue name in English', () {
      final shecan = DnsCatalog.byKey('shecan')!;
      expect(shecan.localizedName, 'Shecan');
      expect(DnsCatalog.byKey('cloudflare')!.localizedName, 'Cloudflare');
    });

    test('localizedName never leaks a raw key', () {
      for (final provider in DnsCatalog.all) {
        expect(provider.localizedName.startsWith('dns_name_'), isFalse,
            reason: provider.key);
      }
    });
  });

  group('engine names', () {
    test('every engine has a name key in all three languages', () {
      for (final engine in EngineRegistry.getAll()) {
        for (final language in LocalizationService.supportedLanguages.keys) {
          final value = LocalizationService.translate(
            'engine_${engine.key}',
            language: language,
          );
          expect(value, isNot('engine_${engine.key}'),
              reason: '${engine.key} has no name in $language');
        }
      }
    });

    test('localizedName falls back to displayName', () {
      for (final engine in EngineRegistry.getAll()) {
        expect(engine.localizedName.startsWith('engine_'), isFalse,
            reason: engine.key);
      }
    });
  });
}
