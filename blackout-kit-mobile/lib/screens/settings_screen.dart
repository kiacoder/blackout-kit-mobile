/// Settings screen - Manage preferences and VPN sources
/// Includes auto-connect, kill switch, theme, language, and more

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controllers/config_controller.dart';
import '../controllers/settings_controller.dart';

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
              ],
            ),
            // Appearance Section
            _buildSection(
              title: 'Appearance',
              children: [
                Obx(() => ListTile(
                  title: const Text('Theme'),
                  subtitle: Text(_getThemeLabel(
                    _settingsController.theme.value,
                  )),
                  onTap: _showThemeDialog,
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
              title: 'General',
              children: [
                Obx(() => ListTile(
                  title: const Text('Language'),
                  subtitle: Text(_getLanguageLabel(
                    _settingsController.selectedLanguage.value,
                  )),
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
              title: 'Protocol',
              children: [
                Obx(() => ListTile(
                  title: const Text('Preferred Protocol'),
                  subtitle: Text(
                    _settingsController.preferredProtocol.value.toUpperCase(),
                  ),
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
                  onTap: _showTestIntervalDialog,
                )),
              ],
            ),
            // Sources Section
            _buildSection(
              title: 'Repositories',
              children: [
                Obx(() {
                  final sources = _configController.sources;
                  return Column(
                    children: [
                      for (final source in sources)
                        ListTile(
                          title: Text(source.name),
                          subtitle: Text(
                            '${source.owner}/${source.repo}',
                            style: const TextStyle(fontSize: 12),
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
                          onTap: () => _showSourceDetails(source),
                        ),
                    ],
                  );
                }),
              ],
            ),
            // Advanced Section
            _buildSection(
              title: 'Advanced',
              children: [
                Obx(() => SwitchListTile(
                  title: const Text('Log Local Connection'),
                  subtitle: const Text('Log connection attempts to local storage'),
                  value: _settingsController.logLocalConnection.value,
                  onChanged: (value) {
                    _settingsController.logLocalConnection.value = value;
                  },
                )),
              ],
            ),
            // About Section
            _buildSection(
              title: 'About',
              children: [
                const ListTile(
                  title: Text('App Version'),
                  subtitle: Text('1.0.0-beta'),
                ),
                ListTile(
                  title: const Text('GitHub'),
                  subtitle: const Text('Open source on GitHub'),
                  onTap: () {
                    Get.snackbar(
                      'GitHub',
                      'Visit: github.com/blackout-kit/blackout-kit-mobile',
                      backgroundColor: Colors.blue,
                      colorText: Colors.white,
                    );
                  },
                ),
                ListTile(
                  title: const Text('Privacy Policy'),
                  onTap: () {
                    Get.snackbar(
                      'Privacy',
                      'No data collection. Open source = transparent.',
                      backgroundColor: Colors.blue,
                      colorText: Colors.white,
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
                child: ElevatedButton(
                  onPressed: _showResetDialog,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Reset to Defaults'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.indigo,
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
      case 'zh':
        return '中文';
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
              title: const Text('System'),
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
        content: Obx(() => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RadioListTile(
              title: const Text('English'),
              value: 'en',
              groupValue: _settingsController.selectedLanguage.value,
              onChanged: (value) {
                if (value != null) _settingsController.setLanguage(value);
                Get.back();
              },
            ),
            RadioListTile(
              title: const Text('Español'),
              value: 'es',
              groupValue: _settingsController.selectedLanguage.value,
              onChanged: (value) {
                if (value != null) _settingsController.setLanguage(value);
                Get.back();
              },
            ),
            RadioListTile(
              title: const Text('Français'),
              value: 'fr',
              groupValue: _settingsController.selectedLanguage.value,
              onChanged: (value) {
                if (value != null) _settingsController.setLanguage(value);
                Get.back();
              },
            ),
          ],
        )),
      ),
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

  void _showSourceDetails(dynamic source) {
    Get.bottomSheet(
      Container(
        padding: const EdgeInsets.all(24),
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
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            if (source.configCount != null) ...[
              const SizedBox(height: 8),
              Text(
                'Configs: ${source.configCount}',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
            if (source.lastFetched != null) ...[
              const SizedBox(height: 8),
              Text(
                'Last fetched: ${_formatDate(source.lastFetched)}',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
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
      backgroundColor: Colors.white,
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
