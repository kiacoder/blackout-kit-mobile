/// Blackout Kit Mobile - Main entry point
/// Flutter VPN app with config-based architecture
/// GetX for state management, Hive for encrypted storage

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
import 'services/vpn_service.dart';
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

  // Initialize config service (opens Hive boxes)
  await configService.initialize();

  // Initialize VPN service (platform channels)
  vpnService.initialize();

  // Register controllers with GetX (singleton pattern)
  Get.put<ConfigService>(configService);
  Get.put<GitHubService>(githubService);
  Get.put<TesterService>(testerService);
  Get.put<VPNService>(vpnService);

  Get.put<ConfigController>(
    ConfigController(
      configService: configService,
      githubService: githubService,
      testerService: testerService,
      logger: logger,
    ),
  );

  Get.put<ConnectionController>(
    ConnectionController(
      vpnService: vpnService,
      testerService: testerService,
      logger: logger,
    ),
  );

  Get.put<SettingsController>(
    SettingsController(logger: logger),
  );

  runApp(const BlackoutKitApp());
}

class BlackoutKitApp extends StatelessWidget {
  const BlackoutKitApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'Blackout Kit',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6366F1),
          brightness: Brightness.light,
        ),
        fontFamily: 'Poppins',
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6366F1),
          brightness: Brightness.dark,
        ),
        fontFamily: 'Poppins',
      ),
      themeMode: ThemeMode.system,
      home: const RootScreen(),
    );
  }
}
