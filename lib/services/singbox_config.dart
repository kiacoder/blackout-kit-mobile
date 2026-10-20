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

/// Protocols served by the bundled sing-box core.
const Set<String> kSingboxProtocols = {
  'hysteria2',
  'tuic',
  'anytls',
  'shadowtls',
  'amneziawg',
  'warp',
};

/// True when [protocol] is served by the bundled sing-box core.
bool isSingboxProtocol(String protocol) => kSingboxProtocols.contains(protocol);

/// Builds the full sing-box JSON document for [config].
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
  });

  /// Serialised JSON, ready to hand to `libsingbox.so run -c <file>`.
  String buildJson(Config config) =>
      const JsonEncoder.withIndent('  ').convert(build(config));

  /// The config as a nested map.
  Map<String, dynamic> build(Config config) {
    final protocol = config.protocol;
    if (!isSingboxProtocol(protocol)) {
      throw ArgumentError.value(
        protocol,
        'config.protocol',
        'Not a sing-box protocol. Supported: ${kSingboxProtocols.join(", ")}',
      );
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
      'inbounds': [
        {
          'type': 'mixed',
          'tag': 'mixed-in',
          'listen': '127.0.0.1',
          'listen_port': socksPort,
        },
      ],
      'outbounds': <Map<String, dynamic>>[
        _buildOutbound(config),
        {
          'type': 'direct',
          'tag': 'direct',
        },
        {
          'type': 'block',
          'tag': 'block',
        },
      ],
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
        'auto_detect_interface': true,
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
      document['dns'] = {
        'servers': [
          {
            'type': 'https',
            'tag': 'remote-dns',
            'server': 'cloudflare-dns.com',
            'detour': 'proxy',
          },
          {
            'type': 'udp',
            'tag': 'local-dns',
            'server': dnsServers.isNotEmpty ? dnsServers.first : '1.1.1.1',
            'detour': 'direct',
          },
        ],
        'strategy': 'prefer_ipv4',
      };
      document['route']!['default_domain_resolver'] = {
        'server': 'local-dns',
        'strategy': 'prefer_ipv4',
      };
      for (final outbound in document['outbounds']!) {
        if (outbound['tag'] == 'proxy') {
          outbound['domain_resolver'] = {
            'server': 'remote-dns',
            'strategy': 'prefer_ipv4',
          };
        }
      }
    }

    return document;
  }

  Map<String, dynamic> _buildOutbound(Config config) {
    switch (config) {
      case Hysteria2Config c:
        return {
          'type': 'hysteria2',
          'tag': 'proxy',
          'server': c.address,
          'server_port': c.port,
          'password': c.password,
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
        return {
          'type': 'wireguard',
          'tag': 'proxy',
          'server': c.address,
          'server_port': c.port,
          'private_key': c.privateKey,
          'peer_public_key': c.publicKey,
          if (c.presharedKey != null && c.presharedKey!.isNotEmpty)
            'pre_shared_key': c.presharedKey,
          'local_address': ['10.0.0.2/32'],
          'mtu': 1420,
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
          'server': c.address,
          'server_port': c.port,
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
}
