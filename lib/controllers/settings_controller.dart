/// Settings controller using GetX for user preferences.
/// Manages app-wide settings like auto-connect, kill switch, theme, etc.
/// Persisted locally via Hive box.

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:logger/logger.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../services/localization_service.dart';
import '../services/debug_service.dart';

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

  /// 'whitelist' (only the listed apps are tunnelled) or 'blacklist' (the
  /// listed apps bypass the tunnel). Persisted because it is a real builder-time
  /// input, not a UI-only preference.
  final RxString splitTunnelingMode = RxString('blacklist');

  /// Force DNS through the tunnel and resolve via the core, so queries cannot
  /// fall back to the carrier resolver.
  final RxBool dnsLeakPreventionEnabled = RxBool(false);

  /// Resolver used when [dnsLeakPreventionEnabled] is on.
  final RxString customDnsServer = RxString('1.1.1.1');

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

  /// Site check: after the TCP latency probe, qualifying candidates are
  /// started in a headless core instance and the URLs below are fetched
  /// *through* them, so a config is judged by real reachability and not just
  /// by a TCP handshake to its server.
  final RxBool siteCheckEnabled = RxBool(true);

  /// Hosts fetched through the probe tunnel. Stored as plain hostnames;
  /// [sanitizeSiteCheckUrls] normalises whatever the user typed.
  final RxList<String> siteCheckUrls = RxList<String>(defaultSiteCheckUrls);

  /// Default verification hosts. The user's list: the sites they actually
  /// want to work, plus github.com and wikipedia.org — high-uptime, global
  /// anycast fronts that are cheap to fetch and rarely blocked wholesale,
  /// so a config that cannot reach them is broken, not the site.
  static const List<String> defaultSiteCheckUrls = [
    'google.com',
    'gemini.google.com',
    'youtube.com',
    'crunchyroll.com',
    'instagram.com',
    'facebook.com',
    'github.com',
    'wikipedia.org',
  ];

  /// Normalises user input into host entries: lower-case, scheme and path
  /// stripped, empty and duplicate entries removed. Returns the defaults if
  /// nothing usable remains, so an over-eager edit can never empty the check.
  static List<String> sanitizeSiteCheckUrls(Iterable<String> raw) {
    final hosts = <String>[];
    for (final entry in raw) {
      var host = entry.trim().toLowerCase();
      if (host.isEmpty) continue;
      final scheme = RegExp(r'^https?://');
      if (scheme.hasMatch(host)) host = host.replaceFirst(scheme, '');
      // Cut path/query/port: only the host part is the check target.
      host = host.split(RegExp(r'[/?#]')).first;
      host = host.split(':').first;
      // Reject anything that is not a plausible hostname.
      if (!RegExp(r'^[a-z0-9.-]+$').hasMatch(host) ||
          !host.contains('.') ||
          host.startsWith('.') ||
          host.endsWith('.')) {
        continue;
      }
      if (!hosts.contains(host)) hosts.add(host);
    }
    return hosts.isEmpty ? List<String>.from(defaultSiteCheckUrls) : hosts;
  }

  SettingsController({Logger? logger}) : _log = logger ?? Logger();

  /// Best-effort action logging: settings changes are user actions and must
  /// be visible in the logs screen. Logging must never break the action.
  void _action(String action, [Map<String, dynamic>? details]) {
    try {
      Get.find<DebugService>().logAction(action, details);
    } catch (_) {}
  }

  @override
  void onInit() {
    super.onInit();
    _initSettings();
  }

  /// Initialize Hive box and load settings
  Future<void> _initSettings() async {
    try {
      await initializeForTest();
      _log.i('SettingsController initialized with persistent storage');
    } catch (e) {
      _log.e('Error opening settings Hive box: $e');
    }
  }

  @visibleForTesting
  Future<void> initializeForTest() async {
    _settingsBox = await Hive.openBox(_settingsBoxName);
    _loadSettings();
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
      splitTunnelingMode.value =
          _settingsBox.get('splitTunnelingMode', defaultValue: 'blacklist');
      dnsLeakPreventionEnabled.value =
          _settingsBox.get('dnsLeakPreventionEnabled', defaultValue: false);
      customDnsServer.value =
          _settingsBox.get('customDnsServer', defaultValue: '1.1.1.1');

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

      siteCheckEnabled.value = _settingsBox.get('siteCheckEnabled', defaultValue: true);
      final savedUrls = _settingsBox.get('siteCheckUrls');
      siteCheckUrls.value = savedUrls is List && savedUrls.isNotEmpty
          ? sanitizeSiteCheckUrls(savedUrls.cast<String>())
          : List<String>.from(defaultSiteCheckUrls);

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
      await _settingsBox.put('splitTunnelingMode', splitTunnelingMode.value);
      await _settingsBox.put('dnsLeakPreventionEnabled', dnsLeakPreventionEnabled.value);
      await _settingsBox.put('customDnsServer', customDnsServer.value);

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

      await _settingsBox.put('siteCheckEnabled', siteCheckEnabled.value);
      await _settingsBox.put('siteCheckUrls', siteCheckUrls.toList());

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
    _action('setting_auto_connect', {'value': value});
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

  /// Set split tunneling mode ('whitelist' | 'blacklist')
  void setSplitTunnelingMode(String newMode) {
    if (newMode != 'whitelist' && newMode != 'blacklist') {
      _log.w('Ignoring unknown split tunneling mode: $newMode');
      return;
    }
    splitTunnelingMode.value = newMode;
    saveSettings();
    _log.i('Split tunneling mode: $newMode');
  }

  /// Toggle DNS leak prevention
  void toggleDnsLeakPrevention(bool value) {
    dnsLeakPreventionEnabled.value = value;
    saveSettings();
    _log.i('DNS leak prevention: $value');
  }

  /// Set the DNS resolver used while leak prevention is on
  void setCustomDnsServer(String server) {
    customDnsServer.value = server;
    saveSettings();
    _log.i('Custom DNS server: $server');
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
    _action('setting_auto_select_fastest', {'value': value});
  }

  /// Set auto-test interval
  void setAutoTestInterval(int minutes) {
    autoTestIntervalMinutes.value = minutes;
    saveSettings();
    _log.i('Auto-test interval set to: $minutes minutes');
  }

  /// Toggle the site check stage.
  void setSiteCheckEnabled(bool value) {
    siteCheckEnabled.value = value;
    saveSettings();
    _log.i('Site check: $value');
    _action('setting_site_check', {'value': value});
  }

  /// Replace the site-check host list with [raw] (sanitised first).
  void setSiteCheckUrls(Iterable<String> raw) {
    final hosts = sanitizeSiteCheckUrls(raw);
    siteCheckUrls.assignAll(hosts);
    saveSettings();
    _log.i('Site check URLs: $hosts');
    _action('setting_site_check_urls', {'count': hosts.length, 'hosts': hosts});
  }

  /// Reset the site-check host list to the defaults.
  void resetSiteCheckUrls() {
    siteCheckUrls.assignAll(defaultSiteCheckUrls);
    saveSettings();
    _log.i('Site check URLs reset to defaults');
  }

  /// Set the app language.
  ///
  /// [selectedLanguage] is the single source of truth: `main.dart` feeds it to
  /// `GetMaterialApp.locale`, so assigning it re-renders the app in the new
  /// language. There is deliberately no second copy to keep in sync — the old
  /// code also pushed the code into `LocalizationService.currentLanguage`, which
  /// was persisted nowhere and read by nothing.
  void setLanguage(String languageCode) {
    if (!LocalizationService.isSupported(languageCode)) {
      _log.w('Ignoring unsupported language code: $languageCode');
      return;
    }
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
    preferredProtocol.value = 'vless';
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
