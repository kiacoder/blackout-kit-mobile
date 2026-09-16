import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:logger/logger.dart';

/// App model for split tunneling configuration
class TunnelApp {
  final String packageName;
  final String appName;
  final String? iconPath;
  final bool includedInTunnel;

  TunnelApp({
    required this.packageName,
    required this.appName,
    this.iconPath,
    this.includedInTunnel = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'packageName': packageName,
      'appName': appName,
      'iconPath': iconPath,
      'includedInTunnel': includedInTunnel,
    };
  }

  factory TunnelApp.fromMap(Map<dynamic, dynamic> map) {
    return TunnelApp(
      packageName: map['packageName'] as String,
      appName: map['appName'] as String,
      iconPath: map['iconPath'] as String?,
      includedInTunnel: map['includedInTunnel'] as bool? ?? false,
    );
  }
}

/// Manages split tunneling - route specific apps through VPN, others direct
///
/// On Android: Uses iptables to route traffic by uid (user id) to VPN
/// On iOS: Uses NEAppProxySettings to configure per-app VPN rules
///
/// Strategies:
/// 1. Whitelist mode: Only selected apps go through VPN
/// 2. Blacklist mode: All apps except selected go through VPN
/// 3. Smart mode: Automatic based on app categories (social, messaging, etc.)
class SplitTunnelingService extends GetxService {
  static const platform = MethodChannel('com.blackoutkit.vpn/splittunneling');

  final _logger = Logger();

  final isEnabled = false.obs;
  final isActive = false.obs;
  final mode = Rxn<String>(); // 'whitelist', 'blacklist', 'smart'
  final installedApps = RxList<TunnelApp>();
  final selectedApps = RxSet<String>(); // packageNames of selected apps
  final lastError = Rxn<String>();

  @override
  void onInit() {
    super.onInit();
    _loadSavedState();
  }

  /// Load split tunneling saved state from persistent storage
  void _loadSavedState() {
    // TODO: Load from SharedPreferences/Hive
    // For now, default to false
  }

  /// Fetch installed apps from device
  Future<List<TunnelApp>> fetchInstalledApps() async {
    try {
      _logger.i('Fetching installed apps...');

      final result = await platform.invokeMethod<List<Object?>>(
        'getInstalledApps',
      );

      if (result != null) {
        final apps = result
            .map((item) => TunnelApp.fromMap(item as Map<dynamic, dynamic>))
            .toList();

        installedApps.assignAll(apps);
        _logger.i('✓ Fetched ${apps.length} apps');
        return apps;
      }

      _logger.w('No apps returned from platform');
      return [];
    } catch (e) {
      lastError.value = 'Failed to fetch apps: ${e.toString()}';
      _logger.e('Error fetching installed apps: $e');
      return [];
    }
  }

  /// Enable split tunneling with specified mode
  Future<bool> enable({String mode = 'whitelist'}) async {
    try {
      _logger.i('Enabling split tunneling ($mode mode)...');

      final result = await platform.invokeMethod<bool>(
        'enableSplitTunneling',
        {'mode': mode},
      );

      if (result == true) {
        isEnabled.value = true;
        this.mode.value = mode;
        lastError.value = null;
        _logger.i('✓ Split tunneling enabled ($mode)');
        return true;
      } else {
        lastError.value = 'Failed to enable split tunneling';
        _logger.w('Split tunneling enablement returned false');
        return false;
      }
    } catch (e) {
      lastError.value = 'Split tunneling unavailable: ${e.toString()}';
      _logger.e('Split tunneling enable failed: $e');
      return false;
    }
  }

  /// Disable split tunneling
  Future<bool> disable() async {
    try {
      _logger.i('Disabling split tunneling...');

      final result = await platform.invokeMethod<bool>(
        'disableSplitTunneling',
      );

      if (result == true) {
        isEnabled.value = false;
        isActive.value = false;
        selectedApps.clear();
        lastError.value = null;
        _logger.i('✓ Split tunneling disabled');
        return true;
      } else {
        lastError.value = 'Failed to disable split tunneling';
        _logger.w('Split tunneling disablement returned false');
        return false;
      }
    } catch (e) {
      lastError.value = 'Error disabling split tunneling: ${e.toString()}';
      _logger.e('Split tunneling disable failed: $e');
      return false;
    }
  }

  /// Add app to split tunneling list
  Future<bool> addApp(String packageName) async {
    try {
      _logger.i('Adding app to split tunneling: $packageName');

      if (!selectedApps.contains(packageName)) {
        selectedApps.add(packageName);
      }

      if (isActive.value) {
        final result = await platform.invokeMethod<bool>(
          'addAppToTunnel',
          {'packageName': packageName},
        );

        if (result == true) {
          _logger.i('✓ App added: $packageName');
          return true;
        }
      }

      return true; // Will be applied when activated
    } catch (e) {
      lastError.value = 'Failed to add app: ${e.toString()}';
      _logger.e('Error adding app: $e');
      return false;
    }
  }

  /// Remove app from split tunneling list
  Future<bool> removeApp(String packageName) async {
    try {
      _logger.i('Removing app from split tunneling: $packageName');

      selectedApps.remove(packageName);

      if (isActive.value) {
        final result = await platform.invokeMethod<bool>(
          'removeAppFromTunnel',
          {'packageName': packageName},
        );

        if (result == true) {
          _logger.i('✓ App removed: $packageName');
          return true;
        }
      }

      return true; // Will be applied when deactivated/reactivated
    } catch (e) {
      lastError.value = 'Failed to remove app: ${e.toString()}';
      _logger.e('Error removing app: $e');
      return false;
    }
  }

  /// Activate split tunneling with current app selection
  Future<void> activate() async {
    if (!isEnabled.value) return;

    try {
      _logger.i('Activating split tunneling...');

      final apps = selectedApps.toList();
      await platform.invokeMethod<void>(
        'activateSplitTunneling',
        {'apps': apps},
      );

      isActive.value = true;
      lastError.value = null;
      _logger.i('✓ Split tunneling activated for ${apps.length} apps');
    } catch (e) {
      lastError.value = 'Failed to activate split tunneling: ${e.toString()}';
      _logger.e('Split tunneling activate failed: $e');
    }
  }

  /// Deactivate split tunneling
  Future<void> deactivate() async {
    try {
      _logger.i('Deactivating split tunneling...');

      await platform.invokeMethod<void>('deactivateSplitTunneling');

      isActive.value = false;
      lastError.value = null;
      _logger.i('✓ Split tunneling deactivated');
    } catch (e) {
      lastError.value = 'Failed to deactivate split tunneling: ${e.toString()}';
      _logger.e('Split tunneling deactivate failed: $e');
    }
  }

  /// Change tunneling mode (whitelist/blacklist/smart)
  Future<bool> changeMode(String newMode) async {
    try {
      _logger.i('Changing split tunneling mode to: $newMode');

      final result = await platform.invokeMethod<bool>(
        'changeSplitTunnelingMode',
        {'mode': newMode},
      );

      if (result == true) {
        mode.value = newMode;
        _logger.i('✓ Mode changed to: $newMode');
        return true;
      }

      return false;
    } catch (e) {
      lastError.value = 'Failed to change mode: ${e.toString()}';
      _logger.e('Error changing mode: $e');
      return false;
    }
  }

  /// Get current split tunneling configuration
  Future<Map<String, dynamic>> getConfiguration() async {
    try {
      final result = await platform.invokeMethod<Map<Object?, Object?>>(
        'getSplitTunnelingConfig',
      );

      if (result != null) {
        return Map<String, dynamic>.from(result);
      }

      return {
        'enabled': isEnabled.value,
        'active': isActive.value,
        'mode': mode.value,
        'appCount': selectedApps.length,
      };
    } catch (e) {
      _logger.e('Error getting configuration: $e');
      return {};
    }
  }

  /// Cleanup split tunneling on app exit
  Future<void> cleanup() async {
    try {
      if (isActive.value) {
        await deactivate();
      }
      _logger.i('Split tunneling cleanup complete');
    } catch (e) {
      _logger.e('Error during split tunneling cleanup: $e');
    }
  }
}
