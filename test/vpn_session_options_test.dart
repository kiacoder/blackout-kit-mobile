/// Tests for [VpnSessionOptions] validation.
///
/// These guard the boundary where Dart hands builder-time decisions to Android.
/// Catching a bad value here produces a message the user can act on; catching it
/// inside `VpnService.Builder` produces an opaque `IllegalArgumentException`
/// from `establish()`, or worse, a tunnel that opens and routes nothing.

import 'package:flutter_test/flutter_test.dart';

import 'package:blackout_kit_mobile/models/vpn_session_options.dart';

void main() {
  group('defaults', () {
    test('a bare options object is valid', () {
      const options = VpnSessionOptions();
      expect(options.validationError, isNull);
    });

    test('no split tunneling by default', () {
      const options = VpnSessionOptions();
      expect(options.hasSplitTunnel, isFalse);
      expect(options.usesWhitelist, isFalse);
      expect(options.effectiveAppList, isEmpty);
    });

    test('kill switch is off by default', () {
      const options = VpnSessionOptions();
      expect(options.holdTunnelOnEngineFailure, isFalse);
    });

    test('DNS is not routed through the proxy by default', () {
      const options = VpnSessionOptions();
      expect(options.routeDnsThroughProxy, isFalse);
    });
  });

  group('split tunneling precedence', () {
    test('whitelist wins when both lists are populated', () {
      const options = VpnSessionOptions(
        allowedApps: ['com.a'],
        disallowedApps: ['com.b'],
      );
      expect(options.usesWhitelist, isTrue);
      expect(options.effectiveAppList, ['com.a']);
    });

    test('blacklist is used when only it is populated', () {
      const options = VpnSessionOptions(disallowedApps: ['com.b']);
      expect(options.usesWhitelist, isFalse);
      expect(options.effectiveAppList, ['com.b']);
    });
  });

  group('app list size', () {
    test('accepts a list at the cap', () {
      final options = VpnSessionOptions(
        allowedApps: List.generate(VpnSessionOptions.maxAppsPerList, (i) => 'p$i'),
      );
      expect(options.validationError, isNull);
    });

    test('rejects a whitelist past the cap', () {
      final options = VpnSessionOptions(
        allowedApps:
            List.generate(VpnSessionOptions.maxAppsPerList + 1, (i) => 'p$i'),
      );
      expect(options.validationError, contains('Too many apps'));
    });

    test('rejects a blacklist past the cap', () {
      final options = VpnSessionOptions(
        disallowedApps:
            List.generate(VpnSessionOptions.maxAppsPerList + 1, (i) => 'p$i'),
      );
      expect(options.validationError, contains('Too many apps'));
    });
  });

  group('DNS validation', () {
    test('rejects an empty resolver list', () {
      const options = VpnSessionOptions(dnsServers: []);
      expect(options.validationError, contains('At least one DNS server'));
    });

    test('accepts IPv4 literals', () {
      const options = VpnSessionOptions(dnsServers: ['1.1.1.1', '8.8.8.8']);
      expect(options.validationError, isNull);
    });

    test('accepts IPv6 literals', () {
      const options = VpnSessionOptions(dnsServers: ['2606:4700:4700::1111']);
      expect(options.validationError, isNull);
    });

    test('rejects a hostname, because addDnsServer only takes IPs', () {
      const options = VpnSessionOptions(dnsServers: ['dns.google']);
      expect(options.validationError, contains('not an IP address'));
    });

    test('rejects an out-of-range octet', () {
      const options = VpnSessionOptions(dnsServers: ['1.1.1.256']);
      expect(options.validationError, contains('not an IP address'));
    });

    test('rejects a truncated address', () {
      const options = VpnSessionOptions(dnsServers: ['1.1.1']);
      expect(options.validationError, contains('not an IP address'));
    });
  });

  group('channel payload', () {
    test('carries every field the native side reads', () {
      const options = VpnSessionOptions(
        allowedApps: ['com.a'],
        dnsServers: ['9.9.9.9'],
        routeDnsThroughProxy: true,
        holdTunnelOnEngineFailure: true,
      );
      final payload = options.toChannelMap();

      expect(payload['allowedApps'], ['com.a']);
      expect(payload['disallowedApps'], isEmpty);
      expect(payload['dnsServers'], ['9.9.9.9']);
      expect(payload['dns'], '9.9.9.9');
      expect(payload['routeDnsThroughProxy'], isTrue);
      expect(payload['holdTunnelOnEngineFailure'], isTrue);
    });

    test('dns mirrors the first resolver for the legacy single-value extra', () {
      const options = VpnSessionOptions(dnsServers: ['9.9.9.9', '1.1.1.1']);
      expect(options.toChannelMap()['dns'], '9.9.9.9');
    });
  });

  group('copyWith', () {
    test('replaces only the named fields', () {
      const base = VpnSessionOptions(
        allowedApps: ['com.a'],
        dnsServers: ['1.1.1.1'],
      );
      final updated = base.copyWith(holdTunnelOnEngineFailure: true);

      expect(updated.allowedApps, ['com.a']);
      expect(updated.dnsServers, ['1.1.1.1']);
      expect(updated.holdTunnelOnEngineFailure, isTrue);
    });

    test('can clear an app list', () {
      const base = VpnSessionOptions(allowedApps: ['com.a']);
      final cleared = base.copyWith(allowedApps: const []);
      expect(cleared.hasSplitTunnel, isFalse);
    });
  });

  group('toString', () {
    test('names the split tunneling mode', () {
      const whitelist = VpnSessionOptions(allowedApps: ['com.a']);
      expect(whitelist.toString(), contains('whitelist'));

      const blacklist = VpnSessionOptions(disallowedApps: ['com.a']);
      expect(blacklist.toString(), contains('blacklist'));

      const off = VpnSessionOptions();
      expect(off.toString(), contains('off'));
    });
  });
}
