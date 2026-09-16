import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:logger/logger.dart';

/// Manages kill switch functionality - blocks all traffic if VPN disconnects
///
/// On Android: Uses iptables to block non-VPN traffic
/// On iOS: Uses PF (packet filter) or NEVPNConfiguration
///
/// If native implementation fails: Falls back to system settings recommendation
class KillSwitchService extends GetxService {
  static const platform = MethodChannel('com.blackoutkit.vpn/killswitch');

  final _logger = Logger();
  final isEnabled = false.obs;
  final isActive = false.obs;
  final lastError = Rxn<String>();

  @override
  void onInit() {
    super.onInit();
    _loadSavedState();
  }

  /// Load kill switch saved state from persistent storage
  void _loadSavedState() {
    // TODO: Load from SharedPreferences/Hive
    // For now, default to false
  }

  /// Enable kill switch - blocks all non-VPN traffic
  Future<bool> enable() async {
    try {
      _logger.i('Enabling kill switch...');

      final result = await platform.invokeMethod<bool>('enableKillSwitch');

      if (result == true) {
        isEnabled.value = true;
        lastError.value = null;
        _logger.i('✓ Kill switch enabled successfully');
        return true;
      } else {
        lastError.value = 'Failed to enable kill switch - falling back to system settings';
        _logger.w('Kill switch enablement returned false');
        return false;
      }
    } catch (e) {
      lastError.value = 'Kill switch unavailable: ${e.toString()}';
      _logger.e('Kill switch enable failed: $e');
      return false;
    }
  }

  /// Disable kill switch - allows non-VPN traffic
  Future<bool> disable() async {
    try {
      _logger.i('Disabling kill switch...');

      final result = await platform.invokeMethod<bool>('disableKillSwitch');

      if (result == true) {
        isEnabled.value = false;
        isActive.value = false;
        lastError.value = null;
        _logger.i('✓ Kill switch disabled successfully');
        return true;
      } else {
        lastError.value = 'Failed to disable kill switch';
        _logger.w('Kill switch disablement returned false');
        return false;
      }
    } catch (e) {
      lastError.value = 'Error disabling kill switch: ${e.toString()}';
      _logger.e('Kill switch disable failed: $e');
      return false;
    }
  }

  /// Activate kill switch (block traffic immediately)
  /// Called when VPN is connecting or connected
  Future<void> activate() async {
    if (!isEnabled.value) return;

    try {
      _logger.i('Activating kill switch (blocking traffic)...');
      await platform.invokeMethod<void>('activateKillSwitch');
      isActive.value = true;
      lastError.value = null;
      _logger.i('✓ Kill switch activated - traffic blocked');
    } catch (e) {
      lastError.value = 'Failed to activate kill switch: ${e.toString()}';
      _logger.e('Kill switch activate failed: $e');
    }
  }

  /// Deactivate kill switch (allow traffic to flow)
  /// Called when VPN is disconnecting
  Future<void> deactivate() async {
    try {
      _logger.i('Deactivating kill switch (allowing traffic)...');
      await platform.invokeMethod<void>('deactivateKillSwitch');
      isActive.value = false;
      lastError.value = null;
      _logger.i('✓ Kill switch deactivated - traffic allowed');
    } catch (e) {
      lastError.value = 'Failed to deactivate kill switch: ${e.toString()}';
      _logger.e('Kill switch deactivate failed: $e');
    }
  }

  /// Check if kill switch is currently active
  Future<bool> getStatus() async {
    try {
      final result = await platform.invokeMethod<bool>('isKillSwitchActive');
      return result ?? false;
    } catch (e) {
      _logger.e('Error checking kill switch status: $e');
      return false;
    }
  }

  /// Get platform-specific kill switch capability info
  Future<Map<String, dynamic>> getCapabilities() async {
    try {
      final result = await platform.invokeMethod<Map<Object?, Object?>>('getKillSwitchCapabilities');
      return Map<String, dynamic>.from(result ?? {});
    } catch (e) {
      _logger.e('Error getting kill switch capabilities: $e');
      return {
        'supported': false,
        'reason': 'Platform check failed: $e'
      };
    }
  }

  /// Test kill switch without enabling it permanently
  /// Useful for testing traffic blocking works
  Future<bool> testKillSwitch({Duration duration = const Duration(seconds: 5)}) async {
    try {
      _logger.i('Testing kill switch for ${duration.inSeconds}s...');

      final result = await platform.invokeMethod<bool>(
        'testKillSwitch',
        {'durationSeconds': duration.inSeconds}
      );

      if (result == true) {
        _logger.i('✓ Kill switch test successful');
        return true;
      } else {
        lastError.value = 'Kill switch test failed';
        _logger.w('Kill switch test returned false');
        return false;
      }
    } catch (e) {
      lastError.value = 'Kill switch test error: ${e.toString()}';
      _logger.e('Kill switch test failed: $e');
      return false;
    }
  }

  /// Cleanup kill switch on app exit
  Future<void> cleanup() async {
    try {
      if (isActive.value) {
        await deactivate();
      }
      _logger.i('Kill switch cleanup complete');
    } catch (e) {
      _logger.e('Error during kill switch cleanup: $e');
    }
  }
}
