/// VPN service for platform channel integration.
/// Bridges to native Android VPN service and iOS NEVPNManager.
/// Handles connect, disconnect, and status checks.

import 'package:flutter/services.dart';
import 'package:logger/logger.dart';
import '../models/config.dart';
import '../models/vpn_session_options.dart';
import 'xray_config.dart';

enum VPNStatus {
  disconnected,
  connecting,
  connected,
  disconnecting,
  error,
}

class VPNService {
  static const platform = MethodChannel('com.blackoutkit.vpn/service');
  final Logger _log;

  VPNStatus _status = VPNStatus.disconnected;
  String? _connectedConfigHash;
  String? _lastError;

  /// Loopback port the bundled engine exposes its SOCKS listener on.
  /// Must match BlackoutVpnService.DEFAULT_SOCKS_PORT on the native side.
  static const int defaultSocksPort = 10808;

  /// TUN interface MTU. Must match BlackoutVpnService.VPN_MTU.
  static const int tunMtu = 1500;

  /// Address the Xray netstack answers on. Must share a subnet with
  /// BlackoutVpnService.VPN_ADDRESS_V4 (10.111.222.1/30) or replies written
  /// back into the tunnel are dropped by the interface.
  static const String tunGatewayCidr = '10.111.222.2/30';

  VPNService({Logger? logger}) : _log = logger ?? Logger();

  VPNStatus get status => _status;
  String? get connectedConfigHash => _connectedConfigHash;
  String? get lastError => _lastError;
  bool get isConnected => _status == VPNStatus.connected;

  /// Initialize platform channel listeners
  void initialize() {
    platform.setMethodCallHandler(_handleMethodCall);
    _log.i('VPNService initialized');
  }

  /// Android requires explicit user consent before the first tunnel.
  /// Returns true when consent is already granted or the user just granted it.
  Future<bool> prepare() async {
    try {
      final result = await platform.invokeMethod<bool>('prepare');
      return result ?? false;
    } on PlatformException catch (e) {
      _lastError = e.message ?? e.code;
      _log.e('VPN prepare failed: ${e.message}');
      return false;
    } catch (e) {
      _lastError = e.toString();
      _log.e('VPN prepare failed: $e');
      return false;
    }
  }

  /// Which engines this build can actually run.
  ///
  /// Lets the UI grey out protocols with no bundled engine instead of letting
  /// the user pick one and hit a dead end.
  Future<EngineAvailability> getEngineInfo() async {
    try {
      final result = await platform.invokeMethod<Map>('getEngineInfo');
      if (result == null) return const EngineAvailability.unknown();
      return EngineAvailability.fromMap(Map<String, dynamic>.from(result));
    } catch (e) {
      _log.w('Could not read engine info: $e');
      return const EngineAvailability.unknown();
    }
  }

  /// Connect to VPN using config
  ///
  /// [options] carries the split tunneling, DNS and kill switch decisions. They
  /// are builder-time inputs, so they must be supplied here rather than applied
  /// afterwards — `Builder.establish()` freezes them into the tunnel.
  Future<bool> connect(Config config, {VpnSessionOptions? options}) async {
    try {
      final session = options ?? VpnSessionOptions(dnsServers: dnsServersForConfig(config));

      final configProblem = session.validationError;
      if (configProblem != null) {
        _status = VPNStatus.error;
        _lastError = configProblem;
        _log.e('Refusing to connect: $configProblem');
        return false;
      }

      _status = VPNStatus.connecting;
      _log.i('Connecting to ${config.displayName} ($session)');

      // Xray-family protocols are carried by the in-process core, which needs a
      // complete config document rather than loose credentials.
      String? xrayJson;
      if (isXrayProtocol(config.protocol)) {
        try {
          xrayJson = XrayConfigBuilder(
            socksPort: defaultSocksPort,
            mtu: tunMtu,
            gatewayCidr: tunGatewayCidr,
            dnsServers: session.dnsServers,
            routeDnsThroughProxy: session.routeDnsThroughProxy,
          ).buildJson(config);
        } on ArgumentError catch (e) {
          // A config that cannot produce a valid outbound (e.g. REALITY with no
          // public key) should fail here, with the reason, rather than starting
          // a core that silently drops every packet.
          _status = VPNStatus.error;
          _lastError = e.message?.toString() ?? e.toString();
          _log.e('Refusing to build an Xray config: $_lastError');
          return false;
        }
      }

      final result = await platform.invokeMethod('connect', {
        'protocol': config.protocol,
        'displayName': config.displayName,
        'address': config.address,
        'port': config.port,
        'rawUri': config.rawUri,
        // Loopback port for engines that bridge the TUN through SOCKS.
        'socksPort': defaultSocksPort,
        ...session.toChannelMap(),
        if (xrayJson != null) 'xrayConfig': xrayJson,
        // NOTE: no per-protocol argument block here. The Kotlin side reads
        // exactly nine keys — protocol, displayName, socksPort, dns,
        // dnsServers, holdTunnelOnEngineFailure, xrayConfig, allowedApps and
        // disallowedApps — all of which are already in the map above. Loose
        // credentials used to be sent as well (privateKey, gateway, method,
        // password, configContent…) and were silently discarded, which made
        // the channel look like it carried more than it did. Everything a
        // protocol actually needs now travels inside `xrayConfig`.
      });

      if (result == true) {
        _status = VPNStatus.connected;
        _connectedConfigHash = config.getHash();
        _lastError = null;
        _log.i('Connected to ${config.displayName}');
        return true;
      } else {
        _status = VPNStatus.error;
        _lastError = 'The tunnel failed to come up';
        _log.e('Failed to connect: $result');
        return false;
      }
    } on PlatformException catch (e) {
      // The native side reports the real reason (missing engine, revoked
      // consent, establish() failure) instead of a generic error.
      _status = VPNStatus.error;
      _lastError = e.message ?? e.code;
      _log.e('Platform error connecting: ${e.message}');
      return false;
    } catch (e) {
      _status = VPNStatus.error;
      _lastError = e.toString();
      _log.e('Error connecting: $e');
      return false;
    }
  }

  /// DNS servers to hand the core, taken from the config where it specifies any.
  static List<String> dnsServersForConfig(Config config) {
    final dns = switch (config) {
      WireGuardConfig c when c.dns.isNotEmpty => c.dns,
      _ => '',
    };
    if (dns.isEmpty) return const ['1.1.1.1', '8.8.8.8'];

    final parsed = dns
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    return parsed.isEmpty ? const ['1.1.1.1', '8.8.8.8'] : parsed;
  }

  /// Disconnect from VPN
  Future<bool> disconnect() async {
    try {
      _status = VPNStatus.disconnecting;
      _log.i('Disconnecting VPN');

      final result = await platform.invokeMethod('disconnect');

      if (result == true) {
        _status = VPNStatus.disconnected;
        _connectedConfigHash = null;
        _log.i('Disconnected from VPN');
        return true;
      } else {
        _status = VPNStatus.error;
        _log.e('Failed to disconnect: $result');
        return false;
      }
    } on PlatformException catch (e) {
      _status = VPNStatus.error;
      _log.e('Platform error disconnecting: ${e.message}');
      return false;
    } catch (e) {
      _status = VPNStatus.error;
      _log.e('Error disconnecting: $e');
      return false;
    }
  }

  /// Check if VPN is running
  Future<bool> isRunning() async {
    try {
      final result = await platform.invokeMethod('isRunning');
      return result == true;
    } on PlatformException catch (e) {
      _log.e('Platform error checking status: ${e.message}');
      return false;
    } catch (e) {
      _log.e('Error checking status: $e');
      return false;
    }
  }

  /// Get current VPN status
  Future<Map<String, dynamic>> getStatus() async {
    try {
      final result = await platform.invokeMethod<Map>('getStatus');
      return Map<String, dynamic>.from(result ?? {});
    } on PlatformException catch (e) {
      _log.e('Platform error getting status: ${e.message}');
      return {};
    } catch (e) {
      _log.e('Error getting status: $e');
      return {};
    }
  }

  /// Get current connected IP (if available)
  Future<String?> getConnectedIP() async {
    try {
      final result = await platform.invokeMethod<String>('getConnectedIP');
      return result;
    } on PlatformException catch (e) {
      _log.e('Platform error getting IP: ${e.message}');
      return null;
    } catch (e) {
      _log.e('Error getting IP: $e');
      return null;
    }
  }

  /// Handle method calls from native side
  Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onStatusChanged':
        final status = call.arguments['status'] as String?;
        _handleStatusChange(status);
        break;
      case 'onError':
        final error = call.arguments['error'] as String?;
        _handleError(error);
        break;
      default:
        _log.w('Unknown method: ${call.method}');
    }
  }

  void _handleStatusChange(String? status) {
    switch (status) {
      case 'connected':
        _status = VPNStatus.connected;
        _log.i('VPN status changed: connected');
        break;
      case 'disconnected':
        _status = VPNStatus.disconnected;
        _connectedConfigHash = null;
        _log.i('VPN status changed: disconnected');
        break;
      case 'connecting':
        _status = VPNStatus.connecting;
        _log.i('VPN status changed: connecting');
        break;
      case 'disconnecting':
        _status = VPNStatus.disconnecting;
        _log.i('VPN status changed: disconnecting');
        break;
      case 'blocked':
        // The kill switch held the tunnel open after the engine died. Traffic
        // is being dropped on purpose; this is not a clean disconnect.
        _status = VPNStatus.error;
        _lastError = 'The proxy stopped, so traffic is being blocked. '
            'Reconnect to restore access.';
        _log.w('VPN status changed: blocked (kill switch holding the tunnel)');
        break;
      default:
        _log.w('Unknown status: $status');
    }
  }

  void _handleError(String? error) {
    _status = VPNStatus.error;
    _log.e('VPN error: $error');
  }
}

/// What this build can actually connect.
///
/// Reported by the native layer so the UI can stop offering protocols that have
/// no bundled engine. [isKnown] is false when the platform channel is absent
/// (iOS, tests, desktop), in which case callers should not grey anything out.
class EngineAvailability {
  final bool isKnown;
  final bool xrayAvailable;
  final String? xrayVersion;
  final List<String> xrayProtocols;
  final bool singboxAvailable;
  final List<String> singboxProtocols;

  /// Protocols the native layer has explicitly declared unusable.
  final List<String> unavailableProtocols;

  const EngineAvailability({
    required this.isKnown,
    required this.xrayAvailable,
    required this.xrayVersion,
    required this.xrayProtocols,
    required this.singboxAvailable,
    required this.singboxProtocols,
    required this.unavailableProtocols,
  });

  const EngineAvailability.unknown()
      : isKnown = false,
        xrayAvailable = false,
        xrayVersion = null,
        xrayProtocols = const [],
        singboxAvailable = false,
        singboxProtocols = const [],
        unavailableProtocols = const [];

  factory EngineAvailability.fromMap(Map<String, dynamic> map) {
    List<String> strings(String key) =>
        (map[key] as List?)?.map((e) => e.toString()).toList() ?? const [];
    return EngineAvailability(
      isKnown: true,
      xrayAvailable: map['xrayAvailable'] == true,
      xrayVersion: map['xrayVersion'] as String?,
      xrayProtocols: strings('xrayProtocols'),
      singboxAvailable: map['singboxAvailable'] == true,
      singboxProtocols: strings('singboxProtocols'),
      unavailableProtocols: strings('unavailableProtocols'),
    );
  }

  /// Every protocol this build can serve.
  List<String> get supportedProtocols => [
        if (xrayAvailable) ...xrayProtocols,
        if (singboxAvailable) ...singboxProtocols,
      ];

  bool canConnect(String protocol) =>
      isKnown ? supportedProtocols.contains(protocol) : true;

  /// Human-readable summary, e.g. for a settings or about screen.
  String get summary {
    if (!isKnown) return 'Engine support could not be determined on this platform.';
    if (supportedProtocols.isEmpty) {
      return 'No engine is bundled in this build.';
    }
    return 'Xray ${xrayVersion ?? ""}'.trim() +
        ' - ${supportedProtocols.join(", ")}';
  }
}
