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
import 'package:blackout_kit_mobile/screens/engine_hub_screen.dart';
import 'package:blackout_kit_mobile/services/vpn_service.dart';
import 'package:blackout_kit_mobile/services/config_service.dart';
import 'package:blackout_kit_mobile/services/github_service.dart';
import 'package:blackout_kit_mobile/services/secure_vault.dart';
import 'package:blackout_kit_mobile/services/tester_service.dart';
import 'package:blackout_kit_mobile/services/update_service.dart';
import 'package:blackout_kit_mobile/services/localization_service.dart';

class _NoEngines extends VPNService {
  @override
  Future<EngineAvailability> getEngineInfo() async =>
      EngineAvailability.fromMap(const <String, dynamic>{});
}

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
    Get.put<VPNService>(_NoEngines());
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
  for (final language in ['fa', 'zh']) {
    testWidgets('engine category filter works in $language', (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 760));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(GetMaterialApp(
        translations: LocalizationService(),
        locale: Locale(language),
        fallbackLocale: const Locale('en'),
        home: const EngineHubScreen(),
      ));
      await tester.pumpAndSettle();
      final core = find.widgetWithText(ChoiceChip, 'Core VPN'.tr);
      expect(core, findsOneWidget);
      await tester.tap(core);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Core VPN'), findsOneWidget);
      expect(find.text('WIREGUARD'), findsWidgets);
      await tester.tap(find.widgetWithText(ChoiceChip, 'All'.tr));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('preferred protocol dialog renders with no available engines',
      (tester) async {
    await tester.pumpWidget(GetMaterialApp(
      translations: LocalizationService(),
      locale: const Locale('en'),
      fallbackLocale: const Locale('en'),
      home: const SettingsScreen(),
    ));
    await tester.pump();
    final tile = find.widgetWithText(ListTile, 'preferred_protocol'.tr);
    await tester.ensureVisible(tile);
    await tester.pump();
    await tester.tap(tile);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.byType(RadioListTile<String>), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('close'.tr));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(AlertDialog), findsNothing);
  });

}
