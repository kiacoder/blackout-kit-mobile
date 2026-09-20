import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:logger/logger.dart';

import 'package:blackout_kit_mobile/services/localization_service.dart';

void main() {
  late LocalizationService localizationService;

  setUp(() {
    localizationService = LocalizationService();
    localizationService.onInit();
  });

  group('LocalizationService', () {
    test('initializes with default language (English)', () {
      expect(localizationService.currentLanguage.value, 'en');
      expect(
        localizationService.currentLocaleDisplay.value,
        'English',
      );
    });

    test('returns all supported languages', () {
      final languages = localizationService.getSupportedLanguages();
      expect(languages.length, 9);
      expect(languages['en'], 'English');
      expect(languages['es'], 'Español');
      expect(languages['fr'], 'Français');
      expect(languages['de'], 'Deutsch');
      expect(languages['zh'], '中文');
      expect(languages['ja'], '日本語');
      expect(languages['ru'], 'Русский');
      expect(languages['ar'], 'العربية');
      expect(languages['pt'], 'Português');
    });

    test('changes language to Spanish', () async {
      await localizationService.setLanguage('es');
      expect(localizationService.currentLanguage.value, 'es');
      expect(
        localizationService.currentLocaleDisplay.value,
        'Español',
      );
    });

    test('changes language to French', () async {
      await localizationService.setLanguage('fr');
      expect(localizationService.currentLanguage.value, 'fr');
      expect(
        localizationService.currentLocaleDisplay.value,
        'Français',
      );
    });

    test('changes language to German', () async {
      await localizationService.setLanguage('de');
      expect(localizationService.currentLanguage.value, 'de');
      expect(
        localizationService.currentLocaleDisplay.value,
        'Deutsch',
      );
    });

    test('changes language to Chinese', () async {
      await localizationService.setLanguage('zh');
      expect(localizationService.currentLanguage.value, 'zh');
      expect(
        localizationService.currentLocaleDisplay.value,
        '中文',
      );
    });

    test('changes language to Japanese', () async {
      await localizationService.setLanguage('ja');
      expect(localizationService.currentLanguage.value, 'ja');
      expect(
        localizationService.currentLocaleDisplay.value,
        '日本語',
      );
    });

    test('changes language to Russian', () async {
      await localizationService.setLanguage('ru');
      expect(localizationService.currentLanguage.value, 'ru');
      expect(
        localizationService.currentLocaleDisplay.value,
        'Русский',
      );
    });

    test('changes language to Arabic', () async {
      await localizationService.setLanguage('ar');
      expect(localizationService.currentLanguage.value, 'ar');
      expect(
        localizationService.currentLocaleDisplay.value,
        'العربية',
      );
    });

    test('changes language to Portuguese', () async {
      await localizationService.setLanguage('pt');
      expect(localizationService.currentLanguage.value, 'pt');
      expect(
        localizationService.currentLocaleDisplay.value,
        'Português',
      );
    });

    test('ignores unsupported language codes', () async {
      await localizationService.setLanguage('invalid');
      expect(localizationService.currentLanguage.value, 'en');
    });

    test('translates common key in English', () {
      final translation = localizationService.translate('connected');
      expect(translation, 'Connected');
    });

    test('translates common key in Spanish', () {
      final translation = localizationService.translate('connected', language: 'es');
      expect(translation, 'Conectado');
    });

    test('translates common key in French', () {
      final translation = localizationService.translate('connected', language: 'fr');
      expect(translation, 'Connecté');
    });

    test('translates common key in Chinese', () {
      final translation = localizationService.translate('connected', language: 'zh');
      expect(translation, '已连接');
    });

    test('returns key when translation not found', () {
      final translation =
          localizationService.translate('nonexistent_key');
      expect(translation, 'nonexistent_key');
    });

    test('translates kill_switch in multiple languages', () {
      expect(
        localizationService.translate('kill_switch', language: 'en'),
        'Kill Switch',
      );
      expect(
        localizationService.translate('kill_switch', language: 'es'),
        'Kill Switch',
      );
      expect(
        localizationService.translate('kill_switch', language: 'fr'),
        'Kill Switch',
      );
      expect(
        localizationService.translate('kill_switch', language: 'de'),
        'Kill Switch',
      );
      expect(
        localizationService.translate('kill_switch', language: 'zh'),
        '断流开关',
      );
    });

    test('translates dns_leak_prevention in multiple languages', () {
      expect(
        localizationService.translate('dns_leak_prevention', language: 'en'),
        'DNS Leak Prevention',
      );
      expect(
        localizationService.translate('dns_leak_prevention', language: 'es'),
        'Prevención de Fugas DNS',
      );
      expect(
        localizationService.translate('dns_leak_prevention', language: 'fr'),
        'Prévention des Fuites DNS',
      );
      expect(
        localizationService.translate('dns_leak_prevention', language: 'de'),
        'DNS-Leck-Prävention',
      );
      expect(
        localizationService.translate('dns_leak_prevention', language: 'ja'),
        'DNS リーク防止',
      );
    });

    test('translates split_tunneling in multiple languages', () {
      expect(
        localizationService.translate('split_tunneling', language: 'en'),
        'Split Tunneling',
      );
      expect(
        localizationService.translate('split_tunneling', language: 'es'),
        'Tunelización Dividida',
      );
      expect(
        localizationService.translate('split_tunneling', language: 'fr'),
        'Tunnelisation Fractionnée',
      );
      expect(
        localizationService.translate('split_tunneling', language: 'pt'),
        'Tunelamento Dividido',
      );
      expect(
        localizationService.translate('split_tunneling', language: 'ru'),
        'Разделенный туннель',
      );
    });

    test('translates app state strings correctly', () {
      expect(
        localizationService.translate('connecting', language: 'en'),
        'Connecting...',
      );
      expect(
        localizationService.translate('disconnecting', language: 'en'),
        'Disconnecting...',
      );
      expect(
        localizationService.translate('error', language: 'en'),
        'Error',
      );
      expect(
        localizationService.translate('success', language: 'en'),
        'Success',
      );
    });

    test('has translations for all supported languages', () {
      final languages = localizationService.getSupportedLanguages().keys;
      for (final lang in languages) {
        final appTitle = localizationService.translate('app_title', language: lang);
        expect(appTitle.isNotEmpty, true);
        expect(appTitle, isNotEmpty);
      }
    });

    test('maintains state across multiple language changes', () async {
      await localizationService.setLanguage('es');
      expect(localizationService.currentLanguage.value, 'es');

      await localizationService.setLanguage('fr');
      expect(localizationService.currentLanguage.value, 'fr');

      await localizationService.setLanguage('zh');
      expect(localizationService.currentLanguage.value, 'zh');

      await localizationService.setLanguage('en');
      expect(localizationService.currentLanguage.value, 'en');
    });

    test('observable language updates listeners', () {
      int callCount = 0;
      localizationService.currentLanguage.listen((_) {
        callCount++;
      });

      localizationService.currentLanguage.value = 'es';
      expect(callCount, 1);

      localizationService.currentLanguage.value = 'fr';
      expect(callCount, 2);
    });
  });
}
