/// Engine capability model.
/// Replicates Blackout Kit CLI's EngineCapability for protocol/platform support.
/// Full 10 engine support: WireGuard, OpenVPN, Shadowsocks, XRay (VLESS/VMess/Trojan),
/// SingBox (Hysteria2/TUIC), AmneziaWG, SNI Spoofer, Cloudflare WARP, Psiphon, MHRV.

enum EngineType {
  wireguard,
  openvpn,
  shadowsocks,
  xray,
  singbox_proxy,
  amneziawg,
  sni,
  warp,
  psiphon,
  mhrv,
}

enum PlatformSupport {
  android,
  ios,
  windows,
  linux,
  both,
  all,
}

class EngineCapability {
  final EngineType engine;
  final String key;
  final String displayName;
  final String description;
  final PlatformSupport platformSupport;
  final List<String> compatibleProtocols;
  final List<String> requirements;
  final bool isEnabled;
  final String? version;
  final String category; // 'Core VPN', 'Proxy Core', 'DPI Obfuscation', 'Relay / Mesh'

  const EngineCapability({
    required this.engine,
    required this.key,
    required this.displayName,
    required this.description,
    required this.platformSupport,
    required this.compatibleProtocols,
    this.requirements = const [],
    this.isEnabled = true,
    this.version,
    this.category = 'Core VPN',
  });

  /// Check if engine supports current platform
  bool supportsPlatform(String platform) {
    if (platformSupport == PlatformSupport.both || platformSupport == PlatformSupport.all) return true;
    if (platformSupport == PlatformSupport.android && platform == 'android') return true;
    if (platformSupport == PlatformSupport.ios && platform == 'ios') return true;
    return false;
  }

  /// Check if engine supports protocol
  bool supportsProtocol(String protocol) =>
    compatibleProtocols.contains(protocol);

  @override
  String toString() =>
    'EngineCapability(key=$key, displayName=$displayName, platforms=$platformSupport)';
}

/// Engine registry for Blackout Kit CLI engine parity.
class EngineRegistry {
  static final Map<String, EngineCapability> _engines = {
    'xray': const EngineCapability(
      engine: EngineType.xray,
      key: 'xray',
      displayName: 'XRay Core',
      description: 'XRay/V2Ray proxy core with REALITY, VLESS, VMess, and Trojan',
      platformSupport: PlatformSupport.all,
      compatibleProtocols: ['vless', 'vmess', 'trojan'],
      requirements: ['Android 6.0+', 'iOS 13.0+'],
      version: '1.8.24',
      category: 'Proxy Core',
    ),
    'singbox_proxy': const EngineCapability(
      engine: EngineType.singbox_proxy,
      key: 'singbox_proxy',
      displayName: 'SingBox Core',
      description: 'Ultra-fast QUIC & UDP proxy core supporting Hysteria2 and TUIC v5',
      platformSupport: PlatformSupport.all,
      compatibleProtocols: ['hysteria2', 'tuic'],
      requirements: ['Android 7.0+', 'iOS 14.0+'],
      version: '1.9.0',
      category: 'Proxy Core',
    ),
    'amneziawg': const EngineCapability(
      engine: EngineType.amneziawg,
      key: 'amneziawg',
      displayName: 'AmneziaWG',
      description: 'WireGuard variant with junk-packet header obfuscation against DPI',
      platformSupport: PlatformSupport.all,
      compatibleProtocols: ['amneziawg', 'wireguard'],
      requirements: ['Android 6.0+', 'sing-box runtime'],
      version: '1.0.0',
      category: 'DPI Obfuscation',
    ),
    'wireguard': const EngineCapability(
      engine: EngineType.wireguard,
      key: 'wireguard',
      displayName: 'WireGuard',
      description: 'Modern, kernel-integrated high-performance VPN protocol',
      platformSupport: PlatformSupport.both,
      compatibleProtocols: ['wireguard'],
      requirements: ['Android 6.0+', 'iOS 13.0+'],
      version: '1.0.0',
      category: 'Core VPN',
    ),
    'openvpn': const EngineCapability(
      engine: EngineType.openvpn,
      key: 'openvpn',
      displayName: 'OpenVPN',
      description: 'Battle-tested, widely compatible SSL/TLS VPN protocol',
      platformSupport: PlatformSupport.both,
      compatibleProtocols: ['openvpn'],
      requirements: ['Android 5.0+', 'iOS 11.0+'],
      version: '2.6.0',
      category: 'Core VPN',
    ),
    'shadowsocks': const EngineCapability(
      engine: EngineType.shadowsocks,
      key: 'shadowsocks',
      displayName: 'Shadowsocks',
      description: 'Lightweight SOCKS5 encrypted proxy protocol',
      platformSupport: PlatformSupport.both,
      compatibleProtocols: ['shadowsocks'],
      requirements: ['Android 5.0+', 'iOS 11.0+'],
      version: '1.15.0',
      category: 'Proxy Core',
    ),
    'sni': const EngineCapability(
      engine: EngineType.sni,
      key: 'sni',
      displayName: 'SNI Spoofer Relay',
      description: 'Local SNI header spoofer & domain fronting relay',
      platformSupport: PlatformSupport.all,
      compatibleProtocols: ['sni', 'https'],
      requirements: ['Local socket binding'],
      version: '1.1.0',
      category: 'DPI Obfuscation',
    ),
    'warp': const EngineCapability(
      engine: EngineType.warp,
      key: 'warp',
      displayName: 'Cloudflare WARP',
      description: 'Cloudflare WARP mesh network over WireGuard',
      platformSupport: PlatformSupport.all,
      compatibleProtocols: ['warp', 'wireguard'],
      requirements: ['Cloudflare registration'],
      version: '2024.3',
      category: 'Relay / Mesh',
    ),
    'psiphon': const EngineCapability(
      engine: EngineType.psiphon,
      key: 'psiphon',
      displayName: 'Psiphon Core',
      description: 'Multi-transport automated circumvention network',
      platformSupport: PlatformSupport.both,
      compatibleProtocols: ['psiphon', 'ssh', 'http'],
      requirements: ['Auto-discovery'],
      version: '3.0.0',
      category: 'Relay / Mesh',
    ),
    'mhrv': const EngineCapability(
      engine: EngineType.mhrv,
      key: 'mhrv',
      displayName: 'MHRV AppsScript Relay',
      description: 'Embedded Google Apps Script HTTP relay backend',
      platformSupport: PlatformSupport.all,
      compatibleProtocols: ['mhrv', 'http'],
      requirements: ['Google Apps Script deployment'],
      version: '1.0.0',
      category: 'Relay / Mesh',
    ),
  };

  /// Get engine by name/key
  static EngineCapability? getEngine(String name) => _engines[name];

  /// Get all engines for platform
  static List<EngineCapability> getForPlatform(String platform) {
    return _engines.values
        .where((e) => e.supportsPlatform(platform) && e.isEnabled)
        .toList();
  }

  /// Get all engines for protocol
  static List<EngineCapability> getForProtocol(String protocol) {
    return _engines.values
        .where((e) => e.supportsProtocol(protocol) && e.isEnabled)
        .toList();
  }

  /// Get all available engines
  static List<EngineCapability> getAll() =>
    _engines.values.where((e) => e.isEnabled).toList();

  /// Register new engine
  static void register(String name, EngineCapability capability) {
    _engines[name] = capability;
  }

  /// Get list of protocol names
  static List<String> getProtocols() {
    final protocols = <String>{};
    for (final engine in _engines.values) {
      protocols.addAll(engine.compatibleProtocols);
    }
    return protocols.toList();
  }

  /// Get engines supporting specific protocol
  static List<EngineCapability> getByProtocol(String protocol) {
    return _engines.values
        .where((e) => e.supportsProtocol(protocol))
        .toList();
  }
}
