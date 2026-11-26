import 'dart:async';
import 'dart:io';

import 'package:blackout_kit_mobile/services/ip_info_service.dart';
import 'package:blackout_kit_mobile/services/vpn_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

class _PendingVpn extends VPNService {
  final response = Completer<String?>();
  @override
  Future<String?> tunnelFetch(String url,
          {Duration timeout = const Duration(seconds: 10)}) =>
      response.future;
}

void main() {
  for (final reenable in [false, true]) {
    test('revoked lookup cannot populate cache (reenable=$reenable)', () async {
      final dir = await Directory.systemTemp.createTemp('bk_consent');
      Hive.init(dir.path);
      final vpn = _PendingVpn();
      final service = IpInfoService(vpnService: vpn);
      try {
        await service.initialize();
        service.setLookupsEnabled(true);
        final pending = service.fetchExit();
        service.setLookupsEnabled(false);
        if (reenable) service.setLookupsEnabled(true);
        vpn.response.complete('{"success":true,"ip":"203.0.113.9"}');
        expect((await pending).isEmpty, isTrue);
        expect(service.cachedExit().isEmpty, isTrue);
        expect(Hive.box('ipinfo').get('exit'), isNull);
      } finally {
        await Hive.close();
        await dir.delete(recursive: true);
      }
    });
  }
}
