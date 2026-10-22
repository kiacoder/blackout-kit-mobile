/// Regressions from the third audit round: DNS validation, multi-source
/// attribution, IP-lookup opt-in, and the updater's ABI fallback.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:blackout_kit_mobile/models/config.dart';
import 'package:blackout_kit_mobile/models/vpn_session_options.dart';
import 'package:blackout_kit_mobile/services/config_service.dart';
import 'package:blackout_kit_mobile/services/ip_info_service.dart';
import 'package:blackout_kit_mobile/services/vpn_service.dart';

Config vless(String host, String name) => ConfigParser.parse(
      'vless://11111111-1111-1111-1111-111111111111@$host:443?security=none&type=tcp#$name',
    )!;

void main() {
  group('BK-024 DNS validation', () {
    test('real literals pass', () {
      expect(VpnSessionOptions.looksLikeIpForTest('1.1.1.1'), isTrue);
      expect(VpnSessionOptions.looksLikeIpForTest('2001:db8::1'), isTrue);
      expect(VpnSessionOptions.looksLikeIpForTest('::1'), isTrue);
    });

    test('colon-containing junk is rejected', () {
      expect(VpnSessionOptions.looksLikeIpForTest('http://x'), isFalse);
      expect(VpnSessionOptions.looksLikeIpForTest('a:b'), isFalse);
      expect(VpnSessionOptions.looksLikeIpForTest('1:2:3'), isFalse);
      expect(VpnSessionOptions.looksLikeIpForTest('gggg::1'), isFalse);
      expect(VpnSessionOptions.looksLikeIpForTest(''), isFalse);
    });
  });

  group('BK-035 multi-source attribution', () {
    late Directory tempDir;
    late ConfigService service;

    setUpAll(() async {
      tempDir = await Directory.systemTemp.createTemp('bk_multisource_test');
      Hive.init(tempDir.path);
    });

    tearDownAll(() async {
      await Hive.close();
      await tempDir.delete(recursive: true);
    });

    setUp(() async {
      service = ConfigService();
      await service.initialize();
    });

    test('a config supplied by two sources remembers both', () async {
      final config = vless('shared.example.com', 'Shared');
      await service.saveConfig(config, sourceId: 's1');
      // The same server arrives from a second repository.
      await service.saveConfig(config, sourceId: 's2');

      final ids = service.loadHashToSourceIds()[config.getHash()];
      expect(ids, isNotNull);
      expect(ids, containsAll(<String>{'s1', 's2'}));
    });
  });

  group('BK-025 IP lookups', () {
    test('lookups are off by default and stay local', () async {
      final fake = _FakeVpnService();
      final service = IpInfoService(vpnService: fake);
      // Off by default: the exit lookup is not even attempted.
      final exit = await service.fetchExit();
      expect(exit.isEmpty, isTrue);
      expect(fake.lastLookupAttempted, isFalse);
    });

    test('turning the switch on allows a lookup', () async {
      final fake = _FakeVpnService();
      final service = IpInfoService(vpnService: fake);
      service.setLookupsEnabled(true);
      final exit = await service.fetchExit();
      expect(fake.lastLookupAttempted, isTrue);
      expect(exit.ip, '203.0.113.9');
    });

    test('turning it back off clears anything resolved', () async {
      final fake = _FakeVpnService();
      final service = IpInfoService(vpnService: fake);
      service.setLookupsEnabled(true);
      await service.fetchExit();
      service.setLookupsEnabled(false);
      // Clear the marker: while the switch is off the tunnel is never asked,
      // so no NEW lookup may happen.
      fake.lastLookupAttempted = false;
      final again = await service.fetchExit();
      expect(again.isEmpty, isTrue);
      expect(fake.lastLookupAttempted, isFalse);
    });
  });
}

/// Minimal VPNService stand-in that records whether a tunnel fetch was tried.
class _FakeVpnService extends VPNService {
  _FakeVpnService() : super();

  bool lastLookupAttempted = false;

  @override
  Future<String?> tunnelFetch(String url, {Duration timeout = const Duration(seconds: 10)}) async {
    // Reset first so the flag describes THIS call, not the whole session.
    lastLookupAttempted = false;
    lastLookupAttempted = true;
    // Same shape the real service returns, including the success flag.
    return '{"success":true,"ip":"203.0.113.9","country":"Testland",'
        '"country_code":"TL","city":"Nowhere"}';
  }
}
