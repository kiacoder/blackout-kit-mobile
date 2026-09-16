/// VPN service for platform channel integration.
/// Bridges to native Android VPN service and iOS NEVPNManager.
/// Handles connect, disconnect, and status checks.

import 'package:flutter/services.dart';
import 'package:logger/logger.dart';
import '../models/config.dart';

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

  VPNService({Logger? logger}) : _log = logger ?? Logger();

  VPNStatus get status => _status;
  String? get connectedConfigHash => _connectedConfigHash;
  bool get isConnected => _status == VPNStatus.connected;

  /// Initialize platform channel listeners
  void initialize() {
    platform.setMethodCallHandler(_handleMethodCall);
    _log.i('VPNService initialized');
  }

  /// Connect to VPN using config
  Future<bool> connect(Config config) async {
    try {
      _status = VPNStatus.connecting;
      _log.i('Connecting to ${config.displayName}');

      final result = await platform.invokeMethod('connect', {
        'protocol': config.protocol,
        'displayName': config.displayName,
        'address': config.address,
        'port': config.port,
        'rawUri': config.rawUri,
        // Protocol-specific data
        if (config is WireGuardConfig) ...{
          'privateKey': config.privateKey,
          'address': config.address,
          'gateway': config.gateway,
          'dns': config.dns,
          'endpoint': config.endpoint,
        },
        if (config is OpenVpnConfig) ...{
          'configContent': config.configContent,
        },
        if (config is ShadowsocksConfig) ...{
          'method': config.method,
          'password': config.password,
          'plugin': config.plugin,
        },
      });

      if (result == true) {
        _status = VPNStatus.connected;
        _connectedConfigHash = config.getHash();
        _log.i('Connected to ${config.displayName}');
        return true;
      } else {
        _status = VPNStatus.error;
        _log.e('Failed to connect: $result');
        return false;
      }
    } on PlatformException catch (e) {
      _status = VPNStatus.error;
      _log.e('Platform error connecting: ${e.message}');
      return false;
    } catch (e) {
      _status = VPNStatus.error;
      _log.e('Error connecting: $e');
      return false;
    }
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
      default:
        _log.w('Unknown status: $status');
    }
  }

  void _handleError(String? error) {
    _status = VPNStatus.error;
    _log.e('VPN error: $error');
  }
}
