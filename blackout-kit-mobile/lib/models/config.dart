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
    return privateKey.isNotEmpty || endpoint != null;
  }

  /// Parse WireGuard INI content
  static WireGuardConfig? fromUri(String content, {String? customName}) {
    try {
      String privateKey = '';
      String address = '';
      String dns = '';
      String publicKey = '';
      String endpoint = '';
      int port = 51820;

      final lines = content.split('\n');
      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.startsWith('#') || !trimmed.contains('=')) continue;

        final parts = trimmed.split('=');
        if (parts.length < 2) continue;

        final key = parts[0].trim().toLowerCase();
        final val = parts.sublist(1).join('=').trim();

        if (key == 'privatekey') privateKey = val;
        if (key == 'address') address = val;
        if (key == 'dns') dns = val;
        if (key == 'publickey') publicKey = val;
        if (key == 'endpoint') {
          endpoint = val;
          final epParts = val.split(':');
          if (epParts.length == 2) {
            port = int.tryParse(epParts[1]) ?? 51820;
          }
        }
      }

      final host = endpoint.isNotEmpty
          ? endpoint.split(':')[0]
          : (address.isNotEmpty ? address.split('/')[0] : '127.0.0.1');

      return WireGuardConfig(
        name: customName ?? 'WireGuard ($host:$port)',
        rawUri: content,
        privateKey: privateKey,
        address: address.isNotEmpty ? address : host,
        gateway: host,
        dns: dns.isNotEmpty ? dns : '1.1.1.1',
        port: port,
        publicKey: publicKey,
        endpoint: endpoint,
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

/// Config parser factory
class ConfigParser {
  static Config? parse(String text, {String? customName}) {
    try {
      final trimmed = text.trim();
      if (trimmed.startsWith('ss://')) {
        return ShadowsocksConfig.fromUri(trimmed, customName: customName);
      } else if (trimmed.contains('remote ') || trimmed.contains('BEGIN CERTIFICATE') || trimmed.contains('client\n')) {
        return OpenVpnConfig.fromUri(trimmed, customName: customName);
      } else if (trimmed.contains('[Interface]') || trimmed.contains('PrivateKey')) {
        return WireGuardConfig.fromUri(trimmed, customName: customName);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Parse all configs from text
  static List<Config> parseMultiple(String text) {
    final list = <Config>[];
    final lines = text.split('\n');
    final buffer = StringBuffer();

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.startsWith('ss://')) {
        final cfg = ShadowsocksConfig.fromUri(trimmed);
        if (cfg != null) list.add(cfg);
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
