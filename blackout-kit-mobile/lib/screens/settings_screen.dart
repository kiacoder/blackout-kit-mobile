/// Settings screen - Manage preferences and VPN sources
/// Includes auto-connect, kill switch, theme, language, and more

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controllers/config_controller.dart';
import '../controllers/settings_controller.dart';
import 'logs_screen.dart';
import 'split_tunneling_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final SettingsController _settingsController;
  late final ConfigController _configController;

  @override
  void initState() {
    super.initState();
    _settingsController = Get.find<SettingsController>();
    _configController = Get.find<ConfigController>();
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
          children: [
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
                Obx(() => SwitchListTile(
                  title: const Text('Block Non-VPN Traffic'),
                  subtitle:
                    const Text('Only allow traffic through VPN tunnel'),
                  value: _settingsController.blockNonVPNTraffic.value,
                  onChanged: (value) {
                    _settingsController.blockNonVPNTraffic.value = value;
                  },
                )),
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
                  subtitle: const Text('Display current speed when connected'),
                  value: _settingsController.showSpeedInTray.value,
                  onChanged: (value) {
                    _settingsController.showSpeedInTray.value = value;
                  },
                )),
              ],
            ),
            // General Section
            _buildSection(
              context: context,
              title: 'General',
              children: [
                Obx(() => ListTile(
                  title: const Text('Language'),
                  subtitle: Text(_getLanguageLabel(
                    _settingsController.selectedLanguage.value,
                  )),
                  leading: const Icon(Icons.language),
                  onTap: _showLanguageDialog,
                )),
                Obx(() => SwitchListTile(
                  title: const Text('Show Notifications'),
                  subtitle: const Text('Notify on connection changes'),
                  value: _settingsController.showNotifications.value,
                  onChanged: _settingsController.toggleNotifications,
                )),
                Obx(() => SwitchListTile(
                  title: const Text('Analytics'),
                  subtitle: const Text('Help improve the app (anonymous)'),
                  value: _settingsController.analyticsEnabled.value,
                  onChanged: _settingsController.toggleAnalytics,
                )),
              ],
            ),
            // Protocol Preference Section
            _buildSection(
              context: context,
              title: 'Protocol',
              children: [
                Obx(() => ListTile(
                  title: const Text('Preferred Protocol'),
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
                    '${_settingsController.autoTestIntervalMinutes.value} minutes',
                  ),
                  leading: const Icon(Icons.timer_outlined),
                  onTap: _showTestIntervalDialog,
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
                  return Column(
                    children: [
                      for (final source in sources)
                        ListTile(
                          title: Text(source.name),
                          subtitle: Text(
                            '${source.owner}/${source.repo} (${source.branch})',
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                            ),
                          ),
                          trailing: Obx(() => Switch(
                            value: source.isEnabled,
                            onChanged: (value) async {
                              final updated = source.copyWith(
                                isEnabled: value,
                              );
                              await _configController.configService
                                  .saveSource(updated);
                              await _configController.loadSources();
                            },
                          )),
                          onTap: () => _showSourceDetails(context, source),
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
                Obx(() => SwitchListTile(
                  title: const Text('Log Local Connection'),
                  subtitle: const Text('Log connection attempts to local storage'),
                  value: _settingsController.logLocalConnection.value,
                  onChanged: (value) {
                    _settingsController.logLocalConnection.value = value;
                  },
                )),
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
                const ListTile(
                  title: Text('App Version'),
                  subtitle: Text('1.0.0-beta.1'),
                  leading: Icon(Icons.info_outline),
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
      crossAxisAlignment: CrossAxisAlignment.start,
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

  void _showProtocolDialog() {
    Get.dialog(
      AlertDialog(
        title: const Text('Preferred Protocol'),
        content: Obx(() => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RadioListTile(
              title: const Text('WireGuard'),
              value: 'wireguard',
              groupValue: _settingsController.preferredProtocol.value,
              onChanged: (value) {
                if (value != null) _settingsController.setPreferredProtocol(value);
                Get.back();
              },
            ),
            RadioListTile(
              title: const Text('OpenVPN'),
              value: 'openvpn',
              groupValue: _settingsController.preferredProtocol.value,
              onChanged: (value) {
                if (value != null) _settingsController.setPreferredProtocol(value);
                Get.back();
              },
            ),
            RadioListTile(
              title: const Text('Shadowsocks'),
              value: 'shadowsocks',
              groupValue: _settingsController.preferredProtocol.value,
              onChanged: (value) {
                if (value != null) _settingsController.setPreferredProtocol(value);
                Get.back();
              },
            ),
          ],
        )),
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
              final minutes = int.tryParse(controller.text) ?? 60;
              if (minutes > 0) {
                _settingsController.setAutoTestInterval(minutes);
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
            if (source.configCount != null) ...[
              const SizedBox(height: 8),
              Text(
                'Configs: ${source.configCount}',
                style: TextStyle(fontSize: 12, color: theme.hintColor),
              ),
            ],
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
