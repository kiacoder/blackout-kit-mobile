/// VPN Config model replicating Blackout Kit CLI's ProxyConfig dataclass.
/// Supports: WireGuard, OpenVPN, Shadowsocks protocols.
/// V2 extensibility: Add V2Ray, Trojan, NaïveProxy subclasses without UI changes.

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

/// WireGuard config
class WireGuardConfig extends Config {
  final String name;
  final String rawUri;
  final String privateKey;
  final String address;
  final String gateway;
  final String dns;
  final int port;
  final String? publicKey;
  final String? presharedKey;
  final String? endpoint;

  WireGuardConfig({
    required this.name,
    required this.rawUri,
    required this.privateKey,
    required this.address,
    required this.gateway,
    required this.dns,
    this.port = 51820,
    this.publicKey,
    this.presharedKey,
    this.endpoint,
  });

  @override
  String get protocol => 'wireguard';

  @override
  String get displayName => name;

  @override
  Future<bool> connect() async {
    // Implemented by VPN service
    return true;
  }

  @override
  Future<void> disconnect() async {
    // Implemented by VPN service
  }

  @override
  Future<bool> isRunning() async {
    // Implemented by VPN service
    return false;
  }

  @override
  bool validate() {
    return privateKey.isNotEmpty &&
        address.isNotEmpty &&
        gateway.isNotEmpty &&
        dns.isNotEmpty;
  }

  static WireGuardConfig? fromUri(String uri) {
    try {
      // Parse WireGuard URI format (typically config file content)
      // For now, basic implementation
      return WireGuardConfig(
        name: 'WireGuard Config',
        rawUri: uri,
        privateKey: '',
        address: '',
        gateway: '',
        dns: '',
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
    // Implemented by VPN service
    return true;
  }

  @override
  Future<void> disconnect() async {
    // Implemented by VPN service
  }

  @override
  Future<bool> isRunning() async {
    // Implemented by VPN service
    return false;
  }

  @override
  bool validate() {
    return configContent.isNotEmpty && address.isNotEmpty;
  }

  static OpenVpnConfig? fromUri(String uri) {
    try {
      // Parse OpenVPN config
      return OpenVpnConfig(
        name: 'OpenVPN Config',
        rawUri: uri,
        configContent: uri,
        address: '',
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
    // Implemented by VPN service
    return true;
  }

  @override
  Future<void> disconnect() async {
    // Implemented by VPN service
  }

  @override
  Future<bool> isRunning() async {
    // Implemented by VPN service
    return false;
  }

  @override
  bool validate() {
    return address.isNotEmpty && port > 0 && method.isNotEmpty && password.isNotEmpty;
  }

  /// Parse ss:// URI format
  /// Format: ss://method:password@host:port/?plugin=...
  static ShadowsocksConfig? fromUri(String uri) {
    try {
      if (!uri.startsWith('ss://')) return null;

      final cleanUri = uri.substring(5);
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
        name: 'Shadowsocks ($address:$port)',
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

/// Config parser factory
class ConfigParser {
  static Config? parse(String uri, {String? customName}) {
    try {
      if (uri.startsWith('ss://')) {
        return ShadowsocksConfig.fromUri(uri);
      } else if (uri.startsWith('ovpn://') || uri.contains('BEGIN CERTIFICATE')) {
        return OpenVpnConfig.fromUri(uri);
      } else if (uri.contains('[Interface]')) {
        return WireGuardConfig.fromUri(uri);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Parse all configs from text (one per line)
  static List<Config> parseMultiple(String text) {
    return text.split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty && !line.startsWith('#'))
        .map((uri) => parse(uri))
        .whereType<Config>()
        .toList();
  }
}
