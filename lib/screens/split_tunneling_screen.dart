import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../services/split_tunneling_service.dart';

/// Split tunneling picker.
///
/// ## What changed
///
/// This screen used to fall back to a hardcoded list of ten popular apps when
/// the platform returned nothing. Since the platform channel it called had no
/// native handler, that fallback was *always* what the user saw — a picker full
/// of apps that were not on their device, where tapping one appeared to work
/// and did nothing. The list now comes from `PackageManager` or the screen says
/// why it could not be loaded.
///
/// The mode chips were also local `setState` state that was never persisted and
/// never read by anything. They now write through to the service.
class SplitTunnelingScreen extends StatefulWidget {
  const SplitTunnelingScreen({Key? key}) : super(key: key);

  @override
  State<SplitTunnelingScreen> createState() => _SplitTunnelingScreenState();
}

class _SplitTunnelingScreenState extends State<SplitTunnelingScreen> {
  late final SplitTunnelingService _service;
  final TextEditingController _searchController = TextEditingController();

  /// Icons are fetched once per package and kept for the life of the screen.
  final Map<String, Future<Uint8List?>> _iconCache = {};

  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _service = Get.find<SplitTunnelingService>();

    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text.toLowerCase().trim());
    });

    _loadApps();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadApps() async {
    final apps = await _service.fetchInstalledApps();
    if (!mounted) return;
    if (apps.isEmpty && _service.lastError.value != null) {
      Get.snackbar(
        'Could not load apps',
        _service.lastError.value!,
        snackPosition: SnackPosition.BOTTOM,
      );
    }
  }

  Future<Uint8List?> _iconFor(String packageName) =>
      _iconCache.putIfAbsent(packageName, () => _service.getAppIcon(packageName));

  List<TunnelApp> _filteredApps() {
    final apps = _service.installedApps;
    if (_searchQuery.isEmpty) return apps;
    return apps
        .where((app) =>
            app.appName.toLowerCase().contains(_searchQuery) ||
            app.packageName.toLowerCase().contains(_searchQuery))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Split Tunneling Apps'),
        elevation: 0,
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            color: isDark ? theme.cardColor : Colors.grey.shade100,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Obx(() => SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'Enable Split Tunneling',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(_service.describe()),
                      value: _service.isEnabled,
                      onChanged: (val) => _service.setEnabled(val),
                    )),
                Obx(() {
                  if (!_service.requiresReconnect.value || !_service.isEnabled) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline,
                            size: 16, color: theme.colorScheme.primary),
                        const SizedBox(width: 6),
                        const Expanded(
                          child: Text(
                            'Reconnect for this selection to take effect. '
                            'Android fixes the app list when the tunnel opens.',
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
                const Divider(),
                const SizedBox(height: 8),
                const Text('Mode:', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Obx(() => Row(
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
                            selected: _service.mode == 'whitelist',
                            onSelected: (selected) {
                              if (selected) _service.setMode('whitelist');
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
                            selected: _service.mode == 'blacklist',
                            onSelected: (selected) {
                              if (selected) _service.setMode('blacklist');
                            },
                          ),
                        ),
                      ],
                    )),
                const SizedBox(height: 12),
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search installed apps...',
                    prefixIcon: const Icon(Icons.search),
                    isDense: true,
                    border:
                        OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Obx(() {
              if (_service.isLoadingApps.value) {
                return const Center(child: CircularProgressIndicator());
              }

              final apps = _filteredApps();
              if (apps.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _service.installedApps.isEmpty
                          ? (_service.lastError.value ??
                              'No launchable apps were found on this device.')
                          : 'No apps match "$_searchQuery".',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: theme.hintColor),
                    ),
                  ),
                );
              }

              final selected = _service.selectedApps;

              return ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: apps.length,
                separatorBuilder: (context, index) =>
                    const Divider(height: 1, indent: 16, endIndent: 16),
                itemBuilder: (context, index) {
                  final app = apps[index];
                  final isSelected = selected.contains(app.packageName);

                  return CheckboxListTile(
                    value: isSelected,
                    title: Text(
                      app.appName,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      app.packageName,
                      style: TextStyle(fontSize: 12, color: theme.hintColor),
                    ),
                    secondary: _AppIcon(
                      iconFuture: _iconFor(app.packageName),
                      fallbackColor: theme.colorScheme.primary,
                    ),
                    onChanged: (checked) {
                      if (checked == true) {
                        _service.addApp(app.packageName);
                      } else {
                        _service.removeApp(app.packageName);
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

/// Renders a real app icon, falling back to a generic one when the platform
/// could not produce bitmap data.
class _AppIcon extends StatelessWidget {
  final Future<Uint8List?> iconFuture;
  final Color fallbackColor;

  const _AppIcon({required this.iconFuture, required this.fallbackColor});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 40,
      height: 40,
      child: FutureBuilder<Uint8List?>(
        future: iconFuture,
        builder: (context, snapshot) {
          final bytes = snapshot.data;
          if (bytes != null && bytes.isNotEmpty) {
            return ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.memory(bytes, width: 40, height: 40, fit: BoxFit.cover),
            );
          }
          return CircleAvatar(
            backgroundColor: fallbackColor.withOpacity(0.12),
            child: Icon(Icons.android, color: fallbackColor),
          );
        },
      ),
    );
  }
}
