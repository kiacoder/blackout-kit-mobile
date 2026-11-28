/// Behavioural tests for the controller/service fixes claimed in v1.12.0,
/// complementing the parser/config coverage in verify_release_claims_test.dart.
///
/// Each test here fails if the corresponding fix is reverted.
library;

import 'dart:io';
import 'dart:async';

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
import 'package:blackout_kit_mobile/services/site_check_service.dart';
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

  // A failed TCP reachability probe must never exclude a real VPN attempt.
  group('auto-connect candidate selection', () {
    test('a failure older than six hours remains eligible', () async {
      final vpn = _RecordingVpnService();
      final controller = _controller(vpn);
      final config = vless('c.example.com', 'C');
      // The stale-failure rule is applied to the results handed to
      // connectFastest, which is what the app does on auto-connect.
      await controller.connectFastest([
        config
      ], testResults: [
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

    test('a recent failure remains eligible for real connection', () async {
      final vpn = _RecordingVpnService();
      final controller = _controller(vpn);
      final config = vless('d.example.com', 'D');

      await controller.connectFastest([
        config
      ], testResults: [
        TestResult(
          configHash: config.getHash(),
          status: TestStatus.failed,
          testedAt: DateTime.now(),
          error: 'probe failed',
        ),
      ]);

      expect(vpn.connectCalls, greaterThanOrEqualTo(1),
          reason: 'a fresh TCP failure cannot replace a real tunnel attempt');
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

    test('parallel bulk imports preserve attribution and count only new records', () async {
      final config = vless('parallel.example.com', 'Parallel');
      final other = vless('another.example.com', 'Other');
      final counts = await Future.wait([
        service.saveConfigs([config], sourceId: 's1'),
        service.saveConfigs([config, other], sourceId: 's2'),
      ]);
      expect(counts, [1, 1]);
      expect(service.loadHashToSourceIds()[config.getHash()], {'s1', 's2'});
      expect(await service.saveConfigs([config, other], sourceId: 's3'), 0);
      expect(service.getAllConfigs(), hasLength(2));
    });

    test('source toggle survives a delayed refresh and duplicate refresh is ignored', () async {
      final github = _DelayedGitHub();
      final ctrl = ConfigController(configService: service, githubService: github,
          testerService: TesterService());
      await ctrl.loadSources();
      final source = ctrl.sources.first;
      final fetch = ctrl.fetchFromSource(source);
      expect(await ctrl.fetchFromSource(source), 0);
      expect(await ctrl.removeSource(source.id), isFalse);
      await ctrl.toggleSource(source.id, false);
      github.pending.complete([vless('refresh.example.com', 'Refresh')]);
      expect(await fetch, 1);
      expect(ctrl.sources.firstWhere((s) => s.id == source.id).isEnabled, isFalse);
      expect(service.getAllSources().firstWhere((s) => s.id == source.id).isEnabled, isFalse);
      expect(github.calls, 1);
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
      final secondToken =
          tester.beginProgressRun((hash, status) => secondSeen.add(hash));

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
      // The documented default, matching what _loadSettings() uses. Resetting
      // to '' left DnsLeakPreventionService with an invalid resolver, so the
      // feature could not be re-enabled without typing an address by hand.
      expect(settings.customDnsServer.value, '1.1.1.1');
      expect(settings.siteCheckEnabled.value, isTrue);
      expect(settings.coreDebugLogs.value, isFalse);
      expect(settings.showMyLocation.value, isFalse);
      expect(settings.killSwitchEnabled.value, isFalse);
      expect(settings.theme.value, 'system');
      expect(settings.connectScanBatchSize.value, 50);
      expect(settings.connectVerificationStrategy.value, 'shortlist');
      expect(settings.connectWebsitePassThreshold.value, -1);
      expect(settings.connectFailureScanPolicy.value, 'next_batch');
    });

    test('a save persists the values as they are now (BK-030)', () async {
      settings.preferredProtocol.value = 'trojan';
      settings.autoTestIntervalMinutes.value = 15;
      settings.connectScanBatchSize.value = 37;
      settings.connectVerificationStrategy.value = 'all';
      settings.connectWebsitePassThreshold.value = 2;
      settings.connectFailureScanPolicy.value = 'restart';
      await settings.saveSettings();

      final reloaded = SettingsController();
      await reloaded.initialize();
      expect(reloaded.preferredProtocol.value, 'trojan');
      expect(reloaded.autoTestIntervalMinutes.value, 15);
      expect(reloaded.connectScanBatchSize.value, 37);
      expect(reloaded.connectVerificationStrategy.value, 'all');
      expect(reloaded.connectWebsitePassThreshold.value, 2);
      expect(reloaded.connectFailureScanPolicy.value, 'restart');
    });
  });

  group('scan candidate controls', () {
    test('plaintext VLESS to a public IP without domain host is refused',
        () async {
      final vpn = _RecordingVpnService();
      final controller = _controller(vpn);
      final config = ConfigParser.parse(
        'vless://11111111-1111-1111-1111-111111111111@203.0.113.8:443?security=none&type=tcp#Plain-IP',
      )!;

      final connected = await controller.connect(config);

      expect(connected, isFalse);
      expect(vpn.connectCalls, 0,
          reason: 'unsafe plaintext public-IP configs are refused before dial');
      expect(controller.statusMessage.value, contains('Plaintext VLESS'));
    });

    test('plaintext VLESS to a public IP with domain host is not pre-refused',
        () async {
      final vpn = _RecordingVpnService();
      final controller = _controller(vpn);
      final config = ConfigParser.parse(
        'vless://11111111-1111-1111-1111-111111111111@203.0.113.8:443?security=none&type=tcp&host=edge.example.com#Domain-host',
      )!;

      final connected = await controller.connect(config);

      expect(connected, isTrue);
      expect(vpn.connectCalls, 1);
    });

    test('shortlist mode attempts its configured candidate count', () async {
      final vpn = _RecordingVpnService()..failedConnectCount = 2;
      final settings = Get.find<SettingsController>();
      settings.siteCheckEnabled.value = false;
      settings.connectVerificationStrategy.value = 'shortlist';
      settings.connectScanBatchSize.value = 5;
      final controller = _controller(vpn);
      final configs = [
        vless('short-1.example.com', 'Short 1'),
        vless('short-2.example.com', 'Short 2'),
        vless('short-3.example.com', 'Short 3'),
        vless('short-4.example.com', 'Short 4'),
        vless('short-5.example.com', 'Short 5'),
      ];

      final connected = await controller.connectFastest(configs);

      expect(connected, isTrue);
      expect(vpn.connectCalls, 3);
    });

    test('native recovery is not a terminal failure and can be cancelled', () async {
      final vpn = _RecordingVpnService();
      final controller = _controller(vpn);
      controller.debugSetConnectedForTest(vless('fixture.example.com', 'Fixture'));
      controller.debugHandleNativeStatusForTest('reconnecting', null);
      expect(controller.nativeRecovering.value, isTrue);
      expect(controller.isConnected, isFalse);
      expect(controller.state.value, ConnectionState.connecting);
      expect(controller.recoveryAvailable.value, isFalse);
      expect(await controller.disconnect(), isTrue);
      expect(controller.nativeRecovering.value, isFalse);
      expect(controller.state.value, ConnectionState.idle);
    });

    test('terminal recovery failure clears the recovery marker', () {
      final controller = _controller(_RecordingVpnService());
      controller.debugSetConnectedForTest(vless('fixture.example.com', 'Fixture'));
      controller.debugHandleNativeStatusForTest('reconnecting', null);
      controller.debugHandleNativeStatusForTest('blocked', 'fixture stopped');
      expect(controller.nativeRecovering.value, isFalse);
      expect(controller.state.value, ConnectionState.error);
      expect(controller.recoveryAvailable.value, isTrue);
    });

    test('reattached UI recognizes retained tunnel without connected claim', () async {
      final vpn = _RecordingVpnService()..heldTunnel = true;
      final controller = _controller(vpn);
      await controller.reconcileWithNativeService();
      expect(controller.nativeTunnelHeld.value, isTrue);
      expect(controller.isConnected, isFalse);
      expect(controller.state.value, ConnectionState.error);
      expect(vpn.connectCalls, 0);
      expect(await controller.disconnect(), isTrue);
      expect(controller.nativeTunnelHeld.value, isFalse);
      expect(controller.recoveryAvailable.value, isFalse);
      expect(vpn.disconnectCalls, 1);
    });

    test('failed explicit release preserves the retained tunnel marker', () async {
      final vpn = _RecordingVpnService()
        ..heldTunnel = true
        ..disconnectSucceeds = false;
      final controller = _controller(vpn);
      await controller.reconcileWithNativeService();
      expect(await controller.disconnect(), isFalse);
      expect(controller.nativeTunnelHeld.value, isTrue);
      expect(controller.isConnected, isFalse);
      vpn.disconnectSucceeds = true;
      expect(await controller.disconnect(), isTrue);
      expect(controller.nativeTunnelHeld.value, isFalse);
    });

    test('pending cleanup never claims a held or connected tunnel', () async {
      final vpn = _RecordingVpnService();
      final controller = _controller(vpn);
      controller.debugSetConnectedForTest(vless('fixture.example.com', 'Fixture'));
      controller.debugHandleNativeStatusForTest('blocked', 'fixture stopped');
      controller.debugHandleNativeStatusForTest('cleanup_pending', 'fixture stop timed out');
      expect(controller.nativeCleanupPending.value, isTrue);
      expect(controller.nativeTunnelHeld.value, isFalse);
      expect(controller.isConnected, isFalse);
      expect(controller.recoveryAvailable.value, isFalse);
      expect(await controller.disconnect(), isTrue);
      expect(controller.nativeCleanupPending.value, isFalse);
    });

    test('native candidate rejection does not request recovery and tries next',
        () async {
      final vpn = _RecordingVpnService();
      final settings = Get.find<SettingsController>();
      settings.siteCheckEnabled.value = false;
      settings.connectVerificationStrategy.value = 'shortlist';
      settings.connectScanBatchSize.value = 3;
      final controller = _controller(vpn);
      final configs = [
        vless('rejected.example.com', 'Rejected'),
        vless('usable.example.com', 'Usable'),
      ];
      vpn.onConnect = (config) {
        if (config.address == 'rejected.example.com') {
          vpn.lastErrorForTest = 'Xray core rejected this candidate';
          controller.debugHandleNativeStatusForTest(
              'error', vpn.lastErrorForTest);
          return false;
        }
        return true;
      };

      expect(await controller.connectFastest(configs), isTrue);
      expect(vpn.connectedAddresses,
          ['rejected.example.com', 'usable.example.com']);
      expect(controller.recoveryAvailable.value, isFalse);
      expect(controller.candidateConfig.value, isNull);
      expect(controller.candidateError.value, isEmpty,
          reason: 'a successful later candidate clears prior rejection copy');
      expect(controller.statusMessage.value, contains('Usable'));
      expect(controller.selectedConfig.value?.address, 'usable.example.com');
      expect(controller.lastKnownWorkingConfig.value?.address,
          'usable.example.com');
    });

    test('site-failing tunnel does not replace the last verified config',
        () async {
      final vpn = _RecordingVpnService();
      final settings = Get.find<SettingsController>();
      settings.siteCheckEnabled.value = true;
      settings.connectVerificationStrategy.value = 'all';
      settings.connectWebsitePassThreshold.value = -1;
      settings.siteCheckUrls.assignAll(['check.example.com']);
      final checker = _SequenceSiteCheckService(vpn, settings, outcomes: [
        false,
        true,
      ]);
      final controller = _controller(vpn, siteCheckService: checker);
      final previouslyGood = vless('good-before.example.com', 'Known good');
      controller.lastKnownWorkingConfig.value = previouslyGood;
      controller.selectedConfig.value = previouslyGood;
      final configs = [
        vless('bad-websites.example.com', 'Tunnel but no traffic'),
        vless('good-websites.example.com', 'Loads sites'),
      ];

      expect(await controller.connectFastest(configs), isTrue);
      expect(controller.selectedConfig.value?.address,
          'good-websites.example.com');
      expect(controller.lastKnownWorkingConfig.value?.address,
          'good-websites.example.com');
      expect(vpn.disconnectCalls, 1);
    });

    test('unresolved exit location does not mark a live tunnel failed',
        () async {
      final vpn = _RecordingVpnService();
      final controller = _controller(vpn);
      final config = vless('located-later.example.com', 'Location pending');
      final connected = await controller.connect(config);

      expect(connected, isTrue);
      expect(controller.isConnected, isTrue);
      expect(controller.recoveryAvailable.value, isFalse,
          reason: 'IP/location lookups are informational, not tunnel liveness');
    });

    test('native AmneziaWG is accepted when its traffic verifier succeeds', () async {
      final vpn = _RecordingVpnService()..nativeTunnel = true;
      final settings = Get.find<SettingsController>();
      settings.siteCheckEnabled.value = true;
      final controller = _controller(vpn,
          siteCheckService: _FakeSiteCheckService(vpn, settings, alive: true));
      final config = ConfigParser.parse("""
[Interface]
PrivateKey = AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQE=
Address = 10.89.0.2/32
DNS = 1.1.1.1
Jc = 4
Jmin = 40
Jmax = 70
[Peer]
PublicKey = AgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgI=
AllowedIPs = 0.0.0.0/0
Endpoint = 127.0.0.1:9
""")!;
      expect(config, isA<AmneziaWGConfig>());
      expect(await controller.connect(config), isTrue);
      expect(controller.isConnected, isTrue);
      expect(vpn.disconnectCalls, 0);
      expect(controller.lastKnownWorkingConfig.value, config);
    });

    test('direct connect refuses tunnel that starts but cannot load websites',
        () async {
      final vpn = _RecordingVpnService();
      final settings = Get.find<SettingsController>();
      settings.siteCheckEnabled.value = true;
      final checker = _FakeSiteCheckService(vpn, settings, alive: false);
      final controller = _controller(vpn, siteCheckService: checker);
      final prior = vless('prior.example.com', 'Prior');
      controller.lastKnownWorkingConfig.value = prior;
      expect(await controller.connect(vless('dead.example.com', 'Dead')), isFalse);
      expect(controller.isConnected, isFalse);
      expect(vpn.disconnectCalls, 1);
      expect(controller.statusMessage.value, contains('nothing loads'));
      expect(controller.lastKnownWorkingConfig.value, prior);
    });

    test('first candidate mode verifies traffic before accepting a tunnel', () async {
      final vpn = _RecordingVpnService();
      final settings = Get.find<SettingsController>();
      settings.autoSelectFastest.value = false;
      settings.siteCheckEnabled.value = true;
      final controller = _controller(vpn,
          siteCheckService: _FakeSiteCheckService(vpn, settings, alive: false));
      expect(await controller.connectFastest([vless('dead.example.com', 'Dead')]), isFalse);
      expect(vpn.disconnectCalls, 1);
      expect(controller.isConnected, isFalse);
    });

    test('late failed liveness probe cannot disconnect a replacement tunnel', () async {
      final vpn = _RecordingVpnService();
      final settings = Get.find<SettingsController>();
      settings.siteCheckEnabled.value = true;
      final checker = _DelayedSiteCheck(vpn, settings);
      final controller = _controller(vpn, siteCheckService: checker);
      controller.debugSetConnectedForTest(vless('old.example.com', 'Old'));
      final probe = controller.debugVerifyTunnelAliveForTest();
      await checker.started.future;
      settings.siteCheckEnabled.value = false;
      expect(await controller.disconnect(), isTrue);
      final replacement = vless('new.example.com', 'New');
      expect(await controller.connect(replacement), isTrue);
      checker.pending.complete(false);
      await probe;
      expect(controller.isConnected, isTrue);
      expect(controller.selectedConfig.value, replacement);
      expect(vpn.disconnectCalls, 1);
    });

    test('cancel during website verification discards the late success', () async {
      final vpn = _RecordingVpnService();
      final settings = Get.find<SettingsController>();
      settings.siteCheckEnabled.value = true;
      settings.siteCheckUrls.assignAll(['check.example.com']);
      settings.autoSelectFastest.value = true;
      final checker = _DelayedSiteCheck(vpn, settings);
      final controller = _controller(vpn, siteCheckService: checker);
      final scan = controller.connectFastest([vless('cancel.example.com', 'Cancel')]);
      await checker.started.future;
      expect(controller.cancelScan(), isTrue);
      checker.pending.complete(true);
      expect(await scan, isFalse);
      expect(controller.isConnected, isFalse);
      expect(controller.candidateConfig.value, isNull);
      expect(controller.lastKnownWorkingConfig.value, isNull);
      expect(vpn.disconnectCalls, 1);
    });

    test('manual connection check cannot declare a dead tunnel working', () async {
      final vpn = _RecordingVpnService();
      final settings = Get.find<SettingsController>();
      final controller = _controller(vpn,
          siteCheckService: _FakeSiteCheckService(vpn, settings, alive: false));
      controller.debugSetConnectedForTest(vless('manual.example.com', 'Manual'));
      expect(await controller.testConnection(), isFalse);
      expect(controller.isConnected, isFalse);
      expect(vpn.disconnectCalls, 1);
    });

    test('unknown status reply is not proof that tunnel has stopped', () async {
      final vpn = _RecordingVpnService();
      final controller = _controller(vpn);
      controller.debugSetConnectedForTest(vless('active.example.com', 'Active'));
      await controller.reconcileWithNativeService();
      expect(controller.isConnected, isTrue);
    });

    test('failed website liveness check opens explicit recovery', () async {
      final vpn = _RecordingVpnService();
      final settings = Get.find<SettingsController>();
      settings.siteCheckEnabled.value = true;
      final checker = _SequenceSiteCheckService(vpn, settings, outcomes: [true, false]);
      final controller = _controller(vpn, siteCheckService: checker);
      final config = vless('dead-tunnel.example.com', 'Dead tunnel');
      expect(await controller.connect(config), isTrue);

      await controller.debugVerifyTunnelAliveForTest();

      expect(controller.isConnected, isFalse);
      expect(controller.recoveryAvailable.value, isTrue);
      expect(controller.recoveryReason.value, contains('nothing loads'));
    });

    test('recovery cursor resumes the remaining config in the same batch',
        () async {
      final vpn = _RecordingVpnService();
      final settings = Get.find<SettingsController>();
      settings.siteCheckEnabled.value = false;
      settings.connectVerificationStrategy.value = 'shortlist';
      settings.connectScanBatchSize.value = 3;
      final controller = _controller(vpn);
      final configs = [
        vless('cursor-1.example.com', 'Cursor 1'),
        vless('cursor-2.example.com', 'Cursor 2'),
        vless('cursor-3.example.com', 'Cursor 3'),
      ];
      expect(await controller.connectFastest(configs), isTrue);
      expect(vpn.lastConnectedAddress, 'cursor-1.example.com');
      vpn.onConnect = (_) => false;
      controller.debugRequestRecoveryForTest();

      expect(await controller.resumeScanAfterFailure(), isFalse);
      expect(vpn.connectedAddresses[1], 'cursor-2.example.com');
      expect(controller.scanItemsTotal.value, 2);
      expect(controller.scanBatchCount.value, 1);
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

class _DelayedGitHub extends GitHubService {
  final pending = Completer<List<Config>>();
  int calls = 0;
  @override
  Future<List<Config>> fetchConfigsFromSource(ConfigSource source, {String? filePattern}) {
    calls++;
    return pending.future;
  }
}

class _DelayedSiteCheck extends SiteCheckService {
  final started = Completer<void>();
  final pending = Completer<bool>();
  _DelayedSiteCheck(VPNService vpn, SettingsController settings)
      : super(vpnService: vpn, settings: settings);
  @override
  Future<bool> verifyLiveConnection({Duration timeout = const Duration(seconds: 8)}) {
    if (!started.isCompleted) started.complete();
    return pending.future;
  }
  @override
  Future<List<SiteCheckOutcome>> checkLiveConnection({Duration timeout = const Duration(seconds: 10)}) async {
    final alive = await verifyLiveConnection();
    return [for (final host in liveCheckHosts) SiteCheckOutcome(host: host, ok: alive)];
  }
}

class _SequenceSiteCheckService extends SiteCheckService {
  final List<bool> outcomes;
  int _nextOutcome = 0;

  _SequenceSiteCheckService(
    VPNService vpn,
    SettingsController settings, {
    required this.outcomes,
  }) : super(vpnService: vpn, settings: settings);

  @override
  bool get enabled => true;

  @override
  Future<List<SiteCheckOutcome>> checkLiveConnection({
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final passed = outcomes[_nextOutcome++];
    return [SiteCheckOutcome(host: 'check.example.com', ok: passed)];
  }

  @override
  Future<bool> verifyLiveConnection({
    Duration timeout = const Duration(seconds: 8),
  }) async =>
      outcomes[_nextOutcome++];
}

class _FakeSiteCheckService extends SiteCheckService {
  final bool alive;

  _FakeSiteCheckService(VPNService vpn, SettingsController settings,
      {required this.alive})
      : super(vpnService: vpn, settings: settings);

  @override
  bool get enabled => true;

  @override
  Future<bool> verifyLiveConnection(
          {Duration timeout = const Duration(seconds: 8)}) async =>
      alive;
}

ConnectionController _controller(
  VPNService vpn, {
  SiteCheckService? siteCheckService,
}) {
  return ConnectionController(
    vpnService: vpn,
    siteCheckService: siteCheckService,
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
  bool nativeTunnel = false;
  bool heldTunnel = false;
  bool disconnectSucceeds = true;

  @override
  Future<Map<String, dynamic>> getStatus() async => {
    'activeNativeTunnel': nativeTunnel,
    if (heldTunnel) 'isRunning': false,
    if (heldTunnel) 'isTunnelHeld': true,
  };

  int connectCalls = 0;
  int disconnectCalls = 0;
  String? lastConnectedProtocol;
  String? lastConnectedAddress;
  final List<String> connectedAddresses = [];
  int failedConnectCount = 0;
  String? lastErrorForTest;
  bool Function(Config config)? onConnect;

  @override
  String? get lastError => lastErrorForTest;

  @override
  Future<bool> connect(Config config, {VpnSessionOptions? options}) async {
    connectCalls += 1;
    lastConnectedProtocol = config.protocol;
    lastConnectedAddress = config.address;
    connectedAddresses.add(config.address);
    lastErrorForTest = null;
    if (failedConnectCount > 0) {
      failedConnectCount--;
      return false;
    }
    return onConnect?.call(config) ?? true;
  }

  @override
  Future<bool> disconnect() async {
    disconnectCalls += 1;
    if (disconnectSucceeds) heldTunnel = false;
    return disconnectSucceeds;
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
