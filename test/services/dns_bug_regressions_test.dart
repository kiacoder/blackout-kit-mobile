/// Regressions found while auditing the Android DNS path.
///
/// Each test names the failure it pins, because every one of them produced a
/// tunnel that reported success while DNS was silently broken.
library;

import 'dart:io';

import 'package:blackout_kit_mobile/controllers/settings_controller.dart';
import 'package:blackout_kit_mobile/models/config.dart';
import 'package:blackout_kit_mobile/models/dns_provider.dart';
import 'package:blackout_kit_mobile/models/vpn_session_options.dart';
import 'package:blackout_kit_mobile/services/dns_leak_prevention_service.dart';
import 'package:blackout_kit_mobile/services/vpn_service.dart';
import 'package:blackout_kit_mobile/services/xray_config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ── BUG 1: an IPv6 resolver can never be reached by this tunnel ──────────
  //
  // The TUN is built with an IPv4 address only and `::/0` routed into it as a
  // deliberate v6 kill switch. Accepting a v6 resolver therefore produced a
  // tunnel that came up "connected" with every lookup black-holed.
  group('IPv6 resolvers are refused for the tunnel', () {
    test('isTunnelDns accepts IPv4 and rejects IPv6', () {
      expect(VpnSessionOptions.isTunnelDns('1.1.1.1'), isTrue);
      expect(VpnSessionOptions.isTunnelDns('2606:4700:4700::1111'), isFalse);
      expect(VpnSessionOptions.isTunnelDns('::1'), isFalse);
      expect(VpnSessionOptions.isTunnelDns('dns.example.com'), isFalse);
    });

    test('isIpLiteral still accepts IPv6 (it is a literal, just not usable)', () {
      expect(VpnSessionOptions.isIpLiteral('2606:4700::1'), isTrue);
      expect(VpnSessionOptions.isTunnelDns('2606:4700::1'), isFalse);
    });

    test('validationError explains why a v6 resolver is refused', () {
      const options = VpnSessionOptions(dnsServers: ['2606:4700:4700::1111']);
      final problem = options.validationError;
      expect(problem, isNotNull);
      expect(problem, contains('IPv6'));
      expect(problem, contains('black-holed'));
    });

    test('a v4 pair still validates', () {
      const options = VpnSessionOptions(
        dnsServers: ['178.22.122.100', '185.51.200.2'],
      );
      expect(options.validationError, isNull);
    });

    test("a config's IPv6 DNS is dropped instead of blocking the connect", () {
      // WireGuard profiles may carry a v6 resolver. Dropping it and falling
      // back keeps the connect working; passing it through would now fail
      // validation and refuse the tunnel entirely.
      final wg = WireGuardConfig(
        name: 'wg',
        rawUri: '',
        privateKey: 'k',
        dns: '2606:4700::1111, 1.0.0.1',
      );
      expect(VPNService.dnsServersForConfig(wg), ['1.0.0.1']);
    });

    test('a v6-only config falls back to the defaults', () {
      final wg = WireGuardConfig(
        name: 'wg',
        rawUri: '',
        privateKey: 'k',
        dns: '2606:4700::1111',
      );
      expect(VPNService.dnsServersForConfig(wg), ['1.1.1.1', '8.8.8.8']);
    });
  });

  // ── BUG 2: three copies of the IP validator, two of them weak ────────────
  //
  // `DnsCatalog.isIpLiteral` and the service's private copy both accepted any
  // string containing ':' — `"a:b"`, `"http://x"` — as IPv6, so garbage was
  // saved as a resolver and only failed later, at connect time.
  group('one IP validator, not three', () {
    test('the catalogue rejects colon junk', () {
      expect(DnsCatalog.isIpLiteral('1.1.1.1'), isTrue);
      expect(DnsCatalog.isIpLiteral('a:b'), isFalse);
      expect(DnsCatalog.isIpLiteral('http://x'), isFalse);
      expect(DnsCatalog.isIpLiteral('1:2:3'), isFalse);
      expect(DnsCatalog.isIpLiteral('1.1.1'), isFalse);
      expect(DnsCatalog.isIpLiteral('1.1.1.256'), isFalse);
    });

    test('parseServers drops everything unusable', () {
      expect(
        DnsCatalog.parseServers('1.1.1.1, a:b, 2606:4700::1, 8.8.8.8'),
        ['1.1.1.1', '8.8.8.8'],
      );
    });
  });

  group('DNSLeakPreventionService.setCustomDnsServer', () {
    late Directory dir;
    late SettingsController settings;
    late DNSLeakPreventionService service;

    setUp(() async {
      await Hive.close();
      dir = await Directory.systemTemp.createTemp('bk_dns_guard');
      Hive.init(dir.path);
      settings = SettingsController();
      Get.put<SettingsController>(settings);
      await settings.initialize();
      service = DNSLeakPreventionService();
    });

    tearDown(() async {
      Get.reset();
      await Hive.close();
      await dir.delete(recursive: true);
    });

    test('rejects a hostname with a clear message', () async {
      await service.setCustomDnsServer('dns.example.com');
      expect(service.lastError.value, contains('not an IP address'));
      expect(settings.customDnsServer.value, '1.1.1.1');
    });

    test('rejects colon junk that the old validator accepted', () async {
      await service.setCustomDnsServer('a:b');
      expect(service.lastError.value, isNotNull);
      expect(settings.dnsProviderKey.value, 'cloudflare');
    });

    test('rejects IPv6 with an explanation instead of accepting it', () async {
      await service.setCustomDnsServer('2606:4700:4700::1111');
      expect(service.lastError.value, contains('IPv6'));
      expect(settings.customDnsServer.value, '1.1.1.1');
      expect(settings.dnsProviderKey.value, 'cloudflare');
    });

    test('accepts a usable IPv4 address and clears the error', () async {
      await service.setCustomDnsServer(' 9.9.9.9 ');
      expect(service.lastError.value, isNull);
      expect(settings.customDnsServer.value, '9.9.9.9');
      expect(settings.dnsProviderKey.value, 'custom');
    });
  });

  // ── BUG 3: the chosen pair was a last resort in Xray ─────────────────────
  //
  // Xray queries `dns.servers` in order. With two hardcoded DoH endpoints
  // ahead of the caller's addresses, the resolver picked in Settings was only
  // tried after both DoH endpoints failed — and on a filtered network every
  // lookup paid two timeouts first.
  group('Xray puts the chosen resolvers first', () {
    Config config() => ConfigParser.parse(
          'vless://11111111-1111-1111-1111-111111111111@a.com:443',
        )!;

    test('the pair leads and the DoH endpoints follow', () {
      final doc = XrayConfigBuilder(
        routeDnsThroughProxy: true,
        dnsServers: const ['178.22.122.100', '185.51.200.2'],
      ).build(config());

      final servers = ((doc['dns'] as Map)['servers'] as List).cast<String>();
      expect(servers.take(2), ['178.22.122.100', '185.51.200.2']);
      expect(servers.skip(2).every((s) => s.startsWith('https://')), isTrue);
    });

    test('the DoH fallbacks are still there and still leak nothing', () {
      final doc = XrayConfigBuilder(
        routeDnsThroughProxy: true,
        dnsServers: const ['9.9.9.9'],
      ).build(config());

      final servers = ((doc['dns'] as Map)['servers'] as List).cast<String>();
      expect(servers, contains('https://cloudflare-dns.com/dns-query'));
      expect(servers.any((s) => s.contains('+local')), isFalse);
      expect(servers.contains('localhost'), isFalse);
    });
  });
}
