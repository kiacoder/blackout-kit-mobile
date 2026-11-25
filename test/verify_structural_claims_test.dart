/// Structural verification for the fixes that live in widget or native code,
/// where a behavioural unit test is not practical.
///
/// These read the source and assert the fix is present in the right order.
/// They are weaker than a behavioural test but they are mutation-checked:
/// reverting the fix makes the matching assertion fail, so an accidental
/// regression cannot slip through unnoticed.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

void main() {
  final repo = Directory.current.path;
  String source(String relative) => _read('$repo/$relative');

  group('BK-001 editor save order', () {
    test('the replacement is stored before the old record is deleted', () {
      final src = source('lib/screens/config_editor_screen.dart');
      // Prefix match, not the exact call: the editor now passes the original
      // source id through so an edited config keeps its attribution.
      final saveAt = src.indexOf('saveConfig(parsed');
      final deleteAt = src.indexOf('deleteConfig(widget.config)');
      expect(saveAt, greaterThan(-1));
      expect(deleteAt, greaterThan(-1));
      expect(saveAt, lessThan(deleteAt),
          reason: 'deleting first is the data-loss bug');
    });
  });

  group('BK-006 subscription file import', () {
    test('a multi-config payload is not collapsed into one config', () {
      final src = source('lib/screens/config_import_screen.dart');
      expect(src.contains('multiple.length > 1'), isTrue);
      expect(src.contains('ConfigParser.parseMultiple(content)'), isTrue);
    });
  });

  group('BK-023 settings load before dependants', () {
    test('settings are awaited before the connection controller is built', () {
      final src = source('lib/main.dart');
      final awaitAt = src.indexOf('await settingsController.initialize()');
      final controllerAt = src.indexOf('ConnectionController(');
      expect(awaitAt, greaterThan(-1));
      expect(controllerAt, greaterThan(-1));
      expect(awaitAt, lessThan(controllerAt));
    });
  });

  group('BK-026 clipboard single-flight', () {
    test('the clipboard dialog respects the open-dialog guard', () {
      final src = source('lib/screens/config_import_screen.dart');
      expect(src.contains('if (!_dialogOpen && !_saving)'), isTrue);
    });
  });

  group('BK-032 benchmark scope', () {
    test('the benchmark uses visibleConfigs, not allConfigs', () {
      final src = source('lib/screens/speed_test_screen.dart');
      expect(src.contains('_configController.visibleConfigs'), isTrue);
    });
  });

  group('BK-037 oversized QR', () {
    test('the QR widget reports content-too-long instead of a blank square', () {
      final src = source('lib/screens/config_editor_screen.dart');
      expect(src.contains('errorStateBuilder'), isTrue);
    });
  });

  group('BK-038/BK-039 file decoding and size', () {
    test('file bytes are decoded as UTF-8 with a size cap', () {
      final src = source('lib/screens/config_import_screen.dart');
      expect(src.contains('utf8.decode(file.bytes!'), isTrue);
      expect(src.contains('maxImportBytes'), isTrue);
    });
  });

  group('BK-040 camera controls', () {
    test('torch and camera-switch failures are caught', () {
      final src = source('lib/screens/config_import_screen.dart');
      expect(src.contains('await _scannerController.toggleTorch()'), isTrue);
      expect(src.contains('await _scannerController.switchCamera()'), isTrue);
    });
  });

  group('BK-042 honest copy', () {
    test('the toggles describe what the app actually does', () {
      final src = source('lib/screens/settings_screen.dart');
      expect(src.contains('No data leaves your device'), isTrue);
      expect(src.contains('latency of the selected config'), isTrue);
    });
  });

  group('BK-043 one-pass repository counts', () {
    test('counts are computed once per build, not once per source', () {
      final src = source('lib/screens/settings_screen.dart');
      expect(src.contains('final sourceCounts ='), isTrue);
      expect(src.contains('sourceCounts[source.id]'), isTrue);
      // The old call inside the loop must be gone.
      expect(src.contains('configService.countConfigsBySource()[source.id]'),
          isFalse);
    });
  });

  group('BK-046 small screens', () {
    test('the details sheet is bounded, scrollable and reflowing', () {
      final src = source('lib/screens/library_screen.dart');
      expect(src.contains('constraints: BoxConstraints(maxHeight: sheetHeight)'),
          isTrue);
      expect(src.contains('child: SingleChildScrollView('), isTrue);
      expect(src.contains('textScaler: TextScaler.linear(textScale)'), isTrue);
      expect(src.contains('Wrap('), isTrue);
    });
  });

  group('BK-051 updater UI', () {
    test('progress is reactive and install errors reach the UI', () {
      final src = source('lib/screens/settings_screen.dart');
      expect(src.contains('title: Obx(() => Text('), isTrue);
      // Install failures reach the UI, and a signing-key mismatch gets the
      // recovery panel instead of a Retry that can never succeed.
      expect(src.contains('installer_failed'), isTrue);
      expect(src.contains('_signerMismatch = true;'), isTrue);
    });
  });

  group('BK-008 fetch failures', () {
    test('an unreachable source raises instead of returning empty', () {
      final src = source('lib/services/github_service.dart');
      expect(src.contains('class SourceUnavailableException'), isTrue);
      expect(src.contains('throw const SourceUnavailableException('), isTrue);
    });
  });

  group('BK-049 notification permission', () {
    test('the permission is requested on the native side', () {
      final kotlin =
          source('android/app/src/main/kotlin/com/blackoutkit/vpn/VpnPlugin.kt');
      expect(kotlin.contains('"requestNotificationPermission"'), isTrue);
      expect(kotlin.contains('addRequestPermissionsResultListener'), isTrue);
      expect(kotlin.contains('Manifest.permission.POST_NOTIFICATIONS'), isTrue);
    });
  });

  group('BK-011/012/013 native teardown and consent', () {
    test('the held-tunnel state is persisted and restored', () {
      final svc = source(
          'android/app/src/main/kotlin/com/blackoutkit/vpn/BlackoutVpnService.kt');
      expect(svc.contains('KEY_HELD_BLOCKING'), isTrue);
      expect(svc.contains('onTeardownComplete'), isTrue);
    });

    test('a superseded consent request settles the previous one', () {
      final plugin =
          source('android/app/src/main/kotlin/com/blackoutkit/vpn/VpnPlugin.kt');
      expect(plugin.contains('CONSENT_SUPERSEDED'), isTrue);
    });

    test('engine death holds the TUN only for an active kill-switch request', () {
      final svc = source(
          'android/app/src/main/kotlin/com/blackoutkit/vpn/BlackoutVpnService.kt');
      expect(svc.contains('if (holdTunnelOnFailure && tun != null)'), isTrue);
      expect(
          RegExp(r'\.putBoolean\(KEY_HELD_BLOCKING, true\)\s*\.apply\(\)')
              .hasMatch(svc),
          isTrue);
      expect(svc.contains('ticket.publish { notifyStatus("blocked") }'), isTrue);
      expect(svc.contains('isRunning = false'), isTrue);
    });
  });

  group('BK-022 sing-box checker timeout', () {
    test('the checker has a hard timeout', () {
      final commands =
          source('android/app/src/main/kotlin/com/blackoutkit/vpn/EngineCommands.kt');
      expect(commands.contains('timeoutMs: Long = 20_000'), isTrue);
      expect(commands, contains('ProcessCompat.waitForExit(process, timeoutMs)'));
      expect(commands, contains('ProcessCompat.forceStop(process)'));
      final compat = source(
          'android/app/src/main/kotlin/com/blackoutkit/vpn/ProcessCompat.kt');
      expect(compat, contains('System.nanoTime()'));
      expect(compat, contains('FORCIBLE_DESTROY_MIN_API = 26'));
      expect(compat, contains('Build.VERSION.SDK_INT >= FORCIBLE_DESTROY_MIN_API'));
      expect(compat, contains('process.destroyForcibly()'));
    });
  });

  group('native tunnel packaging gate', () {
    test('combined WG/AWG runtime is debug-only and release stays disabled', () {
      final gradle = source('android/app/build.gradle');
      final engine = source(
          'android/app/src/main/kotlin/com/blackoutkit/vpn/NativeTunnelEngine.kt');
      expect(gradle.contains('libblackout-tunnels.so'), isTrue);
      expect(gradle.contains('Refusing stale dual-Go-runtime native tunnel staging'),
          isTrue);
      expect(gradle.contains('sourceSets.debug.jniLibs.srcDir nativeDir'), isTrue);
      expect(engine.contains('System.loadLibrary("blackout-tunnels")'), isTrue);
      expect(engine.contains('System.loadLibrary("blackout-awg")'), isFalse);
      expect(engine.contains('System.loadLibrary("blackout-wireguard")'), isFalse);
      expect(
          gradle.contains('buildConfigField "boolean", "ENABLE_EXPERIMENTAL_NATIVE_TUNNELS", "false"'),
          isTrue);
    });

    test('engine catalogue is passive and never loads a Go runtime', () {
      final plugin = source('android/app/src/main/kotlin/com/blackoutkit/vpn/VpnPlugin.kt');
      final catalogue = source('android/app/src/main/kotlin/com/blackoutkit/vpn/EngineCatalogue.kt');
      expect(plugin, contains('EngineCatalogue('));
      expect(catalogue, contains('bundled("libgojni.so")'));
      expect(catalogue, contains('bundled("libblackout-tunnels.so")'));
      for (final forbidden in ['XrayEngine.version(', 'LibboxEngine.version(',
        'LibboxEngine.isAvailable(', 'NativeTunnelEngine.available(', 'System.loadLibrary(', '.claim(']) {
        expect(catalogue, isNot(contains(forbidden)));
      }
      for (final engine in ['XrayEngine', 'LibboxEngine', 'NativeTunnelEngine']) {
        expect(source('android/app/src/main/kotlin/com/blackoutkit/vpn/$engine.kt'),
          contains('GoRuntimeAdmission.process.claim('));
      }
    });

    test('native live verification binds to VPN network, never default HTTP or SOCKS fallback', () {
      final plugin = source('android/app/src/main/kotlin/com/blackoutkit/vpn/VpnPlugin.kt');
      final probe = source('android/app/src/main/kotlin/com/blackoutkit/vpn/SiteProbeRunner.kt');
      expect(plugin, contains('worker.run(request)'));
      expect(plugin, contains('worker.currentOutcomes(request, outcomes)'));
      expect(probe, contains('NetworkCapabilities.TRANSPORT_VPN'));
      expect(
            probe,
            matches(RegExp(r'network\.openConnection\(\s*target,\s*Proxy\.NO_PROXY,?\s*\)')));
      expect(probe, contains('if (request.native && network == null)'));
      expect(probe, contains('return request.urls.map'));
      expect(probe, contains('check(!request.native)'));
      expect(probe, contains('nativeSessionCurrent(session)'));
      final service = source('android/app/src/main/kotlin/com/blackoutkit/vpn/BlackoutVpnService.kt');
      final native = service.split('private fun establishNative(').last.split('private fun establish(').first;
      expect(native, contains('(allowed + packageName).distinct()'));
      expect(native, isNot(contains('(disallowed + packageName)')));
      expect(native, contains('NativeTunnelEngine.start('));
    });

    test('VPN revoke callback is atomically taken and dispatched on main', () {
      final service = source(
          'android/app/src/main/kotlin/com/blackoutkit/vpn/BlackoutVpnService.kt');
      expect(service.contains('val completion = takeConnectResultCallback()'), isTrue);
      expect(service.contains('mainHandler.post { completion(false) }'), isTrue);
      expect(service.contains('clearConnectResultCallback(completion)'), isTrue);
    });

    test('Android JVM suite is a PR and release gate', () {
      final ci = source('.github/workflows/test.yml');
      final release = source('.github/workflows/build.yml');
      expect(ci.contains(':app:testDebugUnitTest'), isTrue);
      expect(release.contains(':app:testDebugUnitTest'), isTrue);
    });

    test('native test APK can use a side-by-side package without changing release', () {
      final gradle = source('android/app/build.gradle');
      final builder = source('tool/build_native_debug_windows.ps1');
      expect(gradle.contains('applicationIdSuffix ".nativetest"'), isTrue);
      expect(gradle.contains('project.findProperty("nativeTestPackage") == "true"'),
          isTrue);
      expect(builder.contains(r'[switch]$SideBySide'), isTrue);
      expect(builder.contains('-PnativeTestPackage=true'), isTrue);
      expect(builder.contains('com.blackoutkit.vpn.nativetest'), isTrue);
    });

    test('native test distribution carries third-party license notices', () {
      final pubspec = source('pubspec.yaml');
      final notices = source('assets/licenses/native_tunnel_licenses.txt');
      final builder = source('tool/build_native_debug_windows.ps1');
      expect(pubspec.contains('assets/licenses/native_tunnel_licenses.txt'), isTrue);
      expect(notices.contains('Apache License'), isTrue);
      expect(notices.contains('MIT license - WireGuard Go core'), isTrue);
      expect(notices.contains('MIT license - AmneziaWG-Go'), isTrue);
      expect(notices.contains('Go Authors BSD-style license'), isTrue);
      expect(builder.contains('native_tunnel_licenses.txt'), isTrue);
    });
  });
}
