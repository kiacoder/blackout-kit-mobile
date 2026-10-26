/// libbox-mode (iOS) sing-box documents: outbound coverage and honest
/// refusals. The generated documents were grammar-verified against the real
/// sing-box binary (tool/_sb_libbox_probe.dart, all 10 accepted).
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:blackout_kit_mobile/models/config.dart';
import 'package:blackout_kit_mobile/services/singbox_config.dart';

const uuid = '11111111-1111-1111-1111-111111111111';

Map<String, dynamic> outbound(Config config) =>
    ((const SingboxConfigBuilder(libboxMode: true).build(config)['outbounds']
                as List)
            .first as Map)
        .cast<String, dynamic>();

void main() {
  group('libbox mode builds the Xray-family protocols', () {
    test('vless ws/tls: transport + tls + uuid + flow', () {
      final o = outbound(ConfigParser.parse(
        'vless://$uuid@a.com:443?security=tls&sni=a.com&type=ws&path=%2Fw&host=cdn.x.com&flow=xtls-rprx-vision#v',
      )!);
      expect(o['type'], 'vless');
      expect(o['uuid'], uuid);
      expect(o['flow'], 'xtls-rprx-vision');
      expect((o['transport'] as Map)['type'], 'ws');
      expect(((o['transport'] as Map)['headers'] as Map)['Host'], 'cdn.x.com');
      expect((o['tls'] as Map)['server_name'], 'a.com');
    });

    test('vless reality: reality block + mandatory uTLS', () {
      final o = outbound(ConfigParser.parse(
        'vless://$uuid@a.com:443?security=reality&pbk=PK&sid=ab&fp=chrome&sni=r.com#v',
      )!);
      final tls = o['tls'] as Map;
      expect((tls['reality'] as Map)['public_key'], 'PK');
      expect((tls['utls'] as Map)['fingerprint'], 'chrome');
    });

    test('reality without fp still gets the chrome default', () {
      final o = outbound(ConfigParser.parse(
        'vless://$uuid@a.com:443?security=reality&pbk=PK&sni=r.com#v',
      )!);
      expect(((o['tls'] as Map)['utls'] as Map)['fingerprint'], 'chrome');
    });

    test('vmess ws/tls: alter_id + cipher + transport', () {
      final o = outbound(ConfigParser.parse(
        'vmess://eyJ2IjoiMiIsInBzIjoibSIsImFkZCI6ImEuY29tIiwicG9ydCI6IjQ0MyIsImlkIjoiMTExMTExMTEtMTExMS0xMTExLTExMTEtMTExMTExMTExMTExIiwiYWlkIjoiNSIsInNjeSI6ImF1dG8iLCJuZXQiOiJ3cyIsInBhdGgiOiIvdyIsInRscyI6InRscyJ9#m',
      )!);
      expect(o['type'], 'vmess');
      expect(o['alter_id'], 5);
      expect((o['transport'] as Map)['type'], 'ws');
      expect((o['tls'] as Map)['enabled'], isTrue);
    });

    test('trojan grpc: service name rides through', () {
      final o = outbound(ConfigParser.parse(
        'trojan://pw@a.com:443?sni=a.com&type=grpc&path=svc#t',
      )!);
      expect((o['transport'] as Map)['service_name'], 'svc');
      expect(o['tls'], isNotNull, reason: 'trojan is TLS by definition');
    });

    test('shadowsocks carries method + password', () {
      final o = outbound(ConfigParser.parse(
        'ss://YWVzLTI1Ni1nY206cGFzcw==@a.com:8388#s',
      )!);
      expect(o['method'], 'aes-256-gcm');
      expect(o['password'], 'pass');
    });

    test('libbox docs carry a tun inbound with auto_route', () {
      // The extension's openTun receives the tun inbound's options — without
      // this inbound the core starts with no interface at all.
      final doc = const SingboxConfigBuilder(libboxMode: true).build(
        ConfigParser.parse('anytls://pw@a.com:443?sni=a.com#y')!,
      );
      final inbound = (doc['inbounds'] as List).first as Map;
      expect(inbound['type'], 'tun');
      expect(inbound['auto_route'], isTrue);
      expect(inbound['address'], contains('172.19.0.1/30'));
    });

    test('android docs still carry the mixed loopback inbound', () {
      final doc = const SingboxConfigBuilder().build(
        ConfigParser.parse('hysteria2://pw@a.com:443?sni=a.com#y')!,
      );
      final inbound = (doc['inbounds'] as List).first as Map;
      expect(inbound['type'], 'mixed');
      expect(inbound['listen_port'], 10808);
    });

    test('wireguard becomes an endpoint with a peer', () {
      final doc = const SingboxConfigBuilder(libboxMode: true).build(
        WireGuardConfig(
          name: 'wg',
          rawUri: '',
          privateKey: '6BqQKsDXmKZ5lM+7ZXYa3GZZQbG0vXbH0Yy6fZpXk1A=',
          localAddresses: const ['172.16.0.2/32'],
          dns: '1.1.1.1',
          mtu: 1280,
          peers: [
            WireGuardPeer(
              publicKey: 'bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=',
              endpoint: 'engage.cloudflareclient.com:2408',
            ),
          ],
        ),
      );
      final endpoint = (doc['endpoints'] as List).first as Map;
      expect(endpoint['type'], 'wireguard');
      expect(endpoint['private_key'], contains('6BqQ'));
      final peer = (endpoint['peers'] as List).first as Map;
      expect(peer['address'], 'engage.cloudflareclient.com');
      expect(peer['port'], 2408);
    });
  });

  group('libbox mode refuses what the core cannot dial', () {
    const refusals = <String, String>{
      'mKCP': 'vless://$uuid@a.com:443?type=kcp#x',
      'xhttp': 'vless://$uuid@a.com:443?type=xhttp#x',
      'quic transport': 'vless://$uuid@a.com:443?type=quic#x',
    };
    refusals.forEach((label, uri) {
      test('refuses $label with a readable reason', () {
        final config = ConfigParser.parse(uri)!;
        expect(
          () => const SingboxConfigBuilder(libboxMode: true).build(config),
          throwsA(
            isA<ArgumentError>().having(
              (e) => e.message.toString(),
              'message',
              contains('not supported by the iOS core'),
            ),
          ),
        );
      });
    });

    test('android mode still refuses vless (engine selection unchanged)', () {
      final config = ConfigParser.parse('vless://$uuid@a.com:443?type=tcp#v')!;
      expect(
        () => const SingboxConfigBuilder().build(config),
        throwsArgumentError,
      );
    });
  });
}
