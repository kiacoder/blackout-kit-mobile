import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:logger/logger.dart';

/// Prevents DNS leaks by forcing DNS queries through VPN tunnel
///
/// On Android: Uses iptables to redirect DNS (port 53) through VPN
/// On iOS: Uses NEDNSSettings with VPN configuration
///
/// Strategies:
/// 1. Force VPN DNS servers only (no system/ISP DNS)
/// 2. Block external DNS queries (port 53)
/// 3. Use secure DNS providers (Cloudflare, Quad9, NextDNS)
/// 4. Monitor for DNS leaks (test against known DNS servers)
class DNSLeakPreventionService extends GetxService {
  static const platform = MethodChannel('com.blackoutkit.vpn/dns');

  final _logger = Logger();

  final isEnabled = false.obs;
  final isActive = false.obs;
  final currentDNS = Rxn<String>();
  final lastError = Rxn<String>();

  // Secure DNS server options (public resolvers)
  static const secureDNSServers = {
    'cloudflare': '1.1.1.1',
    'quad9': '9.9.9.9',
    'adguard': '94.140.14.14',
    'nextdns': '45.90.28.0',
    'opendns': '208.67.222.222',
  };

  @override
  void onInit() {
    super.onInit();
    _loadSavedState();
  }

  /// Load DNS leak prevention saved state from persistent storage
  void _loadSavedState() {
    // TODO: Load from SharedPreferences/Hive
    // For now, default to false
  }

  /// Enable DNS leak prevention
  Future<bool> enable({String? customDNS}) async {
    try {
      _logger.i('Enabling DNS leak prevention...');

      final dnsServer = customDNS ?? secureDNSServers['cloudflare']!;

      final result = await platform.invokeMethod<bool>(
        'enableDNSLeakPrevention',
        {'dnsServer': dnsServer},
      );

      if (result == true) {
        isEnabled.value = true;
        currentDNS.value = dnsServer;
        lastError.value = null;
        _logger.i('✓ DNS leak prevention enabled');
        return true;
      } else {
        lastError.value = 'Failed to enable DNS leak prevention';
        _logger.w('DNS leak prevention enablement returned false');
        return false;
      }
    } catch (e) {
      lastError.value = 'DNS configuration failed: ${e.toString()}';
      _logger.e('DNS leak prevention enable failed: $e');
      return false;
    }
  }

  /// Disable DNS leak prevention - restore system DNS
  Future<bool> disable() async {
    try {
      _logger.i('Disabling DNS leak prevention...');

      final result = await platform.invokeMethod<bool>(
        'disableDNSLeakPrevention',
      );

      if (result == true) {
        isEnabled.value = false;
        isActive.value = false;
        currentDNS.value = null;
        lastError.value = null;
        _logger.i('✓ DNS leak prevention disabled');
        return true;
      } else {
        lastError.value = 'Failed to disable DNS leak prevention';
        _logger.w('DNS leak prevention disablement returned false');
        return false;
      }
    } catch (e) {
      lastError.value = 'Error disabling DNS: ${e.toString()}';
      _logger.e('DNS leak prevention disable failed: $e');
      return false;
    }
  }

  /// Activate DNS leak prevention (block system DNS)
  /// Called when VPN is connecting or connected
  Future<void> activate() async {
    if (!isEnabled.value) return;

    try {
      _logger.i('Activating DNS leak prevention (blocking system DNS)...');
      await platform.invokeMethod<void>('activateDNSLeakPrevention');
      isActive.value = true;
      lastError.value = null;
      _logger.i('✓ DNS leak prevention activated');
    } catch (e) {
      lastError.value = 'Failed to activate DNS: ${e.toString()}';
      _logger.e('DNS leak prevention activate failed: $e');
    }
  }

  /// Deactivate DNS leak prevention (allow system DNS)
  /// Called when VPN is disconnecting
  Future<void> deactivate() async {
    try {
      _logger.i('Deactivating DNS leak prevention (allowing system DNS)...');
      await platform.invokeMethod<void>('deactivateDNSLeakPrevention');
      isActive.value = false;
      lastError.value = null;
      _logger.i('✓ DNS leak prevention deactivated');
    } catch (e) {
      lastError.value = 'Failed to deactivate DNS: ${e.toString()}';
      _logger.e('DNS leak prevention deactivate failed: $e');
    }
  }

  /// Get current DNS configuration
  Future<String?> getCurrentDNS() async {
    try {
      final result = await platform.invokeMethod<String>('getCurrentDNS');
      return result;
    } catch (e) {
      _logger.e('Error getting current DNS: $e');
      return null;
    }
  }

  /// Test for DNS leaks by querying known DNS servers
  Future<List<String>> testForLeaks() async {
    try {
      _logger.i('Testing for DNS leaks...');

      final result = await platform.invokeMethod<List<Object?>>(
        'testDNSLeaks',
      );

      final leakedServers = (result ?? []).cast<String>();

      if (leakedServers.isEmpty) {
        _logger.i('✓ No DNS leaks detected');
      } else {
        _logger.w('⚠ DNS leaks detected on: ${leakedServers.join(', ')}');
      }

      return leakedServers;
    } catch (e) {
      lastError.value = 'DNS leak test failed: ${e.toString()}';
      _logger.e('DNS leak test error: $e');
      return [];
    }
  }

  /// Set custom DNS server
  Future<bool> setCustomDNS(String dnsServer) async {
    try {
      _logger.i('Setting custom DNS: $dnsServer');

      final result = await platform.invokeMethod<bool>(
        'setCustomDNS',
        {'dnsServer': dnsServer},
      );

      if (result == true) {
        currentDNS.value = dnsServer;
        lastError.value = null;
        _logger.i('✓ Custom DNS set: $dnsServer');
        return true;
      } else {
        lastError.value = 'Failed to set custom DNS';
        return false;
      }
    } catch (e) {
      lastError.value = 'Error setting custom DNS: ${e.toString()}';
      _logger.e('Set custom DNS failed: $e');
      return false;
    }
  }

  /// Get available secure DNS providers
  Future<Map<String, String>> getSecureDNSProviders() async {
    try {
      final result = await platform.invokeMethod<Map<Object?, Object?>>(
        'getSecureDNSProviders',
      );

      if (result != null) {
        return Map<String, String>.from(result);
      }

      // Fallback to hardcoded providers
      return secureDNSServers;
    } catch (e) {
      _logger.e('Error getting DNS providers: $e');
      return secureDNSServers;
    }
  }

  /// Cleanup DNS configuration on app exit
  Future<void> cleanup() async {
    try {
      if (isActive.value) {
        await deactivate();
      }
      _logger.i('DNS leak prevention cleanup complete');
    } catch (e) {
      _logger.e('Error during DNS cleanup: $e');
    }
  }
}
