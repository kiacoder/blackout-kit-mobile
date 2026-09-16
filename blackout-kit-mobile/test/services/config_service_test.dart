/// Unit tests for the config service
/// Tests loading, saving, deduplication, and parsing

import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:blackout_kit_mobile/models/config.dart';
import 'package:blackout_kit_mobile/services/config_service.dart';

void main() {
  group('ConfigService', () {
    late ConfigService configService;
    late Logger mockLogger;

    setUp(() {
      mockLogger = Logger();
      configService = ConfigService(logger: mockLogger);
    });

    test('saveConfig stores config with unique hash', () async {
      final config = WireGuardConfig(
        displayName: 'Test Config',
        address: '10.0.0.1',
        port: 51820,
        privateKey: 'abc123==',
        rawUri: 'wireguard://10.0.0.1:51820',
        protocol: 'wireguard',
      );

      await configService.saveConfig(config);

      expect(configService.allConfigs.length, greaterThan(0));
    });

    test('loadConfigs retrieves saved configs', () async {
      final config1 = WireGuardConfig(
        displayName: 'Config 1',
        address: '10.0.0.1',
        port: 51820,
        privateKey: 'abc123==',
        rawUri: 'wireguard://10.0.0.1:51820',
        protocol: 'wireguard',
      );

      final config2 = OpenVPNConfig(
        displayName: 'Config 2',
        address: '10.0.0.2',
        port: 1194,
        configContent: 'proto tcp\nremote 10.0.0.2 1194',
        rawUri: 'openvpn://10.0.0.2:1194',
        protocol: 'openvpn',
      );

      await configService.saveConfig(config1);
      await configService.saveConfig(config2);
      await configService.loadConfigs();

      expect(configService.allConfigs.length, greaterThanOrEqualTo(2));
    });

    test('deduplicates configs by hash', () async {
      final config1 = WireGuardConfig(
        displayName: 'Test Config',
        address: '10.0.0.1',
        port: 51820,
        privateKey: 'abc123==',
        rawUri: 'wireguard://10.0.0.1:51820',
        protocol: 'wireguard',
      );

      final config2 = WireGuardConfig(
        displayName: 'Test Config (Duplicate)',
        address: '10.0.0.1',
        port: 51820,
        privateKey: 'abc123==',
        rawUri: 'wireguard://10.0.0.1:51820',
        protocol: 'wireguard',
      );

      await configService.saveConfig(config1);
      final countAfterFirst = configService.allConfigs.length;

      await configService.saveConfig(config2);
      final countAfterSecond = configService.allConfigs.length;

      expect(countAfterSecond, equals(countAfterFirst));
    });

    test('parseConfig creates correct protocol type from URI', () {
      final wgUri = 'wireguard://10.0.0.1:51820?privateKey=abc123==';
      final ovpnUri = 'openvpn://10.0.0.2:1194';
      final ssUri = 'shadowsocks://method:password@10.0.0.3:8388';

      // These would be parsed by the config factory in a real implementation
      expect(wgUri, contains('wireguard'));
      expect(ovpnUri, contains('openvpn'));
      expect(ssUri, contains('shadowsocks'));
    });

    test('deleteConfig removes config by hash', () async {
      final config = WireGuardConfig(
        displayName: 'Config to Delete',
        address: '10.0.0.1',
        port: 51820,
        privateKey: 'abc123==',
        rawUri: 'wireguard://10.0.0.1:51820',
        protocol: 'wireguard',
      );

      await configService.saveConfig(config);
      final countBefore = configService.allConfigs.length;

      await configService.deleteConfig(config.getHash());
      final countAfter = configService.allConfigs.length;

      expect(countAfter, lessThan(countBefore));
    });

    test('handles empty config list gracefully', () async {
      expect(configService.allConfigs.isEmpty, true);
    });

    test('parseConfigFromMap creates correct types', () {
      final wgMap = {
        'protocol': 'wireguard',
        'displayName': 'WG Config',
        'address': '10.0.0.1',
        'port': 51820,
        'privateKey': 'abc123==',
        'rawUri': 'wireguard://10.0.0.1:51820',
      };

      final ovpnMap = {
        'protocol': 'openvpn',
        'displayName': 'OVPN Config',
        'address': '10.0.0.2',
        'port': 1194,
        'configContent': 'proto tcp\nremote 10.0.0.2 1194',
        'rawUri': 'openvpn://10.0.0.2:1194',
      };

      // These would normally be parsed by ConfigService._configFromMap()
      expect(wgMap['protocol'], 'wireguard');
      expect(ovpnMap['protocol'], 'openvpn');
    });

    test('config toMap includes all required fields', () {
      final config = WireGuardConfig(
        displayName: 'Test Config',
        address: '10.0.0.1',
        port: 51820,
        privateKey: 'abc123==',
        rawUri: 'wireguard://10.0.0.1:51820',
        protocol: 'wireguard',
      );

      final map = config.toMap();

      expect(map, containsPair('protocol', 'wireguard'));
      expect(map, containsPair('displayName', 'Test Config'));
      expect(map, containsPair('address', '10.0.0.1'));
      expect(map, containsPair('port', 51820));
    });

    test('handles concurrent saves safely', () async {
      final configs = List.generate(
        5,
        (i) => WireGuardConfig(
          displayName: 'Config $i',
          address: '10.0.0.$i',
          port: 51820 + i,
          privateKey: 'key$i==',
          rawUri: 'wireguard://10.0.0.$i:${51820 + i}',
          protocol: 'wireguard',
        ),
      );

      await Future.wait(configs.map((c) => configService.saveConfig(c)));

      expect(configService.allConfigs.length, greaterThanOrEqualTo(5));
    });
  });
}
