/// Xray-core configuration generator.
///
/// This is the Dart port of the CLI's `blackoutkit/engines/xray.py`
/// `generate_config()` / `_build_outbound()` pair, adapted for the Android
/// on-device core (libv2ray / AndroidLibXrayLite).
///
/// Why this file exists at all:
///   On desktop the CLI writes an `xray_config.json` next to `xray.exe` and
///   launches it as a subprocess. On Android there is no executable bit, so the
///   core runs **in-process** through the `libv2ray` gomobile binding. The JSON
///   is identical in spirit but must additionally carry a `tun` inbound,
///   because libv2ray's `startLoop(config, tunFd)` only exports the fd through
///   the `xray.tun.fd` environment variable — Xray still has to be told to
///   bind it. Without the tun inbound the core starts and then black-holes
///   every packet.
///
/// Verified against:
///   - libv2ray `libv2ray_main.go`  → `tunFdKey = "xray.tun.fd"`, 0 = no tun
///   - Xray TUN inbound schema      → name / mtu / gateway / dns / userLevel
///   - v2rayNG `v2ray_config_with_tun.json` → the proven inbound shape

import 'dart:convert';

import '../models/config.dart';

/// Which protocols the bundled Xray core can actually serve.
///
/// Kept as an explicit allow-list rather than a `switch` default so that adding
/// a protocol to [Config] cannot silently fall through into a bogus outbound.
///
/// `wireguard` is on this list because the bundled `libgojni.so` genuinely
/// contains `xray.proxy.wireguard` — verified by reading the module
/// registration strings out of the shipped binary, together with the full
/// config schema it accepts (`secretKey`, `address`, `peers`, `endpoint`,
/// `publicKey`, `preSharedKey`, `keepAlive`, `allowedIPs`, `mtu`, `reserved`).
/// It therefore does **not** need the sing-box binary that is absent from this
/// build, and does not drag in sing-box's GPL-3.0 licence.
///
/// Protocols that remain absent from the core: hysteria2 (the core has
/// Hysteria **v1** only — `xray.proxy.hysteria` — which is a different
/// protocol), tuic, amneziawg, openvpn and psiphon.
const Set<String> kXrayProtocols = {
  'vless',
  'vmess',
  'trojan',
  'shadowsocks',
  'wireguard',
};

/// True when [config] is served by the bundled Xray core.
bool isXrayProtocol(String protocol) => kXrayProtocols.contains(protocol);

/// Builds the full Xray JSON document for [config].
class XrayConfigBuilder {
  /// Loopback SOCKS port. Must match [BlackoutVpnService.DEFAULT_SOCKS_PORT].
  final int socksPort;

  /// Optional loopback HTTP port (left disabled by default).
  final int? httpPort;

  /// MTU handed to the TUN inbound. Must match the value given to
  /// `VpnService.Builder.setMtu()` or the interface will fragment.
  final int mtu;

  /// Address the core's netstack answers on. Must sit in the same subnet as the
  /// address passed to `VpnService.Builder.addAddress()`.
  final String gatewayCidr;

  /// DNS servers handed to the core's internal resolver.
  final List<String> dnsServers;

  /// Route DNS through the proxy instead of letting it resolve locally.
  final bool routeDnsThroughProxy;

  /// Send private/loopback ranges straight out, bypassing the proxy.
  final bool bypassPrivateRanges;

  /// Extra domains that should bypass the proxy (split tunneling).
  final List<String> bypassDomains;

  /// Enable Xray's mux. Off by default: mux measurably hurts throughput on
  /// modern TLS/REALITY setups and every mainstream client ships it disabled.
  final bool muxEnabled;

  const XrayConfigBuilder({
    this.socksPort = 10808,
    this.httpPort,
    this.mtu = 1500,
    this.gatewayCidr = '10.111.222.2/30',
    this.dnsServers = const ['1.1.1.1', '8.8.8.8'],
    this.routeDnsThroughProxy = false,
    this.bypassPrivateRanges = true,
    this.bypassDomains = const [],
    this.muxEnabled = false,
  });

  /// Private + link-local ranges that should never enter the proxy.
  static const List<String> _privateCidrs = [
    '127.0.0.0/8',
    '10.0.0.0/8',
    '172.16.0.0/12',
    '192.168.0.0/16',
    '::1/128',
    'fc00::/7',
    'fe80::/10',
  ];

  /// Serialised JSON, ready to hand to `CoreController.startLoop`.
  String buildJson(Config config) =>
      const JsonEncoder.withIndent('  ').convert(build(config));

  /// The config as a nested map (handy for tests and for `debug_service`).
  Map<String, dynamic> build(Config config) {
    final protocol = config.protocol;
    if (!isXrayProtocol(protocol)) {
      throw ArgumentError.value(
        protocol,
        'config.protocol',
        'Not an Xray protocol. Supported: ${kXrayProtocols.join(", ")}',
      );
    }

    final document = <String, dynamic>{
      'log': {
        'loglevel': 'warning',
        'access': 'none',
        'error': 'none',
      },
      'inbounds': _buildInbounds(),
      'outbounds': <Map<String, dynamic>>[],
      'routing': {
        'domainStrategy': 'IPIfNonMatch',
        'rules': <Map<String, dynamic>>[],
      },
    };

    // ── DNS leak protection ────────────────────────────────────────────────
    if (routeDnsThroughProxy) {
      document['dns'] = {
        'servers': [
          'https+local://cloudflare-dns.com/dns-query',
          'https+local://dns.google/dns-query',
          ...dnsServers,
          'localhost',
        ],
        'queryStrategy': 'UseIP',
      };
      _routingRules(document).add({
        'type': 'field',
        'port': 53,
        'network': 'udp,tcp',
        'outboundTag': 'proxy',
      });
    }

    // ── Split tunneling ────────────────────────────────────────────────────
    if (bypassPrivateRanges) {
      _routingRules(document).add({
        'type': 'field',
        'ip': _privateCidrs,
        'outboundTag': 'direct',
      });
    }
    if (bypassDomains.isNotEmpty) {
      _routingRules(document).add({
        'type': 'field',
        'domain': bypassDomains,
        'outboundTag': 'direct',
      });
    }

    // Catch-all: everything else goes through the proxy.
    _routingRules(document).add({
      'type': 'field',
      'network': 'tcp,udp',
      'outboundTag': 'proxy',
    });

    final outbounds = document['outbounds'] as List<Map<String, dynamic>>;
    outbounds.add(_buildOutbound(config));
    outbounds.add({
      'tag': 'direct',
      'protocol': 'freedom',
      'streamSettings': {
        'sockopt': {'domainStrategy': 'UseIP'},
      },
    });
    outbounds.add({
      'tag': 'block',
      'protocol': 'blackhole',
      'settings': {
        'response': {'type': 'http'},
      },
    });

    return document;
  }

  List<Map<String, dynamic>> _routingRules(Map<String, dynamic> document) =>
      (document['routing'] as Map<String, dynamic>)['rules']
          as List<Map<String, dynamic>>;

  // ───────────────────────────── inbounds ─────────────────────────────────

  List<Map<String, dynamic>> _buildInbounds() {
    final sniffing = {
      'enabled': true,
      'destOverride': ['http', 'tls', 'quic'],
    };

    final inbounds = <Map<String, dynamic>>[
      {
        'tag': 'socks',
        'port': socksPort,
        'listen': '127.0.0.1',
        'protocol': 'socks',
        'settings': {
          'auth': 'noauth',
          'udp': true,
          'userLevel': 8,
        },
        'sniffing': sniffing,
      },
    ];

    if (httpPort != null) {
      inbounds.add({
        'tag': 'http',
        'port': httpPort,
        'listen': '127.0.0.1',
        'protocol': 'http',
        'settings': <String, dynamic>{},
        'sniffing': sniffing,
      });
    }

    // The TUN inbound is what actually captures device traffic. libv2ray
    // exports the fd via `xray.tun.fd`; this block tells Xray to use it.
    inbounds.add({
      'tag': 'tun',
      'protocol': 'tun',
      'settings': {
        'name': 'xray0',
        'mtu': mtu,
        'gateway': [gatewayCidr],
        'dns': dnsServers,
        'userLevel': 8,
      },
      'sniffing': sniffing,
    });

    return inbounds;
  }

  // ───────────────────────────── outbounds ────────────────────────────────

  Map<String, dynamic> _buildOutbound(Config config) {
    // WireGuard brings its own framing. There is no TLS layer and no
    // ws/grpc/xhttp transport to describe, so it deliberately never gets a
    // `streamSettings` block — emitting one would describe a transport that
    // does not exist for this protocol.
    if (config is WireGuardConfig) return _buildWireGuardOutbound(config);

    final stream = _buildStreamSettings(config);
    final mux = {'enabled': muxEnabled};

    switch (config) {
      case VlessConfig c:
        _validateReality(c);
        final user = <String, dynamic>{'id': c.uuid, 'encryption': 'none'};
        if (c.flow != null && c.flow!.isNotEmpty) user['flow'] = c.flow;
        return {
          'tag': 'proxy',
          'protocol': 'vless',
          'settings': {
            'vnext': [
              {
                'address': c.address,
                'port': c.port,
                'users': [user],
              },
            ],
          },
          'streamSettings': stream,
          'mux': mux,
        };

      case VmessConfig c:
        return {
          'tag': 'proxy',
          'protocol': 'vmess',
          'settings': {
            'vnext': [
              {
                'address': c.address,
                'port': c.port,
                'users': [
                  {
                    'id': c.uuid,
                    'alterId': int.tryParse(c.alterId) ?? 0,
                    'security': c.cipher.isEmpty ? 'auto' : c.cipher,
                  },
                ],
              },
            ],
          },
          'streamSettings': stream,
          'mux': mux,
        };

      case TrojanConfig c:
        return {
          'tag': 'proxy',
          'protocol': 'trojan',
          'settings': {
            'servers': [
              {
                'address': c.address,
                'port': c.port,
                'password': c.password,
              },
            ],
          },
          'streamSettings': stream,
          'mux': mux,
        };

      case ShadowsocksConfig c:
        return {
          'tag': 'proxy',
          'protocol': 'shadowsocks',
          'settings': {
            'servers': [
              {
                'address': c.address,
                'port': c.port,
                'method': c.method,
                'password': c.password,
              },
            ],
          },
          'streamSettings': stream,
          'mux': mux,
        };

      default:
        throw ArgumentError(
          'No Xray outbound builder for protocol "${config.protocol}"',
        );
    }
  }

  /// Builds the `wireguard` outbound served by the bundled core.
  ///
  /// Field names are Xray's, not WireGuard's: the local tunnel address goes in
  /// `address`, the client key in `secretKey`, and each peer carries
  /// `endpoint` / `publicKey` / `preSharedKey` / `allowedIPs` / `keepAlive`.
  /// All of those tags were read out of the shipped binary rather than guessed.
  ///
  /// A profile that cannot possibly handshake is rejected here, with the
  /// reason, instead of starting a core that would then drop every packet.
  Map<String, dynamic> _buildWireGuardOutbound(WireGuardConfig config) {
    if (config.privateKey.isEmpty) {
      throw ArgumentError(
        'WireGuard config is missing its [Interface] PrivateKey, so no '
        'handshake can be made.',
      );
    }
    if (config.peers.isEmpty) {
      throw ArgumentError(
        'WireGuard config has no [Peer] block, so there is no server to '
        'connect to.',
      );
    }

    final peers = <Map<String, dynamic>>[];
    for (final peer in config.peers) {
      if (peer.publicKey.isEmpty) {
        throw ArgumentError(
          'WireGuard config has a [Peer] with no PublicKey. WireGuard has no '
          'unauthenticated mode.',
        );
      }
      if (peer.endpoint == null || peer.endpoint!.isEmpty) {
        throw ArgumentError(
          'WireGuard config has a [Peer] with no Endpoint, so there is '
          'nowhere to send traffic.',
        );
      }
      peers.add({
        'publicKey': peer.publicKey,
        'endpoint': peer.endpoint,
        if (peer.presharedKey != null && peer.presharedKey!.isNotEmpty)
          'preSharedKey': peer.presharedKey,
        'allowedIPs': peer.allowedIPs,
        if (peer.persistentKeepalive != null)
          'keepAlive': peer.persistentKeepalive,
      });
    }

    return {
      'tag': 'proxy',
      'protocol': 'wireguard',
      'settings': {
        'secretKey': config.privateKey,
        // `address` here is the *local* tunnel address from
        // `[Interface] Address`, not the server. Omitting it makes the core
        // fail with "invalid WireGuard secret key" / no usable interface.
        if (config.localAddresses.isNotEmpty)
          'address': config.localAddresses,
        'peers': peers,
        // WireGuard rides inside UDP, so the outer path costs roughly 60
        // bytes of header. Defaulting to the TUN MTU would fragment every
        // full-size packet; 1420 is the usual working value.
        'mtu': config.mtu ?? 1420,
      },
    };
  }

  /// REALITY configs are unusable without a public key and a server name, and
  /// failing here gives the user a real message instead of a core that starts
  /// and then times out on every request.
  void _validateReality(VlessConfig c) {
    if (c.security.toLowerCase() != 'reality') return;
    if (c.publicKey == null || c.publicKey!.isEmpty) {
      throw ArgumentError(
        'REALITY config is missing the server public key (pbk).',
      );
    }
    if (c.sni == null || c.sni!.isEmpty) {
      throw ArgumentError('REALITY config is missing the server name (sni).');
    }
  }

  /// Builds `streamSettings` — transport, then security.
  ///
  /// Mirrors `_build_outbound()` in `xray.py`: transport is chosen first and
  /// security is layered on top, so REALITY-over-gRPC and TLS-over-WS both
  /// produce the correct nested shape.
  Map<String, dynamic> _buildStreamSettings(Config config) {
    final stream = <String, dynamic>{};

    final (network, path, host, serviceName, xhttpMode) = switch (config) {
      VlessConfig c => (
          c.network ?? 'tcp',
          c.path,
          c.host ?? c.sni,
          c.serviceName,
          c.xhttpMode,
        ),
      VmessConfig c => (c.network, c.path, c.host ?? c.sni, null, null),
      TrojanConfig c => (c.network ?? 'tcp', c.path, c.host ?? c.sni, null, null),
      _ => ('tcp', null, null, null, null),
    };

    final effectiveNetwork = network.isEmpty ? 'tcp' : network;
    // Defensive: a record persisted before the model was corrected can still
    // carry `xhttp`, which this core has no dialer registered for. The
    // settings key stays `xhttpSettings` — that one *is* present in the binary.
    stream['network'] =
        effectiveNetwork == 'xhttp' ? 'splithttp' : effectiveNetwork;

    switch (effectiveNetwork) {
      case 'ws':
      case 'websocket':
        stream['wsSettings'] = {
          'path': (path == null || path.isEmpty) ? '/' : path,
          if (host != null && host.isNotEmpty) 'headers': {'Host': host},
        };
      case 'grpc':
        stream['grpcSettings'] = {
          'serviceName': serviceName ?? '',
        };
      case 'xhttp':
      case 'splithttp':
        stream['xhttpSettings'] = {
          'path': (path == null || path.isEmpty) ? '/' : path,
          if (host != null && host.isNotEmpty) 'host': host,
          if (xhttpMode != null && xhttpMode.isNotEmpty) 'mode': xhttpMode,
        };
      case 'tcp':
      case 'http':
      case 'kcp':
      case 'quic':
        // No extra settings required for these transports.
        break;
      default:
        // Unknown transport: fall back to tcp rather than emitting a key Xray
        // would reject at parse time.
        stream['network'] = 'tcp';
    }

    // ── security ──────────────────────────────────────────────────────────
    if (config is VlessConfig && config.security.toLowerCase() == 'reality') {
      stream['security'] = 'reality';
      stream['realitySettings'] = {
        'show': false,
        'fingerprint': _orDefault(config.fingerprint, 'chrome'),
        'serverName': config.sni ?? '',
        'publicKey': config.publicKey ?? '',
        'shortId': config.shortId ?? '',
        if (config.spiderX != null && config.spiderX!.isNotEmpty)
          'spiderX': config.spiderX,
      };
      return stream;
    }

    // TLS unless the config explicitly says otherwise.
    final security = switch (config) {
      VlessConfig c => c.security.toLowerCase(),
      VmessConfig c => (c.tls == null || c.tls!.isEmpty) ? 'none' : 'tls',
      TrojanConfig _ => 'tls', // Trojan is TLS by definition.
      _ => 'tls',
    };

    if (security == 'none' && config is! TrojanConfig) {
      stream['security'] = 'none';
      return stream;
    }

    final sni = switch (config) {
      VlessConfig c => c.sni,
      VmessConfig c => c.sni,
      TrojanConfig c => c.sni,
      _ => null,
    };
    final fingerprint = switch (config) {
      VlessConfig c => c.fingerprint,
      TrojanConfig c => c.fingerprint,
      _ => null,
    };
    final allowInsecure = switch (config) {
      TrojanConfig c => c.allowInsecure,
      VlessConfig c => c.allowInsecure,
      _ => false,
    };

    stream['security'] = 'tls';
    stream['tlsSettings'] = {
      if (sni != null && sni.isNotEmpty) 'serverName': sni,
      'fingerprint': _orDefault(fingerprint, 'chrome'),
      'allowInsecure': allowInsecure,
    };
    return stream;
  }

  static String _orDefault(String? value, String fallback) =>
      (value == null || value.isEmpty) ? fallback : value;
}
