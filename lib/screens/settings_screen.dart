/// Settings screen - Manage preferences and VPN sources
/// Includes auto-connect, kill switch, theme, language, and more

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../controllers/config_controller.dart';
import '../controllers/connection_controller.dart';
import '../controllers/settings_controller.dart';
import '../models/dns_provider.dart';
import '../services/ip_info_service.dart';
import '../services/kill_switch_service.dart';
import '../services/update_service.dart';
import '../services/vpn_service.dart';
import 'logs_screen.dart';
import 'split_tunneling_screen.dart';
import 'engine_hub_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final SettingsController _settingsController;
  late final ConfigController _configController;
  String _appVersion = 'Loading…';

  @override
  void initState() {
    super.initState();
    _settingsController = Get.find<SettingsController>();
    _configController = Get.find<ConfigController>();
    _loadAppVersion();
  }

  Future<void> _loadAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() => _appVersion = info.version);
    } catch (_) {
      if (!mounted) return;
      setState(() => _appVersion = 'Unknown');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _UpdateSection(),
            // VPN Settings Section
            _buildSection(
              context: context,
              title: 'VPN Settings',
              children: [
                Obx(() => SwitchListTile(
                  title: const Text('Auto-Connect on Launch'),
                  subtitle:
                    const Text('Automatically connect to VPN when app starts'),
                  value: _settingsController.autoConnect.value,
                  onChanged: _settingsController.toggleAutoConnect,
                )),
                Obx(() => SwitchListTile(
                  title: const Text('Kill Switch'),
                  subtitle: const Text('Block all traffic if VPN disconnects'),
                  value: _settingsController.killSwitchEnabled.value,
                  onChanged: _settingsController.toggleKillSwitch,
                )),
                // Was a switch that could never move (Android owns this
                // setting; there is no API). Now it is what the user actually
                // needs: one tap to the system screen where "Always-on VPN"
                // and "Block connections without VPN" live — the same deep-link
                // the kill-switch flow already uses.
                ListTile(
                  leading: const Icon(Icons.shield_outlined),
                  title: const Text('Block Non-VPN Traffic'),
                  subtitle: const Text(
                    'Managed by Android. Opens system VPN settings for Always-on VPN and “Block connections without VPN”.',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Get.find<KillSwitchService>().openSystemSettings(),
                ),
                Obx(() => SwitchListTile(
                  title: const Text('Split Tunneling'),
                  subtitle: const Text('Route selected apps outside VPN'),
                  value: _settingsController.splitTunnelingEnabled.value,
                  onChanged: _settingsController.toggleSplitTunneling,
                )),
                ListTile(
                  title: const Text('Select Apps for Split Tunneling'),
                  subtitle: Obx(() => Text('${_settingsController.splitTunnelingApps.length} apps selected')),
                  leading: const Icon(Icons.apps),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Get.to(() => const SplitTunnelingScreen());
                  },
                ),
              ],
            ),
            // Appearance Section
            _buildSection(
              context: context,
              title: 'Appearance',
              children: [
                Obx(() => ListTile(
                  title: const Text('Theme'),
                  subtitle: Text(_getThemeLabel(
                    _settingsController.theme.value,
                  )),
                  leading: Icon(
                    _settingsController.theme.value == 'dark'
                        ? Icons.dark_mode
                        : (_settingsController.theme.value == 'light'
                            ? Icons.light_mode
                            : Icons.brightness_auto),
                  ),
                  onTap: _showThemeDialog,
                )),
                Obx(() => SwitchListTile(
                  title: const Text('Keep Screen Awake'),
                  subtitle: const Text('Prevent screen from turning off during config testing or active VPN'),
                  secondary: const Icon(Icons.wb_incandescent_outlined),
                  value: _settingsController.keepScreenAwake.value,
                  onChanged: _settingsController.toggleKeepScreenAwake,
                )),
                Obx(() => SwitchListTile(
                  title: const Text('Show Speed in Status Bar'),
                  // Honest subtitle: the tester measures latency, not throughput.
                  // The old copy promised a live speed the app never produced.
                  subtitle: const Text(
                    'Shows the latency of the selected config in the notification',
                  ),
                  value: _settingsController.showSpeedInTray.value,
                  onChanged: (value) {
                    _settingsController.showSpeedInTray.value = value;
                    _settingsController.saveSettings();
                  },
                )),
              ],
            ),
            // DNS section.
            //
            // The DNS leak prevention service, its settings key, the tunnel
            // plumbing and the README all existed - but no widget ever
            // rendered a control for it, so the feature could not be turned on
            // from the app at all.
            _buildSection(
              context: context,
              title: 'DNS',
              children: [
                Obx(() => SwitchListTile(
                  title: const Text('DNS leak prevention'),
                  subtitle: Text(
                    _settingsController.dnsLeakPreventionEnabled.value
                        ? 'DNS queries are resolved inside the tunnel through '
                            '${_dnsSelectionSummary()}.'
                        : 'Off - your provider can see which domains you resolve.',
                  ),
                  value: _settingsController.dnsLeakPreventionEnabled.value,
                  onChanged: (value) {
                    _settingsController.toggleDnsLeakPrevention(value);
                  },
                )),
                Obx(() => ListTile(
                  title: const Text('DNS resolver'),
                  // Shows the whole pair, not just the primary: the tunnel
                  // advertises both addresses, and hiding the secondary made
                  // the "why is it using 185.51.200.2" question unanswerable.
                  subtitle: Text(_dnsSelectionSummary()),
                  leading: const Icon(Icons.dns_outlined),
                  enabled: _settingsController.dnsLeakPreventionEnabled.value,
                  onTap: _settingsController.dnsLeakPreventionEnabled.value
                      ? _showDnsResolverDialog
                      : null,
                )),
              ],
            ),
            // General Section
            _buildSection(
              context: context,
              title: 'General',
              children: [
                Obx(() => ListTile(
                  title: Text('language'.tr),
                  subtitle: Text(_getLanguageLabel(
                    _settingsController.selectedLanguage.value,
                  )),
                  leading: const Icon(Icons.language),
                  onTap: _showLanguageDialog,
                )),
                // "Analytics" claimed to send anonymous usage data while nothing
                // was ever transmitted anywhere. The toggle is kept as a stored
                // preference, but its description now says exactly that.
                Obx(() => SwitchListTile(
                  title: const Text('Show my location'),
                  subtitle: const Text(
                    'Asks a third-party service for your IP and country. Off by '
                    'default - nothing leaves your device while it is off.',
                  ),
                  value: _settingsController.showMyLocation.value,
                  onChanged: (value) {
                    _settingsController.showMyLocation.value = value;
                    _settingsController.saveSettings();
                    // Apply immediately: the connection controller reads the
                    // service on connect.
                    try {
                      Get.find<IpInfoService>().setLookupsEnabled(value);
                    } catch (_) {}
                    // Turning it off has to take the resolved IPs off the
                    // screen too - the service clears its cache, but the home
                    // screen renders in-memory values that survived. Turning
                    // it back on refreshes them, since nothing else will.
                    try {
                      final connection = Get.find<ConnectionController>();
                      if (value) {
                        connection.refreshHomeIpInfo();
                      } else {
                        connection.clearIpInfo();
                      }
                    } catch (_) {}
                  },
                )),
                Obx(() => SwitchListTile(
                  title: const Text('Analytics'),
                  subtitle: const Text(
                    'No data leaves your device - this only stores your preference',
                  ),
                  value: _settingsController.analyticsEnabled.value,
                  onChanged: _settingsController.toggleAnalytics,
                )),
              ],
            ),
            // Protocol Preference Section
            _buildSection(
              context: context,
              title: 'Protocol & Engines',
              children: [
                ListTile(
                  title: Text('engine_hub'.tr),
                  subtitle: const Text('See which engines this build can actually run'),
                  leading: const Icon(Icons.memory),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Get.to(() => const EngineHubScreen());
                  },
                ),
                Obx(() => ListTile(
                  title: Text('preferred_protocol'.tr),
                  subtitle: Text(
                    _settingsController.preferredProtocol.value.toUpperCase(),
                  ),
                  leading: const Icon(Icons.security),
                  onTap: _showProtocolDialog,
                )),
                Obx(() => SwitchListTile(
                  title: const Text('Auto-Select Fastest'),
                  subtitle:
                    const Text('Automatically use fastest working config'),
                  value: _settingsController.autoSelectFastest.value,
                  onChanged: _settingsController.toggleAutoSelectFastest,
                )),
                Obx(() => ListTile(
                  title: const Text('Auto-Test Interval'),
                  subtitle: Text(
                    '${_settingsController.autoTestIntervalMinutes.value} minutes — '
                    'while the app is open, re-checks that the tunnel still loads '
                    'websites (0 disables)',
                    maxLines: 3,
                  ),
                  leading: const Icon(Icons.timer_outlined),
                  onTap: _showTestIntervalDialog,
                )),
                Obx(() => SwitchListTile(
                  title: const Text('Site Check'),
                  subtitle: const Text(
                    'Verify candidate configs by fetching real websites '
                    'through them, not just pinging the server',
                  ),
                  value: _settingsController.siteCheckEnabled.value,
                  onChanged: _settingsController.setSiteCheckEnabled,
                )),
                Obx(() => SwitchListTile(
                  title: const Text('Verbose core logs'),
                  subtitle: const Text(
                    'Core reports every packet decision to logcat — for '
                    'diagnosing a connected-but-nothing-loads tunnel',
                  ),
                  value: _settingsController.coreDebugLogs.value,
                  onChanged: _settingsController.setCoreDebugLogs,
                )),
                Obx(() => ListTile(
                  title: const Text('Site Check Websites'),
                  subtitle: Text(
                    _settingsController.siteCheckUrls.join(', '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  leading: const Icon(Icons.public),
                  onTap: _showSiteCheckUrlsDialog,
                )),
              ],
            ),
            // Repositories Section
            _buildSection(
              context: context,
              title: 'Repositories',
              children: [
                Obx(() {
                  final sources = _configController.sources;
                  if (sources.isEmpty) {
                    return const ListTile(
                      title: Text('No repositories loaded'),
                    );
                  }
                  // Count for every source in ONE pass. Calling this inside the
                  // per-source loop below re-scanned the whole Hive box once per
                  // repository on every rebuild.
                  final sourceCounts =
                      _configController.configService.countConfigsBySource();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final source in sources)
                        Container(
                          width: double.infinity,
                          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                          decoration: BoxDecoration(
                            color: isDark ? theme.cardColor : Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isDark ? Colors.grey.shade800 : Colors.grey.shade300,
                            ),
                          ),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                            leading: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: (source.isEnabled ? theme.colorScheme.primary : Colors.grey).withOpacity(0.12),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                Icons.source_outlined,
                                color: source.isEnabled ? theme.colorScheme.primary : Colors.grey,
                              ),
                            ),
                            title: Text(
                              source.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                              ),
                            ),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                '${source.owner}/${source.repo} (${source.branch ?? "main"})'
                                ' — ${sourceCounts[source.id] ?? 0} configs',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                                ),
                              ),
                            ),
                            trailing: Switch(
                              value: source.isEnabled,
                              // Goes through the controller, which updates the
                              // observable list and persists. Writing to
                              // configService directly and reloading used to
                              // lose the change: loadSources() merged the
                              // hardcoded defaults ahead of stored state, so
                              // the saved `isEnabled: false` was discarded and
                              // the switch snapped back on.
                              onChanged: (value) =>
                                _configController.toggleSource(source.id, value),
                            ),
                            onTap: () => _showSourceDetails(context, source),
                          ),
                        ),
                    ],
                  );
                }),
              ],
            ),
            // Advanced Section
            _buildSection(
              context: context,
              title: 'Advanced & Diagnostics',
              children: [
                ListTile(
                  title: const Text('System Logs & Inspector'),
                  subtitle: const Text('View, filter, copy, and export real-time application logs'),
                  leading: const Icon(Icons.article_outlined),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Get.to(() => const LogsScreen());
                  },
                ),
              ],
            ),
            // About Section
            _buildSection(
              context: context,
              title: 'About',
              children: [
                ListTile(
                  title: const Text('App Version'),
                  subtitle: Text(_appVersion),
                  leading: const Icon(Icons.info_outline),
                ),
                ListTile(
                  title: const Text('GitHub'),
                  subtitle: const Text('github.com/kiacoder/blackout-kit-mobile'),
                  leading: const Icon(Icons.code),
                  onTap: () {
                    Get.snackbar(
                      'GitHub Repository',
                      'github.com/kiacoder/blackout-kit-mobile',
                      backgroundColor: theme.colorScheme.primary,
                      colorText: theme.colorScheme.onPrimary,
                    );
                  },
                ),
                ListTile(
                  title: const Text('Privacy Policy'),
                  subtitle: const Text('No data collection. Open source & transparent.'),
                  leading: const Icon(Icons.privacy_tip_outlined),
                  onTap: () {
                    Get.snackbar(
                      'Privacy Policy',
                      'No user tracking or data collection.',
                      backgroundColor: theme.colorScheme.primary,
                      colorText: theme.colorScheme.onPrimary,
                    );
                  },
                ),
              ],
            ),
            // Reset Button
            Padding(
              padding: const EdgeInsets.all(24),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _showResetDialog,
                  icon: const Icon(Icons.restore),
                  label: const Text('Reset to Defaults'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection({
    required BuildContext context,
    required String title,
    required List<Widget> children,
  }) {
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: primaryColor,
            ),
          ),
        ),
        ...children,
        const Divider(height: 1),
      ],
    );
  }

  String _getThemeLabel(String theme) {
    switch (theme) {
      case 'light':
        return 'Light';
      case 'dark':
        return 'Dark';
      default:
        return 'System';
    }
  }

  String _getLanguageLabel(String lang) {
    switch (lang) {
      case 'en':
        return 'English';
      case 'es':
        return 'Español';
      case 'fr':
        return 'Français';
      case 'de':
        return 'Deutsch';
      case 'zh':
        return '中文';
      case 'ja':
        return '日本語';
      case 'ru':
        return 'Русский';
      case 'ar':
        return 'العربية';
      case 'pt':
        return 'Português';
      default:
        return 'English';
    }
  }

  void _showThemeDialog() {
    Get.dialog(
      AlertDialog(
        title: const Text('Select Theme'),
        content: Obx(() => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RadioListTile(
              title: const Text('System Default'),
              value: 'system',
              groupValue: _settingsController.theme.value,
              onChanged: (value) {
                if (value != null) _settingsController.setTheme(value);
                Get.back();
              },
            ),
            RadioListTile(
              title: const Text('Light'),
              value: 'light',
              groupValue: _settingsController.theme.value,
              onChanged: (value) {
                if (value != null) _settingsController.setTheme(value);
                Get.back();
              },
            ),
            RadioListTile(
              title: const Text('Dark'),
              value: 'dark',
              groupValue: _settingsController.theme.value,
              onChanged: (value) {
                if (value != null) _settingsController.setTheme(value);
                Get.back();
              },
            ),
          ],
        )),
      ),
    );
  }

  /// One-line description of the resolver pair currently selected.
  String _dnsSelectionSummary() {
    final primary = _settingsController.customDnsServer.value;
    final secondary = _settingsController.dnsSecondaryServer.value;
    final provider = DnsCatalog.byKey(_settingsController.dnsProviderKey.value);
    if (primary.isEmpty) return 'Not set - pick one to enable leak prevention';
    if (provider == null) {
      return secondary.isEmpty ? '$primary (custom)' : '$primary, $secondary (custom)';
    }
    return '${provider.name} — ${provider.servers.join(", ")}';
  }

  /// Picks the resolver pair used while DNS leak prevention is on.
  ///
  /// The list is the shared [DnsCatalog], grouped by category, so the mobile
  /// app and the desktop CLI offer the same addresses. Each row shows both
  /// addresses because both are handed to `VpnService.Builder.addDnsServer`.
  void _showDnsResolverDialog() {
    final controller =
        TextEditingController(text: _settingsController.customDnsServer.value);
    Get.dialog(
      AlertDialog(
        title: const Text('DNS resolver'),
        contentPadding: const EdgeInsets.fromLTRB(0, 12, 0, 0),
        content: SizedBox(
          width: 360,
          height: 420,
          child: StatefulBuilder(
            builder: (context, setDialogState) {
              return Column(
                children: [
                  Expanded(
                    child: ListView(
                      padding: EdgeInsets.zero,
                      children: [
                        for (final category in DnsCategory.values) ...[
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                            child: Text(
                              DnsCatalog.categoryLabels[category]!,
                              style: Theme.of(context).textTheme.labelMedium,
                            ),
                          ),
                          for (final provider
                              in DnsCatalog.inCategory(category))
                            RadioListTile<String>(
                              dense: true,
                              value: provider.key,
                              // ignore: deprecated_member_use
                              groupValue:
                                  _settingsController.dnsProviderKey.value,
                              title: Text(provider.name),
                              subtitle: Text(provider.servers.join('  ·  ')),
                              // ignore: deprecated_member_use
                              onChanged: (value) {
                                if (value == null) return;
                                _settingsController.setDnsProvider(value);
                                setDialogState(() {});
                              },
                            ),
                        ],
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: TextField(
                      controller: controller,
                      keyboardType: TextInputType.url,
                      decoration: const InputDecoration(
                        labelText: 'Custom (IP address)',
                        hintText: '1.1.1.1',
                        isDense: true,
                      ),
                      onSubmitted: (value) {
                        final trimmed = value.trim();
                        if (trimmed.isEmpty) return;
                        _settingsController.setCustomDnsServer(trimmed);
                        setDialogState(() {});
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        actions: [
          TextButton(onPressed: Get.back, child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              final trimmed = controller.text.trim();
              if (trimmed.isNotEmpty &&
                  trimmed != _settingsController.customDnsServer.value) {
                _settingsController.setCustomDnsServer(trimmed);
              }
              Get.back();
            },
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  void _showLanguageDialog() {
    Get.dialog(
      AlertDialog(
        title: const Text('Select Language'),
        content: Obx(() => SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildLangRadio('English', 'en'),
              _buildLangRadio('Español', 'es'),
              _buildLangRadio('Français', 'fr'),
              _buildLangRadio('Deutsch', 'de'),
              _buildLangRadio('中文', 'zh'),
              _buildLangRadio('日本語', 'ja'),
              _buildLangRadio('Русский', 'ru'),
              _buildLangRadio('العربية', 'ar'),
              _buildLangRadio('Português', 'pt'),
            ],
          ),
        )),
      ),
    );
  }

  Widget _buildLangRadio(String label, String code) {
    return RadioListTile<String>(
      title: Text(label),
      value: code,
      groupValue: _settingsController.selectedLanguage.value,
      onChanged: (value) {
        if (value != null) _settingsController.setLanguage(value);
        Get.back();
      },
    );
  }

  /// Protocols the bundled engines (Xray & sing-box) can serve.
  static const List<String> _servedProtocols = [
    'vless',
    'vmess',
    'trojan',
    'shadowsocks',
    'wireguard',
    'hysteria2',
    'tuic',
    'amneziawg',
    'warp',
  ];

  /// Protocols that still require external daemons or non-bundled engines.
  static const List<String> _unbundledProtocols = [
    'openvpn',
    'psiphon',
  ];

  Future<void> _showProtocolDialog() async {
    final availability = await Get.find<VPNService>().getEngineInfo();
    if (!mounted) return;

    // If the native layer could not tell us anything (e.g. running on an
    // unsupported host), do not grey anything out — assume the protocol is
    // fine and let the connection attempt produce the real error.
    final served = availability.isKnown
        ? _servedProtocols.where(availability.canConnect).toList()
        : _servedProtocols;
    final blocked = availability.isKnown
        ? _unbundledProtocols.where((p) => !availability.canConnect(p)).toList()
        : <String>[];

    Get.dialog(
      AlertDialog(
        title: Text('preferred_protocol'.tr),
        content: Obx(() => SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final protocol in served)
                RadioListTile<String>(
                  title: Text(protocol.toUpperCase()),
                  value: protocol,
                  groupValue: _settingsController.preferredProtocol.value,
                  onChanged: (value) {
                    if (value != null) {
                      _settingsController.setPreferredProtocol(value);
                    }
                    Get.back();
                  },
                ),
              if (blocked.isNotEmpty) ...[
                const Divider(height: 24),
                Padding(
                  padding: const EdgeInsets.only(left: 16, bottom: 4),
                  child: Text(
                    'Not available in this build',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).hintColor,
                    ),
                  ),
                ),
                for (final protocol in blocked)
                  ListTile(
                    enabled: false,
                    dense: true,
                    title: Text(protocol.toUpperCase()),
                    subtitle: const Text('Requires the sing-box runtime'),
                  ),
              ],
            ],
          ),
        )),
        actions: [
          TextButton(onPressed: () => Get.back(), child: const Text('Close')),
        ],
      ),
    );
  }

  /// Edit the site-check host list: one host per line (or comma separated).
  /// Saved through the controller's sanitiser, which strips schemes/paths,
  /// drops invalid entries and falls back to the defaults if nothing usable
  /// remains.
  void _showSiteCheckUrlsDialog() {
    final controller = TextEditingController(
      text: _settingsController.siteCheckUrls.join('\n'),
    );

    Get.dialog(
      AlertDialog(
        title: const Text('Site Check Websites'),
        content: SizedBox(
          width: double.maxFinite,
          child: TextField(
            controller: controller,
            maxLines: 8,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'One host per line',
              hintText: 'google.com\nyoutube.com',
              helperText:
                  'Checked through each candidate config. Defaults are '
                  'restored if everything is removed.',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              _settingsController.resetSiteCheckUrls();
              controller.text = _settingsController.siteCheckUrls.join('\n');
            },
            child: const Text('Reset to defaults'),
          ),
          TextButton(
            onPressed: () => Get.back(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              _settingsController.setSiteCheckUrls(
                controller.text.split(RegExp(r'[\n,]')),
              );
              Get.back();
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showTestIntervalDialog() {
    final controller = TextEditingController(
      text: _settingsController.autoTestIntervalMinutes.value.toString(),
    );

    Get.dialog(
      AlertDialog(
        title: const Text('Auto-Test Interval'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Minutes',
            hintText: '60',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              // The subtitle tells the user "0 disables", and the scheduler
              // already treats <= 0 as "no timer" - but this guard rejected 0,
              // so the advertised way to turn the feature off did nothing.
              final parsed = int.tryParse(controller.text.trim());
              if (parsed != null) {
                _settingsController.setAutoTestInterval(parsed < 0 ? 0 : parsed);
              }
              Get.back();
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showSourceDetails(BuildContext context, dynamic source) {
    final theme = Theme.of(context);
    final cardColor = theme.cardColor;
    // One pass over the config box when the sheet opens, instead of the
    // previous per-rebuild scan.
    final sourceCounts =
        _configController.configService.countConfigsBySource();

    Get.bottomSheet(
      Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              source.name,
              // Same reason as the tile above: never soft-wrap a single name
              // down to one glyph per line when width is tight.
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Repository: ${source.owner}/${source.repo}',
              style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
            ),
            const SizedBox(height: 8),
            Text(
              'Branch: ${source.branch}',
              style: TextStyle(fontSize: 12, color: theme.hintColor),
            ),
            const SizedBox(height: 8),
            Text(
              // Live count from the config box, not the source record's stored
              // snapshot: a freshly created source reads 0 from configCount
              // even when its configs are already in the library. Resolved
              // once when the dialog opens rather than on every rebuild.
              'Configs: ${sourceCounts[source.id] ?? 0}',
              style: TextStyle(fontSize: 12, color: theme.hintColor),
            ),
            if (source.lastFetched != null) ...[
              const SizedBox(height: 8),
              Text(
                'Last fetched: ${_formatDate(source.lastFetched)}',
                style: TextStyle(fontSize: 12, color: theme.hintColor),
              ),
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Get.back();
                  _configController.fetchFromSource(source);
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh Configs'),
              ),
            ),
          ],
        ),
      ),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
    );
  }

  void _showResetDialog() {
    Get.dialog(
      AlertDialog(
        title: const Text('Reset to Defaults?'),
        content: const Text(
          'This will reset all settings to their default values. Your saved configs will not be affected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              await _settingsController.resetToDefaults();
              Get.back();
              Get.snackbar(
                'Reset',
                'Settings have been reset to defaults',
                backgroundColor: Colors.green,
                colorText: Colors.white,
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inHours < 1) {
      return '${diff.inMinutes}m ago';
    } else if (diff.inHours < 24) {
      return '${diff.inHours}h ago';
    } else if (diff.inDays < 7) {
      return '${diff.inDays}d ago';
    } else {
      return '${date.month}/${date.day}/${date.year}';
    }
  }
}

/// In-app self-update: checks GitHub Releases, downloads the arm64 APK and
/// hands it to the package installer. Self-contained so the settings screen
/// stays untouched.
class _UpdateSection extends StatefulWidget {
  const _UpdateSection();

  @override
  State<_UpdateSection> createState() => _UpdateSectionState();
}

class _UpdateSectionState extends State<_UpdateSection> {
  final UpdateService _service = UpdateService();
  String _phase = 'idle'; // idle | checking | latest | available | downloading | ready | error
  String _currentVersion = '';
  AppUpdate? _update;
  String _error = '';
  String? _apkPath;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  Future<void> _check() async {
    setState(() {
      _phase = 'checking';
      _error = '';
    });
    try {
      final info = await PackageInfo.fromPlatform();
      _currentVersion = '${info.version}+${info.buildNumber}';
    } catch (_) {
      _currentVersion = '';
    }
    try {
      final update = await _service.checkForUpdate();
      if (!mounted) return;
      setState(() {
        _update = update;
        _phase = update == null ? 'latest' : 'available';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = 'error';
        // "Could not check" is not the same as "up to date" - say which.
        _error = 'Could not check for updates: '
            '${e.toString().replaceFirst('Exception: ', '')}';
      });
    }
  }

  /// Hands the downloaded APK to Android's installer.
  Future<void> _startInstaller() async {
    final path = _apkPath;
    if (path == null) return;
    await _service.installApk(path).catchError((Object e) {
      if (!mounted) return;
      setState(() {
        _phase = 'error';
        _error = 'Could not start the installer: $e';
      });
    });
  }

  Future<void> _downloadAndInstall() async {
    final update = _update;
    if (update == null) return;

    // Reuse a finished download. Tapping Retry after Android asked for the
    // "install unknown apps" permission used to call downloadApk() again,
    // which deletes the file it just fetched and pulls the whole APK a second
    // time - 100+ MB for a permission toggle.
    final existing = _apkPath;
    if (existing != null && File(existing).existsSync()) {
      setState(() => _phase = 'ready');
      await _startInstaller();
      return;
    }

    setState(() => _phase = 'downloading');
    try {
      _apkPath = await _service.downloadApk(update);
      if (!mounted) return;
      setState(() => _phase = 'ready');
      // A refused install permission (or a missing installer) used to throw
      // out of this method with no UI update at all - the tile just sat on
      // "downloading" forever.
      await _startInstaller();
      // The OS installer takes over from here; the app may be replaced.
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = 'error';
        // Exception.toString() prefixes "Exception: "; the message alone reads
        // better in a one-line subtitle.
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Card(
        child: ListTile(
          leading: Icon(
            _phase == 'available'
                ? Icons.system_update_alt
                : Icons.system_update,
            color: _phase == 'available' ? Colors.green : null,
          ),
          // Only the downloading label reads an observable, so only that
          // branch is wrapped in Obx. Wrapping the whole switch meant every
          // other phase built an Obx that observed nothing, which GetX
          // rejects with "improper use of a GetX" - and that exception on
          // every build left the whole Settings screen blank.
          title: _phase == 'downloading'
              ? Obx(() => Text(
                    'Downloading '
                    '${(_service.progress.value * 100).toStringAsFixed(0)}%',
                  ))
              : Text(switch (_phase) {
                  'checking' => 'Checking for updates...',
                  'latest' => 'App is up to date',
                  'available' => 'Update available: ${_update!.tagName}',
                  'ready' => 'Ready to install - tap to open the installer',
                  'error' => 'Update failed',
                  _ => 'App update',
                }),
          // The failure reason (missing install permission, truncated
          // download, ...) is the whole point here, so it gets room to wrap
          // instead of being clipped to one line in the title.
          subtitle: Text(
            _phase == 'error'
                ? _error
                : (_currentVersion.isEmpty
                    ? 'Tap to check for updates'
                    : 'Installed: $_currentVersion'),
            maxLines: 5,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: switch (_phase) {
            'checking' || 'downloading' => const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            'available' => ElevatedButton(
                onPressed: _downloadAndInstall,
                child: const Text('Update'),
              ),
            'ready' => ElevatedButton(
                // _startInstaller, not a bare installApk: the raw call throws
                // on a refused install permission and the tile then sat on
                // "ready" forever with no explanation.
                onPressed: _startInstaller,
                child: const Text('Install'),
              ),
            'error' => TextButton(onPressed: _check, child: const Text('Retry')),
            _ => IconButton(onPressed: _check, icon: const Icon(Icons.refresh)),
          },
        ),
      ),
    );
  }
}
