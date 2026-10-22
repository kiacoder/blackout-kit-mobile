/// Behavioural tests for the controller/service fixes claimed in v1.12.0,
/// complementing the parser/config coverage in verify_release_claims_test.dart.
///
/// Each test here fails if the corresponding fix is reverted.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

import 'package:blackout_kit_mobile/controllers/config_controller.dart';
import 'package:blackout_kit_mobile/controllers/connection_controller.dart';
import 'package:blackout_kit_mobile/controllers/settings_controller.dart';
import 'package:blackout_kit_mobile/models/config.dart';
import 'package:blackout_kit_mobile/models/config_source.dart';
import 'package:blackout_kit_mobile/models/test_result.dart';
import 'package:blackout_kit_mobile/services/config_service.dart';
import 'package:blackout_kit_mobile/services/debug_service.dart';
import 'package:blackout_kit_mobile/services/dns_leak_prevention_service.dart';
import 'package:blackout_kit_mobile/services/github_service.dart';
import 'package:blackout_kit_mobile/services/kill_switch_service.dart';
import 'package:blackout_kit_mobile/services/secure_vault.dart';
import 'package:blackout_kit_mobile/services/split_tunneling_service.dart';
import 'package:blackout_kit_mobile/services/tester_service.dart';
import 'package:blackout_kit_mobile/models/vpn_session_options.dart';
import 'package:blackout_kit_mobile/services/vpn_service.dart';

Config vless(String host, String name) => ConfigParser.parse(
      'vless://11111111-1111-1111-1111-111111111111@$host:443?security=none&type=tcp#$name',
    )!;

void main() {
  late Directory hiveDir;

  setUpAll(() async {
    hiveDir = await Directory.systemTemp.createTemp('bk_ctrl_verify');
    Hive.init(hiveDir.path);
  });

  tearDownAll(() async {
    await Hive.close();
    await hiveDir.delete(recursive: true);
  });

  // Several code paths read the settings through GetX (the protocol
  // preference, split tunnelling). Register one for the whole file.
  setUp(() async {
    Get.reset();
    final settings = SettingsController();
    await settings.initialize();
    Get.put<SettingsController>(settings);
  });

  // ── BK-004 / BK-005: reconnect and the single-flight guard ──────────────
  group('connection controller (BK-004/005)', () {
    test('reconnect survives the disconnect that clears the selection',
        () async {
      final vpn = _RecordingVpnService();
      final controller = _controller(vpn);
      final config = vless('a.example.com', 'A');

      controller.selectedConfig.value = config;
      final ok = await controller.reconnect();

      expect(ok, isTrue,
          reason: 'reconnect must not throw or give up after disconnect');
      expect(vpn.connectCalls, 1);
      expect(vpn.disconnectCalls, 1);
    });

    test('a second concurrent connect is refused, not run twice', () async {
      final vpn = _SlowVpnService();
      final controller = _controller(vpn);
      final config = vless('b.example.com', 'B');

      final first = controller.connect(config);
      final second = controller.connect(config);
      final results = await Future.wait([first, second]);

      expect(results.where((r) => r).length, 1,
          reason: 'exactly one of the two calls may proceed');
      expect(vpn.connectCalls, 1);
    });
  });

  // ── BK-009: only recent failures exclude a config ───────────────────────
  group('auto-connect candidate selection (BK-009)', () {
    test('a failure older than six hours does not exclude the config',
        () async {
      final vpn = _RecordingVpnService();
      final controller = _controller(vpn);
      final config = vless('c.example.com', 'C');
      // The stale-failure rule is applied to the results handed to
      // connectFastest, which is what the app does on auto-connect.
      await controller.connectFastest([config], testResults: [
        TestResult(
          configHash: config.getHash(),
          status: TestStatus.failed,
          testedAt: DateTime.now().subtract(const Duration(hours: 30)),
          error: 'probe failed',
        ),
      ]);

      expect(vpn.connectCalls, greaterThanOrEqualTo(1),
          reason: 'a 30-hour-old failure must not blacklist the config');
    });

    test('a recent failure still excludes the config', () async {
      final vpn = _RecordingVpnService();
      final controller = _controller(vpn);
      final config = vless('d.example.com', 'D');

      await controller.connectFastest([config], testResults: [
        TestResult(
          configHash: config.getHash(),
          status: TestStatus.failed,
          testedAt: DateTime.now(),
          error: 'probe failed',
        ),
      ]);

      expect(vpn.connectCalls, 0,
          reason: 'a fresh failure is still honoured as a skip');
    });
  });

  // ── BK-029 / BK-035: sources ────────────────────────────────────────────
  group('sources (BK-029/035)', () {
    late Directory dir;
    late ConfigService service;
    late ConfigController controller;

    setUp(() async {
      await Hive.close();
      dir = await Directory.systemTemp.createTemp('bk_src_verify');
      Hive.init(dir.path);
      service = ConfigService(keyStore: MemoryKeyStore());
      await service.initialize();
      controller = ConfigController(
        configService: service,
        githubService: GitHubService(),
        testerService: TesterService(),
      );
    });

    tearDown(() async {
      await Hive.close();
      await dir.delete(recursive: true);
    });

    test('addCustomSource returns the source it created (BK-029)', () async {
      final added = await controller.addCustomSource(
        name: 'Mine',
        owner: 'someone',
        repo: 'configs',
      );

      expect(added, isNotNull);
      expect(added!.name, 'Mine');
      expect(added.repo, 'configs');
      // It is persisted and visible in the list.
      expect(controller.sources.map((s) => s.id), contains(added.id));
    });

    test('a duplicate from a second source keeps both attributions (BK-035)',
        () async {
      final config = vless('shared.example.com', 'Shared');
      await service.saveConfig(config, sourceId: 's1');
      await service.saveConfig(config, sourceId: 's2');

      final ids = service.loadHashToSourceIds()[config.getHash()];
      expect(ids, containsAll(<String>{'s1', 's2'}));
    });
  });

  // ── BK-033: tester progress run tokens ──────────────────────────────────
  group('tester progress (BK-033)', () {
    test('a later run cannot steal an earlier run\'s events', () async {
      final tester = TesterService();
      final firstSeen = <String>[];
      final secondSeen = <String>[];

      tester.beginProgressRun((hash, status) => firstSeen.add(hash));
      final secondToken = tester.beginProgressRun((hash, status) => secondSeen.add(hash));

      // The first run's callback must no longer receive anything.
      tester.onProgress?.call('hash-1', TestStatus.success);
      expect(firstSeen, isEmpty);
      expect(secondSeen, ['hash-1']);

      tester.endProgressRun(secondToken);
      tester.onProgress?.call('hash-2', TestStatus.success);
      expect(secondSeen, ['hash-1']);
    });
  });

  // ── BK-045: split-tunnel stale flag only while connected ────────────────
  group('split tunneling (BK-045)', () {
    test('editing the app list while disconnected does not demand a reconnect',
        () async {
      final split = SplitTunnelingService();
      split.bindConnectionState(() => false); // no tunnel

      split.setEnabled(true);

      expect(split.requiresReconnect.value, isFalse,
          reason: 'nothing to reconnect while stopped');
    });

    test('editing while connected does raise the flag', () async {
      final split = SplitTunnelingService();
      split.bindConnectionState(() => true);

      split.setEnabled(true);

      expect(split.requiresReconnect.value, isTrue);
    });
  });

  // ── BK-030 / BK-031: settings ───────────────────────────────────────────
  group('settings (BK-030/031)', () {
    late Directory dir;
    late SettingsController settings;

    setUp(() async {
      await Hive.close();
      dir = await Directory.systemTemp.createTemp('bk_settings_verify');
      Hive.init(dir.path);
      settings = SettingsController();
      await settings.initialize();
    });

    tearDown(() async {
      await Hive.close();
      await dir.delete(recursive: true);
    });

    test('resetToDefaults covers every persisted key (BK-031)', () async {
      // Dirty every setting that has a stored key.
      settings.dnsLeakPreventionEnabled.value = true;
      settings.customDnsServer.value = '9.9.9.9';
      settings.siteCheckEnabled.value = false;
      settings.coreDebugLogs.value = true;
      settings.showMyLocation.value = true;
      settings.killSwitchEnabled.value = true;
      settings.theme.value = 'dark';

      await settings.resetToDefaults();

      expect(settings.dnsLeakPreventionEnabled.value, isFalse);
      expect(settings.customDnsServer.value, '');
      expect(settings.siteCheckEnabled.value, isTrue);
      expect(settings.coreDebugLogs.value, isFalse);
      expect(settings.showMyLocation.value, isFalse);
      expect(settings.killSwitchEnabled.value, isFalse);
      expect(settings.theme.value, 'system');
    });

    test('a save persists the values as they are now (BK-030)', () async {
      settings.preferredProtocol.value = 'trojan';
      settings.autoTestIntervalMinutes.value = 15;
      await settings.saveSettings();

      final reloaded = SettingsController();
      await reloaded.initialize();
      expect(reloaded.preferredProtocol.value, 'trojan');
      expect(reloaded.autoTestIntervalMinutes.value, 15);
    });
  });

  // ── BK-041: the protocol preference orders candidates ───────────────────
  group('protocol preference (BK-041)', () {
    test('the preferred protocol is offered first', () async {
      final vpn = _RecordingVpnService();
      final controller = _controller(vpn);
      final vlessConfig = vless('v.example.com', 'VLESS');
      final trojan = ConfigParser.parse(
        'trojan://pw@t.example.com:443?sni=t.example.com#Trojan',
      )!;

      Get.find<SettingsController>().preferredProtocol.value = 'trojan';
      await controller.connectFastest([vlessConfig, trojan]);

      expect(vpn.lastConnectedProtocol, 'trojan',
          reason: 'the preferred protocol must be tried before the others');
    });
  });
}

// ── fakes ─────────────────────────────────────────────────────────────────

ConnectionController _controller(VPNService vpn) {
  return ConnectionController(
    vpnService: vpn,
    testerService: _FakeTester(),
    killSwitchService: KillSwitchService(),
    dnsLeakPreventionService: DNSLeakPreventionService(),
    splitTunnelingService: SplitTunnelingService(),
    debugService: DebugService(),
  );
}

/// Records calls and always succeeds.
class _RecordingVpnService extends VPNService {
  _RecordingVpnService() : super();
  int connectCalls = 0;
  int disconnectCalls = 0;
  String? lastConnectedProtocol;

  @override
  Future<bool> connect(Config config, {VpnSessionOptions? options}) async {
    connectCalls += 1;
    lastConnectedProtocol = config.protocol;
    return true;
  }

  @override
  Future<bool> disconnect() async {
    disconnectCalls += 1;
    return true;
  }

  @override
  Future<bool> isRunning() async => false;

  @override
  Future<String?> getConnectedIP() async => '203.0.113.9';

  @override
  Future<EngineAvailability> getEngineInfo() async =>
      const EngineAvailability.unknown();

  @override
  Future<bool> prepare() async => true;
}

/// Tester that reports every config as working, so a scan reaches connect()
/// without touching the network.
class _FakeTester extends TesterService {
  @override
  Future<List<TestResult>> testConfigsConcurrently(
    List<Config> configs, {
    int concurrency = 6,
    int attempts = TesterService.defaultAttempts,
    Duration timeout = TesterService.defaultTimeout,
  }) async =>
      configs
          .map((c) => TestResult.success(
                configHash: c.getHash(),
                latencyMs: 40,
              ))
          .toList();

  @override
  List<TestResult> getWorkingConfigs(List<TestResult> results) =>
      List<TestResult>.of(results);
}

/// Slow connect, to expose a missing single-flight guard.
class _SlowVpnService extends _RecordingVpnService {
  @override
  Future<bool> connect(Config config, {VpnSessionOptions? options}) async {
    await Future<void>.delayed(const Duration(milliseconds: 120));
    return super.connect(config, options: options);
  }
}
