/// sing-box configuration generator.
///
/// Builds sing-box JSON configuration for protocols served by the bundled
/// sing-box native core (libsingbox.so):
/// - Hysteria 2 (hy2://, hysteria2://)
/// - TUIC v5 (tuic://)
/// - AnyTLS (anytls://)
/// - ShadowTLS v3 (shadowtls://)
/// - AmneziaWG (obfuscated WireGuard with junk packets)
/// - Cloudflare WARP
///
/// Inbound exposes a local SOCKS5 proxy on `127.0.0.1:$socksPort`, which
/// [EngineRunner] bridges to the TUN interface via [libtun2socks.so].

import 'dart:convert';
import '../models/config.dart';

/// Protocols served by the bundled sing-box core on ANDROID, where the
/// Xray-family protocols are carried by the in-process Xray core instead.
const Set<String> kSingboxProtocols = {
  'hysteria2',
  'tuic',
  'anytls',
  // 'shadowtls' is intentionally absent: a shadowtls outbound is only a TLS
  // camouflage layer and must carry an inner proxy as its `detour`, which a
  // shadowtls:// link does not contain. Emitting it as the final outbound
  // produced a tunnel that reported "connected" and passed no traffic.
  //
  // 'amneziawg' is absent for the same kind of reason: the bundled core
  // (libsingbox.so) contains no AmneziaWG symbols at all, so the `amnezia`
  // block is rejected as an unknown field. Advertising it meant every awg://
  // config was imported, ranked and offered, then refused at connect.
  //
  // 'warp' is absent because WarpConfig.fromUri() always returns null - there
  // is no parser, so no warp config can ever exist.
};

/// Protocols the iOS core (libbox) can carry.
///
/// On iOS there is no in-process Xray core: the tunnel runs inside a Network
/// Extension around libbox, which speaks the same outbound types the Android
/// sing-box does - including vless/vmess/trojan/shadowsocks/wireguard. So the
/// whole servable set is wider there, EXCEPT the transports libbox has no
/// dialer for (mKCP and the QUIC transport of vless links).
const Set<String> kLibboxProtocols = {
  'vless',
  'vmess',
  'trojan',
  'shadowsocks',
  'wireguard',
  'hysteria2',
  'tuic',
  'anytls',
};

/// True when [protocol] is served by the bundled sing-box core.
bool isSingboxProtocol(String protocol) => kSingboxProtocols.contains(protocol);

/// Builds the full sing-box JSON document for [config].
/// Converts a hop-ports spec into sing-box's `server_ports` + `hop_interval`
/// fields. `20000-30000` → `20000:30001`; `443,8443` → `443:444,8443:8444`.
Map<String, dynamic> buildServerPorts(String spec) {
  try {
    final parts = <String>[];
    for (final piece in spec.split(',')) {
      final p = piece.trim();
      if (p.contains('-')) {
        final lo = int.parse(p.split('-')[0]);
        final hi = int.parse(p.split('-')[1]);
        parts.add('$lo:${hi + 1}');
      } else {
        final port = int.parse(p);
        parts.add('$port:${port + 1}');
      }
    }
    if (parts.isEmpty) return {};
    return {'server_ports': parts.join(','), 'hop_interval': 30};
  } on Object {
    return {};
  }
}

class SingboxConfigBuilder {
  /// Loopback SOCKS port. Must match [BlackoutVpnService.DEFAULT_SOCKS_PORT].
  final int socksPort;

  /// DNS servers handed to sing-box's internal resolver.
  final List<String> dnsServers;

  /// Route DNS through the proxy instead of letting it resolve locally.
  final bool routeDnsThroughProxy;

  /// Send private/loopback ranges straight out, bypassing the proxy.
  final bool bypassPrivateRanges;

  /// Extra domains that should bypass the proxy (split tunneling).
  final List<String> bypassDomains;

  const SingboxConfigBuilder({
    this.socksPort = 10808,
    this.dnsServers = const ['1.1.1.1', '8.8.8.8'],
    this.routeDnsThroughProxy = false,
    this.bypassPrivateRanges = true,
    this.bypassDomains = const [],
    this.libboxMode = false,
  });

  /// When true the protocol gate accepts the wider [kLibboxProtocols] set —
  /// the iOS engine (libbox) carries the Xray-family protocols too, because
  /// there is no separate Xray core on that platform. Android keeps the
  /// narrower gate so nothing about its engine selection changes.
  final bool libboxMode;

  /// Serialised JSON, ready to hand to `libsingbox.so run -c <file>`.
  String buildJson(Config config) =>
      const JsonEncoder.withIndent('  ').convert(build(config));

  /// The config as a nested map.
  /// WireGuard (and its AmneziaWG/WARP variants) must be an `endpoint`.
  static bool _isWireguardEndpoint(Config config) =>
      config is AmneziaWGConfig ||
      config is WarpConfig ||
      config is WireGuardConfig;

  Map<String, dynamic> build(Config config) {
    final protocol = config.protocol;
    final supported = libboxMode ? kLibboxProtocols : kSingboxProtocols;
    if (!supported.contains(protocol)) {
      throw ArgumentError.value(
        protocol,
        'config.protocol',
        'Not a sing-box protocol. Supported: ${supported.join(", ")}',
      );
    }
    if (libboxMode) {
      final refusal = libboxTransportRefusal(config);
      if (refusal != null) throw ArgumentError(refusal);
    }

    final document = <String, dynamic>{
      'log': {
        'level': 'warn',
        'timestamp': true,
      },
      // No `sniff` field on the inbound: sing-box 1.11 deprecated it and 1.13
      // REMOVED it - the whole document fails to decode ("legacy inbound
      // fields ... inbounds[0]"), which is exactly what the bundled
      // libsingbox.so did on the phone. Sniffing is a route rule action now.
      //
      // libboxMode (iOS): the tunnel extension hands libbox a real TUN file
      // descriptor, so the document must carry a tun inbound with
      // auto_route — the core derives the interface settings from it and
      // calls the platform's openTun. A mixed loopback inbound would start
      // the core with no interface at all.
      'inbounds': [
        if (libboxMode)
          {
            'type': 'tun',
            'tag': 'tun-in',
            'address': ['172.19.0.1/30'],
            'mtu': 9000,
            'auto_route': true,
            'strict_route': true,
            'stack': 'mixed',
          }
        else
          {
            'type': 'mixed',
            'tag': 'mixed-in',
            'listen': '127.0.0.1',
            'listen_port': socksPort,
          },
      ],
      // WireGuard lives in `endpoints` since sing-box 1.11; the outbound form
      // was removed in 1.13 and the bundled core says so in as many words.
      // Everything else stays an outbound.
      'outbounds': <Map<String, dynamic>>[
        if (!_isWireguardEndpoint(config)) _buildOutbound(config),
        {
          'type': 'direct',
          'tag': 'direct',
        },
        {
          'type': 'block',
          'tag': 'block',
        },
      ],
      if (_isWireguardEndpoint(config))
        'endpoints': <Map<String, dynamic>>[_buildOutbound(config)],
      'route': {
        'rules': <Map<String, dynamic>>[
          if (bypassPrivateRanges)
            {
              'ip_is_private': true,
              'outbound': 'direct',
            },
          if (bypassDomains.isNotEmpty)
            {
              'domain_suffix': bypassDomains,
              'outbound': 'direct',
            },
          // Sniff LAST of the rules: a sniff action terminates route
          // evaluation, so putting it first would starve the bypass rules.
          {
            'action': 'sniff',
          },
        ],
        // NO `auto_detect_interface` on Android. sing-box tries to open a
        // netlink socket for the interface monitor, and Google's SELinux
        // policy bans that for normal apps ("netlink socket in Android is
        // banned by Google"). We run sing-box as a subprocess, so no Android
        // platform interface is supplied either - and with the monitor
        // *enforced* by auto_detect_interface, sing-box turns that failure
        // into a FATAL instead of carrying on without a monitor
        // (route/network.go: `enforceInterfaceMonitor :=
        // options.AutoDetectInterface` gates the error). The field is also
        // documented as Linux/Windows/macOS-only. Routing without it works
        // fine behind a VPN service: the TUN carries the traffic.
        'final': 'proxy',
      },
    };

    if (routeDnsThroughProxy) {
      // Typed DNS servers ({"type": ..., "server": ...}): the legacy
      // `address` form was deprecated in 1.12 and REMOVED in 1.14.
      //
      // The old `dns.rules: [{outbound: any, server: remote-dns}]` (an
      // "outbound DNS rule item") is removed too - that association now lives
      // in the dial fields: `route.default_domain_resolver` for everything
      // else, and `domain_resolver` on the proxy outbound so domains dialed
      // through the tunnel are resolved inside it.
      // Strict mode: one resolver, and it is proxied. The previous config kept
      // a `local-dns` entry with `detour: direct` and made it the DEFAULT
      // domain resolver, so anything outside the proxy outbound was resolved
      // by the carrier - the opposite of what the toggle promises.
      // A resolver used THROUGH the proxy cannot also be the one that resolves
      // the proxy's own hostname: that is a cycle (resolve the server address
      // -> needs the proxy -> needs the server address). Worse, the DoH
      // endpoint was a hostname (`cloudflare-dns.com`) with no bootstrap, so
      // even the resolver's own address needed resolving.
      //
      // Two resolvers instead:
      //   bootstrap-dns - IP literal, direct. Only ever resolves the proxy's
      //                   server hostname. Unavoidably outside the tunnel:
      //                   you cannot resolve the tunnel's own endpoint through
      //                   the tunnel. It never sees the user's browsing.
      //   remote-dns    - IP literal, through the proxy. Resolves everything
      //                   the user actually visits.
      //
      // The chosen pair is what `remote-dns` (and therefore `final`) uses. The
      // previous version hardcoded `https://1.1.1.1` as `remote-dns` and put
      // the user's address in a `remote-dns-ip` entry that nothing referenced:
      // on every sing-box protocol (and all of iOS) the resolver the user
      // picked in Settings was never used, and the secondary was dropped
      // entirely. On a network where 1.1.1.1 is filtered — the exact reason
      // someone picks Shecan or Radar — in-tunnel DNS simply died.
      //
      // Plain `udp` rather than DoH on purpose: these resolvers are addressed
      // by IP and speak port 53. DoH on an arbitrary IP is not something most
      // of them offer, so a `https` server here would fail to come up.
      final primary = dnsServers.isNotEmpty ? dnsServers.first : '1.1.1.1';
      final secondary = dnsServers.length > 1 ? dnsServers[1] : null;
      document['dns'] = {
        'servers': [
          {
            'type': 'udp',
            'tag': 'bootstrap-dns',
            // IP literal: no name resolution needed to reach it.
            'server': primary,
            // NO `detour: "direct"` here. The default dialer already dials
            // direct, and the bundled core REFUSES the explicit form with
            // `start dns/https[bootstrap-dns]: detour to an empty direct
            // outbound makes no sense` — a FATAL that killed every sing-box
            // protocol (hysteria2/tuic/anytls) at startup whenever DNS leak
            // prevention was on. The proxy resolver below keeps its detour:
            // that one points at a real outbound.
          },
          {
            'type': 'udp',
            'tag': 'remote-dns',
            'server': primary,
            'detour': 'proxy',
          },
          // The secondary address of the pair. sing-box has no automatic
          // failover between servers, but keeping it defined means a future
          // rule (or a core that rotates) can use it, and it documents what
          // the user selected.
          if (secondary != null)
            {
              'type': 'udp',
              'tag': 'remote-dns-2',
              'server': secondary,
              'detour': 'proxy',
            },
        ],
        'strategy': 'prefer_ipv4',
        'final': 'remote-dns',
      };
      document['route']!['default_domain_resolver'] = {
        'server': 'remote-dns',
        'strategy': 'prefer_ipv4',
      };
      // The proxy's own hostname is the one thing that must resolve outside
      // the tunnel, or the tunnel can never come up.
      for (final outbound in [
        ...(document['outbounds'] as List? ?? const []),
        ...(document['endpoints'] as List? ?? const []),
      ]) {
        if (outbound is Map && outbound['tag'] == 'proxy') {
          outbound['domain_resolver'] = {
            'server': 'bootstrap-dns',
            'strategy': 'prefer_ipv4',
          };
        }
      }
    }

    return document;
  }

  Map<String, dynamic> _buildOutbound(Config config) {
    switch (config) {
      case VlessConfig c:
        return _buildVlessOutbound(c);

      case VmessConfig c:
        return _buildVmessOutbound(c);

      case TrojanConfig c:
        return _buildTrojanOutbound(c);

      case ShadowsocksConfig c:
        return {
          'type': 'shadowsocks',
          'tag': 'proxy',
          'server': c.address,
          'server_port': c.port,
          'method': c.method,
          'password': c.password,
        };

      case WireGuardConfig c:
        return _buildWireguardEndpoint(c);

      case Hysteria2Config c:
        return {
          'type': 'hysteria2',
          'tag': 'proxy',
          'server': c.address,
          'server_port': c.port,
          'password': c.password,
          // Port hopping: sing-box expects `server_ports` as `start:end`
          // (exclusive end, colon-separated) plus `hop_interval` seconds.
          // Accepts both `20000-30000` (range) and `443,8443` (list) forms.
          if (c.hopPorts != null && c.hopPorts!.isNotEmpty)
            ...buildServerPorts(c.hopPorts!),
          if (c.upMbps != null && c.upMbps! > 0) 'up_mbps': c.upMbps,
          if (c.downMbps != null && c.downMbps! > 0) 'down_mbps': c.downMbps,
          if (c.obfs != null && c.obfs!.isNotEmpty)
            'obfs': {
              'type': c.obfs,
              if (c.obfsPassword != null && c.obfsPassword!.isNotEmpty)
                'password': c.obfsPassword,
            },
          'tls': {
            'enabled': true,
            if (c.sni != null && c.sni!.isNotEmpty) 'server_name': c.sni,
            'insecure': c.insecure,
            'alpn': ['h3'],
          },
        };

      case TuicConfig c:
        return {
          'type': 'tuic',
          'tag': 'proxy',
          'server': c.address,
          'server_port': c.port,
          'uuid': c.uuid,
          if (c.password.isNotEmpty) 'password': c.password,
          'congestion_control': c.congestionControl ?? 'bbr',
          'tls': {
            'enabled': true,
            if (c.sni != null && c.sni!.isNotEmpty) 'server_name': c.sni,
            'insecure': c.insecure,
            'alpn': c.alpn != null && c.alpn!.isNotEmpty
                ? c.alpn!.split(',').map((e) => e.trim()).toList()
                : ['h3'],
          },
        };

      case AnyTlsConfig c:
        return {
          'type': 'anytls',
          'tag': 'proxy',
          'server': c.address,
          'server_port': c.port,
          'password': c.password,
          'tls': {
            'enabled': true,
            if (c.sni != null && c.sni!.isNotEmpty) 'server_name': c.sni,
            'insecure': c.insecure,
          },
        };

      case ShadowTlsConfig c:
        // v3 only: v2 is deprecated and v1 was removed. `detour` is a
        // SERVER-side field (it routes the decrypted inner stream to the
        // real proxy inbound) - a client-side detour is rejected by sing-box.
        return {
          'type': 'shadowtls',
          'tag': 'proxy',
          'server': c.address,
          'server_port': c.port,
          'password': c.password,
          'version': c.version,
          'tls': {
            'enabled': true,
            if (c.sni != null && c.sni!.isNotEmpty) 'server_name': c.sni,
            'insecure': c.insecure,
          },
        };

      case AmneziaWGConfig c:
        // WireGuard moved from outbounds to `endpoints` in sing-box 1.11 and
        // the outbound form was REMOVED in 1.13 - the bundled core carries the
        // literal "use WireGuard endpoint instead". The caller emits this into
        // `endpoints`, not `outbounds`.
        return {
          'type': 'wireguard',
          'tag': 'proxy',
          'address': c.address,
          'port': c.port,
          'private_key': c.privateKey,
          'peer_public_key': c.publicKey,
          if (c.presharedKey != null && c.presharedKey!.isNotEmpty)
            'pre_shared_key': c.presharedKey,
          // The tunnel address is the config's own, not a hard-coded
          // 10.0.0.2/32 - that guessed address dropped every packet on any
          // server whose inner subnet differs.
          'local_address': c.localAddresses.isEmpty
              ? ['10.0.0.2/32']
              : c.localAddresses,
          'mtu': c.mtu ?? 1420,
          // `reserved` is the 3-byte WireGuard header field (a WARP thing),
          // NOT AmneziaWG obfuscation — stuffing the junk-packet numbers in
          // there dialed AWG servers as vanilla WireGuard and the handshake
          // died instantly. The junk parameters belong in sing-box's
          // `amnezia` block (only honoured by sing-box builds with AWG
          // support; a vanilla wireguard outbound must not receive it).
          'amnezia': {
            'jc': c.junkCount,
            'jmin': c.junkMin,
            'jmax': c.junkMax,
          },
        };

      case WarpConfig c:
        return {
          'type': 'wireguard',
          'tag': 'proxy',
          'address': c.address,
          'port': c.port,
          'private_key': c.privateKey,
          'peer_public_key': 'bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=',
          'local_address': ['172.16.0.2/32', '2606:4700:110:8f9f:6f5:7c45:9d36:31e9/128'],
          'mtu': 1280,
        };

      default:
        throw ArgumentError(
          'No sing-box outbound builder for protocol "${config.protocol}"',
        );
    }
  }

  // ───────────────────── libbox (iOS) outbounds ────────────────────────────

  /// Human-readable refusal for a config libbox cannot serve, or null.
  ///
  /// sing-box has no mKCP dialer, no QUIC *transport* dialer for vless links,
  /// and no xhttp/splithttp transport — those configs stay Xray-only and are
  /// honestly refused on iOS instead of failing deep inside the extension.
  static String? libboxTransportRefusal(Config config) {
    final network = switch (config) {
      VlessConfig c => c.network,
      VmessConfig c => c.network,
      TrojanConfig c => c.network,
      _ => null,
    };
    const unsupported = {'kcp', 'quic', 'xhttp', 'splithttp', 'httpupgrade'};
    if (network != null && unsupported.contains(network.toLowerCase())) {
      return "The '$network' transport is not supported by the iOS core. "
          'Use a ws, grpc or tcp link instead.';
    }
    return null;
  }

  /// sing-box's `transport` block for the share-link `type`, or null for raw
  /// TCP. Field names are sing-box's, not Xray's.
  static Map<String, dynamic>? _transportSettings(
    String? network,
    String? path,
    String? host,
    String? serviceName,
  ) {
    switch (network) {
      case 'ws':
      case 'websocket':
        return {
          'type': 'ws',
          'path': (path == null || path.isEmpty) ? '/' : path,
          if (host != null && host.isNotEmpty)
            'headers': {'Host': host},
        };
      case 'grpc':
        return {
          'type': 'grpc',
          'service_name': serviceName ?? path ?? '',
        };
      case 'http':
        // Xray's "http" transport is HTTP/2; sing-box names it `http` too.
        return {
          'type': 'http',
          'path': (path == null || path.isEmpty) ? '/' : path,
          if (host != null && host.isNotEmpty) 'host': [host],
        };
      case 'httpupgrade':
        return {
          'type': 'httpupgrade',
          'path': (path == null || path.isEmpty) ? '/' : path,
          if (host != null && host.isNotEmpty) 'host': host,
        };
      default:
        return null;
    }
  }

  /// sing-box's `tls` block from the share-link TLS material.
  ///
  /// REALITY additionally REQUIRES uTLS in sing-box (a plain Go TLS stack
  /// cannot produce the uTLS handshake REALITY's server-side probe logic
  /// expects), so a reality block without a fingerprint is fatal — the same
  /// default (`chrome`) the Xray builder applies.
  static Map<String, dynamic>? _tlsSettings({
    required bool enabled,
    required String? sni,
    required bool insecure,
    required String? fingerprint,
    required String? alpn,
    required String? publicKey,
    required String? shortId,
  }) {
    if (!enabled) return null;
    final isReality = publicKey != null && publicKey.isNotEmpty;
    return {
      'enabled': true,
      if (sni != null && sni.isNotEmpty) 'server_name': sni,
      'insecure': insecure,
      if (fingerprint != null && fingerprint.isNotEmpty || isReality)
        'utls': {
          'enabled': true,
          'fingerprint':
              (fingerprint != null && fingerprint.isNotEmpty)
                  ? fingerprint
                  : 'chrome',
        },
      if (alpn != null && alpn.isNotEmpty)
        'alpn': alpn
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList(),
      if (isReality)
        'reality': {
          'enabled': true,
          'public_key': publicKey,
          if (shortId != null) 'short_id': shortId,
        },
    };
  }

  Map<String, dynamic> _buildVlessOutbound(VlessConfig c) {
    final isReality = c.security.toLowerCase() == 'reality';
    final isTls = c.security.toLowerCase() == 'tls' || isReality;
    final sni = _orDefault(c.sni, _orDefault(c.host, c.address));
    return {
      'type': 'vless',
      'tag': 'proxy',
      'server': c.address,
      'server_port': c.port,
      'uuid': c.uuid,
      if (c.flow != null && c.flow!.isNotEmpty) 'flow': c.flow,
      if (_transportSettings(c.network, c.path, c.host ?? c.sni, c.serviceName)
          case final transport?)
        'transport': transport,
      if (_tlsSettings(
            enabled: isTls,
            sni: sni,
            insecure: c.allowInsecure,
            fingerprint: c.fingerprint,
            alpn: c.alpn,
            publicKey: isReality ? (c.publicKey ?? c.pbk) : null,
            shortId: c.shortId,
          )
          case final tls?)
        'tls': tls,
    };
  }

  Map<String, dynamic> _buildVmessOutbound(VmessConfig c) {
    final isTls = c.tls != null &&
        c.tls!.isNotEmpty &&
        c.tls!.toLowerCase() != 'none';
    return {
      'type': 'vmess',
      'tag': 'proxy',
      'server': c.address,
      'server_port': c.port,
      'uuid': c.uuid,
      'security': c.cipher.isEmpty ? 'auto' : c.cipher,
      'alter_id': int.tryParse(c.alterId) ?? 0,
      if (_transportSettings(c.network, c.path, c.host ?? c.sni, c.serviceName)
          case final transport?)
        'transport': transport,
      if (_tlsSettings(
            enabled: isTls,
            sni: _orDefault(c.sni, c.host),
            insecure: c.allowInsecure,
            fingerprint: c.fingerprint,
            alpn: c.alpn,
            publicKey: null,
            shortId: null,
          )
          case final tls?)
        'tls': tls,
    };
  }

  Map<String, dynamic> _buildTrojanOutbound(TrojanConfig c) {
    return {
      'type': 'trojan',
      'tag': 'proxy',
      'server': c.address,
      'server_port': c.port,
      'password': c.password,
      if (_transportSettings(c.network, c.path, c.host ?? c.sni, c.serviceName)
          case final transport?)
        'transport': transport,
      if (_tlsSettings(
            enabled: true, // Trojan is TLS by definition.
            sni: _orDefault(c.sni, c.host),
            insecure: c.allowInsecure,
            fingerprint: c.fingerprint,
            alpn: c.alpn,
            publicKey: null,
            shortId: null,
          )
          case final tls?)
        'tls': tls,
    };
  }

  /// Vanilla WireGuard as a sing-box `endpoint` (1.11+ form — the outbound
  /// form was removed in 1.13). Same shape the AmneziaWG builder emits, minus
  /// the junk-packet block.
  Map<String, dynamic> _buildWireguardEndpoint(WireGuardConfig c) {
    final peer = c.peers.isEmpty ? null : c.peers.first;
    return {
      'type': 'wireguard',
      'tag': 'proxy',
      'address': c.localAddresses.isEmpty
          ? ['172.16.0.2/32']
          : c.localAddresses,
      'private_key': c.privateKey,
      'mtu': c.mtu ?? 1420,
      'peers': [
        {
          'address': peer?.host ?? c.address,
          'port': peer?.port ?? c.port,
          'public_key': peer?.publicKey ?? '',
          if (peer?.presharedKey != null &&
              peer!.presharedKey!.isNotEmpty)
            'pre_shared_key': peer.presharedKey,
          'allowed_ips': (peer?.allowedIPs.isNotEmpty ?? false)
              ? peer!.allowedIPs
              : const ['0.0.0.0/0', '::/0'],
        },
      ],
    };
  }

  static String _orDefault(String? value, String? fallback) =>
      (value == null || value.isEmpty) ? (fallback ?? '') : value;
}
