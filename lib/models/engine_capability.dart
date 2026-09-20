/// Engine capability model.
/// Mirrors Blackout Kit CLI's EngineCapability catalogue: ten engines, with the
/// protocols and platform each one claims to support.
///
/// IMPORTANT: this catalogue describes what the *family* of Blackout Kit
/// clients can do. It is NOT a statement about what this APK can run. Most of
/// these engines have no runtime bundled here. The authoritative answer comes
/// from the native layer via `VPNService.getEngineInfo()`; the engine hub
/// screen intersects the two and greys out anything without a bundled runtime.
///
/// [version] is intentionally left null throughout. Version strings that
/// describe a runtime we do not ship cannot be verified, and asserting them in
/// the UI would be a false claim. The one engine we do ship (Xray) reports its
/// real version from `Libv2ray.checkVersionX()` at runtime.

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

  /// Catalogue-level on/off flag. **Every entry is currently `true`**, so the
  /// `isEnabled` filters in [EngineRegistry] are no-ops today.
  ///
  /// This is NOT a statement about whether the engine can run on this build.
  /// For that, ask the native layer via `VPNService.getEngineInfo()` and check
  /// [EngineAvailability.canConnect]. Kept as a seam for a future "user
  /// disables an engine" preference.
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

/// Engine registry for the Blackout Kit CLI engine catalogue.
///
/// This is a *catalogue*, not a capability report: it lists what the engine
/// family can do, and every entry is returned as enabled. Use
/// `VPNService.getEngineInfo()` to find out what this build can actually run.
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
      category: 'DPI Obfuscation',
    ),
    'wireguard': const EngineCapability(
      engine: EngineType.wireguard,
      key: 'wireguard',
      displayName: 'WireGuard',
      // Not "kernel-integrated" on Android: there is no kernel module here, so
      // WireGuard runs as a userspace outbound inside the bundled Xray core's
      // netstack (`xray.proxy.wireguard`). Saying otherwise would describe a
      // data path this build does not have.
      description:
          'Modern, high-performance VPN protocol, carried by the bundled core',
      platformSupport: PlatformSupport.both,
      compatibleProtocols: ['wireguard'],
      requirements: ['Android 6.0+', 'iOS 13.0+'],
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

/// True when this build can serve **every** protocol [engine] advertises.
///
/// The rule is deliberately `every`, not `any`. AmneziaWG lists
/// `['amneziawg', 'wireguard']` and WARP lists `['warp', 'wireguard']`; under an
/// `any` rule, the moment WireGuard became servable by the bundled Xray core
/// both cards would have rendered as "available" even though neither engine is
/// bundled and neither of their own protocols can run. Requiring every
/// advertised protocol to be servable keeps the engine hub honest.
///
/// [canConnect] is injected rather than reaching for `EngineAvailability`
/// directly, so this stays a pure function of the capability report and can be
/// tested without a platform channel.
bool engineIsRunnable(
  EngineCapability engine,
  bool Function(String protocol) canConnect,
) {
  if (engine.compatibleProtocols.isEmpty) return false;
  return engine.compatibleProtocols.every(canConnect);
}
