/// Engine capability model (V2 prep).
/// Replicates Blackout Kit CLI's EngineCapability for protocol/platform support.
/// Allows seamless addition of V2Ray, Trojan, NaïveProxy without UI redesign.

enum EngineType {
  wireguard,
  openvpn,
  shadowsocks,
  v2ray,      // V2
  trojan,     // V2
  naiveproxy, // V2
  hotspotshield, // V3
}

enum PlatformSupport {
  android,
  ios,
  both,
}

class EngineCapability {
  final EngineType engine;
  final String displayName;
  final String description;
  final PlatformSupport platformSupport;
  final List<String> compatibleProtocols;
  final List<String> requirements; // e.g., "Android 8.0+", "permission: VPN"
  final bool isEnabled;
  final String? version;

  const EngineCapability({
    required this.engine,
    required this.displayName,
    required this.description,
    required this.platformSupport,
    required this.compatibleProtocols,
    this.requirements = const [],
    this.isEnabled = true,
    this.version,
  });

  /// Check if engine supports current platform
  bool supportsPlatform(String platform) {
    // platform: "android", "ios"
    if (platformSupport == PlatformSupport.both) return true;
    if (platformSupport == PlatformSupport.android && platform == 'android') return true;
    if (platformSupport == PlatformSupport.ios && platform == 'ios') return true;
    return false;
  }

  /// Check if engine supports protocol
  bool supportsProtocol(String protocol) =>
    compatibleProtocols.contains(protocol);

  @override
  String toString() =>
    'EngineCapability(engine=$engine, platforms=$platformSupport)';
}

/// Engine registry for V2 extensibility.
/// Maps protocol → available engines.
class EngineRegistry {
  static final Map<String, EngineCapability> _engines = {
    'wireguard': EngineCapability(
      engine: EngineType.wireguard,
      displayName: 'WireGuard',
      description: 'Modern, fast, kernel-integrated VPN protocol',
      platformSupport: PlatformSupport.both,
      compatibleProtocols: ['wireguard'],
      requirements: ['Android 6.0+', 'iOS 13.0+'],
      version: '1.0.0',
    ),
    'openvpn': EngineCapability(
      engine: EngineType.openvpn,
      displayName: 'OpenVPN',
      description: 'Battle-tested, widely supported VPN protocol',
      platformSupport: PlatformSupport.both,
      compatibleProtocols: ['openvpn'],
      requirements: ['Android 5.0+', 'iOS 11.0+'],
      version: '2.5.0',
    ),
    'shadowsocks': EngineCapability(
      engine: EngineType.shadowsocks,
      displayName: 'Shadowsocks',
      description: 'Lightweight SOCKS5 proxy protocol',
      platformSupport: PlatformSupport.both,
      compatibleProtocols: ['shadowsocks'],
      requirements: ['Android 5.0+', 'iOS 11.0+'],
      version: '1.0.0',
    ),
    // V2 engines (added later)
    // 'v2ray': EngineCapability(...),
    // 'trojan': EngineCapability(...),
    // 'naiveproxy': EngineCapability(...),
  };

  /// Get engine by name
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

  /// Register new engine (V2/V3 extensibility)
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
