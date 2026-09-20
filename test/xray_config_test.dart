/// Tests for the Xray config generator.
///
/// This is the highest-risk code in the app: a malformed document makes the
/// core either refuse to start or, worse, start and silently drop every packet.
/// The shapes asserted here mirror `blackoutkit/engines/xray.py` (the desktop
/// CLI) and the TUN inbound proven by v2rayNG's `v2ray_config_with_tun.json`.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:blackout_kit_mobile/models/config.dart';
import 'package:blackout_kit_mobile/services/xray_config.dart';

void main() {
  const builder = XrayConfigBuilder();

  Map<String, dynamic> buildFor(String uri) {
    final config = ConfigParser.parse(uri);
    expect(config, isNotNull, reason: 'could not parse $uri');
    return builder.build(config!);
  }

  List<Map<String, dynamic>> inboundsOf(Map<String, dynamic> doc) =>
      (doc['inbounds'] as List).cast<Map<String, dynamic>>();

  List<Map<String, dynamic>> outboundsOf(Map<String, dynamic> doc) =>
      (doc['outbounds'] as List).cast<Map<String, dynamic>>();

  Map<String, dynamic> proxyOutbound(Map<String, dynamic> doc) =>
      outboundsOf(doc).firstWhere((o) => o['tag'] == 'proxy');

  List<Map<String, dynamic>> routingRules(Map<String, dynamic> doc) =>
      ((doc['routing'] as Map)['rules'] as List).cast<Map<String, dynamic>>();

  group('protocol support', () {
    test('accepts the five protocols the bundled core can serve', () {
      expect(isXrayProtocol('vless'), isTrue);
      expect(isXrayProtocol('vmess'), isTrue);
      expect(isXrayProtocol('trojan'), isTrue);
      expect(isXrayProtocol('shadowsocks'), isTrue);
      // Added once `xray.proxy.wireguard` was confirmed present in the shipped
      // libgojni.so. It is served in-process, so it needs no sing-box binary.
      expect(isXrayProtocol('wireguard'), isTrue);
    });

    test('rejects protocols the bundled core really cannot serve', () {
      // hysteria2 stays out: the core carries Hysteria v1, not v2.
      expect(isXrayProtocol('hysteria2'), isFalse);
      expect(isXrayProtocol('tuic'), isFalse);
      expect(isXrayProtocol('amneziawg'), isFalse);
      expect(isXrayProtocol('openvpn'), isFalse);
    });

    test('throws rather than emitting a bogus outbound', () {
      final config = Hysteria2Config(
        name: 'hy2',
        rawUri: 'hy2://x@1.2.3.4:443',
        password: 'x',
        address: '1.2.3.4',
        port: 443,
      );
      expect(() => builder.build(config), throwsArgumentError);
    });
  });

  group('wireguard outbound', () {
    const conf = '''
[Interface]
PrivateKey = PRIVKEY
Address = 10.0.0.2/32, fd00::2/128
DNS = 1.1.1.1, 8.8.8.8
MTU = 1380

[Peer]
PublicKey = PUBKEY
PresharedKey = PSK
AllowedIPs = 0.0.0.0/0, ::/0
Endpoint = vpn.example.com:51820
PersistentKeepalive = 25
''';

    WireGuardConfig parsed() =>
        ConfigParser.parse(conf) as WireGuardConfig;

    test('is tagged proxy and uses Xray field names', () {
      final out = proxyOutbound(builder.build(parsed()));

      expect(out['protocol'], 'wireguard');
      final settings = out['settings'] as Map;
      expect(settings['secretKey'], 'PRIVKEY');
      // `address` is the *local* tunnel address, not the server.
      expect(settings['address'], ['10.0.0.2/32', 'fd00::2/128']);
      expect(settings['mtu'], 1380);
    });

    test('carries the peer key, endpoint and allowed IPs', () {
      final settings =
          proxyOutbound(builder.build(parsed()))['settings'] as Map;
      final peer = (settings['peers'] as List).single as Map;

      expect(peer['publicKey'], 'PUBKEY');
      expect(peer['endpoint'], 'vpn.example.com:51820');
      expect(peer['allowedIPs'], ['0.0.0.0/0', '::/0']);
    });

    test('carries the preshared key and keepalive', () {
      // Both were silently dropped by the old parser, which made any profile
      // that uses a preshared key fail to handshake.
      final settings =
          proxyOutbound(builder.build(parsed()))['settings'] as Map;
      final peer = (settings['peers'] as List).single as Map;

      expect(peer['preSharedKey'], 'PSK');
      expect(peer['keepAlive'], 25);
    });

    test('emits no streamSettings, because WireGuard has no transport layer',
        () {
      final out = proxyOutbound(builder.build(parsed()));
      expect(out.containsKey('streamSettings'), isFalse);
      expect(out.containsKey('mux'), isFalse);
    });

    test('defaults the MTU to 1420 rather than the TUN MTU', () {
      // Riding inside UDP costs ~60 bytes of outer header, so the TUN's 1500
      // would fragment every full-size packet.
      final noMtu = ConfigParser.parse('''
[Interface]
PrivateKey = PRIVKEY
Address = 10.0.0.2/32

[Peer]
PublicKey = PUBKEY
Endpoint = vpn.example.com:51820
''') as WireGuardConfig;

      final settings =
          proxyOutbound(builder.build(noMtu))['settings'] as Map;
      expect(settings['mtu'], 1420);
    });

    test('refuses a profile with no peer', () {
      final noPeer = WireGuardConfig(
        name: 'wg',
        rawUri: 'wg',
        privateKey: 'PRIVKEY',
        localAddresses: const ['10.0.0.2/32'],
      );
      expect(() => builder.build(noPeer), throwsArgumentError);
    });

    test('refuses a profile with no private key', () {
      final noKey = WireGuardConfig(
        name: 'wg',
        rawUri: 'wg',
        privateKey: '',
        peers: const [
          WireGuardPeer(publicKey: 'PUBKEY', endpoint: 'vpn.example.com:51820'),
        ],
      );
      expect(() => builder.build(noKey), throwsArgumentError);
    });

    test('refuses a peer with no endpoint', () {
      final noEndpoint = WireGuardConfig(
        name: 'wg',
        rawUri: 'wg',
        privateKey: 'PRIVKEY',
        peers: const [WireGuardPeer(publicKey: 'PUBKEY')],
      );
      expect(() => builder.build(noEndpoint), throwsArgumentError);
    });

    test('still routes everything through the proxy by default', () {
      final rules = routingRules(builder.build(parsed()));
      expect(rules.last['outboundTag'], 'proxy');
    });
  });

  group('tun inbound', () {
    test('is present, because startLoop only exports the fd via an env var', () {
      final doc = buildFor('vless://11111111-1111-1111-1111-111111111111@a.com:443');
      final tun = inboundsOf(doc).firstWhere((i) => i['protocol'] == 'tun');

      expect(tun['tag'], 'tun');
      final settings = tun['settings'] as Map;
      expect(settings['name'], 'xray0');
      expect(settings['mtu'], 1500);
      expect(settings['userLevel'], 8);
      expect(settings['gateway'], ['10.111.222.2/30']);
      expect(settings['dns'], ['1.1.1.1', '8.8.8.8']);
    });

    test('gateway shares a subnet with the VpnService address', () {
      final doc = buildFor('vless://11111111-1111-1111-1111-111111111111@a.com:443');
      final tun = inboundsOf(doc).firstWhere((i) => i['protocol'] == 'tun');
      final gateway = ((tun['settings'] as Map)['gateway'] as List).first as String;

      // BlackoutVpnService.VPN_ADDRESS_V4 is 10.111.222.1/30. If the gateway
      // falls outside that subnet the interface drops the core's replies and
      // every connection stalls with no error anywhere.
      expect(gateway, startsWith('10.111.222.'));
      expect(gateway, endsWith('/30'));
    });

    test('a socks inbound is still offered for local tooling', () {
      final doc = buildFor('vless://11111111-1111-1111-1111-111111111111@a.com:443');
      final socks = inboundsOf(doc).firstWhere((i) => i['protocol'] == 'socks');
      expect(socks['port'], 10808);
      expect(socks['listen'], '127.0.0.1');
      expect((socks['settings'] as Map)['udp'], isTrue);
    });
  });

  group('vless', () {
    test('builds a vnext outbound with encryption none', () {
      final doc = buildFor(
        'vless://11111111-1111-1111-1111-111111111111@a.com:443?security=tls&sni=a.com',
      );
      final proxy = proxyOutbound(doc);

      expect(proxy['protocol'], 'vless');
      final vnext = ((proxy['settings'] as Map)['vnext'] as List).first as Map;
      expect(vnext['address'], 'a.com');
      expect(vnext['port'], 443);
      final user = (vnext['users'] as List).first as Map;
      expect(user['id'], '11111111-1111-1111-1111-111111111111');
      expect(user['encryption'], 'none');
      expect(user.containsKey('flow'), isFalse);
    });

    test('carries the flow when the link specifies one', () {
      final doc = buildFor(
        'vless://11111111-1111-1111-1111-111111111111@a.com:443'
        '?security=tls&sni=a.com&flow=xtls-rprx-vision',
      );
      final proxy = proxyOutbound(doc);
      final vnext = ((proxy['settings'] as Map)['vnext'] as List).first as Map;
      final user = (vnext['users'] as List).first as Map;
      expect(user['flow'], 'xtls-rprx-vision');
    });

    test('REALITY produces realitySettings, not tlsSettings', () {
      final doc = buildFor(
        'vless://11111111-1111-1111-1111-111111111111@a.com:443'
        '?security=reality&sni=www.microsoft.com&pbk=PUBKEY&sid=ab12&fp=firefox',
      );
      final stream = proxyOutbound(doc)['streamSettings'] as Map;

      expect(stream['security'], 'reality');
      expect(stream.containsKey('tlsSettings'), isFalse);
      final reality = stream['realitySettings'] as Map;
      expect(reality['serverName'], 'www.microsoft.com');
      expect(reality['publicKey'], 'PUBKEY');
      expect(reality['shortId'], 'ab12');
      expect(reality['fingerprint'], 'firefox');
      expect(reality['show'], isFalse);
    });

    test('REALITY without a public key is refused, not silently broken', () {
      final config = ConfigParser.parse(
        'vless://11111111-1111-1111-1111-111111111111@a.com:443'
        '?security=reality&sni=www.microsoft.com',
      )!;
      expect(() => builder.build(config), throwsArgumentError);
    });

    test('REALITY without a server name is refused', () {
      final config = ConfigParser.parse(
        'vless://11111111-1111-1111-1111-111111111111@a.com:443'
        '?security=reality&pbk=PUBKEY',
      )!;
      expect(() => builder.build(config), throwsArgumentError);
    });

    test('security=none emits no tlsSettings', () {
      final doc = buildFor(
        'vless://11111111-1111-1111-1111-111111111111@a.com:443?security=none',
      );
      final stream = proxyOutbound(doc)['streamSettings'] as Map;
      expect(stream['security'], 'none');
      expect(stream.containsKey('tlsSettings'), isFalse);
      expect(stream.containsKey('realitySettings'), isFalse);
    });
  });

  group('transports', () {
    test('ws carries path and Host header', () {
      final doc = buildFor(
        'vless://11111111-1111-1111-1111-111111111111@a.com:443'
        '?security=tls&type=ws&path=%2Fws&host=cdn.example.com',
      );
      final stream = proxyOutbound(doc)['streamSettings'] as Map;
      expect(stream['network'], 'ws');
      final ws = stream['wsSettings'] as Map;
      expect(ws['path'], '/ws');
      expect((ws['headers'] as Map)['Host'], 'cdn.example.com');
    });

    test('ws without a path defaults to /', () {
      final doc = buildFor(
        'vless://11111111-1111-1111-1111-111111111111@a.com:443?security=tls&type=ws',
      );
      final stream = proxyOutbound(doc)['streamSettings'] as Map;
      expect((stream['wsSettings'] as Map)['path'], '/');
    });

    test('grpc carries the service name', () {
      final doc = buildFor(
        'vless://11111111-1111-1111-1111-111111111111@a.com:443'
        '?security=tls&type=grpc&serviceName=mygrpc',
      );
      final stream = proxyOutbound(doc)['streamSettings'] as Map;
      expect(stream['network'], 'grpc');
      expect((stream['grpcSettings'] as Map)['serviceName'], 'mygrpc');
    });

    test('both xhttp spellings normalise to splithttp', () {
      // The bundled core registers the transport as `splithttp`; the literal
      // `xhttp` never appears in libgojni.so, so `network: "xhttp"` names a
      // transport it cannot resolve. The settings key is still
      // `xhttpSettings`, which *is* present.
      for (final spelling in ['splithttp', 'xhttp']) {
        final config = ConfigParser.parse(
          'vless://11111111-1111-1111-1111-111111111111@a.com:443'
          '?security=tls&type=$spelling&path=%2Fx',
        ) as VlessConfig;
        expect(config.network, 'splithttp', reason: 'input type=$spelling');

        final doc = builder.build(config);
        final stream = proxyOutbound(doc)['streamSettings'] as Map;
        expect(stream['network'], 'splithttp');
        expect((stream['xhttpSettings'] as Map)['path'], '/x');
      }
    });

    test('a persisted xhttp record is still emitted as splithttp', () {
      // Guards the migration path: records saved before the model was
      // corrected can carry `network: 'xhttp'` verbatim.
      final config = VlessConfig(
        name: 'legacy',
        rawUri: 'vless://11111111-1111-1111-1111-111111111111@a.com:443',
        uuid: '11111111-1111-1111-1111-111111111111',
        address: 'a.com',
        port: 443,
        security: 'tls',
        network: 'xhttp',
      );

      final doc = builder.build(config);
      final stream = proxyOutbound(doc)['streamSettings'] as Map;
      expect(stream['network'], 'splithttp');
      expect(stream.containsKey('xhttpSettings'), isTrue);
    });

    test('tcp needs no transport settings', () {
      final doc = buildFor(
        'vless://11111111-1111-1111-1111-111111111111@a.com:443?security=tls&type=tcp',
      );
      final stream = proxyOutbound(doc)['streamSettings'] as Map;
      expect(stream['network'], 'tcp');
      expect(stream.containsKey('wsSettings'), isFalse);
      expect(stream.containsKey('grpcSettings'), isFalse);
    });
  });

  group('vmess', () {
    test('builds vnext with alterId 0 and security auto', () {
      final payload = base64.encode(utf8.encode(jsonEncode({
        'v': '2',
        'ps': 'node',
        'add': 'b.com',
        'port': '8080',
        'id': '22222222-2222-2222-2222-222222222222',
        'aid': '0',
        'scy': 'auto',
        'net': 'tcp',
        'tls': 'tls',
        'sni': 'b.com',
      })));

      final doc = buildFor('vmess://$payload');
      final proxy = proxyOutbound(doc);

      expect(proxy['protocol'], 'vmess');
      final vnext = ((proxy['settings'] as Map)['vnext'] as List).first as Map;
      expect(vnext['address'], 'b.com');
      expect(vnext['port'], 8080);
      final user = (vnext['users'] as List).first as Map;
      expect(user['id'], '22222222-2222-2222-2222-222222222222');
      expect(user['alterId'], 0);
      expect(user['security'], 'auto');
    });
  });

  group('trojan', () {
    test('builds a servers outbound and is TLS by definition', () {
      final doc = buildFor('trojan://hunter2@c.com:8443?sni=c.com');
      final proxy = proxyOutbound(doc);

      expect(proxy['protocol'], 'trojan');
      final server = ((proxy['settings'] as Map)['servers'] as List).first as Map;
      expect(server['address'], 'c.com');
      expect(server['port'], 8443);
      expect(server['password'], 'hunter2');

      final stream = proxy['streamSettings'] as Map;
      expect(stream['security'], 'tls');
      expect((stream['tlsSettings'] as Map)['serverName'], 'c.com');
    });
  });

  group('shadowsocks', () {
    test('builds a servers outbound with method and password', () {
      final credentials = base64.encode(utf8.encode('aes-256-gcm:secret'));
      final doc = buildFor('ss://$credentials@d.com:8388');
      final proxy = proxyOutbound(doc);

      expect(proxy['protocol'], 'shadowsocks');
      final server = ((proxy['settings'] as Map)['servers'] as List).first as Map;
      expect(server['address'], 'd.com');
      expect(server['port'], 8388);
      expect(server['method'], 'aes-256-gcm');
      expect(server['password'], 'secret');
    });
  });

  group('routing and outbounds', () {
    test('always emits direct and block outbounds', () {
      final doc = buildFor('vless://11111111-1111-1111-1111-111111111111@a.com:443');
      final tags = outboundsOf(doc).map((o) => o['tag']).toList();
      expect(tags, containsAll(['proxy', 'direct', 'block']));
    });

    test('catch-all rule routes to the proxy', () {
      final doc = buildFor('vless://11111111-1111-1111-1111-111111111111@a.com:443');
      final rules = routingRules(doc);
      final last = rules.last;
      expect(last['outboundTag'], 'proxy');
      expect(last['network'], 'tcp,udp');
    });

    test('private ranges bypass the proxy', () {
      final doc = buildFor('vless://11111111-1111-1111-1111-111111111111@a.com:443');
      final direct = routingRules(doc)
          .firstWhere((r) => r['outboundTag'] == 'direct' && r.containsKey('ip'));
      final cidrs = (direct['ip'] as List).cast<String>();

      expect(cidrs, contains('10.0.0.0/8'));
      expect(cidrs, contains('192.168.0.0/16'));
      expect(cidrs, contains('127.0.0.0/8'));
      // Literal CIDRs on purpose: geosite:/geoip: tags would require the geo
      // data files to be resolvable at runtime.
      expect(cidrs.any((c) => c.startsWith('geoip:')), isFalse);
    });

    test('DNS-through-proxy adds a dns block and a port 53 rule', () {
      final config = ConfigParser.parse(
        'vless://11111111-1111-1111-1111-111111111111@a.com:443',
      )!;
      final doc = const XrayConfigBuilder(routeDnsThroughProxy: true).build(config);

      expect(doc.containsKey('dns'), isTrue);
      final servers = ((doc['dns'] as Map)['servers'] as List).cast<String>();
      expect(servers.any((s) => s.startsWith('https+local://')), isTrue);

      final dnsRule = routingRules(doc).firstWhere((r) => r['port'] == 53);
      expect(dnsRule['outboundTag'], 'proxy');
    });

    test('DNS-through-proxy is off by default', () {
      final doc = buildFor('vless://11111111-1111-1111-1111-111111111111@a.com:443');
      expect(doc.containsKey('dns'), isFalse);
      expect(routingRules(doc).any((r) => r['port'] == 53), isFalse);
    });

    test('split tunneling can be disabled', () {
      final config = ConfigParser.parse(
        'vless://11111111-1111-1111-1111-111111111111@a.com:443',
      )!;
      final doc =
          const XrayConfigBuilder(bypassPrivateRanges: false).build(config);
      final directRules = routingRules(doc)
          .where((r) => r['outboundTag'] == 'direct' && r.containsKey('ip'));
      expect(directRules, isEmpty);
    });

    test('bypass domains are emitted when supplied', () {
      final config = ConfigParser.parse(
        'vless://11111111-1111-1111-1111-111111111111@a.com:443',
      )!;
      final doc = const XrayConfigBuilder(
        bypassDomains: ['domain:ir', 'domain:example.ir'],
      ).build(config);

      final rule = routingRules(doc)
          .firstWhere((r) => r['outboundTag'] == 'direct' && r.containsKey('domain'));
      expect((rule['domain'] as List), ['domain:ir', 'domain:example.ir']);
    });
  });

  group('serialisation', () {
    test('buildJson round-trips through jsonDecode', () {
      final config = ConfigParser.parse(
        'vless://11111111-1111-1111-1111-111111111111@a.com:443?security=tls&sni=a.com',
      )!;
      final decoded = jsonDecode(builder.buildJson(config)) as Map<String, dynamic>;
      expect(decoded['inbounds'], isA<List>());
      expect(decoded['outbounds'], isA<List>());
      expect(decoded['log'], isA<Map>());
    });

    test('log level is quiet by default', () {
      final doc = buildFor('vless://11111111-1111-1111-1111-111111111111@a.com:443');
      final log = doc['log'] as Map;
      expect(log['loglevel'], 'warning');
      expect(log['access'], 'none');
      expect(log['error'], 'none');
    });

    test('socksPort and mtu are configurable', () {
      final config = ConfigParser.parse(
        'vless://11111111-1111-1111-1111-111111111111@a.com:443',
      )!;
      final doc = const XrayConfigBuilder(socksPort: 12345, mtu: 1400).build(config);

      final socks = inboundsOf(doc).firstWhere((i) => i['protocol'] == 'socks');
      expect(socks['port'], 12345);

      final tun = inboundsOf(doc).firstWhere((i) => i['protocol'] == 'tun');
      expect((tun['settings'] as Map)['mtu'], 1400);
    });
  });
}
