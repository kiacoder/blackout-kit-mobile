/// Settings controller using GetX for user preferences.
/// Manages app-wide settings like auto-connect, kill switch, theme, etc.

import 'package:get/get.dart';
import 'package:logger/logger.dart';

class SettingsController extends GetxController {
  final Logger _log;

  // Observable preferences
  final RxBool autoConnect = RxBool(false);
  final RxBool killSwitchEnabled = RxBool(false);
  final RxBool blockNonVPNTraffic = RxBool(false);
  final RxBool splitTunnelingEnabled = RxBool(false);
  final RxList<String> splitTunnelingApps = RxList<String>();

  final RxString theme = RxString('system'); // system, light, dark
  final RxBool showSpeedInTray = RxBool(true);
  final RxBool showNotifications = RxBool(true);

  final RxString selectedLanguage = RxString('en');
  final RxBool analyticsEnabled = RxBool(false);

  // VPN-specific settings
  final RxString preferredProtocol = RxString('wireguard'); // wireguard, openvpn, shadowsocks
  final RxBool autoSelectFastest = RxBool(true);
  final RxInt autoTestIntervalMinutes = RxInt(60); // Re-test configs every N minutes
  final RxBool logLocalConnection = RxBool(false);

  SettingsController({Logger? logger}) : _log = logger ?? Logger();

  @override
  void onInit() {
    super.onInit();
    _loadSettings();
    _log.i('SettingsController initialized');
  }

  /// Load settings from storage (future implementation with Hive)
  void _loadSettings() {
    // In production, load from persistent storage
    // For now, use defaults set above
    _log.i('Settings loaded');
  }

  /// Save all settings to storage
  Future<void> saveSettings() async {
    try {
      // In production, save to Hive encrypted box
      _log.i('Settings saved');
    } catch (e) {
      _log.e('Error saving settings: $e');
    }
  }

  /// Toggle auto-connect
  void toggleAutoConnect(bool value) {
    autoConnect.value = value;
    saveSettings();
    _log.i('Auto-connect: $value');
  }

  /// Toggle kill switch
  void toggleKillSwitch(bool value) {
    killSwitchEnabled.value = value;
    saveSettings();
    _log.i('Kill switch: $value');
  }

  /// Toggle split tunneling
  void toggleSplitTunneling(bool value) {
    splitTunnelingEnabled.value = value;
    saveSettings();
    _log.i('Split tunneling: $value');
  }

  /// Add app to split tunneling list
  void addSplitTunnelingApp(String appPackage) {
    if (!splitTunnelingApps.contains(appPackage)) {
      splitTunnelingApps.add(appPackage);
      saveSettings();
      _log.i('Added app to split tunneling: $appPackage');
    }
  }

  /// Remove app from split tunneling list
  void removeSplitTunnelingApp(String appPackage) {
    splitTunnelingApps.remove(appPackage);
    saveSettings();
    _log.i('Removed app from split tunneling: $appPackage');
  }

  /// Set theme
  void setTheme(String themeValue) {
    theme.value = themeValue;
    saveSettings();
    _log.i('Theme set to: $themeValue');
  }

  /// Set preferred protocol
  void setPreferredProtocol(String protocol) {
    preferredProtocol.value = protocol;
    saveSettings();
    _log.i('Preferred protocol set to: $protocol');
  }

  /// Toggle auto-select fastest config
  void toggleAutoSelectFastest(bool value) {
    autoSelectFastest.value = value;
    saveSettings();
    _log.i('Auto-select fastest: $value');
  }

  /// Set auto-test interval
  void setAutoTestInterval(int minutes) {
    autoTestIntervalMinutes.value = minutes;
    saveSettings();
    _log.i('Auto-test interval set to: $minutes minutes');
  }

  /// Set language
  void setLanguage(String languageCode) {
    selectedLanguage.value = languageCode;
    saveSettings();
    _log.i('Language set to: $languageCode');
  }

  /// Toggle analytics
  void toggleAnalytics(bool value) {
    analyticsEnabled.value = value;
    saveSettings();
    _log.i('Analytics: $value');
  }

  /// Toggle notifications
  void toggleNotifications(bool value) {
    showNotifications.value = value;
    saveSettings();
    _log.i('Notifications: $value');
  }

  /// Reset to defaults
  Future<void> resetToDefaults() async {
    autoConnect.value = false;
    killSwitchEnabled.value = false;
    blockNonVPNTraffic.value = false;
    splitTunnelingEnabled.value = false;
    splitTunnelingApps.clear();
    theme.value = 'system';
    showSpeedInTray.value = true;
    showNotifications.value = true;
    selectedLanguage.value = 'en';
    analyticsEnabled.value = false;
    preferredProtocol.value = 'wireguard';
    autoSelectFastest.value = true;
    autoTestIntervalMinutes.value = 60;
    logLocalConnection.value = false;

    await saveSettings();
    _log.i('Settings reset to defaults');
  }

  /// Get all settings as map
  Map<String, dynamic> getAllSettings() {
    return {
      'autoConnect': autoConnect.value,
      'killSwitchEnabled': killSwitchEnabled.value,
      'blockNonVPNTraffic': blockNonVPNTraffic.value,
      'splitTunnelingEnabled': splitTunnelingEnabled.value,
      'splitTunnelingApps': splitTunnelingApps.toList(),
      'theme': theme.value,
      'showSpeedInTray': showSpeedInTray.value,
      'showNotifications': showNotifications.value,
      'selectedLanguage': selectedLanguage.value,
      'analyticsEnabled': analyticsEnabled.value,
      'preferredProtocol': preferredProtocol.value,
      'autoSelectFastest': autoSelectFastest.value,
      'autoTestIntervalMinutes': autoTestIntervalMinutes.value,
      'logLocalConnection': logLocalConnection.value,
    };
  }
}
