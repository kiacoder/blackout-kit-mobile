import 'dart:io';
import 'dart:convert';
import 'package:blackout_kit_mobile/models/config.dart';
import 'package:blackout_kit_mobile/services/config_service.dart';
import 'package:blackout_kit_mobile/services/openvpn_credentials.dart';
import 'package:blackout_kit_mobile/services/secure_vault.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  test('saved login is scoped to encrypted profile and removed with it',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('openvpn_login_vault');
    Hive.init(directory.path);
    try {
      final store = MemoryKeyStore();
      var service = ConfigService(keyStore: store);
      await service.initialize();
      final profile = OpenVpnConfig.fromUri(
          'client\ndev tun\nremote fixture.test 1194\nauth-user-pass\n')!;
      final credentials = OpenVpnCredentials(
          'fixture-account', 'synthetic-password-923',
          keySecret: 'key-pass-only', remember: true);
      expect(service.canRememberOpenVpn(profile), isFalse);
      await expectLater(
          service.updateOpenVpnLogin(profile, credentials), throwsStateError);
      expect(await service.saveConfig(profile), isTrue);
      await service.updateOpenVpnLogin(profile, credentials);
      credentials.clear();
      await Hive.close();
      final bytes =
          await File('${directory.path}/configs_v2.hive').readAsBytes();
      expect(latin1.decode(bytes), isNot(contains('synthetic-password-923')));
      service = ConfigService(keyStore: store);
      await service.initialize();
      final saved = service.readOpenVpnLogin(profile)!;
      expect(utf8.decode(saved.username), 'fixture-account');
      expect(utf8.decode(saved.password), 'synthetic-password-923');
      expect(saved.keyPassword, isEmpty);
      saved.clear();
      expect(service.getAllConfigs().single.rawUri, profile.rawUri);
      final temporary = OpenVpnCredentials('fixture-account', 'different');
      await service.updateOpenVpnLogin(profile, temporary);
      expect(service.readOpenVpnLogin(profile), isNull);
      temporary.clear();
      final remembered =
          OpenVpnCredentials('fixture-account', 'another', remember: true);
      await service.updateOpenVpnLogin(profile, remembered);
      remembered.clear();
      expect(await service.deleteConfig(profile.getHash()), isTrue);
      expect(service.readOpenVpnLogin(profile), isNull);
      expect(await service.saveConfig(profile), isTrue);
      expect(service.readOpenVpnLogin(profile), isNull);
    } finally {
      await Hive.close();
      await directory.delete(recursive: true);
    }
  });
}
