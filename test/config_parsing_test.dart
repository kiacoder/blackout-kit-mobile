/// Tests for share-link parsing.
///
/// Every protocol the app claims to support has to survive a round trip from
/// its URI form, because a dropped query parameter does not fail loudly — it
/// produces a config that connects to the right host on the right port and then
/// does not work, which is the hardest kind of bug to diagnose.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:blackout_kit_mobile/models/config.dart';

void main() {
  group('vless', () {
    test('parses the basics', () {
      final config = ConfigParser.parse(
        'vless://11111111-1111-1111-1111-111111111111@a.com:443?security=tls&sni=a.com',
      ) as VlessConfig;

      expect(config.protocol, 'vless');
      expect(config.uuid, '11111111-1111-1111-1111-111111111111');
      expect(config.address, 'a.com');
      expect(config.port, 443);
      expect(config.security, 'tls');
      expect(config.sni, 'a.com');
    });

    test('defaults security to none and transport to tcp', () {
      final config = ConfigParser.parse(
        'vless://11111111-1111-1111-1111-111111111111@a.com:443',
      ) as VlessConfig;
      expect(config.security, 'none');
      expect(config.network, 'tcp');
    });

    test('keeps the transport detail that used to be discarded', () {
      final config = ConfigParser.parse(
        'vless://11111111-1111-1111-1111-111111111111@a.com:443'
        '?type=ws&path=%2Fvpath&host=cdn.example.com',
      ) as VlessConfig;

      expect(config.network, 'ws');
      expect(config.path, '/vpath');
      expect(config.host, 'cdn.example.com');
    });

    test('keeps the grpc service name', () {
      final config = ConfigParser.parse(
        'vless://11111111-1111-1111-1111-111111111111@a.com:443'
        '?type=grpc&serviceName=svc',
      ) as VlessConfig;
      expect(config.serviceName, 'svc');
    });

    test('keeps REALITY fields', () {
      final config = ConfigParser.parse(
        'vless://11111111-1111-1111-1111-111111111111@a.com:443'
        '?security=reality&sni=s.com&pbk=PBK&sid=SID&spx=%2Fspider&fp=firefox',
      ) as VlessConfig;

      expect(config.security, 'reality');
      expect(config.publicKey, 'PBK');
      expect(config.shortId, 'SID');
      expect(config.spiderX, '/spider');
      expect(config.fingerprint, 'firefox');
    });

    test('accepts the long-form REALITY parameter names', () {
      final config = ConfigParser.parse(
        'vless://11111111-1111-1111-1111-111111111111@a.com:443'
        '?security=reality&publicKey=PBK&shortId=SID',
      ) as VlessConfig;
      expect(config.publicKey, 'PBK');
      expect(config.shortId, 'SID');
    });

    test('normalises the xhttp spelling to splithttp', () {
      // The bundled core registers this transport as `splithttp`; `xhttp`
      // never appears as a name in libgojni.so, only as the settings key
      // `xhttpSettings`. Normalising the other way produced a config the core
      // could not dial.
      for (final spelling in ['splithttp', 'xhttp']) {
        final config = ConfigParser.parse(
          'vless://11111111-1111-1111-1111-111111111111@a.com:443'
          '?type=$spelling',
        ) as VlessConfig;
        expect(config.network, 'splithttp', reason: 'input type=$spelling');
      }
    });

    test('reads insecure as a boolean', () {
      final insecure = ConfigParser.parse(
        'vless://11111111-1111-1111-1111-111111111111@a.com:443?insecure=1',
      ) as VlessConfig;
      expect(insecure.allowInsecure, isTrue);

      final secure = ConfigParser.parse(
        'vless://11111111-1111-1111-1111-111111111111@a.com:443',
      ) as VlessConfig;
      expect(secure.allowInsecure, isFalse);
    });

    test('uses the fragment as the display name', () {
      final config = ConfigParser.parse(
        'vless://11111111-1111-1111-1111-111111111111@a.com:443#My%20Node',
      )!;
      expect(config.displayName, 'My Node');
    });

    test('a custom name overrides the fragment', () {
      final config = ConfigParser.parse(
        'vless://11111111-1111-1111-1111-111111111111@a.com:443#Node',
        customName: 'Renamed',
      )!;
      expect(config.displayName, 'Renamed');
    });

    test('validation rejects a missing uuid', () {
      final config = ConfigParser.parse('vless://@a.com:443') as VlessConfig;
      expect(config.validate(), isFalse);
    });
  });

  group('vmess', () {
    String link(Map<String, dynamic> json) =>
        'vmess://${base64.encode(utf8.encode(jsonEncode(json)))}';

    test('parses the base64 JSON payload', () {
      final config = ConfigParser.parse(link({
        'v': '2',
        'ps': 'node',
        'add': 'b.com',
        'port': '8080',
        'id': '22222222-2222-2222-2222-222222222222',
        'aid': '0',
        'scy': 'auto',
        'net': 'ws',
        'path': '/p',
        'host': 'b.com',
        'tls': 'tls',
        'sni': 'b.com',
      })) as VmessConfig;

      expect(config.protocol, 'vmess');
      expect(config.uuid, '22222222-2222-2222-2222-222222222222');
      expect(config.address, 'b.com');
      expect(config.port, 8080);
      expect(config.network, 'ws');
      expect(config.path, '/p');
      expect(config.host, 'b.com');
      expect(config.tls, 'tls');
      expect(config.sni, 'b.com');
      expect(config.displayName, 'node');
    });

    test('defaults the cipher to auto', () {
      final config = ConfigParser.parse(link({
        'add': 'b.com',
        'port': 443,
        'id': '22222222-2222-2222-2222-222222222222',
      })) as VmessConfig;
      expect(config.cipher, 'auto');
      expect(config.network, 'tcp');
    });
  });

  group('trojan', () {
    test('parses password, sni and fingerprint', () {
      final config = ConfigParser.parse(
        'trojan://hunter2@c.com:8443?sni=c.com&fp=chrome',
      ) as TrojanConfig;

      expect(config.protocol, 'trojan');
      expect(config.password, 'hunter2');
      expect(config.address, 'c.com');
      expect(config.port, 8443);
      expect(config.sni, 'c.com');
      expect(config.fingerprint, 'chrome');
    });

    test('reads both insecure spellings', () {
      final a = ConfigParser.parse('trojan://p@c.com:443?allowInsecure=1')
          as TrojanConfig;
      expect(a.allowInsecure, isTrue);

      final b = ConfigParser.parse('trojan://p@c.com:443?insecure=1')
          as TrojanConfig;
      expect(b.allowInsecure, isTrue);
    });

    test('keeps WebSocket detail', () {
      final config = ConfigParser.parse(
        'trojan://p@c.com:443?type=ws&path=%2Fws&host=c.com',
      ) as TrojanConfig;
      expect(config.network, 'ws');
      expect(config.path, '/ws');
      expect(config.host, 'c.com');
    });
  });

  group('shadowsocks', () {
    test('parses base64 credentials', () {
      final credentials = base64.encode(utf8.encode('aes-256-gcm:secret'));
      final config = ConfigParser.parse('ss://$credentials@d.com:8388')
          as ShadowsocksConfig;

      expect(config.protocol, 'shadowsocks');
      expect(config.method, 'aes-256-gcm');
      expect(config.password, 'secret');
      expect(config.address, 'd.com');
      expect(config.port, 8388);
    });

    test('parses a fully base64-encoded link', () {
      final inner = base64.encode(utf8.encode('aes-256-gcm:secret@d.com:8388'));
      final config = ConfigParser.parse('ss://$inner') as ShadowsocksConfig;
      expect(config.method, 'aes-256-gcm');
      expect(config.address, 'd.com');
      expect(config.port, 8388);
    });

    test('uses the fragment as the name', () {
      final credentials = base64.encode(utf8.encode('aes-256-gcm:secret'));
      final config = ConfigParser.parse('ss://$credentials@d.com:8388#Fast')
          as ShadowsocksConfig;
      expect(config.displayName, 'Fast');
    });
  });

  group('sing-box protocols', () {
    test('parses hysteria2', () {
      final config = ConfigParser.parse(
        'hy2://pw@e.com:443?sni=e.com&insecure=1&obfs=salamander&obfs-password=x',
      ) as Hysteria2Config;

      expect(config.protocol, 'hysteria2');
      expect(config.password, 'pw');
      expect(config.address, 'e.com');
      expect(config.sni, 'e.com');
      expect(config.insecure, isTrue);
      expect(config.obfs, 'salamander');
      expect(config.obfsPassword, 'x');
    });

    test('accepts the long hysteria2 scheme', () {
      final config = ConfigParser.parse('hysteria2://pw@e.com:443');
      expect(config, isA<Hysteria2Config>());
    });

    test('parses tuic with split credentials', () {
      final config = ConfigParser.parse(
        'tuic://uuid-here:pass@f.com:443?sni=f.com&congestion_control=bbr',
      ) as TuicConfig;

      expect(config.uuid, 'uuid-here');
      expect(config.password, 'pass');
      expect(config.address, 'f.com');
      expect(config.congestionControl, 'bbr');
    });
  });

  group('block protocols', () {
    test('parses a WireGuard INI', () {
      final config = ConfigParser.parse('''
[Interface]
PrivateKey = PRIVKEY
Address = 10.0.0.2/32
DNS = 1.1.1.1

[Peer]
PublicKey = PUBKEY
Endpoint = g.com:51820
''') as WireGuardConfig;

      expect(config.protocol, 'wireguard');
      expect(config.privateKey, 'PRIVKEY');
      // `address` is the server the user dials, not the local tunnel address.
      expect(config.address, 'g.com');
      expect(config.port, 51820);
      expect(config.localAddresses, ['10.0.0.2/32']);
      expect(config.peers.single.publicKey, 'PUBKEY');
      expect(config.validate(), isTrue);
    });

    test('keeps the local tunnel address out of the server field', () {
      // The old parser wrote `[Interface] Address` into `Config.address`, so
      // the config list displayed the device's own tunnel IP as the server.
      final config = ConfigParser.parse('''
[Interface]
PrivateKey = PRIVKEY
Address = 10.0.0.2/32

[Peer]
PublicKey = PUBKEY
Endpoint = vpn.example.com:51820
''') as WireGuardConfig;

      expect(config.address, 'vpn.example.com');
      expect(config.localAddresses, contains('10.0.0.2/32'));
    });

    test('reads PresharedKey, AllowedIPs and PersistentKeepalive', () {
      // All three were ignored entirely before, so any profile using a
      // preshared key could not complete a handshake.
      final config = ConfigParser.parse('''
[Interface]
PrivateKey = PRIVKEY
Address = 10.0.0.2/32

[Peer]
PublicKey = PUBKEY
PresharedKey = PSK
AllowedIPs = 0.0.0.0/0, ::/0
Endpoint = vpn.example.com:51820
PersistentKeepalive = 25
''') as WireGuardConfig;

      final peer = config.peers.single;
      expect(peer.presharedKey, 'PSK');
      expect(peer.allowedIPs, ['0.0.0.0/0', '::/0']);
      expect(peer.persistentKeepalive, 25);
    });

    test('parses a bracketed IPv6 endpoint', () {
      final config = ConfigParser.parse('''
[Interface]
PrivateKey = PRIVKEY
Address = 10.0.0.2/32

[Peer]
PublicKey = PUBKEY
Endpoint = [2606:4700::1]:2408
''') as WireGuardConfig;

      expect(config.address, '2606:4700::1');
      expect(config.port, 2408);
    });

    test('keeps every peer in a multi-peer profile', () {
      final config = ConfigParser.parse('''
[Interface]
PrivateKey = PRIVKEY
Address = 10.0.0.2/32

[Peer]
PublicKey = ONE
Endpoint = a.com:51820

[Peer]
PublicKey = TWO
Endpoint = b.com:51821
''') as WireGuardConfig;

      expect(config.peers.length, 2);
      expect(config.peers.map((p) => p.publicKey).toList(), ['ONE', 'TWO']);
    });

    test('a profile with no private key cannot validate', () {
      final config = ConfigParser.parse('''
[Interface]
Address = 10.0.0.2/32

[Peer]
PublicKey = PUBKEY
Endpoint = vpn.example.com:51820
''') as WireGuardConfig;

      // Both halves are mandatory. The old `||` check accepted this.
      expect(config.validate(), isFalse);
    });

    test('a profile with no peer cannot validate', () {
      final config = ConfigParser.parse('''
[Interface]
PrivateKey = PRIVKEY
Address = 10.0.0.2/32
''') as WireGuardConfig;

      expect(config.peers, isEmpty);
      expect(config.validate(), isFalse);
    });

    test('parses an OpenVPN config', () {
      final config = ConfigParser.parse('''
client
dev tun
remote h.com 1194
''') as OpenVpnConfig;

      expect(config.protocol, 'openvpn');
      expect(config.address, 'h.com');
      expect(config.port, 1194);
    });

    test('parses an AmneziaWG config with junk parameters', () {
      final config = ConfigParser.parse('''
[Interface]
PrivateKey = PRIV
Jc = 5
Jmin = 50
Jmax = 80

[Peer]
PublicKey = PUB
Endpoint = i.com:51820
''') as AmneziaWGConfig;

      expect(config.protocol, 'amneziawg');
      expect(config.junkCount, 5);
      expect(config.junkMin, 50);
      expect(config.junkMax, 80);
    });
  });

  group('parser dispatch', () {
    test('returns null for unrecognised input', () {
      expect(ConfigParser.parse('this is not a config'), isNull);
    });

    test('returns null for an empty string', () {
      expect(ConfigParser.parse(''), isNull);
    });

    test('parseMultiple extracts several URI links from one blob', () {
      final blob = [
        'vless://11111111-1111-1111-1111-111111111111@a.com:443#One',
        'trojan://p@b.com:443#Two',
        'ss://${base64.encode(utf8.encode("aes-256-gcm:secret"))}@c.com:8388#Three',
      ].join('\n');

      final configs = ConfigParser.parseMultiple(blob);
      expect(configs.length, 3);
      expect(
        configs.map((c) => c.protocol).toSet(),
        {'vless', 'trojan', 'shadowsocks'},
      );
    });
  });

  group('hashing', () {
    test('identical URIs hash identically', () {
      const uri = 'vless://11111111-1111-1111-1111-111111111111@a.com:443';
      expect(ConfigParser.parse(uri)!.getHash(), ConfigParser.parse(uri)!.getHash());
    });

    test('different URIs hash differently', () {
      final a = ConfigParser.parse('vless://x@a.com:443')!;
      final b = ConfigParser.parse('vless://y@a.com:443')!;
      expect(a.getHash(), isNot(b.getHash()));
    });
  });

  group('reload round-trip', () {
    // `ConfigService` stores a record plus the original `rawUri`, and rebuilds
    // the object from that link when the library is loaded. If re-parsing does
    // not yield the same protocol, the config is dropped from the library —
    // which is exactly what used to happen to every VLESS, VMess, Trojan,
    // Hysteria2 and TUIC entry on each app start.
    const uris = [
      'vless://11111111-1111-1111-1111-111111111111@a.com:443'
          '?security=tls&type=ws&path=%2Fws&sni=a.com',
      'vmess://eyJ2IjoiMiIsInBzIjoidiIsImFkZCI6ImIuY29tIiwicG9ydCI6IjQ0MyIsImlkIjoi'
          'MTExMTExMTEtMTExMS0xMTExLTExMTEtMTExMTExMTExMTExIiwiYWlkIjoiMCIsIm5ldCI6IndzIn0=',
      'trojan://pw@c.com:443?sni=c.com',
      'hy2://pw@d.com:443?sni=d.com',
      'tuic://11111111-1111-1111-1111-111111111111:pw@e.com:443',
      'ss://${'YWVzLTI1Ni1nY206c2VjcmV0'}@f.com:8388',
    ];

    for (final uri in uris) {
      test('re-parses ${uri.split('://').first} into the same protocol', () {
        final original = ConfigParser.parse(uri);
        expect(original, isNotNull, reason: 'could not parse $uri');

        final reloaded = ConfigParser.parse(original!.rawUri);
        expect(reloaded, isNotNull);
        expect(reloaded!.protocol, original.protocol);
        expect(reloaded.getHash(), original.getHash());
      });
    }

    test('every reloaded protocol survives the library filter', () {
      // Mirrors `_configFromMap`'s contract: a protocol the app can import
      // must also be reconstructible on the next launch.
      final protocols = uris
          .map((u) => ConfigParser.parse(u)!)
          .map((c) => ConfigParser.parse(c.rawUri)?.protocol)
          .toList();

      expect(protocols.every((p) => p != null), isTrue);
      expect(protocols.toSet(), {'vless', 'vmess', 'trojan', 'hysteria2', 'tuic', 'shadowsocks'});
    });
  });
}
