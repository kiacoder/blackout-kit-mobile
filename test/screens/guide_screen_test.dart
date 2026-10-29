/// The beginner guide renders, in every shipped language.
///
/// The guide is the only part of the app written for someone who has never
/// used a VPN, so a missing key or an untranslated step is a real failure:
/// `'guide_step1_body'.tr` would show the raw key to exactly the audience that
/// cannot cope with it.
library;

import 'package:blackout_kit_mobile/screens/guide_screen.dart';
import 'package:blackout_kit_mobile/services/localization_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

Widget _app(Locale locale) => GetMaterialApp(
      translations: LocalizationService(),
      locale: locale,
      fallbackLocale: const Locale('en'),
      home: const GuideScreen(),
    );

/// A tall viewport: the guide is a ListView, so a 600px-tall test surface
/// never builds the later steps and `findsNothing` would mean "not scrolled
/// to" rather than "missing".
void _useTallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('renders all six steps in English', (tester) async {
    _useTallSurface(tester);
    await tester.pumpWidget(_app(const Locale('en')));
    await tester.pumpAndSettle();

    expect(find.text('How to use Blackout Kit'), findsOneWidget);
    expect(find.textContaining('Get a config'), findsOneWidget);
    expect(find.textContaining('Add it to the app'), findsOneWidget);
    expect(find.textContaining('Check it works'), findsOneWidget);
    expect(find.textContaining('only want a different DNS'), findsOneWidget);
    expect(find.text('Got it'), findsOneWidget);
  });

  testWidgets('renders the Persian guide', (tester) async {
    _useTallSurface(tester);
    await tester.pumpWidget(_app(const Locale('fa')));
    await tester.pumpAndSettle();

    expect(find.text('چطور از بلک‌اوت کیت استفاده کنیم'), findsOneWidget);
    expect(find.textContaining('کانفیگ'), findsWidgets);
    expect(find.text('فهمیدم'), findsOneWidget);

    // Direction is applied by main.dart's Directionality around the whole app,
    // so this only pins that Persian is classified as RTL.
    expect(LocalizationService.isRtl('fa'), isTrue);
  });

  testWidgets('renders the Chinese guide', (tester) async {
    _useTallSurface(tester);
    await tester.pumpWidget(_app(const Locale('zh')));
    await tester.pumpAndSettle();

    expect(find.text('如何使用 Blackout Kit'), findsOneWidget);
    expect(find.textContaining('配置'), findsWidgets);
    expect(find.text('明白了'), findsOneWidget);
  });

  test('every guide key exists in every shipped language', () {
    final keys = [
      'guide_title', 'guide_subtitle', 'guide_intro',
      'guide_step1_title', 'guide_step1_body',
      'guide_step2_title', 'guide_step2_body',
      'guide_step3_title', 'guide_step3_body',
      'guide_step4_title', 'guide_step4_body',
      'guide_step5_title', 'guide_step5_body',
      'guide_step6_title', 'guide_step6_body',
      'guide_need_help', 'guide_need_help_body', 'guide_got_it',
    ];
    for (final language in LocalizationService.supportedLanguages.keys) {
      for (final key in keys) {
        final value = LocalizationService.translate(key, language: language);
        expect(value, isNot(key), reason: '$key is missing from "$language"');
        expect(value.trim(), isNotEmpty, reason: '$key is empty in "$language"');
      }
    }
  });
}
