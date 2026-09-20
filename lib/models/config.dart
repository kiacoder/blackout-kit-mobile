/// VPN Config model replicating Blackout Kit CLI's ProxyConfig dataclass.
/// Supports: WireGuard, OpenVPN, Shadowsocks protocols.
/// V2 extensibility: Add V2Ray, Trojan, NaïveProxy subclasses without UI changes.

import 'dart:convert';
import 'package:crypto/crypto.dart';

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
  if (parts.length >= 2) {
    final port = int.tryParse(parts.last);
    // A bare IPv6 literal splits into many non-numeric parts; only treat the
    // tail as a port when it actually parses as one.
    if (port != null) {
      return (parts.sublist(0, parts.length - 1).join(':'), port);
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
      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.startsWith('remote ')) {
          final parts = trimmed.split(RegExp(r'\s+'));
          if (parts.length >= 2) remoteHost = parts[1];
          if (parts.length >= 3) remotePort = int.tryParse(parts[2]) ?? 1194;
          break;
        }
      }

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
      if (!uri.startsWith('ss://')) return null;

      String nameFromHash = customName ?? '';
      String cleanUri = uri.substring(5);

      final hashIndex = cleanUri.indexOf('#');
      if (hashIndex != -1) {
        if (nameFromHash.isEmpty) {
          nameFromHash = Uri.decodeComponent(cleanUri.substring(hashIndex + 1));
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
      final serverPart = cleanUri.substring(atIndex + 1);

      final credParts = creds.split(':');
      if (credParts.length < 2) return null;

      final method = credParts[0];
      final password = credParts.sublist(1).join(':');

      final colonIndex = serverPart.lastIndexOf(':');
      if (colonIndex == -1) return null;

      final address = serverPart.substring(0, colonIndex);
      final portStr = serverPart.substring(colonIndex + 1);
      final port = int.tryParse(portStr) ?? 8388;

      return ShadowsocksConfig(
        name: nameFromHash.isNotEmpty ? nameFromHash : 'Shadowsocks ($address:$port)',
        rawUri: uri,
        address: address,
        port: port,
        method: method,
        password: password,
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

  VlessConfig({
    required this.name, required this.rawUri, required this.uuid,
    required this.address, required this.port,
    this.security = 'none', this.flow, this.sni, this.fingerprint,
    this.publicKey, this.shortId, this.pbk, this.network,
    this.path, this.host, this.serviceName, this.spiderX, this.xhttpMode,
    this.alpn, this.allowInsecure = false,
  });

  @override String get protocol => 'vless';
  @override String get displayName => name;
  @override Future<bool> connect() async => true;
  @override Future<void> disconnect() async {}
  @override Future<bool> isRunning() async => false;
  @override bool validate() => address.isNotEmpty && port > 0 && uuid.isNotEmpty;

  /// vless://UUID@host:port?security=...&sni=...#name
  static VlessConfig? fromUri(String uri, {String? customName}) {
    try {
      if (!uri.startsWith('vless://')) return null;
      final u = Uri.parse(uri);
      final uuid = u.userInfo;
      final host = u.host;
      final port = u.port;
      final params = u.queryParameters;
      final name = customName ?? Uri.decodeComponent(u.fragment.isNotEmpty ? u.fragment : 'VLESS ($host:$port)');

      // `type` is the Xray share-link spelling. Both `xhttp` and `splithttp`
      // appear in the wild; the bundled core registers the transport under
      // **`splithttp` only** — a byte scan of libgojni.so finds `splithttp`
      // 14 times and the literal `xhttp` never (only the settings key
      // `xhttpSettings`, which is a different thing). Emitting
      // `network: "xhttp"` therefore names a transport the core cannot
      // resolve, so both spellings are normalised to `splithttp`.
      var network = params['type'] ?? 'tcp';
      if (network == 'xhttp') network = 'splithttp';

      final insecureRaw = (params['insecure'] ?? '').toLowerCase();

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

  VmessConfig({
    required this.name, required this.rawUri, required this.uuid,
    required this.address, required this.port,
    this.alterId = '0', this.cipher = 'auto', this.network = 'tcp',
    this.tls, this.sni, this.path, this.host,
  });

  @override String get protocol => 'vmess';
  @override String get displayName => name;
  @override Future<bool> connect() async => true;
  @override Future<void> disconnect() async {}
  @override Future<bool> isRunning() async => false;
  @override bool validate() => address.isNotEmpty && port > 0 && uuid.isNotEmpty;

  /// vmess://BASE64(JSON)
  static VmessConfig? fromUri(String uri, {String? customName}) {
    try {
      if (!uri.startsWith('vmess://')) return null;
      final encoded = uri.substring(8).trim().split('#')[0];
      final normalized = base64.normalize(encoded);
      final decoded = utf8.decode(base64.decode(normalized));
      final json = jsonDecode(decoded) as Map<String, dynamic>;
      final host = json['add']?.toString() ?? '';
      final port = int.tryParse(json['port']?.toString() ?? '443') ?? 443;
      final name = customName ?? json['ps']?.toString() ?? 'VMess ($host:$port)';
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

  TrojanConfig({
    required this.name, required this.rawUri, required this.password,
    required this.address, required this.port,
    this.sni, this.allowInsecure = false, this.fingerprint, this.network,
    this.path, this.host, this.alpn,
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
      if (!uri.startsWith('trojan://')) return null;
      final u = Uri.parse(uri);
      final name = customName ?? Uri.decodeComponent(u.fragment.isNotEmpty ? u.fragment : 'Trojan (${u.host}:${u.port})');
      var network = u.queryParameters['type'] ?? 'tcp';
      // See the note in [VlessConfig.fromUri]: the bundled core knows this
      // transport as `splithttp`, not `xhttp`.
      if (network == 'xhttp') network = 'splithttp';
      return TrojanConfig(
        name: name, rawUri: uri,
        password: u.userInfo,
        address: u.host, port: u.port,
        sni: u.queryParameters['sni'],
        allowInsecure: u.queryParameters['allowInsecure'] == '1' ||
            u.queryParameters['insecure'] == '1',
        fingerprint: u.queryParameters['fp'],
        network: network,
        path: u.queryParameters['path'],
        host: u.queryParameters['host'],
        alpn: u.queryParameters['alpn'],
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
      if (!uri.startsWith('hy2://') && !uri.startsWith('hysteria2://')) return null;
      final u = Uri.parse(uri);
      final name = customName ?? Uri.decodeComponent(u.fragment.isNotEmpty ? u.fragment : 'Hysteria2 (${u.host}:${u.port})');
      return Hysteria2Config(
        name: name, rawUri: uri,
        password: u.userInfo,
        address: u.host, port: u.port,
        sni: u.queryParameters['sni'],
        insecure: u.queryParameters['insecure'] == '1',
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
  @override bool validate() => address.isNotEmpty && port > 0 && uuid.isNotEmpty;

  /// tuic://uuid:password@host:port?sni=...
  static TuicConfig? fromUri(String uri, {String? customName}) {
    try {
      if (!uri.startsWith('tuic://')) return null;
      final u = Uri.parse(uri);
      final userInfo = u.userInfo.split(':');
      final uuid = userInfo.isNotEmpty ? userInfo[0] : '';
      final pwd = userInfo.length > 1 ? userInfo.sublist(1).join(':') : '';
      final name = customName ?? Uri.decodeComponent(u.fragment.isNotEmpty ? u.fragment : 'TUIC (${u.host}:${u.port})');
      return TuicConfig(
        name: name, rawUri: uri, uuid: uuid, password: pwd,
        address: u.host, port: u.port,
        sni: u.queryParameters['sni'],
        insecure: u.queryParameters['insecure'] == '1',
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

  AmneziaWGConfig({
    required this.name, required this.rawUri, required this.address,
    required this.port, required this.endpoint,
    required this.privateKey, required this.publicKey,
    this.presharedKey, this.dns,
    this.junkCount = 4, this.junkMin = 40, this.junkMax = 70,
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
      int port = 51820, jc = 4, jmin = 40, jmax = 70;
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
          final parts = v.split(':');
          port = int.tryParse(parts.last) ?? 51820;
        }
        if (k == 'jc') jc = int.tryParse(v) ?? 4;
        if (k == 'jmin') jmin = int.tryParse(v) ?? 40;
        if (k == 'jmax') jmax = int.tryParse(v) ?? 70;
      }
      final host = endpoint.isNotEmpty ? endpoint.split(':')[0] : address.split('/')[0];
      return AmneziaWGConfig(
        name: customName ?? 'AmneziaWG ($host:$port)',
        rawUri: content, address: host, port: port,
        endpoint: endpoint, privateKey: privateKey, publicKey: publicKey,
        dns: dns, junkCount: jc, junkMin: jmin, junkMax: jmax,
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
    if (!content.toLowerCase().contains('psiphon') && !content.startsWith('{')) return null;
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
      case BlackoutEngine.amneziawg:   return 'amneziawg';
      case BlackoutEngine.warp:        return 'warp';
      case BlackoutEngine.psiphon:     return 'psiphon';
    }
  }
}

/// Config parser factory
class ConfigParser {
  static Config? parse(String text, {String? customName}) {
    try {
      final trimmed = text.trim();
      // URI-based single-line protocols
      if (trimmed.startsWith('vless://'))       return VlessConfig.fromUri(trimmed, customName: customName);
      if (trimmed.startsWith('vmess://'))       return VmessConfig.fromUri(trimmed, customName: customName);
      if (trimmed.startsWith('trojan://'))      return TrojanConfig.fromUri(trimmed, customName: customName);
      if (trimmed.startsWith('hy2://') || trimmed.startsWith('hysteria2://'))
                                                return Hysteria2Config.fromUri(trimmed, customName: customName);
      if (trimmed.startsWith('tuic://'))        return TuicConfig.fromUri(trimmed, customName: customName);
      if (trimmed.startsWith('ss://'))          return ShadowsocksConfig.fromUri(trimmed, customName: customName);
      // File/block content protocols
      if (trimmed.contains('remote ') || trimmed.contains('BEGIN CERTIFICATE') || trimmed.contains('client\n'))
                                                return OpenVpnConfig.fromUri(trimmed, customName: customName);
      if (trimmed.contains('Jc =') || trimmed.contains('JC =') || trimmed.contains('junk_count'))
                                                return AmneziaWGConfig.fromUri(trimmed, customName: customName);
      if (trimmed.contains('[Interface]') || trimmed.contains('PrivateKey'))
                                                return WireGuardConfig.fromUri(trimmed, customName: customName);
      if (trimmed.toLowerCase().contains('psiphon'))
                                                return PsiphonConfig.fromUri(trimmed, customName: customName);
      if (trimmed.toLowerCase().contains('warp'))
                                                return WarpConfig.fromUri(trimmed, customName: customName);
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Parse all configs from multi-line text
  static List<Config> parseMultiple(String text) {
    final list = <Config>[];
    final lines = text.split('\n');
    final buffer = StringBuffer();

    for (final line in lines) {
      final trimmed = line.trim();
      final single = parse(trimmed);
      if (single != null && trimmed.contains('://')) {
        list.add(single);
      } else {
        buffer.writeln(line);
      }
    }

    final blockText = buffer.toString();
    if (blockText.contains('[Interface]')) {
      final wg = WireGuardConfig.fromUri(blockText);
      if (wg != null) list.add(wg);
    } else if (blockText.contains('remote ') || blockText.contains('BEGIN CERTIFICATE')) {
      final ovpn = OpenVpnConfig.fromUri(blockText);
      if (ovpn != null) list.add(ovpn);
    }

    return list;
  }
}
