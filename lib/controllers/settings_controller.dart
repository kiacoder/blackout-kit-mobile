/// Settings controller using GetX for user preferences.
/// Manages app-wide settings like auto-connect, kill switch, theme, etc.
/// Persisted locally via Hive box.

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:logger/logger.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../services/localization_service.dart';

class SettingsController extends GetxController {
  static const String _settingsBoxName = 'settings';
  late Box _settingsBox;
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
  final RxBool keepScreenAwake = RxBool(false);

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
    _initSettings();
  }

  /// Initialize Hive box and load settings
  Future<void> _initSettings() async {
    try {
      _settingsBox = await Hive.openBox(_settingsBoxName);
      _loadSettings();
      _log.i('SettingsController initialized with persistent storage');
    } catch (e) {
      _log.e('Error opening settings Hive box: $e');
    }
  }

  /// Load settings from persistent storage
  void _loadSettings() {
    try {
      autoConnect.value = _settingsBox.get('autoConnect', defaultValue: false);
      killSwitchEnabled.value = _settingsBox.get('killSwitchEnabled', defaultValue: false);
      blockNonVPNTraffic.value = _settingsBox.get('blockNonVPNTraffic', defaultValue: false);
      splitTunnelingEnabled.value = _settingsBox.get('splitTunnelingEnabled', defaultValue: false);

      final savedApps = _settingsBox.get('splitTunnelingApps');
      if (savedApps is List) {
        splitTunnelingApps.value = List<String>.from(savedApps);
      }

      theme.value = _settingsBox.get('theme', defaultValue: 'system');
      showSpeedInTray.value = _settingsBox.get('showSpeedInTray', defaultValue: true);
      showNotifications.value = _settingsBox.get('showNotifications', defaultValue: true);
      keepScreenAwake.value = _settingsBox.get('keepScreenAwake', defaultValue: false);
      selectedLanguage.value = _settingsBox.get('selectedLanguage', defaultValue: 'en');
      analyticsEnabled.value = _settingsBox.get('analyticsEnabled', defaultValue: false);

      preferredProtocol.value = _settingsBox.get('preferredProtocol', defaultValue: 'wireguard');
      autoSelectFastest.value = _settingsBox.get('autoSelectFastest', defaultValue: true);
      autoTestIntervalMinutes.value = _settingsBox.get('autoTestIntervalMinutes', defaultValue: 60);
      logLocalConnection.value = _settingsBox.get('logLocalConnection', defaultValue: false);

      // Apply initial theme mode & wakelock
      _applyTheme(theme.value);
      _applyKeepScreenAwake(keepScreenAwake.value);

      _log.i('Settings loaded successfully');
    } catch (e) {
      _log.e('Error loading settings from Hive: $e');
    }
  }

  /// Save all settings to Hive storage
  Future<void> saveSettings() async {
    try {
      await _settingsBox.put('autoConnect', autoConnect.value);
      await _settingsBox.put('killSwitchEnabled', killSwitchEnabled.value);
      await _settingsBox.put('blockNonVPNTraffic', blockNonVPNTraffic.value);
      await _settingsBox.put('splitTunnelingEnabled', splitTunnelingEnabled.value);
      await _settingsBox.put('splitTunnelingApps', splitTunnelingApps.toList());

      await _settingsBox.put('theme', theme.value);
      await _settingsBox.put('showSpeedInTray', showSpeedInTray.value);
      await _settingsBox.put('showNotifications', showNotifications.value);
      await _settingsBox.put('keepScreenAwake', keepScreenAwake.value);
      await _settingsBox.put('selectedLanguage', selectedLanguage.value);
      await _settingsBox.put('analyticsEnabled', analyticsEnabled.value);

      await _settingsBox.put('preferredProtocol', preferredProtocol.value);
      await _settingsBox.put('autoSelectFastest', autoSelectFastest.value);
      await _settingsBox.put('autoTestIntervalMinutes', autoTestIntervalMinutes.value);
      await _settingsBox.put('logLocalConnection', logLocalConnection.value);

      _log.i('Settings saved to storage');
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

  /// Set theme and trigger Get.changeThemeMode
  void setTheme(String themeValue) {
    theme.value = themeValue;
    _applyTheme(themeValue);
    saveSettings();
    _log.i('Theme set to: $themeValue');
  }

  void _applyTheme(String themeValue) {
    if (themeValue == 'light') {
      Get.changeThemeMode(ThemeMode.light);
    } else if (themeValue == 'dark') {
      Get.changeThemeMode(ThemeMode.dark);
    } else {
      Get.changeThemeMode(ThemeMode.system);
    }
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
    if (Get.isRegistered<LocalizationService>()) {
      Get.find<LocalizationService>().setLanguage(languageCode);
    }
    _log.i('Language set to: $languageCode');
  }

  /// Toggle analytics
  void toggleAnalytics(bool value) {
    analyticsEnabled.value = value;
    saveSettings();
    _log.i('Analytics: $value');
  }

  /// Toggle keep screen awake
  void toggleKeepScreenAwake(bool value) {
    keepScreenAwake.value = value;
    _applyKeepScreenAwake(value);
    saveSettings();
    _log.i('Keep screen awake: $value');
  }

  void _applyKeepScreenAwake(bool enabled) {
    try {
      if (enabled) {
        WakelockPlus.enable().catchError((e) {
          _log.w('Wakelock enable failed: $e');
        });
      } else {
        WakelockPlus.disable().catchError((e) {
          _log.w('Wakelock disable failed: $e');
        });
      }
    } catch (e) {
      _log.w('Wakelock error: $e');
    }
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
    keepScreenAwake.value = false;
    selectedLanguage.value = 'en';
    analyticsEnabled.value = false;
    preferredProtocol.value = 'wireguard';
    autoSelectFastest.value = true;
    autoTestIntervalMinutes.value = 60;
    logLocalConnection.value = false;

    _applyTheme('system');
    _applyKeepScreenAwake(false);
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
