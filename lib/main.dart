/// Blackout Kit Mobile - Main entry point
/// Flutter VPN app with config-based architecture
/// GetX for state management, Hive for local persistence

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:logger/logger.dart';

import 'controllers/config_controller.dart';
import 'controllers/connection_controller.dart';
import 'controllers/settings_controller.dart';
import 'services/config_service.dart';
import 'services/github_service.dart';
import 'services/tester_service.dart';
import 'services/site_check_service.dart';
import 'services/ip_info_service.dart';
import 'services/vpn_service.dart';
import 'services/kill_switch_service.dart';
import 'services/dns_leak_prevention_service.dart';
import 'services/split_tunneling_service.dart';
import 'services/debug_service.dart';
import 'services/localization_service.dart';
import 'screens/root_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Hive for local storage
  await Hive.initFlutter();

  // Initialize services
  final logger = Logger();
  final configService = ConfigService(logger: logger);
  final githubService = GitHubService(logger: logger);
  final testerService = TesterService(logger: logger);
  final vpnService = VPNService(logger: logger);
  final killSwitchService = KillSwitchService();
  final dnsLeakPreventionService = DNSLeakPreventionService();
  final splitTunnelingService = SplitTunnelingService();
  final debugService = DebugService();

  // Initialize config service (opens Hive boxes)
  await configService.initialize();

  // Initialize VPN service (platform channels)
  vpnService.initialize();

  // Register services with GetX (singleton pattern)
  Get.put<ConfigService>(configService);
  Get.put<GitHubService>(githubService);
  Get.put<TesterService>(testerService);
  Get.put<VPNService>(vpnService);
  Get.put<KillSwitchService>(killSwitchService);
  Get.put<DNSLeakPreventionService>(dnsLeakPreventionService);
  Get.put<SplitTunnelingService>(splitTunnelingService);
  Get.put<DebugService>(debugService);
  // Must be registered before runApp: GetMaterialApp reads it for `translations`,
  // and LanguageSettingsScreen-style callers do Get.find<LocalizationService>().
  Get.put<LocalizationService>(LocalizationService());

  Get.put<ConfigController>(
    ConfigController(
      configService: configService,
      githubService: githubService,
      testerService: testerService,
      logger: logger,
    ),
  );

  // Settings first: the site-check service reads the toggle and host list,
  // and the connection controller consumes the service.
  final settingsController = SettingsController(logger: logger);
  Get.put<SettingsController>(settingsController);
  // Load persisted settings before anything reads them: the site-check service
  // takes the toggle and host list, and the connection controller's
  // auto-connect/watchdog setup runs in onInit. Without this await they saw
  // defaults for a frame and could act on them (auto-connecting to a config,
  // scheduling a scan) before the real values arrived.
  await settingsController.initialize();

  // Android 13+ needs a runtime grant before the VPN status notification can
  // be shown; without this prompt the tunnel notification is silently dropped.
  try {
    await vpnService.requestNotificationPermission();
  } catch (_) {}

  Get.put<SiteCheckService>(
    SiteCheckService(
      vpnService: vpnService,
      settings: settingsController,
      logger: logger,
    ),
  );

  final ipInfoService = IpInfoService(vpnService: vpnService, logger: logger);
  await ipInfoService.initialize();
  Get.put<IpInfoService>(ipInfoService);
  // Apply the stored privacy preference: with it off, no third-party IP
  // lookup ever leaves the device.
  try {
    ipInfoService.setLookupsEnabled(settingsController.showMyLocation.value);
  } catch (_) {}

  Get.put<ConnectionController>(
    ConnectionController(
      vpnService: vpnService,
      testerService: testerService,
      killSwitchService: killSwitchService,
      dnsLeakPreventionService: dnsLeakPreventionService,
      splitTunnelingService: splitTunnelingService,
      debugService: debugService,
      siteCheckService: Get.find<SiteCheckService>(),
      ipInfoService: ipInfoService,
      logger: logger,
    ),
  );

  runApp(const BlackoutKitApp());
}

class BlackoutKitApp extends StatelessWidget {
  const BlackoutKitApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final settingsController = Get.find<SettingsController>();

    return Obx(() {
      final themeStr = settingsController.theme.value;
      ThemeMode mode = ThemeMode.system;
      if (themeStr == 'light') mode = ThemeMode.light;
      if (themeStr == 'dark') mode = ThemeMode.dark;

      // The locale is driven straight off the persisted setting, so it is
      // correct as soon as SettingsController finishes loading from Hive and it
      // re-renders whenever the user changes it. Nothing else stores the
      // language — two sources of truth is how this used to silently not work.
      final languageCode = settingsController.selectedLanguage.value;

      return GetMaterialApp(
        title: LocalizationService.translate('app_title', language: languageCode),
        debugShowCheckedModeBanner: false,
        translations: Get.find<LocalizationService>(),
        locale: Locale(languageCode),
        fallbackLocale: const Locale(LocalizationService.fallbackLanguageCode),
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF6366F1),
            brightness: Brightness.light,
          ),
        ),
        darkTheme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF6366F1),
            brightness: Brightness.dark,
          ),
        ),
        themeMode: mode,
        home: const RootScreen(),
      );
    });
  }
}
