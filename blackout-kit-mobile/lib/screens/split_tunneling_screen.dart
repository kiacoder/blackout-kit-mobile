import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controllers/settings_controller.dart';
import '../services/split_tunneling_service.dart';

class SplitTunnelingScreen extends StatefulWidget {
  const SplitTunnelingScreen({Key? key}) : super(key: key);

  @override
  State<SplitTunnelingScreen> createState() => _SplitTunnelingScreenState();
}

class _SplitTunnelingScreenState extends State<SplitTunnelingScreen> {
  late final SplitTunnelingService _splitTunnelingService;
  late final SettingsController _settingsController;
  final TextEditingController _searchController = TextEditingController();

  String _searchQuery = '';
  String _mode = 'whitelist'; // 'whitelist' or 'blacklist'
  bool _isLoading = false;

  // Mock device apps fallback if platform methodchannel is not available
  final List<TunnelApp> _demoApps = [
    TunnelApp(packageName: 'com.android.chrome', appName: 'Google Chrome', includedInTunnel: false),
    TunnelApp(packageName: 'org.telegram.messenger', appName: 'Telegram', includedInTunnel: true),
    TunnelApp(packageName: 'com.whatsapp', appName: 'WhatsApp', includedInTunnel: true),
    TunnelApp(packageName: 'com.instagram.android', appName: 'Instagram', includedInTunnel: false),
    TunnelApp(packageName: 'com.youtube.android', appName: 'YouTube', includedInTunnel: false),
    TunnelApp(packageName: 'com.twitter.android', appName: 'X / Twitter', includedInTunnel: true),
    TunnelApp(packageName: 'com.spotify.music', appName: 'Spotify', includedInTunnel: false),
    TunnelApp(packageName: 'com.netflix.mediaclient', appName: 'Netflix', includedInTunnel: false),
    TunnelApp(packageName: 'com.discord', appName: 'Discord', includedInTunnel: true),
    TunnelApp(packageName: 'com.github.android', appName: 'GitHub', includedInTunnel: false),
  ];

  @override
  void initState() {
    super.initState();
    _splitTunnelingService = Get.find<SplitTunnelingService>();
    _settingsController = Get.find<SettingsController>();

    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.toLowerCase().trim();
      });
    });

    _loadApps();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadApps() async {
    setState(() => _isLoading = true);
    final apps = await _splitTunnelingService.fetchInstalledApps();
    if (apps.isEmpty) {
      _splitTunnelingService.installedApps.assignAll(_demoApps);
    }
    setState(() => _isLoading = false);
  }

  List<TunnelApp> _getFilteredApps() {
    final apps = _splitTunnelingService.installedApps;
    if (_searchQuery.isEmpty) return apps;

    return apps.where((app) {
      return app.appName.toLowerCase().contains(_searchQuery) ||
          app.packageName.toLowerCase().contains(_searchQuery);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Split Tunneling Apps'),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.select_all),
            tooltip: 'Select all',
            onPressed: () {
              for (final app in _splitTunnelingService.installedApps) {
                _settingsController.addSplitTunnelingApp(app.packageName);
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.deselect),
            tooltip: 'Deselect all',
            onPressed: () {
              _settingsController.splitTunnelingApps.clear();
              _settingsController.saveSettings();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Control Header
          Container(
            padding: const EdgeInsets.all(16),
            color: isDark ? theme.cardColor : Colors.grey.shade100,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Global Switch
                Obx(() => SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Enable Split Tunneling', style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: const Text('Route specific apps inside or outside VPN'),
                  value: _settingsController.splitTunnelingEnabled.value,
                  onChanged: (val) {
                    _settingsController.toggleSplitTunneling(val);
                  },
                )),
                const Divider(),
                const SizedBox(height: 8),
                const Text('Mode:', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                // Mode selector
                Row(
                  children: [
                    Expanded(
                      child: ChoiceChip(
                        label: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.filter_alt_outlined, size: 16),
                            SizedBox(width: 4),
                            Text('Whitelist (VPN Only)'),
                          ],
                        ),
                        selected: _mode == 'whitelist',
                        onSelected: (selected) {
                          if (selected) setState(() => _mode = 'whitelist');
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ChoiceChip(
                        label: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.block_outlined, size: 16),
                            SizedBox(width: 4),
                            Text('Bypass (Direct)'),
                          ],
                        ),
                        selected: _mode == 'blacklist',
                        onSelected: (selected) {
                          if (selected) setState(() => _mode = 'blacklist');
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Search bar
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search installed apps...',
                    prefixIcon: const Icon(Icons.search),
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ],
            ),
          ),
          // App list
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : Obx(() {
                    final apps = _getFilteredApps();
                    final selected = _settingsController.splitTunnelingApps;

                    if (apps.isEmpty) {
                      return Center(
                        child: Text(
                          'No apps found',
                          style: TextStyle(color: theme.hintColor),
                        ),
                      );
                    }

                    return ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: apps.length,
                      separatorBuilder: (context, index) => const Divider(height: 1, indent: 16, endIndent: 16),
                      itemBuilder: (context, index) {
                        final app = apps[index];
                        final isSelected = selected.contains(app.packageName);

                        return CheckboxListTile(
                          value: isSelected,
                          title: Text(app.appName, style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text(app.packageName, style: TextStyle(fontSize: 12, color: theme.hintColor)),
                          secondary: CircleAvatar(
                            backgroundColor: theme.colorScheme.primary.withOpacity(0.12),
                            child: Icon(Icons.android, color: theme.colorScheme.primary),
                          ),
                          onChanged: (checked) {
                            if (checked == true) {
                              _settingsController.addSplitTunnelingApp(app.packageName);
                            } else {
                              _settingsController.removeSplitTunnelingApp(app.packageName);
                            }
                          },
                        );
                      },
                    );
                  }),
          ),
        ],
      ),
    );
  }
}
