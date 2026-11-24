/// Reproduces the "Settings is a blank gray box" report.
///
/// The report: opening Settings shows no text at all, just a gray rectangle
/// that extends without end. That is the signature of a widget asking for
/// unbounded height inside a scroll view, so this test pumps the real screen
/// and asserts the sections actually render.
library;

import 'dart:io';
import 'dart:async';
import 'package:flutter/services.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

import 'package:blackout_kit_mobile/controllers/config_controller.dart';
import 'package:blackout_kit_mobile/controllers/connection_controller.dart';
import 'package:blackout_kit_mobile/models/config.dart';
import 'package:blackout_kit_mobile/screens/root_screen.dart';
import 'package:blackout_kit_mobile/screens/home_screen.dart';
import 'package:blackout_kit_mobile/screens/library_screen.dart';
import 'package:blackout_kit_mobile/screens/speed_test_screen.dart';
import 'package:blackout_kit_mobile/screens/config_editor_screen.dart';
import 'package:blackout_kit_mobile/services/kill_switch_service.dart';
import 'package:blackout_kit_mobile/services/dns_leak_prevention_service.dart';
import 'package:blackout_kit_mobile/controllers/settings_controller.dart';
import 'package:blackout_kit_mobile/screens/settings_screen.dart';
import 'package:blackout_kit_mobile/screens/engine_hub_screen.dart';
import 'package:blackout_kit_mobile/screens/logs_screen.dart';
import 'package:blackout_kit_mobile/screens/split_tunneling_screen.dart';
import 'package:blackout_kit_mobile/screens/guide_screen.dart';
import 'package:blackout_kit_mobile/services/debug_service.dart';
import 'package:blackout_kit_mobile/services/split_tunneling_service.dart';
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

  testWidgets('real Settings navigation opens Engine Hub repeatedly with Android-shaped data',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    Get.delete<VPNService>(force: true);
    Get.put<VPNService>(VPNService());
    var reads = 0;
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(VPNService.platform, (call) async {
      expect(call.method, 'getEngineInfo');
      reads++;
      return <String, dynamic>{
        'capabilitySource': 'packaged',
        'xrayAvailable': true,
        'xrayProtocols': ['vless', 'vmess', 'trojan', 'shadowsocks', 'wireguard'],
        'singboxAvailable': true,
        'singboxProtocols': ['hysteria2', 'tuic', 'anytls'],
        'nativeWireguardAvailable': true,
        'nativeAmneziawgAvailable': true,
        'endpointGatedProtocols': ['sni', 'mhrv'],
      };
    });
    addTearDown(() => messenger.setMockMethodCallHandler(VPNService.platform, null));
    await tester.pumpWidget(GetMaterialApp(
      translations: LocalizationService(),
      locale: const Locale('en'),
      theme: ThemeData(useMaterial3: true),
      home: const SettingsScreen(),
    ));
    await tester.pump();
    for (var i = 0; i < 3; i++) {
      final tile = find.widgetWithText(ListTile, 'engine_hub'.tr);
      await tester.ensureVisible(tile);
      await tester.pump();
      await tester.tap(tile);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(EngineHubScreen), findsOneWidget);
      expect(find.text('Packaged engines; runtime checked at connection.'), findsOneWidget);
      expect(tester.takeException(), isNull);
      // Exercise a real engine details sheet.
      final card = find.byType(Card).first;
      await tester.tap(card);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('requirements'.tr), findsOneWidget);
      expect(tester.takeException(), isNull);
      Get.back();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      Get.back();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(SettingsScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
    expect(reads, 3);
  });

  testWidgets('rapid protocol taps produce one dialog and a late response is harmless',
      (tester) async {
    Get.delete<VPNService>(force: true);
    Get.put<VPNService>(VPNService());
    final pending = Completer<Map<String, dynamic>>();
    var reads = 0;
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(VPNService.platform, (_) {
      reads++;
      return pending.future;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(VPNService.platform, null));
    await tester.pumpWidget(GetMaterialApp(
      translations: LocalizationService(),
      locale: const Locale('en'),
      home: const SettingsScreen(),
    ));
    await tester.pump();
    final tile = find.widgetWithText(ListTile, 'preferred_protocol'.tr);
    await tester.ensureVisible(tile);
    await tester.pump();
    await tester.tap(tile);
    await tester.tap(tile);
    expect(reads, 1);
    Get.to(() => const GuideScreen());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    pending.complete({});
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(GuideScreen), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Settings opens logs and split tunneling on narrow screens',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    Get.put<DebugService>(DebugService());
    Get.put<SplitTunnelingService>(SplitTunnelingService());
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SplitTunnelingService.platform, (call) async {
      if (call.method == 'getInstalledApps') {
        return [{'packageName': 'example.app', 'appName': 'Example app'}];
      }
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(SplitTunnelingService.platform, null));
    await tester.pumpWidget(GetMaterialApp(
      translations: LocalizationService(),
      locale: const Locale('en'),
      theme: ThemeData(useMaterial3: true),
      home: const SettingsScreen(),
    ));
    await tester.pump();
    for (final entry in [
      ('system_logs_inspector', LogsScreen),
      ('select_apps', SplitTunnelingScreen),
    ]) {
      final tile = find.widgetWithText(ListTile, entry.$1.tr);
      await tester.ensureVisible(tile);
      await tester.pump();
      await tester.tap(tile);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(entry.$2), findsOneWidget);
      expect(tester.takeException(), isNull);
      Get.back();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(SettingsScreen), findsOneWidget);
    }
  });

  testWidgets('main navigation, Library actions and benchmark survive a populated library',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final settings = Get.find<SettingsController>();
    settings.autoConnect.value = false;
    settings.autoTestIntervalMinutes.value = 0;
    final config = ConfigParser.parse(
      'vless://11111111-2222-3333-4444-555555555555@example.com:443?security=tls&type=tcp#UI-smoke',
    )!;
    final configs = Get.find<ConfigController>();
    configs.allConfigs.assignAll([config]);
    final controller = Get.put(ConnectionController(
      vpnService: Get.find<VPNService>(),
      testerService: configs.testerService,
      killSwitchService: KillSwitchService(),
      dnsLeakPreventionService: DNSLeakPreventionService(),
      splitTunnelingService: SplitTunnelingService(),
      debugService: DebugService(),
    ), permanent: true);
    addTearDown(() => Get.delete<ConnectionController>(force: true));
    await tester.pumpWidget(GetMaterialApp(
      translations: LocalizationService(),
      locale: const Locale('en'),
      theme: ThemeData(useMaterial3: true),
      home: const RootScreen(),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.descendant(of: find.byType(BottomNavigationBar), matching: find.byIcon(Icons.library_books)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(LibraryScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(find.text('UI-smoke'), findsWidgets);
    await tester.tap(find.byTooltip('Add custom source'.tr));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(tester.takeException(), isNull);
    Get.back();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byTooltip('Speed Benchmark'.tr));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(SpeedTestScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
    Get.back();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    Get.to(() => ConfigEditorScreen(config: config));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(ConfigEditorScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    // Keep teardown explicit: GetX controllers must not retain timers.
    expect(controller.operationInFlight, isFalse);
  });

}
