/// Settings controller using GetX for user preferences.
/// Manages app-wide settings like auto-connect, kill switch, theme, etc.
/// Persisted locally via Hive box.

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:logger/logger.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../models/dns_provider.dart';
import '../services/localization_service.dart';
import '../services/debug_service.dart';
import '../services/xray_config.dart';

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

  /// Opt-in for the IP/geolocation lookups. The app queried a third-party
  /// service on every connect while its privacy copy said it never phones home;
  /// now nothing leaves the device unless this is on.
  final RxBool showMyLocation = RxBool(false);

  /// Resolver used when [dnsLeakPreventionEnabled] is on.
  ///
  /// This is the *primary* address. It stays the single source of truth for
  /// the address itself so older saved settings keep loading; [dnsProviderKey]
  /// records which catalogue pair it came from, and [dnsSecondaryServer]
  /// carries the second address of that pair.
  final RxString customDnsServer = RxString('1.1.1.1');

  /// Catalogue key of the selected resolver pair ('cloudflare', 'shecan', …).
  /// The value `'custom'` means "use the typed address only".
  final RxString dnsProviderKey = RxString('cloudflare');

  /// Second address of the selected pair. Empty for a single-address choice.
  final RxString dnsSecondaryServer = RxString('1.0.0.1');

  /// Verbose core logs: the generated Xray config logs at 'debug' so the
  /// TUN data path (packet dispositions, routing, DNS) is visible in logcat
  /// through the core's status callback. Diagnosis tool — noisy otherwise.
  final RxBool coreDebugLogs = RxBool(false);

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

  /// The single in-flight load, shared by [onInit] and [initialize].
  ///
  /// Both used to call `_initSettings()` independently, so registering the
  /// controller and then awaiting `initialize()` ran TWO `openBox` + two
  /// `_loadSettings()` passes. The second one landed asynchronously and wrote
  /// stored values back over anything changed in between — a value set right
  /// after `await initialize()` could silently revert, and the extra open kept
  /// the box alive past `Hive.close()` in tests.
  Future<void>? _initFuture;

  @override
  void onInit() {
    super.onInit();
    // Fire-and-forget is fine for the UI, but main() awaits initialize()
    // explicitly before building the services that read these values.
    initialize();
  }

  /// Load persisted settings. Callers that immediately construct something
  /// reading settings (the site-check service, the connection controller's
  /// auto-connect and watchdog setup) must await this first.
  ///
  /// Idempotent: awaiting this after `onInit()` has already started the load
  /// waits for that same load instead of starting a second one.
  Future<void> initialize() => _initFuture ??= _initSettings();

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
    // A corrupt box (interrupted write) used to leave the `late` field
    // unopened: the open failure was swallowed, and the first settings write
    // then crashed with a LateInitializationError. Quarantine-and-reopen
    // keeps the controller usable at the cost of the stored settings.
    try {
      _settingsBox = await Hive.openBox(_settingsBoxName);
    } catch (e) {
      _log.e('Settings box unreadable ($e) - quarantining it');
      await Hive.deleteBoxFromDisk(_settingsBoxName);
      _settingsBox = await Hive.openBox(_settingsBoxName);
    }
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
      dnsProviderKey.value =
          _settingsBox.get('dnsProviderKey', defaultValue: 'cloudflare');
      dnsSecondaryServer.value =
          _settingsBox.get('dnsSecondaryServer', defaultValue: '1.0.0.1');

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
      // This key was written on every save and never read back, so every cold
      // start silently returned the user to "off" and disabled all IP lookups
      // even though they had opted in.
      showMyLocation.value = _settingsBox.get('showMyLocation', defaultValue: false);

      siteCheckEnabled.value = _settingsBox.get('siteCheckEnabled', defaultValue: true);
      final savedUrls = _settingsBox.get('siteCheckUrls');
      siteCheckUrls.value = savedUrls is List && savedUrls.isNotEmpty
          ? sanitizeSiteCheckUrls(savedUrls.cast<String>())
          : List<String>.from(defaultSiteCheckUrls);

      coreDebugLogs.value = _settingsBox.get('coreDebugLogs', defaultValue: false);
      XrayConfigBuilder.coreLogLevel = coreDebugLogs.value ? 'debug' : 'warning';

      // Apply initial theme mode & wakelock
      _applyTheme(theme.value);
      _applyKeepScreenAwake(keepScreenAwake.value);

      _log.i('Settings loaded successfully');
    } catch (e) {
      _log.e('Error loading settings from Hive: $e');
    }
  }

  /// Save all settings to Hive storage.
  ///
  /// Values are captured into a snapshot BEFORE the first await. Writing each
  /// Rx as it is read let a toggle landing mid-save publish an older value
  /// over a newer one, so the stored settings quietly disagreed with the UI.
  Future<void> saveSettings() async {
    final snapshot = {
      'autoConnect': autoConnect.value,
      'killSwitchEnabled': killSwitchEnabled.value,
      'blockNonVPNTraffic': blockNonVPNTraffic.value,
      'splitTunnelingEnabled': splitTunnelingEnabled.value,
      'splitTunnelingApps': splitTunnelingApps.toList(),
      'splitTunnelingMode': splitTunnelingMode.value,
      'dnsLeakPreventionEnabled': dnsLeakPreventionEnabled.value,
      'customDnsServer': customDnsServer.value,
      'dnsProviderKey': dnsProviderKey.value,
      'dnsSecondaryServer': dnsSecondaryServer.value,
      'showMyLocation': showMyLocation.value,
      'theme': theme.value,
      'showSpeedInTray': showSpeedInTray.value,
      'showNotifications': showNotifications.value,
      'keepScreenAwake': keepScreenAwake.value,
      'selectedLanguage': selectedLanguage.value,
      'analyticsEnabled': analyticsEnabled.value,
      'preferredProtocol': preferredProtocol.value,
      'autoSelectFastest': autoSelectFastest.value,
      'autoTestIntervalMinutes': autoTestIntervalMinutes.value,
      'logLocalConnection': logLocalConnection.value,
      'siteCheckEnabled': siteCheckEnabled.value,
      'siteCheckUrls': siteCheckUrls.toList(),
      'coreDebugLogs': coreDebugLogs.value,
    };
    try {
      // If init failed entirely this raises LateInitializationError, which
      // the catch below turns into a log line - settings simply do not save.
      // Every value comes from the snapshot taken above.
      for (final entry in snapshot.entries) {
        await _settingsBox.put(entry.key, entry.value);
      }

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
    // This line did not belong here: toggling DNS leak prevention re-read
    // showMyLocation from storage and overwrote the live value with whatever
    // happened to be persisted, silently flipping an unrelated switch.
    saveSettings();
    _log.i('DNS leak prevention: $value');
  }

  /// Set the DNS resolver used while leak prevention is on.
  ///
  /// Kept for the custom-address path: typing an address means "this one, not
  /// a catalogue pair", so the provider key moves to 'custom' and the
  /// secondary address is cleared.
  void setCustomDnsServer(String server) {
    customDnsServer.value = server;
    dnsProviderKey.value = 'custom';
    dnsSecondaryServer.value = '';
    saveSettings();
    _log.i('Custom DNS server: $server');
  }

  /// Select a resolver pair from [DnsCatalog].
  ///
  /// Writes both addresses: the tunnel advertises the pair, so a dead primary
  /// falls through to the secondary instead of to the carrier resolver.
  void setDnsProvider(String key) {
    final provider = DnsCatalog.byKey(key);
    if (provider == null) {
      _log.w('Ignoring unknown DNS provider: $key');
      return;
    }
    dnsProviderKey.value = provider.key;
    customDnsServer.value = provider.primary;
    dnsSecondaryServer.value = provider.secondary ?? '';
    saveSettings();
    _log.i('DNS provider: ${provider.key} -> ${provider.servers.join(", ")}');
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

  /// Toggle verbose core logging (Xray config log level debug/warning).
  void setCoreDebugLogs(bool value) {
    coreDebugLogs.value = value;
    XrayConfigBuilder.coreLogLevel = value ? 'debug' : 'warning';
    saveSettings();
    _log.i('Core debug logs: $value');
    _action('setting_core_debug_logs', {'value': value});
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
    // The old reset stopped here, so DNS leak prevention, the custom resolver,
    // site checking and core debug logs survived a "Reset to Defaults" and the
    // user was left wondering which of their settings were actually reset.
    dnsLeakPreventionEnabled.value = false;
    // This was set to '', while _loadSettings() defaults the same key to
    // 1.1.1.1. DnsLeakPreventionService treats an empty resolver as invalid,
    // so after a reset the feature could never be turned back on until the
    // user typed an address by hand.
    customDnsServer.value = '1.1.1.1';
    // Reset the pair as well: leaving a stale provider key behind would make
    // the service advertise the old provider's addresses over the reset ones.
    dnsProviderKey.value = 'cloudflare';
    dnsSecondaryServer.value = '1.0.0.1';
    showMyLocation.value = false;
    siteCheckEnabled.value = true;
    siteCheckUrls.value = List<String>.from(defaultSiteCheckUrls);
    coreDebugLogs.value = false;

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
