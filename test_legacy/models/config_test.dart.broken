/// Unit tests for VPN config models
/// Tests config parsing, validation, and serialization

import 'package:flutter_test/flutter_test.dart';
import 'package:blackout_kit_mobile/models/config.dart';

void main() {
  group('WireGuardConfig', () {
    test('creates config with valid URI', () {
      final config = WireGuardConfig(
        displayName: 'Test WireGuard',
        address: '10.0.0.1',
        port: 51820,
        privateKey: 'abc123==',
        rawUri: 'wireguard://10.0.0.1:51820?key=abc123',
        protocol: 'wireguard',
      );

      expect(config.displayName, 'Test WireGuard');
      expect(config.address, '10.0.0.1');
      expect(config.port, 51820);
      expect(config.protocol, 'wireguard');
    });

    test('getHash returns consistent SHA256', () {
      final config1 = WireGuardConfig(
        displayName: 'Test',
        address: '10.0.0.1',
        port: 51820,
        privateKey: 'abc123==',
        rawUri: 'wireguard://10.0.0.1:51820?key=abc123',
        protocol: 'wireguard',
      );

      final config2 = WireGuardConfig(
        displayName: 'Test',
        address: '10.0.0.1',
        port: 51820,
        privateKey: 'abc123==',
        rawUri: 'wireguard://10.0.0.1:51820?key=abc123',
        protocol: 'wireguard',
      );

      expect(config1.getHash(), config2.getHash());
    });

    test('different configs have different hashes', () {
      final config1 = WireGuardConfig(
        displayName: 'Test',
        address: '10.0.0.1',
        port: 51820,
        privateKey: 'abc123==',
        rawUri: 'wireguard://10.0.0.1:51820?key=abc123',
        protocol: 'wireguard',
      );

      final config2 = WireGuardConfig(
        displayName: 'Test',
        address: '10.0.0.2',
        port: 51820,
        privateKey: 'abc123==',
        rawUri: 'wireguard://10.0.0.2:51820?key=abc123',
        protocol: 'wireguard',
      );

      expect(config1.getHash(), isNot(config2.getHash()));
    });
  });

  group('OpenVPNConfig', () {
    test('creates config with valid parameters', () {
      const configContent = 'client\nremote 10.0.0.1 443\n';

      final config = OpenVPNConfig(
        displayName: 'Test OpenVPN',
        address: '10.0.0.1',
        port: 443,
        configContent: configContent,
        rawUri: 'openvpn://10.0.0.1:443?config=....',
        protocol: 'openvpn',
      );

      expect(config.displayName, 'Test OpenVPN');
      expect(config.protocol, 'openvpn');
      expect(config.configContent, configContent);
    });

    test('serializes config to map', () {
      const configContent = 'client\nremote 10.0.0.1 443\n';

      final config = OpenVPNConfig(
        displayName: 'Test',
        address: '10.0.0.1',
        port: 443,
        configContent: configContent,
        rawUri: 'openvpn://10.0.0.1:443',
        protocol: 'openvpn',
      );

      final map = config.toMap();

      expect(map['displayName'], 'Test');
      expect(map['protocol'], 'openvpn');
      expect(map['address'], '10.0.0.1');
    });
  });

  group('ShadowsocksConfig', () {
    test('creates config with valid parameters', () {
      final config = ShadowsocksConfig(
        displayName: 'Test SS',
        address: '10.0.0.1',
        port: 8388,
        method: 'aes-256-gcm',
        password: 'password123',
        plugin: 'obfs-local',
        pluginOpts: 'obfs=http',
        rawUri: 'ss://aes-256-gcm:password123@10.0.0.1:8388',
        protocol: 'shadowsocks',
      );

      expect(config.protocol, 'shadowsocks');
      expect(config.method, 'aes-256-gcm');
      expect(config.password, 'password123');
    });

    test('validates method', () {
      expect(
        ShadowsocksConfig(
          displayName: 'Test',
          address: '10.0.0.1',
          port: 8388,
          method: 'aes-256-gcm',
          password: 'password',
          rawUri: 'ss://...',
          protocol: 'shadowsocks',
        ).method,
        'aes-256-gcm',
      );
    });
  });

  group('Config validation', () {
    test('rejects invalid port numbers', () {
      expect(
        () => WireGuardConfig(
          displayName: 'Test',
          address: '10.0.0.1',
          port: 65536, // Port out of range
          privateKey: 'abc',
          rawUri: 'wireguard://...',
          protocol: 'wireguard',
        ),
        throwsException,
      );
    });

    test('accepts valid port range', () {
      for (final port in [1, 80, 443, 8080, 65535]) {
        expect(
          WireGuardConfig(
            displayName: 'Test',
            address: '10.0.0.1',
            port: port,
            privateKey: 'abc',
            rawUri: 'wireguard://...',
            protocol: 'wireguard',
          ).port,
          port,
        );
      }
    });

    test('requires non-empty display name', () {
      expect(
        () => WireGuardConfig(
          displayName: '',
          address: '10.0.0.1',
          port: 51820,
          privateKey: 'abc',
          rawUri: 'wireguard://...',
          protocol: 'wireguard',
        ),
        throwsException,
      );
    });
  });
}
