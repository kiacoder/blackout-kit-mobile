/// VPN Config model replicating Blackout Kit CLI's ProxyConfig dataclass.
/// Supports: WireGuard, OpenVPN, Shadowsocks protocols.
/// V2 extensibility: Add V2Ray, Trojan, NaïveProxy subclasses without UI changes.

import 'dart:convert';
import 'package:crypto/crypto.dart';

/// Canonical RFC 4122 UUID shape: 8-4-4-4-12 hex digits.
///
/// VMess, VLESS and TUIC all embed a UUID as the client identity. A
/// non-empty but malformed id passes a naive emptiness check, is happily
/// written into the generated engine config, and then fails deep inside
/// the core with a generic init error that gives the user nothing to act
/// on. Rejecting the shape here fails the config at validation time with
/// a clear cause instead.
bool isValidUuid(String s) {
  if (s.length != 36) return false;
  for (var i = 0; i < 36; i++) {
    final c = s.codeUnitAt(i);
    if (i == 8 || i == 13 || i == 18 || i == 23) {
      if (c != 0x2D) return false; // '-'
    } else {
      final isDigit = c >= 0x30 && c <= 0x39;
      final isUpperHex = c >= 0x41 && c <= 0x46;
      final isLowerHex = c >= 0x61 && c <= 0x66;
      if (!isDigit && !isUpperHex && !isLowerHex) return false;
    }
  }
  return true;
}

/// Base proxy config class (protocol-agnostic)
abstract class Config {
  String get protocol;
  String get displayName;
  String get address;
  int get port;
  String get rawUri;

  /// Connection lifecycle (to be implemented by VPN service)
  Future<bool> connect();
  Future<void> disconnect();
  Future<bool> isRunning();

  /// Get unique hash for deduplication
  String getHash() => sha256.convert(rawUri.codeUnits).toString();

  /// Validate config before connection
  bool validate() => address.isNotEmpty && port > 0 && port < 65536;
}

/// Splits `host:port`, a bracketed `[v6]:port`, or a bare host/IPv6 literal.
///
/// Returns null only for empty input. When no port can be read, [fallbackPort]
/// is used — WireGuard's registered default is 51820, but real profiles
/// routinely pin something else, so the value from the file always wins.
(String, int)? _splitHostPort(String? raw, {int fallbackPort = 51820}) {
  final value = raw?.trim() ?? '';
  if (value.isEmpty) return null;

  // Bracketed IPv6, e.g. `[2606:4700::1]:51820`.
  if (value.startsWith('[')) {
    final close = value.indexOf(']');
    if (close == -1) return (value, fallbackPort);
    final host = value.substring(1, close);
    final rest = value.substring(close + 1);
    final port = rest.startsWith(':')
        ? int.tryParse(rest.substring(1)) ?? fallbackPort
        : fallbackPort;
    return (host, port);
  }

  final parts = value.split(':');
  // Only `host:port` — exactly two parts — may be split. A bare IPv6 literal
  // splits into several groups, and the last group of e.g. `2606:4700::1` is
  // numeric (`1`), which the old >= 2 check read as a port: the host became
  // `2606:4700::` and the port became 1. IPv6 + port always arrives bracketed
  // (handled above), so any multi-colon input is an unbracketed v6 literal.
  if (parts.length == 2) {
    final port = int.tryParse(parts.last);
    if (port != null) {
      return (parts[0], port);
    }
  }
  return (value, fallbackPort);
}

/// Splits a comma-separated INI value (`1.1.1.1, 8.8.8.8`).
List<String> _splitList(String value) => value
    .split(',')
    .map((e) => e.trim())
    .where((e) => e.isNotEmpty)
    .toList();

/// A single `[Peer]` block from a WireGuard `.conf`.
///
/// A profile may legally carry more than one peer, and the Xray `wireguard`
/// outbound accepts an array, so every block is kept. Collapsing to the first
/// peer would silently drop routes for the rest.
class WireGuardPeer {
  /// `PublicKey` — the peer's public key. Required; there is no
  /// unauthenticated WireGuard handshake.
  final String publicKey;

  /// `PresharedKey` — optional extra symmetric key. A profile that specifies
  /// one cannot complete a handshake without it, so it is carried through.
  final String? presharedKey;

  /// `AllowedIPs` — which destinations this peer may carry.
  final List<String> allowedIPs;

  /// `Endpoint` — `host:port` as written, or null when the profile omits it.
  final String? endpoint;

  /// `PersistentKeepalive` in seconds.
  final int? persistentKeepalive;

  const WireGuardPeer({
    required this.publicKey,
    this.presharedKey,
    this.allowedIPs = const ['0.0.0.0/0', '::/0'],
    this.endpoint,
    this.persistentKeepalive,
  });

  /// Host half of [endpoint], or null when no endpoint was given.
  String? get host => _splitHostPort(endpoint)?.$1;

  /// Port half of [endpoint], defaulting to 51820.
  int get port => _splitHostPort(endpoint)?.$2 ?? 51820;

  Map<String, dynamic> toMap() => {
        'publicKey': publicKey,
        if (presharedKey != null) 'presharedKey': presharedKey,
        'allowedIPs': allowedIPs,
        if (endpoint != null) 'endpoint': endpoint,
        if (persistentKeepalive != null) 'persistentKeepalive': persistentKeepalive,
      };

  static WireGuardPeer fromMap(Map data) => WireGuardPeer(
        publicKey: data['publicKey'] as String? ?? '',
        presharedKey: data['presharedKey'] as String?,
        allowedIPs: (data['allowedIPs'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            const ['0.0.0.0/0', '::/0'],
        endpoint: data['endpoint'] as String?,
        persistentKeepalive: data['persistentKeepalive'] as int?,
      );
}

/// AnyTLS config (anytls://password@host:port?sni=...&insecure=1).
///
/// Served by the bundled sing-box core (libsingbox.so).
class AnyTlsConfig extends Config {
  final String name;
  final String rawUri;
  final String password;
  final String address;
  final int port;
  final String? sni;
  final bool insecure;

  AnyTlsConfig({
    required this.name, required this.rawUri, required this.password,
    required this.address, required this.port,
    this.sni, this.insecure = false,
  });

  @override String get protocol => 'anytls';
  @override String get displayName => name;
  @override Future<bool> connect() async => true;
  @override Future<void> disconnect() async {}
  @override Future<bool> isRunning() async => false;
  @override bool validate() => address.isNotEmpty && port > 0 && password.isNotEmpty;

  static AnyTlsConfig? fromUri(String uri, {String? customName}) {
    try {
      uri = ConfigParser.normalizeScheme(uri.trim());
      if (!uri.startsWith('anytls://')) return null;
      final u = ConfigParser.tryParseUri(uri);
      if (u == null) return null;
      String name = customName ?? 'AnyTLS (${u.host}:${u.port})';
      if (customName == null && u.fragment.isNotEmpty) {
        name = ConfigParser.safeFragment(uri, fallback: name);
      }
      return AnyTlsConfig(
        name: name, rawUri: uri,
        // `userInfo` is still percent-encoded: a password written as
        // p%40ss must reach the engine as p@ss, or authentication
        // fails on every server whose password has a reserved char.
        password: ConfigParser._decodeUserInfo(u.userInfo),
        address: u.host, port: u.port,
        sni: u.queryParameters['sni'],
        insecure: ConfigParser._insecure(u.queryParameters),
      );
    } catch (_) { return null; }
  }
}

/// ShadowTLS v3 config (shadowtls://password@host:port?sni=...).
///
/// v3 shadows a real TLS site: active probes see the genuine handshake of the
/// shadowed domain, not a proxy.
class ShadowTlsConfig extends Config {
  final String name;
  final String rawUri;
  final String password;
  final String address;
  final int port;
  final String? sni;
  final bool insecure;
  final int version;

  ShadowTlsConfig({
    required this.name, required this.rawUri, required this.password,
    required this.address, required this.port,
    this.sni, this.insecure = false, this.version = 3,
  });

  @override String get protocol => 'shadowtls';
  @override String get displayName => name;
  @override Future<bool> connect() async => true;
  @override Future<void> disconnect() async {}
  @override Future<bool> isRunning() async => false;
  @override bool validate() => address.isNotEmpty && port > 0 && password.isNotEmpty;

  static ShadowTlsConfig? fromUri(String uri, {String? customName}) {
    try {
      uri = ConfigParser.normalizeScheme(uri.trim());
      if (!uri.startsWith('shadowtls://')) return null;
      final u = ConfigParser.tryParseUri(uri);
      if (u == null) return null;
      String name = customName ?? 'ShadowTLS (${u.host}:${u.port})';
      if (customName == null && u.fragment.isNotEmpty) {
        name = ConfigParser.safeFragment(uri, fallback: name);
      }
      return ShadowTlsConfig(
        name: name, rawUri: uri,
        // `userInfo` is still percent-encoded: a password written as
        // p%40ss must reach the engine as p@ss, or authentication
        // fails on every server whose password has a reserved char.
        password: ConfigParser._decodeUserInfo(u.userInfo),
        address: u.host, port: u.port,
        sni: u.queryParameters['sni'],
        insecure: ConfigParser._insecure(u.queryParameters),
        version: int.tryParse(u.queryParameters['version'] ?? '') ?? 3,
      );
    } catch (_) { return null; }
  }
}

/// WireGuard config, parsed from a standard `.conf` / `wg-quick` profile.
///
/// Carried on Android by the bundled Xray core's own `wireguard` outbound
/// (`xray.proxy.wireguard`), so no separate sing-box binary is required.
class WireGuardConfig extends Config {
  final String name;
  final String rawUri;

  /// `[Interface] PrivateKey` — this device's static private key.
  final String privateKey;

  /// `[Interface] Address` — the local address(es) the interface claims.
  ///
  /// This is **not** the server. It is what Xray's `wireguard` outbound wants
  /// in its own `address` field, and it must stay distinct from
  /// [Config.address], which is the server the user dials.
  final List<String> localAddresses;

  /// `[Interface] DNS`, comma separated exactly as written in the file.
  final String dns;

  /// `[Interface] MTU`, when the profile pins one.
  final int? mtu;

  /// Every `[Peer]` block, in file order.
  final List<WireGuardPeer> peers;

  WireGuardConfig({
    required this.name,
    required this.rawUri,
    required this.privateKey,
    this.localAddresses = const [],
    this.dns = '',
    this.mtu,
    this.peers = const [],
  });

  @override
  String get protocol => 'wireguard';

  @override
  String get displayName => name;

  /// The server the user connects to: the first peer's endpoint host.
  @override
  String get address => peers.isEmpty ? '' : (peers.first.host ?? '');

  @override
  int get port => peers.isEmpty ? 51820 : peers.first.port;

  @override
  Future<bool> connect() async {
    return true;
  }

  @override
  Future<void> disconnect() async {}

  @override
  Future<bool> isRunning() async {
    return false;
  }

  /// Both halves are mandatory — WireGuard has no unauthenticated mode, so a
  /// profile missing its private key, or any peer missing its public key or
  /// endpoint, cannot handshake. The previous implementation used `||` and so
  /// accepted a profile with an endpoint and no key at all.
  @override
  bool validate() {
    if (privateKey.isEmpty) return false;
    if (peers.isEmpty) return false;
    // Xray's wireguard outbound needs `address`; without a local address the
    // builder omits it and the core refuses the whole config at load time.
    // Validating only the keys let an unbuildable profile pass as ready.
    if (localAddresses.isEmpty) return false;
    return peers.every(
      (p) => p.publicKey.isNotEmpty && (p.endpoint ?? '').isNotEmpty,
    );
  }

  /// Parse a WireGuard `.conf` / `wg-quick` profile.
  ///
  /// Section-aware: keys are attributed to `[Interface]` or to the `[Peer]`
  /// block they appear in, which the previous flat scan could not do — it read
  /// the first `PublicKey` anywhere in the file as *the* peer key and never
  /// looked at `AllowedIPs`, `PresharedKey` or `PersistentKeepalive` at all.
  static WireGuardConfig? fromUri(String content, {String? customName}) {
    try {
      String privateKey = '';
      String dns = '';
      int? mtu;
      final localAddresses = <String>[];

      // Raw key/value maps per peer, in file order. Built first, then
      // converted, because a peer's fields arrive incrementally.
      final peerMaps = <Map<String, String>>[];
      Map<String, String>? current;

      for (final rawLine in content.split('\n')) {
        final line = rawLine.trim();
        if (line.isEmpty || line.startsWith('#') || line.startsWith(';')) {
          continue;
        }

        if (line.startsWith('[')) {
          final section = line.toLowerCase();
          if (section.startsWith('[peer')) {
            current = <String, String>{};
            peerMaps.add(current);
          } else {
            // `[Interface]` or anything unrecognised ends the current peer.
            current = null;
          }
          continue;
        }

        final eq = line.indexOf('=');
        if (eq == -1) continue;
        final key = line.substring(0, eq).trim().toLowerCase();
        final value = line.substring(eq + 1).trim();
        if (value.isEmpty) continue;

        if (current != null) {
          current[key] = value;
          continue;
        }

        switch (key) {
          case 'privatekey':
            privateKey = value;
          case 'address':
            localAddresses.addAll(_splitList(value));
          case 'dns':
            dns = value;
          case 'mtu':
            mtu = int.tryParse(value);
        }
      }

      final peers = peerMaps.map((m) {
        final allowed = m['allowedips'];
        return WireGuardPeer(
          publicKey: m['publickey'] ?? '',
          presharedKey: m['presharedkey'],
          allowedIPs: allowed == null || allowed.isEmpty
              ? const ['0.0.0.0/0', '::/0']
              : _splitList(allowed),
          endpoint: m['endpoint'],
          persistentKeepalive: int.tryParse(m['persistentkeepalive'] ?? ''),
        );
      }).toList();

      final host = peers.isEmpty ? '' : (peers.first.host ?? '');
      return WireGuardConfig(
        name: customName ??
            (host.isEmpty ? 'WireGuard' : 'WireGuard ($host:${peers.first.port})'),
        rawUri: content,
        privateKey: privateKey,
        localAddresses: localAddresses,
        dns: dns,
        mtu: mtu,
        peers: peers,
      );
    } catch (e) {
      return null;
    }
  }
}

/// OpenVPN config
class OpenVpnConfig extends Config {
  final String name;
  final String rawUri;
  final String configContent;
  final String address;
  final int port;

  OpenVpnConfig({
    required this.name,
    required this.rawUri,
    required this.configContent,
    required this.address,
    this.port = 1194,
  });

  @override
  String get protocol => 'openvpn';

  @override
  String get displayName => name;

  @override
  Future<bool> connect() async {
    return true;
  }

  @override
  Future<void> disconnect() async {}

  @override
  Future<bool> isRunning() async {
    return false;
  }

  @override
  bool validate() {
    return configContent.isNotEmpty && address.isNotEmpty;
  }

  static OpenVpnConfig? fromUri(String content, {String? customName}) {
    try {
      String remoteHost = '127.0.0.1';
      int remotePort = 1194;

      final lines = content.split('\n');
      var foundRemote = false;
      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.startsWith('remote ')) {
          final parts = trimmed.split(RegExp(r'\s+'));
          if (parts.length >= 2) {
            remoteHost = parts[1];
            foundRemote = true;
          }
          if (parts.length >= 3) remotePort = int.tryParse(parts[2]) ?? 1194;
          break;
        }
      }
      // A profile without a remote cannot connect to anything. Defaulting to
      // 127.0.0.1 produced a "valid" config that silently dialled the phone.
      if (!foundRemote) return null;

      return OpenVpnConfig(
        name: customName ?? 'OpenVPN ($remoteHost:$remotePort)',
        rawUri: content,
        configContent: content,
        address: remoteHost,
        port: remotePort,
      );
    } catch (e) {
      return null;
    }
  }
}

/// Shadowsocks config
class ShadowsocksConfig extends Config {
  final String name;
  final String rawUri;
  final String address;
  final int port;
  final String method;
  final String password;
  final String? plugin;

  ShadowsocksConfig({
    required this.name,
    required this.rawUri,
    required this.address,
    required this.port,
    required this.method,
    required this.password,
    this.plugin,
  });

  @override
  String get protocol => 'shadowsocks';

  @override
  String get displayName => name;

  @override
  Future<bool> connect() async {
    return true;
  }

  @override
  Future<void> disconnect() async {}

  @override
  Future<bool> isRunning() async {
    return false;
  }

  @override
  bool validate() {
    return address.isNotEmpty && port > 0 && method.isNotEmpty && password.isNotEmpty;
  }

  /// Parse ss:// URI format (supports plain & base64 encoded)
  static ShadowsocksConfig? fromUri(String uri, {String? customName}) {
    try {
      uri = ConfigParser.normalizeScheme(uri.trim());
      if (!uri.startsWith('ss://')) return null;

      String nameFromHash = customName ?? '';
      String cleanUri = uri.substring(5);

      final hashIndex = cleanUri.indexOf('#');
      if (hashIndex != -1) {
        if (nameFromHash.isEmpty) {
          nameFromHash = ConfigParser.safeFragment(uri, fallback: nameFromHash);
        }
        cleanUri = cleanUri.substring(0, hashIndex);
      }

      // Check if base64 encoded (ss://BASE64@host:port) or full base64 (ss://BASE64)
      if (!cleanUri.contains('@')) {
        try {
          final normalized = base64.normalize(cleanUri);
          final decoded = utf8.decode(base64.decode(normalized));
          cleanUri = decoded;
        } catch (_) {}
      } else {
        final parts = cleanUri.split('@');
        final encodedCreds = parts[0];
        try {
          final normalized = base64.normalize(encodedCreds);
          final decodedCreds = utf8.decode(base64.decode(normalized));
          cleanUri = '$decodedCreds@${parts[1]}';
        } catch (_) {}
      }

      final atIndex = cleanUri.lastIndexOf('@');
      if (atIndex == -1) return null;

      final creds = cleanUri.substring(0, atIndex);
      // A query string (e.g. `?type=tcp` on shadowsocks-2022 links) is not part
      // of the server address. Leaving it in made `int.tryParse` on the port
      // fail and the config fall back to port 8388 — a silent wrong-port bug on
      // every ss link that carries transport metadata.
      // Strip the query AND the path: `ss://m:p@host:1234/` used to leave the
      // slash attached to the port, `int.tryParse` failed, and the config
      // silently fell back to 8388 - connecting to the wrong port.
      final serverPart = cleanUri
          .substring(atIndex + 1)
          .split('?')[0]
          .split('/')[0]
          .trim();

      final credParts = creds.split(':');
      if (credParts.length < 2) return null;

      // SIP002 allows a NON-base64 `method:password` userinfo. This branch is
      // the plain one, and it was the only credential path in the file that
      // skipped the shared decoder - so a password containing %40 or %3A was
      // sent literally and the server rejected it.
      final method = ConfigParser._decodeUserInfo(credParts[0]);
      final password =
          ConfigParser._decodeUserInfo(credParts.sublist(1).join(':'));

      final colonIndex = serverPart.lastIndexOf(':');
      if (colonIndex == -1) return null;

      var address = serverPart.substring(0, colonIndex);
      final portStr = serverPart.substring(colonIndex + 1);
      final parsedPort = int.tryParse(portStr);
      // No port in the link: 8388 is shadowsocks' conventional default, which
      // is what the old code did on every parse failure too. Only fall back
      // when the port is genuinely absent or unparseable, never to paper over
      // a malformed address.
      final port = parsedPort ?? 8388;
      if (address.startsWith('[') && address.endsWith(']')) {
        address = address.substring(1, address.length - 1);
      }
      if (address.isEmpty) return null;

      // `plugin=` (obfs-local / v2ray-plugin) was silently dropped even though
      // the model carries the field, so a plugin-protected server was dialled
      // as plain shadowsocks and could never handshake.
      String? plugin;
      final queryIndex = cleanUri.indexOf('?');
      if (queryIndex != -1) {
        final query = cleanUri.substring(queryIndex + 1);
        for (final pair in query.split('&')) {
          final eq = pair.indexOf('=');
          if (eq <= 0) continue;
          if (pair.substring(0, eq) == 'plugin') {
            plugin = Uri.decodeComponent(pair.substring(eq + 1));
            break;
          }
        }
      }

      return ShadowsocksConfig(
        name: nameFromHash.isNotEmpty ? nameFromHash : 'Shadowsocks ($address:$port)',
        rawUri: uri,
        address: address,
        port: port,
        method: method,
        password: password,
        plugin: plugin,
      );
    } catch (e) {
      return null;
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// VLESS config  (xray engine — vless://uuid@host:port?security=reality&...)
// ─────────────────────────────────────────────────────────────────────────────
class VlessConfig extends Config {
  final String name;
  final String rawUri;
  final String uuid;
  final String address;
  final int port;
  final String security;   // none / tls / reality
  final String? flow;
  final String? sni;
  final String? fingerprint;
  final String? publicKey;  // REALITY
  final String? shortId;    // REALITY
  final String? pbk;        // REALITY short alias
  final String? network;    // tcp / ws / grpc / http / splithttp
  // Transport detail. These were previously parsed away, which silently broke
  // every WebSocket / gRPC config: the outbound would dial the right host on
  // the right port but request the wrong path and get 404s forever.
  final String? path;       // ws / splithttp path
  final String? host;       // ws Host header / splithttp host
  final String? serviceName; // grpc service name
  final String? spiderX;    // REALITY spider path
  final String? xhttpMode;  // splithttp mode: auto / packet-up / stream-up
  final String? alpn;       // TLS ALPN list
  final bool allowInsecure;
  // Transport detail for http / kcp / quic. These parameters are present in
  // every share link that uses those transports, and they used to be parsed
  // away: the outbound was built with the right host and port but no
  // transport settings at all, so an mKCP server rejected the connection and
  // an http/2 or QUIC server never saw the request it expected.
  final String? headerType;   // kcp / quic / httpheader disguise
  final String? kcpSeed;      // mKCP obfuscation seed
  final String? quicSecurity; // quic: none / aes-128-gcm / chacha20-poly1305
  final String? quicKey;      // quic encryption key

  VlessConfig({
    required this.name, required this.rawUri, required this.uuid,
    required this.address, required this.port,
    this.security = 'none', this.flow, this.sni, this.fingerprint,
    this.publicKey, this.shortId, this.pbk, this.network,
    this.path, this.host, this.serviceName, this.spiderX, this.xhttpMode,
    this.alpn, this.allowInsecure = false,
    this.headerType, this.kcpSeed, this.quicSecurity, this.quicKey,
  });

  @override String get protocol => 'vless';
  @override String get displayName => name;
  @override Future<bool> connect() async => true;
  @override Future<void> disconnect() async {}
  @override Future<bool> isRunning() async => false;
  /// A REALITY config without a server public key cannot handshake and cannot
  /// even be turned into an Xray outbound, so it is rejected here — at import —
  /// rather than parked in the library where the only thing tapping it produces
  /// is an error.
  @override
  bool validate() {
    if (address.isEmpty || port <= 0 || !isValidUuid(uuid)) return false;
    if (security.toLowerCase() == 'reality') {
      return publicKey != null && publicKey!.isNotEmpty;
    }
    return true;
  }

  /// vless://UUID@host:port?security=...&sni=...#name
  static VlessConfig? fromUri(String uri, {String? customName}) {
    try {
      uri = ConfigParser.normalizeScheme(uri.trim());
      if (!uri.startsWith('vless://')) return null;
      final u = ConfigParser.tryParseUri(uri);
      if (u == null) return null;
      final uuid = u.userInfo;
      final host = u.host;
      final port = u.port;
      final params = u.queryParameters;
      String name = customName ?? 'VLESS ($host:$port)';
      if (customName == null && u.fragment.isNotEmpty) {
        name = ConfigParser.safeFragment(uri, fallback: name);
      }

      // `type` is the Xray share-link spelling. Both `xhttp` and `splithttp`
      // appear in the wild; the bundled core registers the transport under
      // **`splithttp` only** — a byte scan of libgojni.so finds `splithttp`
      // 14 times and the literal `xhttp` never (only the settings key
      // `xhttpSettings`, which is a different thing). Emitting
      // `network: "xhttp"` therefore names a transport the core cannot
      // resolve, so both spellings are normalised to `splithttp`.
      var network = params['type'] ?? 'tcp';
      if (network == 'xhttp') network = 'splithttp';

      // Every spelling the shared helper understands: insecure, allow_insecure,
      // allowInsecure. Reading only `insecure` kept certificate verification
      // on for links that asked to skip it.
      final insecureRaw = (params['insecure'] ??
              params['allow_insecure'] ??
              params['allowInsecure'] ??
              '')
          .toLowerCase();

      return VlessConfig(
        name: name, rawUri: uri, uuid: uuid, address: host, port: port,
        security: params['security'] ?? 'none',
        flow: params['flow'],
        sni: params['sni'],
        fingerprint: params['fp'],
        publicKey: params['pbk'] ?? params['publicKey'],
        shortId: params['sid'] ?? params['shortId'],
        pbk: params['pbk'],
        network: network,
        path: params['path'],
        host: params['host'],
        serviceName: params['serviceName'],
        spiderX: params['spx'] ?? params['spiderX'],
        xhttpMode: params['mode'],
        alpn: params['alpn'],
        allowInsecure: insecureRaw == '1' || insecureRaw == 'true' || insecureRaw == 'yes',
        // mKCP/QUIC disguise and encryption, plus the http header type. Read
        // under both the `headerType` and `header` spellings, which is what
        // different client generators emit.
        headerType: params['headerType'] ?? params['header'],
        kcpSeed: params['seed'],
        quicSecurity: params['quicSecurity'] ?? params['security'],
        quicKey: params['key'],
      );
    } catch (_) { return null; }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// VMESS config  (xray engine — vmess://base64json)
// ─────────────────────────────────────────────────────────────────────────────
class VmessConfig extends Config {
  final String name;
  final String rawUri;
  final String uuid;
  final String address;
  final int port;
  final String alterId;
  final String cipher;
  final String network;
  final String? tls;
  final String? sni;
  final String? path;
  final String? host;
  /// gRPC service name. The vmess share format carries it in `path`, so it
  /// was being written to wsSettings and never reached grpcSettings - every
  /// vmess-over-gRPC config dialled an empty service name.
  final String? serviceName;

  /// TLS material carried by the share JSON: many vmess servers use
  /// self-signed certificates, and links asking to skip verification used to
  /// connect with certificate validation ON and fail the handshake.
  final bool allowInsecure;
  final String? fingerprint;
  final String? alpn;

  VmessConfig({
    required this.name, required this.rawUri, required this.uuid,
    required this.address, required this.port,
    this.alterId = '0', this.cipher = 'auto', this.network = 'tcp',
    this.tls, this.sni, this.path, this.host, this.serviceName,
    this.allowInsecure = false, this.fingerprint, this.alpn,
  });

  @override String get protocol => 'vmess';
  @override String get displayName => name;
  @override Future<bool> connect() async => true;
  @override Future<void> disconnect() async {}
  @override Future<bool> isRunning() async => false;
  @override bool validate() =>
      address.isNotEmpty && port > 0 && isValidUuid(uuid);

  /// vmess://BASE64(JSON)
  static VmessConfig? fromUri(String uri, {String? customName}) {
    try {
      uri = ConfigParser.normalizeScheme(uri.trim());
      if (!uri.startsWith('vmess://')) return null;
      final encoded = uri.substring(8).trim().split('#')[0];
      final normalized = base64.normalize(encoded);
      final decoded = utf8.decode(base64.decode(normalized));
      final json = jsonDecode(decoded) as Map<String, dynamic>;
      final host = json['add']?.toString() ?? '';
      final port = int.tryParse(json['port']?.toString() ?? '443') ?? 443;
      final name = customName ?? json['ps']?.toString() ?? 'VMess ($host:$port)';
      // `allowInsecure` arrives as a bool, a number or a string depending on
      // the generating client; accept all three.
      final insecureRaw = json['allowInsecure'] ?? json['insecure'];
      final insecure = insecureRaw == true ||
          insecureRaw == 1 ||
          insecureRaw.toString().toLowerCase() == 'true' ||
          insecureRaw.toString() == '1';
      // `alpn` may be a comma-separated string or an array.
      final alpnRaw = json['alpn'];
      final alpn = switch (alpnRaw) {
        final List list => list.map((e) => e.toString()).join(','),
        final String s => s,
        _ => null,
      };
      return VmessConfig(
        name: name, rawUri: uri,
        uuid: json['id']?.toString() ?? '',
        address: host, port: port,
        alterId: json['aid']?.toString() ?? '0',
        cipher: json['scy']?.toString() ?? 'auto',
        network: json['net']?.toString() ?? 'tcp',
        tls: json['tls']?.toString(),
        sni: json['sni']?.toString(),
        path: json['path']?.toString(),
        host: json['host']?.toString(),
        // For gRPC the share link puts the service name in `path`.
        serviceName: (json['net']?.toString() == 'grpc')
            ? json['path']?.toString()
            : json['serviceName']?.toString(),
        allowInsecure: insecure,
        fingerprint: json['fp']?.toString(),
        alpn: (alpn == null || alpn.isEmpty) ? null : alpn,
      );
    } catch (_) { return null; }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TROJAN config  (xray engine — trojan://password@host:port?sni=...)
// ─────────────────────────────────────────────────────────────────────────────
class TrojanConfig extends Config {
  final String name;
  final String rawUri;
  final String password;
  final String address;
  final int port;
  final String? sni;
  final bool allowInsecure;
  final String? fingerprint;
  final String? network;
  final String? path;   // Trojan over WebSocket path
  final String? host;   // Trojan over WebSocket Host header
  final String? alpn;

  /// gRPC service name. Trojan share links put it in `path` (the same
  /// convention the vmess JSON uses), so without this field every
  /// trojan-over-gRPC config dialled an empty service name.
  final String? serviceName;

  TrojanConfig({
    required this.name, required this.rawUri, required this.password,
    required this.address, required this.port,
    this.sni, this.allowInsecure = false, this.fingerprint, this.network,
    this.path, this.host, this.alpn, this.serviceName,
  });

  @override String get protocol => 'trojan';
  @override String get displayName => name;
  @override Future<bool> connect() async => true;
  @override Future<void> disconnect() async {}
  @override Future<bool> isRunning() async => false;
  @override bool validate() => address.isNotEmpty && port > 0 && password.isNotEmpty;

  /// trojan://password@host:port?sni=...#name
  static TrojanConfig? fromUri(String uri, {String? customName}) {
    try {
      uri = ConfigParser.normalizeScheme(uri.trim());
      if (!uri.startsWith('trojan://')) return null;
      final u = ConfigParser.tryParseUri(uri);
      if (u == null) return null;
      String name = customName ?? 'Trojan (${u.host}:${u.port})';
      if (customName == null && u.fragment.isNotEmpty) {
        name = ConfigParser.safeFragment(uri, fallback: name);
      }
      var network = u.queryParameters['type'] ?? 'tcp';
      // See the note in [VlessConfig.fromUri]: the bundled core knows this
      // transport as `splithttp`, not `xhttp`.
      if (network == 'xhttp') network = 'splithttp';
      // `Uri.userInfo` is still percent-encoded; a password containing `@` or
      // `:` only matched the server after decoding.
      String decodedPassword;
      try {
        decodedPassword = Uri.decodeComponent(u.userInfo);
      } catch (_) {
        decodedPassword = u.userInfo;
      }
      // Same helper every other protocol uses; Trojan had its own third
      // spelling of this check and missed `allow_insecure`.
      final insecureFlag = ConfigParser._insecure(u.queryParameters);

      return TrojanConfig(
        name: name, rawUri: uri,
        password: decodedPassword,
        address: u.host, port: u.port,
        sni: u.queryParameters['sni'],
        // The helper already returns a bool. Comparing it to the strings it
        // replaced (`insecureFlag == '1'`) compiles - `==` takes any Object -
        // but is always false, which would have quietly disabled the flag.
        allowInsecure: insecureFlag,
        fingerprint: u.queryParameters['fp'],
        network: network,
        path: u.queryParameters['path'],
        host: u.queryParameters['host'],
        alpn: u.queryParameters['alpn'],
        // Over gRPC the service name rides in `path` (v2rayN convention);
        // an explicit `serviceName` parameter wins when a generator emits one.
        serviceName: network == 'grpc'
            ? (u.queryParameters['serviceName'] ?? u.queryParameters['path'])
            : u.queryParameters['serviceName'],
      );
    } catch (_) { return null; }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// HYSTERIA2 config  (singbox engine — hy2://password@host:port?...)
// ─────────────────────────────────────────────────────────────────────────────
class Hysteria2Config extends Config {
  final String name;
  final String rawUri;
  final String password;
  final String address;
  final int port;
  final String? sni;
  final bool insecure;
  final int? upMbps;
  final int? downMbps;
  final String? obfs;
  final String? obfsPassword;

  Hysteria2Config({
    required this.name, required this.rawUri, required this.password,
    required this.address, required this.port,
    this.sni, this.insecure = false, this.upMbps, this.downMbps,
    this.obfs, this.obfsPassword,
  });

  @override String get protocol => 'hysteria2';
  @override String get displayName => name;
  @override Future<bool> connect() async => true;
  @override Future<void> disconnect() async {}
  @override Future<bool> isRunning() async => false;
  @override bool validate() => address.isNotEmpty && port > 0 && password.isNotEmpty;

  /// hy2://password@host:port?sni=...&insecure=1
  static Hysteria2Config? fromUri(String uri, {String? customName}) {
    try {
      uri = ConfigParser.normalizeScheme(uri.trim());
      if (!uri.startsWith('hy2://') && !uri.startsWith('hysteria2://') && !uri.startsWith('hysteria://')) return null;
      final u = ConfigParser.tryParseUri(uri);
      if (u == null) return null;
      String name = customName ?? 'Hysteria2 (${u.host}:${u.port})';
      if (customName == null && u.fragment.isNotEmpty) {
        name = ConfigParser.safeFragment(uri, fallback: name);
      }
      return Hysteria2Config(
        name: name, rawUri: uri,
        // `userInfo` is still percent-encoded: a password written as
        // p%40ss must reach the engine as p@ss, or authentication
        // fails on every server whose password has a reserved char.
        password: ConfigParser._decodeUserInfo(u.userInfo),
        address: u.host, port: u.port,
        sni: u.queryParameters['sni'],
        insecure: ConfigParser._insecure(u.queryParameters),
        upMbps: int.tryParse(u.queryParameters['up'] ?? ''),
        downMbps: int.tryParse(u.queryParameters['down'] ?? ''),
        obfs: u.queryParameters['obfs'],
        obfsPassword: u.queryParameters['obfs-password'],
      );
    } catch (_) { return null; }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TUIC v5 config  (singbox engine — tuic://uuid:password@host:port?...)
// ─────────────────────────────────────────────────────────────────────────────
class TuicConfig extends Config {
  final String name;
  final String rawUri;
  final String uuid;
  final String password;
  final String address;
  final int port;
  final String? sni;
  final bool insecure;
  final String? alpn;
  final String? congestionControl;

  TuicConfig({
    required this.name, required this.rawUri, required this.uuid,
    required this.password, required this.address, required this.port,
    this.sni, this.insecure = false, this.alpn, this.congestionControl,
  });

  @override String get protocol => 'tuic';
  @override String get displayName => name;
  @override Future<bool> connect() async => true;
  @override Future<void> disconnect() async {}
  @override Future<bool> isRunning() async => false;
  @override bool validate() =>
      address.isNotEmpty && port > 0 && isValidUuid(uuid);

  /// tuic://uuid:password@host:port?sni=...
  static TuicConfig? fromUri(String uri, {String? customName}) {
    try {
      uri = ConfigParser.normalizeScheme(uri.trim());
      if (!uri.startsWith('tuic://')) return null;
      final u = ConfigParser.tryParseUri(uri);
      if (u == null) return null;
      // Split BEFORE decoding: a password may legitimately contain an encoded
      // colon (%3A), which must not be treated as the uuid separator, and
      // decoding first would turn it into a real colon.
      final userInfo = u.userInfo.split(':');
      final uuid = userInfo.isNotEmpty
          ? ConfigParser._decodeUserInfo(userInfo[0])
          : '';
      final pwd = userInfo.length > 1
          ? ConfigParser._decodeUserInfo(userInfo.sublist(1).join(':'))
          : '';
      String name = customName ?? 'TUIC (${u.host}:${u.port})';
      if (customName == null && u.fragment.isNotEmpty) {
        name = ConfigParser.safeFragment(uri, fallback: name);
      }
      return TuicConfig(
        name: name, rawUri: uri, uuid: uuid, password: pwd,
        address: u.host, port: u.port,
        sni: u.queryParameters['sni'],
        insecure: ConfigParser._insecure(u.queryParameters),
        alpn: u.queryParameters['alpn'],
        congestionControl: u.queryParameters['congestion_control'] ?? 'bbr',
      );
    } catch (_) { return null; }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// AMNEZIAWG config  (amnezia-wireguard engine — AWG .conf file content)
// ─────────────────────────────────────────────────────────────────────────────
class AmneziaWGConfig extends Config {
  final String name;
  final String rawUri;
  final String address;
  final int port;
  final String endpoint;
  final String privateKey;
  final String publicKey;
  final String? presharedKey;
  final String? dns;
  final int junkCount;
  final int junkMin;
  final int junkMax;

  /// The tunnel's own address from [Interface] Address.
  ///
  /// Distinct from [address], which is the server host. These used to be the
  /// same field: the endpoint host overwrote the interface address, and the
  /// builder then hard-coded 10.0.0.2/32 - so any server whose inner subnet
  /// was not 10.0.0.x dropped every packet.
  final List<String> localAddresses;
  final int? mtu;

  /// AmneziaWG obfuscation parameters. Parsing only Jc/Jmin/Jmax meant a
  /// server configured with magic headers or padding saw a vanilla handshake.
  final int? s1;
  final int? s2;
  final int? h1;
  final int? h2;
  final int? h3;
  final int? h4;

  AmneziaWGConfig({
    required this.name, required this.rawUri, required this.address,
    required this.port, required this.endpoint,
    required this.privateKey, required this.publicKey,
    this.presharedKey, this.dns,
    this.junkCount = 4, this.junkMin = 40, this.junkMax = 70,
    this.localAddresses = const [], this.mtu,
    this.s1, this.s2, this.h1, this.h2, this.h3, this.h4,
  });

  @override String get protocol => 'amneziawg';
  @override String get displayName => name;
  @override Future<bool> connect() async => true;
  @override Future<void> disconnect() async {}
  @override Future<bool> isRunning() async => false;
  @override bool validate() => endpoint.isNotEmpty && privateKey.isNotEmpty;

  static AmneziaWGConfig? fromUri(String content, {String? customName}) {
    try {
      if (!content.contains('[Interface]') && !content.contains('Jc =') && !content.contains('JC =')) return null;
      String privateKey = '', publicKey = '', endpoint = '', address = '', dns = '';
      String psk = '';
      int port = 51820, jc = 4, jmin = 40, jmax = 70;
      int? mtu, s1, s2, h1, h2, h3, h4;
      for (final line in content.split('\n')) {
        final t = line.trim();
        if (!t.contains('=')) continue;
        final idx = t.indexOf('=');
        final k = t.substring(0, idx).trim().toLowerCase();
        final v = t.substring(idx + 1).trim();
        if (k == 'privatekey') privateKey = v;
        if (k == 'publickey') publicKey = v;
        if (k == 'address') address = v;
        if (k == 'dns') dns = v;
        if (k == 'endpoint') {
          endpoint = v;
          final parsedEndpoint = _splitHostPort(v);
          port = parsedEndpoint?.$2 ?? 51820;
        }
        if (k == 'jc') jc = int.tryParse(v) ?? 4;
        if (k == 'jmin') jmin = int.tryParse(v) ?? 40;
        if (k == 'jmax') jmax = int.tryParse(v) ?? 70;
        if (k == 'presharedkey') psk = v;
        if (k == 'mtu') mtu = int.tryParse(v);
        // AmneziaWG obfuscation: the padding sizes and the magic headers.
        if (k == 's1') s1 = int.tryParse(v);
        if (k == 's2') s2 = int.tryParse(v);
        if (k == 'h1') h1 = int.tryParse(v);
        if (k == 'h2') h2 = int.tryParse(v);
        if (k == 'h3') h3 = int.tryParse(v);
        if (k == 'h4') h4 = int.tryParse(v);
      }
      final host = endpoint.isNotEmpty
          ? (_splitHostPort(endpoint)?.$1 ?? endpoint)
          : address.split('/')[0].split(',')[0];
      return AmneziaWGConfig(
        name: customName ?? 'AmneziaWG ($host:$port)',
        rawUri: content, address: host, port: port,
        endpoint: endpoint, privateKey: privateKey, publicKey: publicKey,
        presharedKey: psk.isEmpty ? null : psk,
        dns: dns, junkCount: jc, junkMin: jmin, junkMax: jmax,
        // Keep the interface address instead of discarding it.
        localAddresses: address
            .split(',')
            .map((a) => a.trim())
            .where((a) => a.isNotEmpty)
            .toList(),
        mtu: mtu, s1: s1, s2: s2, h1: h1, h2: h2, h3: h3, h4: h4,
      );
    } catch (_) { return null; }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// WARP config  (Cloudflare WARP — no URI standard, uses account key pair)
// ─────────────────────────────────────────────────────────────────────────────
class WarpConfig extends Config {
  final String name;
  final String rawUri;
  final String privateKey;
  final String accountId;
  final String? endpoint;

  WarpConfig({
    required this.name, required this.rawUri,
    required this.privateKey, required this.accountId,
    this.endpoint,
  });

  @override String get protocol => 'warp';
  @override String get displayName => name;
  @override String get address => (endpoint ?? '162.159.193.1').split(':')[0];
  @override int get port => int.tryParse((endpoint ?? '162.159.193.1:2408').split(':').last) ?? 2408;
  @override Future<bool> connect() async => true;
  @override Future<void> disconnect() async {}
  @override Future<bool> isRunning() async => false;
  @override bool validate() => privateKey.isNotEmpty || accountId.isNotEmpty;

  /// Refuses to fabricate a config.
  ///
  /// WARP is WireGuard underneath, and a real profile — the kind `wgcf`
  /// generates — is a plain `.conf` with an `[Interface]` and a `[Peer]`, so it
  /// is parsed by [WireGuardConfig.fromUri] earlier in [ConfigParser.parse] and
  /// is served by the bundled core's `wireguard` outbound.
  ///
  /// This method used to return a config with an **empty** `privateKey` and an
  /// empty `accountId` for any text that merely contained the word "warp".
  /// That produced a plausible-looking entry in the config list which could
  /// never connect, and which `validate()` only rejected by accident. There is
  /// no WARP registration flow to mint a real key pair, so the honest answer
  /// for non-WireGuard WARP input is "cannot parse".
  static WarpConfig? fromUri(String content, {String? customName}) => null;
}

// ─────────────────────────────────────────────────────────────────────────────
// PSIPHON config  (multi-transport circumvention — no standard URI)
// ─────────────────────────────────────────────────────────────────────────────
class PsiphonConfig extends Config {
  final String name;
  final String rawUri;
  final String? serverAddress;
  final String? configJson;

  PsiphonConfig({
    required this.name, required this.rawUri,
    this.serverAddress, this.configJson,
  });

  @override String get protocol => 'psiphon';
  @override String get displayName => name;
  @override String get address => serverAddress ?? '0.0.0.0';
  @override int get port => 0;
  @override Future<bool> connect() async => true;
  @override Future<void> disconnect() async {}
  @override Future<bool> isRunning() async => false;
  @override bool validate() => true; // Psiphon uses auto-discovery

  static PsiphonConfig? fromUri(String content, {String? customName}) {
    // Must be an actual psiphon link or a psiphon JSON document. The old test
    // was `contains('psiphon') || startsWith('{')`, so any scanned line that
    // merely mentioned psiphon - "psiphon lists: vless://..." - was stored as
    // a Psiphon config, and so was every bare JSON blob of any shape.
    final trimmed = content.trim();
    final lower = trimmed.toLowerCase();
    if (!lower.startsWith('psiphon://') && !lower.startsWith('{')) return null;
    if (lower.startsWith('{')) {
      // A psiphon document carries a region or an embedded server entry.
      if (!lower.contains('"region"') &&
          !lower.contains('"proxiedsites"') &&
          !lower.contains('"localproxyport"')) {
        return null;
      }
    }
    return PsiphonConfig(
      name: customName ?? 'Psiphon',
      rawUri: content,
      configJson: content,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Config parser factory — extended for all 10 engines
// ─────────────────────────────────────────────────────────────────────────────
/// Engine identifier enum (matches Blackout Kit CLI engine names)
enum BlackoutEngine {
  wireguard,
  openvpn,
  shadowsocks,
  vless,       // xray
  vmess,       // xray
  trojan,      // xray
  hysteria2,   // singbox
  tuic,        // singbox
  anytls,      // singbox
  shadowtls,   // singbox
  amneziawg,   // amneziawg
  warp,        // warp
  psiphon,     // psiphon
}

extension BlackoutEngineInfo on BlackoutEngine {
  String get displayName {
    switch (this) {
      case BlackoutEngine.wireguard:  return 'WireGuard';
      case BlackoutEngine.openvpn:    return 'OpenVPN';
      case BlackoutEngine.shadowsocks:return 'Shadowsocks';
      case BlackoutEngine.vless:      return 'VLESS (XRay)';
      case BlackoutEngine.vmess:      return 'VMess (XRay)';
      case BlackoutEngine.trojan:     return 'Trojan (XRay)';
      case BlackoutEngine.hysteria2:  return 'Hysteria2';
      case BlackoutEngine.tuic:       return 'TUIC v5';
      case BlackoutEngine.anytls:     return 'AnyTLS';
      case BlackoutEngine.shadowtls:  return 'ShadowTLS v3';
      case BlackoutEngine.amneziawg:  return 'AmneziaWG';
      case BlackoutEngine.warp:       return 'Cloudflare WARP';
      case BlackoutEngine.psiphon:    return 'Psiphon';
    }
  }

  String get description {
    switch (this) {
      case BlackoutEngine.wireguard:  return 'Fast, modern VPN protocol';
      case BlackoutEngine.openvpn:    return 'Battle-tested, widely supported';
      case BlackoutEngine.shadowsocks:return 'Lightweight SOCKS5 obfuscation proxy';
      case BlackoutEngine.vless:      return 'XRay VLESS with REALITY/TLS transport';
      case BlackoutEngine.vmess:      return 'XRay VMess with configurable transport';
      case BlackoutEngine.trojan:     return 'XRay Trojan masquerades as HTTPS';
      case BlackoutEngine.hysteria2:  return 'Ultra-fast UDP-based censorship bypass';
      case BlackoutEngine.tuic:       return 'QUIC-based low-latency proxy (SingBox)';
      case BlackoutEngine.anytls:     return 'Padding-aware TLS proxy against traffic classification';
      case BlackoutEngine.shadowtls:  return 'Shadows a real TLS site - defeats active probing';
      case BlackoutEngine.amneziawg:  return 'WireGuard + junk packets, DPI-resistant';
      case BlackoutEngine.warp:       return 'Cloudflare WARP free VPN';
      case BlackoutEngine.psiphon:    return 'Multi-transport circumvention (auto)';
    }
  }

  String get iconTag {
    switch (this) {
      case BlackoutEngine.wireguard:   return 'WG';
      case BlackoutEngine.openvpn:     return 'OV';
      case BlackoutEngine.shadowsocks: return 'SS';
      case BlackoutEngine.vless:       return 'VL';
      case BlackoutEngine.vmess:       return 'VM';
      case BlackoutEngine.trojan:      return 'TR';
      case BlackoutEngine.hysteria2:   return 'H2';
      case BlackoutEngine.tuic:        return 'TC';
      case BlackoutEngine.anytls:      return 'AT';
      case BlackoutEngine.shadowtls:   return 'ST';
      case BlackoutEngine.amneziawg:   return 'AW';
      case BlackoutEngine.warp:        return 'WP';
      case BlackoutEngine.psiphon:     return 'PS';
    }
  }

  String get protocolId {
    switch (this) {
      case BlackoutEngine.wireguard:   return 'wireguard';
      case BlackoutEngine.openvpn:     return 'openvpn';
      case BlackoutEngine.shadowsocks: return 'shadowsocks';
      case BlackoutEngine.vless:       return 'vless';
      case BlackoutEngine.vmess:       return 'vmess';
      case BlackoutEngine.trojan:      return 'trojan';
      case BlackoutEngine.hysteria2:   return 'hysteria2';
      case BlackoutEngine.tuic:        return 'tuic';
      case BlackoutEngine.anytls:      return 'anytls';
      case BlackoutEngine.shadowtls:   return 'shadowtls';
      case BlackoutEngine.amneziawg:   return 'amneziawg';
      case BlackoutEngine.warp:        return 'warp';
      case BlackoutEngine.psiphon:     return 'psiphon';
    }
  }
}

/// Config parser factory
class ConfigParser {
  /// Decodes the display name carried after `#` in a share link.
  ///
  /// Subscriptions routinely embed a literal `%` or other invalid percent
  /// sequence in the name (it is just a label). A fragment that cannot be
  /// percent-decoded must not void an otherwise valid config, so a bad one is
  /// returned raw instead of throwing — which previously dropped hundreds of
  /// real shadowsocks links.
  static String safeFragment(String uri, {String fallback = ''}) {
    final h = uri.indexOf('#');
    if (h == -1 || h == uri.length - 1) return fallback;
    final raw = uri.substring(h + 1);
    try {
      return Uri.decodeComponent(raw);
    } on Object {
      return raw;
    }
  }

  /// Parses a share link, tolerating a malformed fragment.
  ///
  /// `Uri.parse` throws on illegal percent-encoding, and the fragment is the
  /// most common offender even though it is cosmetic. Retry without the
  /// fragment before giving up, so a bad name never discards a usable server.
  static Uri? tryParseUri(String uri) {
    try {
      return Uri.parse(uri);
    } on FormatException {
      final h = uri.indexOf('#');
      if (h == -1) return null;
      try {
        return Uri.parse(uri.substring(0, h));
      } on FormatException {
        return null;
      }
    }
  }

  /// Converts an `awg://` link into AmneziaWG conf text.
  ///
  /// Two payload shapes are accepted, mirroring the desktop engine:
  ///   awg://<base64 of the whole .conf>
  ///   awg://?private_key=…&address=…&endpoint=…&public_key=…&jc=…&h1=…
  /// A payload that already looks like conf text (`[Interface]` / `Jc =`) is
  /// returned untouched, so round-tripping a copied conf costs nothing.
  static String awgUriToConf(String uri) {
    final lower = uri.toLowerCase();
    if (!lower.startsWith('awg://') && !lower.startsWith('amneziawg://')) {
      return uri;
    }
    final body = uri.substring(uri.indexOf('://') + 3);

    if (body.startsWith('?')) {
      final q = Uri.splitQueryString(body);
      final lines = <String>['[Interface]'];
      void add(String confKey, List<String> queryKeys) {
        for (final k in queryKeys) {
          final v = q[k];
          if (v != null && v.isNotEmpty) {
            lines.add('$confKey = $v');
            return;
          }
        }
      }
      add('PrivateKey', ['private_key', 'privatekey', 'private']);
      add('Address', ['address', 'addresses', 'addr']);
      add('DNS', ['dns']);
      add('MTU', ['mtu']);
      for (final obf in ['Jc', 'Jmin', 'Jmax', 'S1', 'S2', 'S3', 'S4',
                         'H1', 'H2', 'H3', 'H4', 'I1', 'I2', 'I3', 'I4', 'I5']) {
        add(obf, [obf.toLowerCase(), obf.toLowerCase().replaceAll('m', 'M')]);
      }
      lines.add('');
      lines.add('[Peer]');
      add('PublicKey', ['public_key', 'publickey', 'public']);
      add('PresharedKey', ['preshared_key', 'presharedkey']);
      add('Endpoint', ['endpoint', 'server', 'host']);
      add('AllowedIPs', ['allowed_ips', 'allowedips']);
      add('PersistentKeepalive', ['persistentkeepalive', 'keepalive']);
      return '${lines.join('\n')}\n';
    }

    // Base64 payload — try standard and url-safe, padding optional.
    if (body.contains('[Interface]') || body.contains('Jc =') || body.contains('JC =')) {
      return body;
    }
    final cleaned = body.replaceAll(RegExp(r'\s+'), '');
    for (final padded in [cleaned, cleaned + '=' * ((4 - cleaned.length % 4) % 4)]) {
      try {
        final decoded = utf8.decode(base64.decode(base64.normalize(padded)));
        if (decoded.contains('[Interface]') || decoded.contains('Jc =') || decoded.contains('JC =')) {
          return decoded;
        }
      } catch (_) {}
    }
    return body;
  }

  /// The "accept any certificate" flag, spelled inconsistently across clients:
  /// `insecure=1` (sing-box), `allow_insecure=1` (SIP002/v2rayNG), `allowInsecure=1`
  /// (v2rayNG JSON-style links). A link using a spelling this parser did not know
  /// silently connected with certificate validation ON, which fails against the
  /// self-signed certs most servers actually use.
  /// Percent-decodes a URI user-info segment.
  ///
  /// Trojan decoded its password and every other protocol did not, so a
  /// password containing @, :, %, + or / was sent literally and the server
  /// rejected it. One helper, used by all of them.
  static String _decodeUserInfo(String raw) {
    try {
      return Uri.decodeComponent(raw);
    } catch (_) {
      // A malformed escape is not worth losing the credential over.
      return raw;
    }
  }

  static bool _insecure(Map<String, String> q) {
    final v = q['insecure'] ?? q['allow_insecure'] ?? q['allowInsecure'];
    if (v == null) return false;
    final low = v.toLowerCase();
    return low == '1' || low == 'true' || low == 'yes';
  }

  static Config? parse(String text, {String? customName}) {
    try {
      // Normalise the scheme before dispatching: the guards below are
      // case-sensitive, so a list that spells `VMESS://` or `Vless://` — which
      // community config lists do — used to be dropped silently. Only the
      // scheme is touched; credentials and base64 payloads stay byte-identical.
      final trimmed = ConfigParser.normalizeScheme(text.trim());
      // URI-based single-line protocols
      if (trimmed.startsWith('vless://'))       return VlessConfig.fromUri(trimmed, customName: customName);
      if (trimmed.startsWith('vmess://'))       return VmessConfig.fromUri(trimmed, customName: customName);
      if (trimmed.startsWith('trojan://'))      return TrojanConfig.fromUri(trimmed, customName: customName);
      if (trimmed.startsWith('hy2://') || trimmed.startsWith('hysteria2://') || trimmed.startsWith('hysteria://'))
                                                return Hysteria2Config.fromUri(trimmed, customName: customName);
      if (trimmed.startsWith('tuic://'))        return TuicConfig.fromUri(trimmed, customName: customName);
      if (trimmed.startsWith('anytls://'))      return AnyTlsConfig.fromUri(trimmed, customName: customName);
      if (trimmed.startsWith('shadowtls://'))   return ShadowTlsConfig.fromUri(trimmed, customName: customName);
      if (trimmed.startsWith('ss://'))          return ShadowsocksConfig.fromUri(trimmed, customName: customName);
      if (trimmed.startsWith('awg://') || trimmed.startsWith('amneziawg://'))
                                                return AmneziaWGConfig.fromUri(awgUriToConf(trimmed), customName: customName);
      // File/block content protocols. A bare substring match meant any text
      // whose comment mentioned "remote " (e.g. "# remote server is in DE")
      // was classified as OpenVPN. Require a real directive at line start.
      if (_hasOpenVpnDirective(trimmed) || trimmed.contains('BEGIN CERTIFICATE'))
                                                return OpenVpnConfig.fromUri(trimmed, customName: customName);
      // Case-insensitive: `jc = 5` is as valid as `Jc = 5`, and the old
      // case-sensitive test sent every lowercase conf to plain WireGuard,
      // where the obfuscation parameters were dropped.
      if (_looksLikeAmnezia(trimmed))
                                                return AmneziaWGConfig.fromUri(trimmed, customName: customName);
      if (trimmed.contains('[Interface]') || trimmed.contains('PrivateKey'))
                                                return WireGuardConfig.fromUri(trimmed, customName: customName);
      // A psiphon document is JSON and does not have to contain the word
      // "psiphon"; a link does. Both are handled by the parser's own checks.
      if (trimmed.toLowerCase().contains('psiphon') || trimmed.startsWith('{'))
                                                return PsiphonConfig.fromUri(trimmed, customName: customName);
      if (trimmed.toLowerCase().contains('warp'))
                                                return WarpConfig.fromUri(trimmed, customName: customName);
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Parse all configs from multi-line text, Base64 subscriptions, or embedded markdown
  /// Lower-cases ONLY the URI scheme, leaving everything after `://` exactly
  /// as it was.
  ///
  /// Share links are dispatched with case-sensitive `startsWith` guards, so an
  /// uppercase or mixed-case scheme (`VLESS://`, `Vmess://`, `SS://`) failed
  /// every guard and the line was silently discarded. Lower-casing the whole
  /// URI would be wrong: UUIDs, passwords and base64 payloads are
  /// case-sensitive.
  static String normalizeScheme(String uri) {
    final separator = uri.indexOf('://');
    if (separator <= 0) return uri;
    final scheme = uri.substring(0, separator);
    // Only a real scheme may be lower-cased. A whole .conf file that happens
    // to mention a URL has its separator far into the text, and the "scheme"
    // is then every line before it - including `PrivateKey = AbC...`, whose
    // case is significant. Lower-casing that corrupted the key.
    if (!RegExp(r'^[A-Za-z][A-Za-z0-9+.\-]*$').hasMatch(scheme)) return uri;
    if (scheme == scheme.toLowerCase()) return uri;
    return scheme.toLowerCase() + uri.substring(separator);
  }

  /// True when a block contains an OpenVPN directive at line start (not in a
  /// comment). Used to classify pasted .ovpn content without matching prose.
  /// True when a block carries AmneziaWG's obfuscation parameters.
  ///
  /// Case-insensitive, and keyed on the parameters that only AWG has - Jc
  /// alone is enough, since vanilla WireGuard defines no such key.
  static bool _looksLikeAmnezia(String content) {
    final lower = content.toLowerCase();
    if (lower.contains('junk_count')) return true;
    for (final key in const ['jc', 'jmin', 'jmax', 's1', 's2', 'h1', 'h2', 'h3', 'h4']) {
      // Match `key = value` at the start of a line, ignoring leading spaces.
      if (RegExp('^\\s*${key}\\s*=', multiLine: true, caseSensitive: false)
          .hasMatch(content)) {
        return true;
      }
    }
    return false;
  }

  static bool _hasOpenVpnDirective(String content) {
    for (final rawLine in content.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#') || line.startsWith(';')) continue;
      for (final directive in const ['remote ', 'client', 'dev tun', 'proto ']) {
        if (line == directive.trim() || line.startsWith(directive)) return true;
      }
    }
    return false;
  }

  static List<Config> parseMultiple(String text) {
    if (text.trim().isEmpty) return [];

    var rawText = text.trim();

    // 0. Subscriptions wrapped by a client: sub://BASE64 / subscription://BASE64.
    //    These contain `://` after de-framing, so the whole-payload base64
    //    probe below would skip them.
    final lowerRaw = rawText.toLowerCase();
    for (final prefix in ['sub://', 'subscription://']) {
      if (lowerRaw.startsWith(prefix)) {
        try {
          final decoded = utf8.decode(base64.decode(base64.normalize(
              rawText.substring(prefix.length).replaceAll(RegExp(r'\s+'), ''))));
          if (decoded.trim().isNotEmpty) rawText = decoded.trim();
        } catch (_) {}
        break;
      }
    }

    // 0b. A JSON array of share links — some subscription tools emit this
    //     from a QR code instead of newline-separated text.
    if (rawText.startsWith('[')) {
      try {
        final data = jsonDecode(rawText);
        if (data is List) {
          final list = <Config>[];
          final seen = <String>{};
          for (final entry in data) {
            if (entry is! String) continue;
            final c = parse(entry.trim());
            if (c != null && c.validate() && seen.add(c.rawUri)) list.add(c);
          }
          return list;
        }
      } catch (_) {}
    }

    // 1. Check if the entire payload is a Base64-encoded subscription
    if (!rawText.contains('://') &&
        !rawText.contains('[Interface]') &&
        !rawText.contains('remote ') &&
        !rawText.contains('BEGIN CERTIFICATE')) {
      try {
        final cleanBase64 = rawText.replaceAll(RegExp(r'\s+'), '');
        final normalized = base64.normalize(cleanBase64);
        final decoded = utf8.decode(base64.decode(normalized));
        if (decoded.contains('://') ||
            decoded.contains('[Interface]') ||
            decoded.contains('remote ') ||
            decoded.contains('BEGIN CERTIFICATE')) {
          rawText = decoded;
        }
      } catch (_) {}
    }

    final list = <Config>[];
    final seenUris = <String>{};

    void addIfValid(Config? c) {
      if (c != null && c.validate() && !seenUris.contains(c.rawUri)) {
        seenUris.add(c.rawUri);
        list.add(c);
      }
    }

    final lines = rawText.split(RegExp(r'[\r\n]+'));
    final buffer = StringBuffer();

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#') || trimmed.startsWith('//')) {
        continue;
      }

      // Direct single line parse
      final single = parse(trimmed);
      if (single != null && trimmed.contains('://')) {
        addIfValid(single);
        continue;
      }

      // Single line base64 URI check
      if (!trimmed.contains('://') && trimmed.length > 20) {
        try {
          final normalized = base64.normalize(trimmed);
          final decoded = utf8.decode(base64.decode(normalized));
          final decodedParsed = parse(decoded);
          if (decodedParsed != null) {
            addIfValid(decodedParsed);
            continue;
          }
        } catch (_) {}
      }

      // Extract embedded URIs from markdown tables, bullet points, or HTML
      // caseSensitive: false so `VLESS://` in a markdown table is found, and the
      // character class keeps `]` so a bracketed IPv6 authority
      // (`vless://id@[2001:db8::1]:443`) is not truncated at the bracket.
      final uriRegex = RegExp(
        r'(vless|vmess|trojan|ss|hy2|hysteria2|hysteria|tuic|awg|amneziawg|anytls|shadowtls)://[^\s<>"|]+',
        caseSensitive: false,
      );
      final matches = uriRegex.allMatches(trimmed);
      if (matches.isNotEmpty) {
        for (final match in matches) {
          final matchedUri = match.group(0);
          if (matchedUri != null) {
            final parsedMatched = parse(matchedUri);
            if (parsedMatched != null) {
              addIfValid(parsedMatched);
            }
          }
        }
      } else {
        buffer.writeln(line);
      }
    }

    final blockText = buffer.toString();
    if (blockText.contains('[Interface]')) {
      final blocks = blockText.split(RegExp(r'(?=\[Interface\])', caseSensitive: false));
      for (final block in blocks) {
        final text = block.trim();
        if (!text.contains('[Interface]')) continue;
        // Classify the block instead of assuming WireGuard: this hard-coded
        // WireGuardConfig.fromUri, so an AmneziaWG conf imported as part of a
        // bundle silently lost Jc/Jmin/Jmax and became a vanilla tunnel.
        if (_looksLikeAmnezia(text)) {
          addIfValid(AmneziaWGConfig.fromUri(text));
        } else {
          addIfValid(WireGuardConfig.fromUri(text));
        }
      }
    } else if (blockText.contains('remote ') || blockText.contains('BEGIN CERTIFICATE')) {
      final ovpn = OpenVpnConfig.fromUri(blockText);
      addIfValid(ovpn);
    }

    return list;
  }
}
