/// Verifies the Android native tunnel on a **physical device**.
///
/// Every other test in this repo runs against mocked platform channels and would
/// pass even if the native layer did not exist — which is precisely what
/// happened to the 1,053 lines of mock Kotlin that commit `4e73204` removed.
/// This file is the one that actually talks to `android.net.VpnService`.
///
/// This is the test that closes the project's top open risk. It has **never been
/// run**, because no Android hardware has been available.
///
/// ```bash
/// # Plug in a device with USB debugging on, then:
/// adb devices                                     # confirm it is listed
/// adb shell appops set com.blackoutkit.vpn ACTIVATE_VPN allow   # skip the consent dialog
/// flutter test integration_test/native_tunnel_test.dart -d <device-id>
/// ```
///
/// While the third test holds the tunnel open for 20 seconds, confirm the
/// interface from another shell:
///
/// ```bash
/// adb shell ip addr show tun0     # expect inet 10.111.222.1/30
/// adb shell ip route              # expect the default route via tun0
/// ```
///
/// A physical arm64 device is required. The release build strips the x86/x86_64
/// `libgojni.so` (see `packagingOptions` in `android/app/build.gradle`), and this
/// project does not target emulators.
library;

import 'package:blackout_kit_mobile/models/config.dart';
import 'package:blackout_kit_mobile/services/vpn_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final vpn = VPNService();

  /// A structurally valid VLESS config.
  ///
  /// The upstream is deliberately unreachable (`127.0.0.1:1`). This test is
  /// about whether the TUN interface and the in-process Xray core come up — not
  /// whether any particular server answers. `Builder.establish()` and
  /// `CoreController.startLoop()` do not validate upstream reachability, so an
  /// unreachable server is the correct choice here: it isolates the tunnel
  /// mechanics from the network.
  const probeUri =
      'vless://11111111-2222-3333-4444-555555555555@127.0.0.1:1'
      '?encryption=none&security=none&type=tcp#NativeTunnelProbe';

  tearDown(() async {
    // Never leave a tunnel up between tests.
    try {
      await vpn.disconnect();
    } catch (_) {
      // Best effort. A failure here is reported by the test that follows.
    }
  });

  testWidgets('native layer answers getEngineInfo', (tester) async {
    final info = await vpn.getEngineInfo();

    expect(
      info.isKnown,
      isTrue,
      reason: 'getEngineInfo returned nothing — VpnPlugin is not registered on '
          'the running FlutterEngine',
    );
    expect(
      info.xrayAvailable,
      isTrue,
      reason: 'libv2ray.aar did not load. Either libgojni.so is missing for this '
          'ABI, or Seq.setContext/initCoreEnv failed.',
    );
    expect(info.xrayProtocols, contains('vless'));
    expect(info.singboxAvailable, isFalse,
        reason: 'this build bundles no sing-box runtime');
    expect(info.canConnect('vless'), isTrue);
    expect(info.canConnect('hysteria2'), isFalse);
  });

  testWidgets('VpnService.prepare() succeeds', (tester) async {
    final prepared = await vpn.prepare();

    expect(
      prepared,
      isTrue,
      reason: 'VPN consent is not granted. Pre-grant it with:\n'
          '  adb shell appops set com.blackoutkit.vpn ACTIVATE_VPN allow',
    );
  });

  testWidgets('the tunnel comes up and the Xray core starts', (tester) async {
    final config = ConfigParser.parse(probeUri);
    expect(config, isNotNull, reason: 'the probe URI did not parse');
    expect(config, isA<VlessConfig>());

    final prepared = await vpn.prepare();
    expect(prepared, isTrue, reason: 'consent missing');

    // Returns true only when BlackoutVpnService reports that establish()
    // succeeded AND the engine is running. A false here is the real signal that
    // the tunnel does not work.
    final connected = await vpn.connect(config!);

    expect(
      connected,
      isTrue,
      reason: 'connect() returned false. Native error: ${vpn.lastError}',
    );

    expect(await vpn.isRunning(), isTrue,
        reason: 'connect() reported success but isRunning() says otherwise');

    // Hold the tunnel open briefly so it can be inspected from outside while it
    // is live:
    //   adb shell ip addr show tun0        -> expect 10.111.222.1/30
    //   adb shell dumpsys connectivity     -> expect our VPN
    await Future<void>.delayed(const Duration(seconds: 20));

    expect(await vpn.isRunning(), isTrue,
        reason: 'the tunnel died while it was supposed to be up');
  }, timeout: const Timeout(Duration(minutes: 2)));

  testWidgets('disconnect tears the tunnel down', (tester) async {
    final config = ConfigParser.parse(probeUri);
    expect(config, isNotNull);

    expect(await vpn.prepare(), isTrue);
    expect(await vpn.connect(config!), isTrue,
        reason: 'could not establish the tunnel to tear it down');

    expect(await vpn.disconnect(), isTrue);
    expect(await vpn.isRunning(), isFalse,
        reason: 'disconnect() reported success but the tunnel is still running');
  }, timeout: const Timeout(Duration(minutes: 2)));

  testWidgets('an unbundled protocol is refused, not black-holed', (tester) async {
    // hysteria2 needs a sing-box runtime that this build does not bundle. The
    // service must refuse rather than install a default route it cannot serve —
    // a tunnel that comes up with no working engine black-holes all traffic.
    final config = ConfigParser.parse(
      'hysteria2://password@127.0.0.1:1?sni=example.com#UnbundledProbe',
    );

    if (config == null) {
      // The parser may not produce a Hysteria2Config; nothing to assert.
      return;
    }

    expect(await vpn.prepare(), isTrue);
    final connected = await vpn.connect(config);

    expect(connected, isFalse,
        reason: 'a protocol with no bundled engine must not report success');
    expect(await vpn.isRunning(), isFalse,
        reason: 'a refused connection must not leave a tunnel up');
  }, timeout: const Timeout(Duration(minutes: 2)));
}
