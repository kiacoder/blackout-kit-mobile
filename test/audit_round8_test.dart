/// Regressions for the bug-scan fixes of 2026-10-25 (post-1.12.4 audit round).
///
/// Covers: the DNS selection chain (config DNS reaching the tunnel), the
/// share-URI fields that were parsed but dropped (vmess allowInsecure/fp/alpn,
/// trojan-gRPC service name, ALPN emission), and the bare-IPv6 host:port
/// mis-split in the WireGuard endpoint parser.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:blackout_kit_mobile/models/config.dart';
import 'package:blackout_kit_mobile/models/vpn_session_options.dart';
import 'package:blackout_kit_mobile/services/dns_leak_prevention_service.dart';
import 'package:blackout_kit_mobile/services/singbox_config.dart';
import 'package:blackout_kit_mobile/services/vpn_service.dart';
import 'package:blackout_kit_mobile/services/xray_config.dart';

const uuid = '11111111-1111-1111-1111-111111111111';

Map<String, dynamic> streamOf(String uri) {
  final config = ConfigParser.parse(uri)!;
  final doc = const XrayConfigBuilder().build(config);
  return (((doc['outbounds'] as List).first as Map)['streamSettings'] as Map)
      .cast<String, dynamic>();
}

void main() {
  group('DNS: config resolvers reach the session options', () {
    test('dnsServersForConfig keeps IP entries and drops hostnames', () {
      final wg = WireGuardConfig(
        name: 'wg',
        rawUri: '',
        privateKey: 'k',
        dns: '1.0.0.1, dns.example.com, 8.8.4.4',
      );
      expect(VPNService.dnsServersForConfig(wg), ['1.0.0.1', '8.8.4.4']);
    });

    test('dnsServersForConfig falls back when the profile has no usable DNS',
        () {
      final wg = WireGuardConfig(
        name: 'wg',
        rawUri: '',
        privateKey: 'k',
        dns: 'resolver.internal.example',
      );
      expect(
        VPNService.dnsServersForConfig(wg),
        const ['1.1.1.1', '8.8.8.8'],
      );
    });

    test('leak prevention OFF keeps the incoming resolver list', () {
      // No SettingsController registered here, so the service is disabled —
      // exactly the state the bug showed itself in: applyTo replaced the
      // caller's list with [1.1.1.1] even while the feature was off.
      final options = const VpnSessionOptions(dnsServers: ['9.9.9.9']);
      final applied = DNSLeakPreventionService().applyTo(options);
      expect(applied.dnsServers, ['9.9.9.9']);
      expect(applied.routeDnsThroughProxy, isFalse);
    });
  });

  group('Xray builder: ALPN reaches the TLS settings', () {
    test('vless tls link carries its alpn list', () {
      final s = streamOf(
        'vless://$uuid@a.com:443?security=tls&alpn=h2,http/1.1#x',
      );
      expect((s['tlsSettings'] as Map)['alpn'], ['h2', 'http/1.1']);
    });

    test('reality link carries its alpn list', () {
      final s = streamOf(
        'vless://$uuid@a.com:443?security=reality&pbk=KEY&alpn=h2#r',
      );
      expect((s['realitySettings'] as Map)['alpn'], ['h2']);
    });

    test('a link without alpn emits none', () {
      final s = streamOf('vless://$uuid@a.com:443?security=tls#x');
      expect((s['tlsSettings'] as Map).containsKey('alpn'), isFalse);
    });
  });

  group('vmess TLS material is no longer dropped', () {
    Map<String, dynamic> vmessStream(Map<String, dynamic> json) {
      final b64 =
          base64.encode(utf8.encode(jsonEncode(json))).replaceAll('+', '-').replaceAll('/', '_');
      return streamOf('vmess://$b64');
    }

    test('allowInsecure is emitted when the link asks for it', () {
      final s = vmessStream({
        'v': '2',
        'ps': 't',
        'add': 'a.com',
        'port': '443',
        'id': uuid,
        'aid': '0',
        'scy': 'auto',
        'net': 'tcp',
        'type': 'none',
        'host': '',
        'path': '',
        'tls': 'tls',
        'allowInsecure': 1,
      });
      expect(s['security'], 'tls');
      expect((s['tlsSettings'] as Map)['allowInsecure'], isTrue);
    });

    test('no allowInsecure keeps full verification', () {
      final s = vmessStream({
        'v': '2',
        'ps': 't',
        'add': 'a.com',
        'port': '443',
        'id': uuid,
        'net': 'tcp',
        'tls': 'tls',
      });
      expect((s['tlsSettings'] as Map).containsKey('allowInsecure'), isFalse);
    });

    test('fp and alpn reach the TLS settings', () {
      final s = vmessStream({
        'v': '2',
        'ps': 't',
        'add': 'a.com',
        'port': '443',
        'id': uuid,
        'net': 'tcp',
        'tls': 'tls',
        'fp': 'safari',
        'alpn': 'h2,http/1.1',
      });
      expect((s['tlsSettings'] as Map)['fingerprint'], 'safari');
      expect((s['tlsSettings'] as Map)['alpn'], ['h2', 'http/1.1']);
    });
  });

  group('trojan over gRPC gets its service name', () {
    test('path carries the service name (v2rayN convention)', () {
      final config = ConfigParser.parse(
        'trojan://pw@c.com:443?type=grpc&path=myservice&sni=c.com#t',
      )! as TrojanConfig;
      expect(config.serviceName, 'myservice');

      final doc = const XrayConfigBuilder().build(config);
      final stream = ((doc['outbounds'] as List).first
          as Map)['streamSettings'] as Map;
      expect((stream['grpcSettings'] as Map)['serviceName'], 'myservice');
    });

    test('an explicit serviceName parameter wins', () {
      final config = ConfigParser.parse(
        'trojan://pw@c.com:443?type=grpc&path=frompath&serviceName=explicit#t',
      )! as TrojanConfig;
      expect(config.serviceName, 'explicit');
    });

    test('a websocket trojan keeps using path as the path', () {
      final config = ConfigParser.parse(
        'trojan://pw@c.com:443?type=ws&path=%2Fws&sni=c.com#t',
      )! as TrojanConfig;
      expect(config.serviceName, isNull);
      expect(config.path, '/ws');
    });
  });

  group('bare IPv6 endpoints are not mis-split', () {
    test('a numeric last group is not read as a port', () {
      // 2606:4700::1 used to parse as host "2606:4700::" port 1.
      final peer = WireGuardPeer(publicKey: 'k', endpoint: '2606:4700::1');
      expect(peer.host, '2606:4700::1');
      expect(peer.port, 51820);
    });

    test('a plain host:port still splits', () {
      final peer = WireGuardPeer(publicKey: 'k', endpoint: 'example.com:51820');
      expect(peer.host, 'example.com');
      expect(peer.port, 51820);
    });

    test('a bracketed IPv6 endpoint still splits', () {
      final peer = WireGuardPeer(publicKey: 'k', endpoint: '[2001:db8::1]:443');
      expect(peer.host, '2001:db8::1');
      expect(peer.port, 443);
    });
  });

  group('VpnSessionOptions.isIpLiteral', () {
    test('accepts IPv4 and IPv6 literals, rejects everything else', () {
      expect(VpnSessionOptions.isIpLiteral('1.1.1.1'), isTrue);
      expect(VpnSessionOptions.isIpLiteral('2606:4700::1'), isTrue);
      expect(VpnSessionOptions.isIpLiteral('dns.example.com'), isFalse);
      expect(VpnSessionOptions.isIpLiteral(''), isFalse);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // Samsung FATAL regression (2026-10-25): `start dns/https[bootstrap-dns]:
  // detour to an empty direct outbound makes no sense` — the bundled sing-box
  // core refuses a DNS server detoured to the bare `direct` outbound, which
  // killed every sing-box protocol (hy2/tuic/anytls) whenever DNS leak
  // prevention was on. The default dialer already dials direct, so the detour
  // key must simply not be emitted.
  // ───────────────────────────────────────────────────────────────────────────
  group('sing-box DNS section never detours to the bare direct outbound', () {
    Map<String, dynamic> buildWithLeakPrevention() {
      const uri =
          'anytls://secretpass@185.208.172.212:39007?sni=a.com&insecure=0#x';
      final config = ConfigParser.parse(uri)!;
      return const SingboxConfigBuilder(routeDnsThroughProxy: true)
          .build(config);
    }

    test('no dns server carries detour: direct', () {
      final doc = buildWithLeakPrevention();
      final servers = ((doc['dns'] as Map)['servers'] as List).cast<Map>();
      for (final server in servers) {
        expect(
          server['detour'] == 'direct',
          isFalse,
          reason: 'dns server "${server['tag']}" must not detour to the bare '
              'direct outbound — the bundled core FATALs on it',
        );
      }
    });

    test('the DNS section stays complete (bootstrap + remote + final)', () {
      final doc = buildWithLeakPrevention();
      final servers = ((doc['dns'] as Map)['servers'] as List)
          .cast<Map>()
          .map((s) => s['tag'])
          .toSet();
      expect(servers, containsAll(['bootstrap-dns', 'remote-dns']));
      expect((doc['dns'] as Map)['final'], 'remote-dns');
      // The proxy outbound still resolves through the bootstrap resolver.
      final proxy = (doc['outbounds'] as List).first as Map;
      expect((proxy['domain_resolver'] as Map)['server'], 'bootstrap-dns');
    });

    test('leak prevention off emits no dns section at all', () {
      const uri =
          'anytls://secretpass@185.208.172.212:39007?sni=a.com&insecure=0#x';
      final config = ConfigParser.parse(uri)!;
      final doc =
          const SingboxConfigBuilder(routeDnsThroughProxy: false).build(config);
      expect(doc.containsKey('dns'), isFalse);
    });
  });
}
