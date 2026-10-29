/// Reproduces the "Settings is a blank gray box" report.
///
/// The report: opening Settings shows no text at all, just a gray rectangle
/// that extends without end. That is the signature of a widget asking for
/// unbounded height inside a scroll view, so this test pumps the real screen
/// and asserts the sections actually render.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

import 'package:blackout_kit_mobile/controllers/config_controller.dart';
import 'package:blackout_kit_mobile/controllers/settings_controller.dart';
import 'package:blackout_kit_mobile/screens/settings_screen.dart';
import 'package:blackout_kit_mobile/services/config_service.dart';
import 'package:blackout_kit_mobile/services/github_service.dart';
import 'package:blackout_kit_mobile/services/secure_vault.dart';
import 'package:blackout_kit_mobile/services/tester_service.dart';
import 'package:blackout_kit_mobile/services/update_service.dart';
import 'package:blackout_kit_mobile/services/localization_service.dart';

void main() {
  late Directory dir;

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('bk_settings_screen');
    Hive.init(dir.path);
  });

  tearDownAll(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  setUp(() async {
    Get.reset();
    final settings = SettingsController();
    await settings.initialize();
    Get.put<SettingsController>(settings);

    final service = ConfigService(keyStore: MemoryKeyStore());
    await service.initialize();
    Get.put<ConfigController>(ConfigController(
      configService: service,
      githubService: GitHubService(),
      testerService: TesterService(),
    ));
    Get.put<UpdateService>(UpdateService());
  });

  testWidgets('settings renders its sections, not a blank gray box',
      (tester) async {
    await tester.pumpWidget(
      GetMaterialApp(
        // The real app always installs the catalogue; without it `.tr`
        // resolves to the raw key and every assertion here would be looking
        // for `settings` instead of `Settings`.
        translations: LocalizationService(),
        locale: const Locale('en'),
        fallbackLocale: const Locale('en'),
        home: const SettingsScreen(),
      ),
    );
    await tester.pump();

    // The screen must contain real text.
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('VPN Settings'), findsOneWidget);
    expect(find.text('Auto-Connect on Launch'), findsOneWidget);
    expect(find.text('Kill Switch'), findsOneWidget);
  });

  testWidgets('settings scrolls end to end without a layout exception',
      (tester) async {
    await tester.pumpWidget(
      GetMaterialApp(
        // The real app always installs the catalogue; without it `.tr`
        // resolves to the raw key and every assertion here would be looking
        // for `settings` instead of `Settings`.
        translations: LocalizationService(),
        locale: const Locale('en'),
        fallbackLocale: const Locale('en'),
        home: const SettingsScreen(),
      ),
    );
    await tester.pump();

    // Walk the whole screen: the Obx regression only threw for the sections
    // further down, so a single pump is not enough to prove it is gone.
    final finder = find.byType(SingleChildScrollView).first;
    for (var i = 0; i < 12; i++) {
      await tester.drag(finder, const Offset(0, -400));
      await tester.pump();
    }
    expect(tester.takeException(), isNull);

    // Sections that only exist further down must have rendered.
    expect(find.text('Appearance'), findsOneWidget);
    expect(find.text('Repositories'), findsOneWidget);
    expect(find.text('About'), findsOneWidget);
  });
}
