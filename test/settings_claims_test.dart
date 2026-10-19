import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:hive/hive.dart';

import 'package:blackout_kit_mobile/services/config_service.dart';
import 'package:blackout_kit_mobile/controllers/settings_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const MethodChannel wakelockChannel = MethodChannel('dev.fluttercommunity.plus/wakelock');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(wakelockChannel, (call) async => null);
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('bk_settings_claims');
    Hive.init(tempDir.path);
  });

  tearDownAll(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  test('config service opens existing plaintext Hive boxes without migration', () async {
    final existing = await Hive.openBox<Map>('configs');
    await existing.put('config_legacy-config', {
      'protocol': 'vless',
      'rawUri': 'vless://stored-secret',
      'displayName': 'legacy',
      'address': 'example.test',
      'port': 443,
    });

    final service = ConfigService();
    await service.initialize();

    expect(service.getConfigCount(), 1);
    expect(existing.get('config_legacy-config')?['rawUri'], 'vless://stored-secret');
  });

  test('settings retains dormant preferences for backward-compatible storage', () async {
    final box = await Hive.openBox('settings');
    await box.put('blockNonVPNTraffic', true);
    await box.put('showNotifications', false);
    await box.put('logLocalConnection', true);

    final controller = SettingsController();
    await controller.initializeForTest();

    expect(controller.blockNonVPNTraffic.value, isTrue);
    expect(controller.showNotifications.value, isFalse);
    expect(controller.logLocalConnection.value, isTrue);
  });
}
