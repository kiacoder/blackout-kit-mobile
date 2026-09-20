import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:logger/logger.dart';

import '../controllers/settings_controller.dart';
import '../models/vpn_session_options.dart';

/// An app that can be routed into or out of the tunnel.
class TunnelApp {
  final String packageName;
  final String appName;
  final bool isSystem;

  TunnelApp({
    required this.packageName,
    required this.appName,
    this.isSystem = false,
  });

  Map<String, dynamic> toMap() => {
        'packageName': packageName,
        'appName': appName,
        'isSystem': isSystem,
      };

  factory TunnelApp.fromMap(Map<dynamic, dynamic> map) => TunnelApp(
        packageName: map['packageName']?.toString() ?? '',
        appName: map['appName']?.toString() ?? '',
        isSystem: map['isSystem'] == true,
      );
}

/// Split tunneling: choose which apps are routed through the tunnel.
///
/// ## What changed
///
/// The old version called four method channels
/// (`enableSplitTunneling`, `activateSplitTunneling`, ...) that had no native
/// handler at all, so every call threw `MissingPluginException` and was
/// swallowed. It also shipped a hardcoded `_demoApps` list that the UI fell
/// back to when the real list came back empty — so the picker looked populated
/// with apps that were not on the device, and selecting one did nothing.
///
/// Neither exists now. The app list comes from `PackageManager`, and the
/// selection is fed into [VpnSessionOptions], which the native layer applies
/// through `Builder.addAllowedApplication` / `addDisallowedApplication`.
///
/// ## Why there is no "activate" any more
///
/// Android freezes the per-app list into the tunnel at `establish()`. There is
/// no API to add or remove an app from a live tunnel. Changing the selection
/// therefore takes effect on the next connect, which is what [requiresReconnect]
/// reports so the UI can say so honestly.
class SplitTunnelingService extends GetxService {
  static const platform = MethodChannel('com.blackoutkit.vpn/network');

  final _logger = Logger();

  final installedApps = RxList<TunnelApp>();
  final isLoadingApps = RxBool(false);
  final lastError = Rxn<String>();

  /// True once a selection has changed while a tunnel is up, meaning the new
  /// selection will not be in force until the user reconnects.
  final requiresReconnect = RxBool(false);

  SettingsController? get _settings =>
      Get.isRegistered<SettingsController>() ? Get.find<SettingsController>() : null;

  bool get isEnabled => _settings?.splitTunnelingEnabled.value ?? false;

  /// 'whitelist' (only selected apps are tunnelled) or 'blacklist' (selected
  /// apps bypass the tunnel).
  String get mode => _settings?.splitTunnelingMode.value ?? 'blacklist';

  List<String> get selectedApps =>
      _settings?.splitTunnelingApps.toList() ?? const [];

  /// Loads the real installed-app list from `PackageManager`.
  ///
  /// Returns an empty list on failure and records [lastError]. It deliberately
  /// does **not** substitute sample data: an empty picker is honest, a picker
  /// full of apps that are not installed is not.
  Future<List<TunnelApp>> fetchInstalledApps({bool includeSystem = false}) async {
    if (isLoadingApps.value) return installedApps.toList();

    isLoadingApps.value = true;
    try {
      _logger.i('Fetching installed apps (includeSystem=$includeSystem)...');

      final result = await platform.invokeMethod<List<Object?>>(
        'getInstalledApps',
        {'includeSystem': includeSystem},
      );

      final apps = (result ?? [])
          .whereType<Map<dynamic, dynamic>>()
          .map(TunnelApp.fromMap)
          .where((app) => app.packageName.isNotEmpty)
          .toList();

      installedApps.assignAll(apps);
      lastError.value = null;
      _logger.i('Loaded ${apps.length} apps');
      return apps;
    } on MissingPluginException {
      lastError.value = 'App listing is not available on this platform.';
      _logger.w('getInstalledApps has no handler on this platform');
      return const [];
    } catch (e) {
      lastError.value = 'Could not list installed apps: $e';
      _logger.e('Error fetching installed apps: $e');
      return const [];
    } finally {
      isLoadingApps.value = false;
    }
  }

  /// PNG bytes for an app icon, fetched one at a time.
  ///
  /// Lazy on purpose: encoding icons for 200 apps up front would push tens of
  /// megabytes across the platform channel to draw a list nobody has scrolled.
  Future<Uint8List?> getAppIcon(String packageName) async {
    try {
      final encoded = await platform.invokeMethod<String>(
        'getAppIcon',
        {'packageName': packageName},
      );
      if (encoded == null || encoded.isEmpty) return null;
      return base64.decode(encoded);
    } catch (e) {
      _logger.w('No icon for $packageName: $e');
      return null;
    }
  }

  // ─────────────────────────── selection ─────────────────────────────────

  Future<void> setEnabled(bool enabled) async {
    final settings = _settings;
    if (settings == null) return;
    settings.toggleSplitTunneling(enabled);
    _markStale();
  }

  Future<void> setMode(String newMode) async {
    if (newMode != 'whitelist' && newMode != 'blacklist') {
      lastError.value = 'Unknown split tunneling mode "$newMode".';
      return;
    }
    final settings = _settings;
    if (settings == null) return;
    settings.setSplitTunnelingMode(newMode);
    _markStale();
  }

  Future<void> addApp(String packageName) async {
    _settings?.addSplitTunnelingApp(packageName);
    _markStale();
  }

  Future<void> removeApp(String packageName) async {
    _settings?.removeSplitTunnelingApp(packageName);
    _markStale();
  }

  Future<void> clearSelection() async {
    final settings = _settings;
    if (settings == null) return;
    settings.splitTunnelingApps.clear();
    await settings.saveSettings();
    _markStale();
  }

  /// Selecting every installed app is almost never what the user wants and can
  /// exceed the per-list cap Android enforces, so it is capped here with a
  /// reason rather than failing later inside `establish()`.
  Future<int> selectAll(List<TunnelApp> apps) async {
    final settings = _settings;
    if (settings == null) return 0;

    final capped = apps.take(VpnSessionOptions.maxAppsPerList).toList();
    for (final app in capped) {
      if (!settings.splitTunnelingApps.contains(app.packageName)) {
        settings.splitTunnelingApps.add(app.packageName);
      }
    }
    await settings.saveSettings();
    _markStale();

    if (apps.length > capped.length) {
      lastError.value =
          'Only the first ${VpnSessionOptions.maxAppsPerList} apps were '
          'selected; Android rejects longer lists.';
    }
    return capped.length;
  }

  void _markStale() {
    // Only meaningful while a tunnel is live.
    requiresReconnect.value = true;
  }

  /// Called by the connection controller once a fresh tunnel is up.
  void clearStaleFlag() => requiresReconnect.value = false;

  /// Translates the current selection into builder-time options.
  ///
  /// Returns [options] untouched when split tunneling is off, and clears any
  /// app list when the selection is empty (an empty allowed-list would mean
  /// "route nothing", which is not what an empty picker means to a user).
  VpnSessionOptions applyTo(VpnSessionOptions options) {
    if (!isEnabled) {
      return options.copyWith(allowedApps: const [], disallowedApps: const []);
    }

    final selected = selectedApps;
    if (selected.isEmpty) {
      return options.copyWith(allowedApps: const [], disallowedApps: const []);
    }

    return switch (mode) {
      'whitelist' => options.copyWith(
          allowedApps: selected,
          disallowedApps: const [],
        ),
      _ => options.copyWith(
          allowedApps: const [],
          disallowedApps: selected,
        ),
    };
  }

  /// Human-readable description of what is currently configured.
  String describe() {
    if (!isEnabled) return 'Off';
    if (selectedApps.isEmpty) return 'On, but no apps selected';
    final label = mode == 'whitelist' ? 'only' : 'all except';
    return 'On - $label ${selectedApps.length} app(s)';
  }

  @override
  void onClose() {
    installedApps.clear();
    super.onClose();
  }
}
