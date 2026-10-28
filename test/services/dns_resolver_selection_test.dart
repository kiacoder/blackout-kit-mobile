/// Resolver selection end to end: controller -> service -> session options.
///
/// The behaviour under test is the pair: selecting a provider must write BOTH
/// addresses and the tunnel must receive both, in order. A single address was
/// the old behaviour and it silently dropped the secondary every operator of
/// these resolvers relies on.
library;

import 'dart:io';

import 'package:blackout_kit_mobile/controllers/settings_controller.dart';
import 'package:blackout_kit_mobile/models/dns_provider.dart';
import 'package:blackout_kit_mobile/models/vpn_session_options.dart';
import 'package:blackout_kit_mobile/services/dns_leak_prevention_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('settings controller', () {
    late Directory dir;
    late SettingsController settings;

    setUp(() async {
      await Hive.close();
      dir = await Directory.systemTemp.createTemp('bk_dns_settings');
      Hive.init(dir.path);
      settings = SettingsController();
      await settings.initialize();
    });

    tearDown(() async {
      await Hive.close();
      await dir.delete(recursive: true);
    });

    test('defaults to the Cloudflare pair', () {
      expect(settings.dnsProviderKey.value, 'cloudflare');
      expect(settings.customDnsServer.value, '1.1.1.1');
      expect(settings.dnsSecondaryServer.value, '1.0.0.1');
    });

    test('setDnsProvider writes both addresses', () {
      settings.setDnsProvider('shecan');
      expect(settings.dnsProviderKey.value, 'shecan');
      expect(settings.customDnsServer.value, '178.22.122.100');
      expect(settings.dnsSecondaryServer.value, '185.51.200.2');
    });

    test('setDnsProvider ignores an unknown key', () {
      settings.setDnsProvider('cloudflare');
      settings.setDnsProvider('not-a-provider');
      expect(settings.dnsProviderKey.value, 'cloudflare');
    });

    test('a custom address clears the pair', () {
      settings.setDnsProvider('electro');
      settings.setCustomDnsServer('9.9.9.9');
      expect(settings.dnsProviderKey.value, 'custom');
      expect(settings.customDnsServer.value, '9.9.9.9');
      expect(settings.dnsSecondaryServer.value, isEmpty);
    });

    test('the selection survives a save/load cycle', () async {
      settings.setDnsProvider('begzar');
      await settings.saveSettings();

      final reloaded = SettingsController();
      await reloaded.initialize();
      expect(reloaded.dnsProviderKey.value, 'begzar');
      expect(reloaded.customDnsServer.value, '185.55.226.26');
      expect(reloaded.dnsSecondaryServer.value, '185.55.226.25');
    });

    test('reset returns to the Cloudflare pair', () async {
      settings.setDnsProvider('radar');
      await settings.resetToDefaults();
      expect(settings.dnsProviderKey.value, 'cloudflare');
      expect(settings.customDnsServer.value, '1.1.1.1');
      expect(settings.dnsSecondaryServer.value, '1.0.0.1');
    });
  });

  group('DNS leak prevention service', () {
    late Directory dir;
    late SettingsController settings;
    late DNSLeakPreventionService service;

    setUp(() async {
      await Hive.close();
      dir = await Directory.systemTemp.createTemp('bk_dns_service');
      Hive.init(dir.path);
      settings = SettingsController();
      // Register BEFORE initialising: GetX's onInit starts its own async load,
      // and a load that lands after the test has written a value would put the
      // stored value back. Awaiting initialize() afterwards serialises both.
      Get.put<SettingsController>(settings);
      await settings.initialize();
      service = DNSLeakPreventionService();
    });

    tearDown(() async {
      Get.reset();
      await Hive.close();
      await dir.delete(recursive: true);
    });

    test('disabled advertises the single fallback', () {
      expect(service.resolvers, ['1.1.1.1']);
    });

    test('enabled advertises both addresses of the pair', () {
      settings.toggleDnsLeakPrevention(true);
      settings.setDnsProvider('shecan');
      expect(service.resolvers, ['178.22.122.100', '185.51.200.2']);
    });

    test('a custom address yields one resolver', () {
      settings.toggleDnsLeakPrevention(true);
      settings.setCustomDnsServer('9.9.9.9');
      expect(service.resolvers, ['9.9.9.9']);
      expect(service.selectedProvider, isNull);
    });

    test('selectProvider rejects an unknown key and reports why', () async {
      await service.selectProvider('nope');
      expect(service.lastError.value, contains('nope'));
      expect(settings.dnsProviderKey.value, 'cloudflare');
    });

    test('selectProvider accepts a catalogue key', () async {
      await service.selectProvider('yandex');
      expect(settings.dnsProviderKey.value, 'yandex');
      expect(service.selectedProvider?.name, 'Yandex');
    });

    test('applyTo hands the whole pair to the session options', () {
      settings.toggleDnsLeakPrevention(true);
      settings.setDnsProvider('google');

      final applied = service.applyTo(const VpnSessionOptions());

      expect(applied.dnsServers, ['8.8.8.8', '8.8.4.4']);
      expect(applied.routeDnsThroughProxy, isTrue);
    });

    test('applyTo leaves the caller list alone while disabled', () {
      const options = VpnSessionOptions(dnsServers: ['9.9.9.9']);
      final applied = service.applyTo(options);
      expect(applied.dnsServers, ['9.9.9.9']);
      expect(applied.routeDnsThroughProxy, isFalse);
    });

    test('describe names the provider and both addresses', () {
      settings.toggleDnsLeakPrevention(true);
      settings.setDnsProvider('radar');
      final text = service.describe();
      expect(text, contains('Radar'));
      expect(text, contains('10.202.10.10'));
      expect(text, contains('10.202.10.11'));
    });

    test('every catalogue provider is reachable through selectProvider', () async {
      for (final provider in DnsCatalog.all) {
        await service.selectProvider(provider.key);
        expect(service.selectedProvider?.key, provider.key);
        expect(service.lastError.value, isNull);
      }
    });
  });
}
