import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:blackout_kit_mobile/controllers/settings_controller.dart';
import 'package:blackout_kit_mobile/models/config.dart';
import 'package:blackout_kit_mobile/services/singbox_config.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FLUX & AmneziaWG Configuration', () {
    test('AmneziaWGConfig parses full S1-S2 and H1-H4 obfuscation block', () {
      final awgText = '''[Interface]
PrivateKey = aaaaaa=
Address = 10.0.0.2/32
Jc = 8
Jmin = 50
Jmax = 100
S1 = 64
S2 = 96
H1 = 123456
H2 = 654321
H3 = 999999
H4 = 888888

[Peer]
PublicKey = bbbbbb=
Endpoint = 1.2.3.4:51820
AllowedIPs = 0.0.0.0/0
''';

      final config = ConfigParser.parse(awgText);
      expect(config, isA<AmneziaWGConfig>());
      final awg = config as AmneziaWGConfig;
      expect(awg.junkCount, 8);
      expect(awg.junkMin, 50);
      expect(awg.junkMax, 100);
      expect(awg.s1, 64);
      expect(awg.s2, 96);
      expect(awg.h1, 123456);
      expect(awg.h2, 654321);
      expect(awg.h3, 999999);
      expect(awg.h4, 888888);
    });

    test('SettingsController defaults for FLUX are sane and configurable', () {
      final controller = SettingsController();
      expect(controller.fluxEnabled.value, isTrue);
      expect(controller.fluxConcurrency.value, 3);
      expect(controller.fluxProbeTarget.value, 'http://cp.cloudflare.com/generate_204');
      expect(controller.fluxProbeIntervalSeconds.value, 10);
      expect(controller.fluxFailureThreshold.value, 3);
      expect(controller.fluxHysteresisMs.value, 40);

      // Verify setters clamp appropriately
      controller.setFluxConcurrency(5);
      expect(controller.fluxConcurrency.value, 5);
      controller.setFluxConcurrency(10); // out of range 1-5, ignored
      expect(controller.fluxConcurrency.value, 5);

      controller.toggleFlux(false);
      expect(controller.fluxEnabled.value, isFalse);
    });
  });
}
