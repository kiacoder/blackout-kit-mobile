import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:blackout_kit_mobile/models/config.dart';
import 'package:blackout_kit_mobile/services/config_service.dart';

void main() {
  group('SNI relay profile (configuration only)', () {
    const validUri =
        'sni://alice:secret@relay.example:443?sni=front.example.com&transport=http-connect#Work';

    test('parses endpoint, SNI and credentials without claiming connectability', () {
      final profile = ConfigParser.parse(validUri) as SniRelayConfig?;
      expect(profile, isNotNull);
      expect(profile!.address, 'relay.example');
      expect(profile.port, 443);
      expect(profile.serverName, 'front.example.com');
      expect(profile.username, 'alice');
      expect(profile.password, 'secret');
      expect(profile.validate(), isTrue);
      expect(profile.connect(), completion(isFalse));
    });

    test('is invalid without SNI or with an unknown transport', () {
      final missingSni = ConfigParser.parse(
        'sni://relay.example:443?transport=http-connect',
      ) as SniRelayConfig?;
      final unknownTransport = ConfigParser.parse(
        'sni://relay.example:443?sni=front.example.com&transport=magic',
      ) as SniRelayConfig?;
      expect(missingSni?.validate(), isFalse);
      expect(unknownTransport?.validate(), isFalse);
    });

    test('embedded subscription parser extracts endpoint-gated links', () {
      final parsed = ConfigParser.parseMultiple(
        'SNI: $validUri\nMHRV: mhrv://relay?endpoint=https%3A%2F%2Fscript.example%2Fexec',
      );
      expect(parsed.map((c) => c.protocol), containsAll(['sni', 'mhrv']));
    });
  });

  group('MHRV relay profile (configuration only)', () {
    test('requires a valid HTTPS endpoint and does not claim a VPN tunnel', () {
      final profile = ConfigParser.parse(
        'mhrv://relay?endpoint=https%3A%2F%2Fscript.example%2Fexec#School',
      ) as MhrvRelayConfig?;
      expect(profile, isNotNull);
      expect(profile!.endpoint.toString(), 'https://script.example/exec');
      expect(profile.validate(), isTrue);
      expect(profile.connect(), completion(isFalse));

      final insecure = ConfigParser.parse(
        'mhrv://relay?endpoint=http%3A%2F%2Fscript.example%2Fexec',
      ) as MhrvRelayConfig?;
      expect(insecure?.validate(), isFalse);
    });

    test('retains an optional bearer token in the endpoint URI', () {
      final profile = ConfigParser.parse(
        'mhrv://relay?endpoint=https%3A%2F%2Fscript.example%2Fexec&token=abc123',
      ) as MhrvRelayConfig?;
      expect(profile?.bearerToken, 'abc123');
    });
  });

  group('endpoint-gated profile storage', () {
    late Directory tempDir;
    late ConfigService service;

    setUpAll(() async {
      tempDir = await Directory.systemTemp.createTemp('endpoint_profile_test');
      Hive.init(tempDir.path);
    });

    setUp(() async {
      service = ConfigService();
      await service.initialize();
    });

    tearDownAll(() async {
      await Hive.close();
      await tempDir.delete(recursive: true);
    });

    test('SNI and MHRV profiles survive save and reload', () async {
      final sni = ConfigParser.parse(
        'sni://relay.example:443?sni=front.example.com&transport=http-connect#SNI',
      ) as SniRelayConfig;
      final mhrv = ConfigParser.parse(
        'mhrv://relay?endpoint=https%3A%2F%2Fscript.example%2Fexec&token=tkn#MHRV',
      ) as MhrvRelayConfig;

      expect(await service.saveConfig(sni), isTrue);
      expect(await service.saveConfig(mhrv), isTrue);

      final loaded = service.getAllConfigs();
      final loadedSni = loaded.whereType<SniRelayConfig>().single;
      final loadedMhrv = loaded.whereType<MhrvRelayConfig>().single;
      expect(loadedSni.serverName, 'front.example.com');
      expect(loadedMhrv.endpoint.toString(), 'https://script.example/exec');
      expect(loadedMhrv.bearerToken, 'tkn');
      expect(loadedSni.connect(), completion(isFalse));
      expect(loadedMhrv.connect(), completion(isFalse));
    });
  });
}
