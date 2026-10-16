/// Library screen - Browse, filter, and manage VPN configs
/// Shows all loaded configs with filtering by protocol/source/speed
/// Allows quick connect, view details, or delete configs

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controllers/config_controller.dart';
import '../controllers/connection_controller.dart';
import '../models/config.dart';
import '../models/test_result.dart';
import '../widgets/config_tile.dart';
import 'config_import_screen.dart';
import 'speed_test_screen.dart';
import 'config_editor_screen.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({Key? key}) : super(key: key);

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  late final ConfigController _configController;
  late final ConnectionController _connectionController;

  @override
  void initState() {
    super.initState();
    _configController = Get.find<ConfigController>();
    _connectionController = Get.find<ConnectionController>();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Config Library'),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.speed),
            onPressed: () => Get.to(() => const SpeedTestScreen()),
            tooltip: 'Speed Benchmark',
          ),
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            onPressed: () => Get.to(() => const ConfigImportScreen()),
            tooltip: 'Import Config / Scan QR',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () async {
              Get.snackbar(
                'Fetching',
                'Updating repositories and configs...',
                backgroundColor: Theme.of(context).colorScheme.primary,
                colorText: Theme.of(context).colorScheme.onPrimary,
                duration: const Duration(seconds: 2),
              );
              final count = await _configController.fetchFromAllSources(force: true);
              Get.snackbar(
                'Update Complete',
                '$count configs updated',
                backgroundColor: Colors.green,
                colorText: Colors.white,
              );
            },
            tooltip: 'Refresh all sources',
          ),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _showAddCustomSourceDialog,
            tooltip: 'Add custom source',
          ),
        ],
      ),
      body: Column(
        children: [
          // Refresh banner — non-blocking progress for fetch/test work.
          Obx(() {
            if (!_configController.isRefreshing.value) {
              return const SizedBox.shrink();
            }
            return Material(
              color: Theme.of(context).colorScheme.primaryContainer,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _configController.refreshStatus.value.isEmpty
                            ? 'Updating repositories & configs...'
                            : _configController.refreshStatus.value,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
          // Filter bar
          _buildFilterBar(context),
          // Config list
          Expanded(
            child: Obx(() {
              // Only a storage load blocks the list. Network refresh and the
              // reachability tests used to flip the same flag, so opening the
              // Library mid-startup hid thousands of stored configs behind a
              // spinner for minutes. Refresh progress is now a banner instead.
              if (_configController.isLoading.value) {
                return const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('Loading repositories & configs...'),
                    ],
                  ),
                );
              }

              final filtered = _configController.getFilteredConfigs();

              // A fetch that failed used to be indistinguishable from "no
              // configs": both rendered the same empty state, so the user had
              // no way to see *why* the list was blank (or that retrying might
              // fix it). Show the recorded per-source errors instead when the
              // whole library is empty and any source carries one.
              final libraryEmpty = _configController.allConfigs.isEmpty;
              if (filtered.isEmpty && libraryEmpty) {
                final failedSources = _configController.sources
                    .where((s) => s.error != null && s.error!.isNotEmpty)
                    .toList();
                if (failedSources.isNotEmpty) {
                  return _buildErrorState(context, failedSources);
                }
              }

              // Render a window, not the whole list. A real source returns
              // thousands of configs; handing all of them to the builder made
              // opening the library stall.
              final limit = _configController.visibleConfigLimit.value;
              final visibleCount =
                  limit < filtered.length ? limit : filtered.length;
              final remaining = filtered.length - visibleCount;

              if (filtered.isEmpty) {
                return RefreshIndicator(
                  onRefresh: () async {
                    await _configController.fetchFromAllSources(force: true);
                  },
                  child: ListView(
                    children: [
                      SizedBox(
                        height: MediaQuery.of(context).size.height * 0.5,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.folder_open,
                              size: 64,
                              color: Theme.of(context).disabledColor,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No configs found',
                              style: TextStyle(
                                fontSize: 16,
                                color: Theme.of(context).textTheme.bodyMedium?.color,
                              ),
                            ),
                            const SizedBox(height: 8),
                            ElevatedButton.icon(
                              onPressed: () async {
                                final count = await _configController.fetchFromAllSources(force: true);
                                Get.snackbar(
                                  'Configs Fetched',
                                  '$count configs loaded',
                                  backgroundColor: Colors.green,
                                  colorText: Colors.white,
                                );
                              },
                              icon: const Icon(Icons.refresh),
                              label: const Text('Fetch Configs'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }

              return RefreshIndicator(
                onRefresh: () async {
                  await _configController.fetchFromAllSources(force: true);
                },
                child: ListView.builder(
                  padding: const EdgeInsets.all(8),
                  // +1 for the "show more" row when the window is not the whole
                  // list yet.
                  itemCount: visibleCount + (remaining > 0 ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index >= visibleCount) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Center(
                          child: OutlinedButton.icon(
                            onPressed: _configController.showMoreConfigs,
                            icon: const Icon(Icons.expand_more),
                            label: Text(
                              'Show ${ConfigController.configPageSize} more '
                              '— $remaining of ${filtered.length} not shown',
                            ),
                          ),
                        ),
                      );
                    }

                    final config = filtered[index];
                    final result = _configController.testResults[config.getHash()];

                    return ConfigTile(
                      config: config,
                      testResult: result,
                      onTap: () => _showConfigDetails(config, result),
                      onConnect: () => _handleConnect(config),
                      onDelete: () => _handleDelete(config),
                    );
                  },
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  /// Error state for an empty library: names the sources that failed, shows a
  /// short reason each, and offers a retry. Distinct from the plain "no
  /// configs" empty state so a network failure can never look like data loss.
  Widget _buildErrorState(BuildContext context, List<dynamic> failedSources) {
    final theme = Theme.of(context);

    return RefreshIndicator(
      onRefresh: () async {
        await _configController.fetchFromAllSources(force: true);
      },
      child: ListView(
        children: [
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.6,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.cloud_off,
                  size: 64,
                  color: theme.colorScheme.error,
                ),
                const SizedBox(height: 16),
                Text(
                  'Could not load your configs',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: theme.textTheme.bodyMedium?.color,
                  ),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    'Your saved configs are not lost — the update failed. '
                    'Check your connection and try again.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: theme.textTheme.bodySmall?.color,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // The failing sources, with the reason the controller recorded
                // on the model (network error, rate limit, auth, ...).
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final source in failedSources)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.error_outline,
                                  size: 16, color: Colors.red),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '${source.name}: ${source.error}',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  onPressed: () async {
                    await _configController.fetchFromAllSources(force: true);
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final containerColor = isDark
        ? theme.cardColor
        : Colors.grey.shade100;

    final protocols = [
      {'id': 'all', 'label': 'All'},
      {'id': 'vless', 'label': 'VLESS'},
      {'id': 'vmess', 'label': 'VMess'},
      {'id': 'trojan', 'label': 'Trojan'},
      {'id': 'shadowsocks', 'label': 'Shadowsocks'},
      {'id': 'wireguard', 'label': 'WireGuard'},
      {'id': 'hysteria2', 'label': 'Hysteria 2'},
      {'id': 'tuic', 'label': 'TUIC'},
      {'id': 'openvpn', 'label': 'OpenVPN'},
      {'id': 'amneziawg', 'label': 'AmneziaWG'},
      {'id': 'warp', 'label': 'WARP'},
      {'id': 'psiphon', 'label': 'Psiphon'},
    ];

    return Container(
      padding: const EdgeInsets.all(12),
      color: containerColor,
      child: Column(
        children: [
          // Protocol filter
          Obx(() => SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: protocols.map((proto) {
                final id = proto['id']!;
                final label = proto['label']!;
                return _buildFilterChip(
                  label: label,
                  selected: _configController.filterProtocol.value == id,
                  onSelected: () => _configController.filterProtocol.value = id,
                );
              }).toList(),
            ),
          )),
          const SizedBox(height: 12),
          // Sort dropdown
          Obx(() => Row(
            children: [
              Text(
                'Sort by:',
                style: TextStyle(color: theme.textTheme.bodyMedium?.color),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButton<String>(
                  value: _configController.sortBy.value,
                  isExpanded: true,
                  dropdownColor: theme.cardColor,
                  onChanged: (value) {
                    if (value != null) {
                      _configController.sortBy.value = value;
                    }
                  },
                  items: [
                    _buildDropdownItem('speed', 'Speed (fastest first)'),
                    _buildDropdownItem('name', 'Name (A-Z)'),
                    _buildDropdownItem('recently_added', 'Recently added'),
                  ],
                ),
              ),
            ],
          )),
        ],
      ),
    );
  }

  Widget _buildFilterChip({
    required String label,
    required bool selected,
    required VoidCallback onSelected,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: FilterChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onSelected(),
      ),
    );
  }

  DropdownMenuItem<String> _buildDropdownItem(String value, String label) {
    return DropdownMenuItem(
      value: value,
      child: Text(label),
    );
  }

  void _showConfigDetails(Config config, TestResult? result) {
    final theme = Theme.of(context);
    final cardColor = theme.cardColor;

    Get.bottomSheet(
      Obx(() {
        final result = _configController.testResults[config.getHash()];
        final isTesting =
            _configController.testingHashes.contains(config.getHash());
        return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        config.displayName,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        config.protocol.toUpperCase(),
                        style: TextStyle(fontSize: 12, color: theme.hintColor),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isTesting
                        ? Colors.orange.withOpacity(0.2)
                        : result?.isWorking == true
                            ? Colors.green.withOpacity(0.2)
                            : (result != null && !result.isWorking)
                                ? Colors.red.withOpacity(0.2)
                                : Colors.grey.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    isTesting
                        ? '⏳ Testing…'
                        : result?.isWorking == true
                            ? '✓ Working'
                            : (result != null && !result.isWorking)
                                ? '✗ Failed'
                                : '• Untested',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isTesting
                          ? Colors.orange
                          : result?.isWorking == true
                              ? Colors.green
                              : (result != null && !result.isWorking)
                                  ? Colors.red
                                  : Colors.grey,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              '${config.address}:${config.port}',
              style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
            ),
            if (result != null) ...[
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Speed',
                        style: TextStyle(fontSize: 12, color: theme.hintColor),
                      ),
                      Text(
                        // Throughput is never measured — show latency instead
                        // of a perpetual "N/A" Mbps readout.
                        result.latencyMs != null ? '${result.latencyMs}ms' : 'N/A',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Latency',
                        style: TextStyle(fontSize: 12, color: theme.hintColor),
                      ),
                      Text(
                        result.latencyMs != null
                            ? '${result.latencyMs}ms'
                            : 'N/A',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Reliability',
                        style: TextStyle(fontSize: 12, color: theme.hintColor),
                      ),
                      Text(
                        '${result.reliability.toStringAsFixed(0)}%',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
            if (isTesting) ...[
              const SizedBox(height: 16),
              const LinearProgressIndicator(),
              const SizedBox(height: 4),
              Text(
                'Probing ${config.address}:${config.port}…',
                style: TextStyle(fontSize: 11, color: theme.hintColor),
              ),
            ],
            if (result != null && result.isWorking == false) ...[
              const SizedBox(height: 12),
              Text(
                'Last failure: ${result.error ?? 'no response'}',
                style: TextStyle(fontSize: 11, color: theme.colorScheme.error),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Get.back();
                      _handleConnect(config);
                    },
                    icon: const Icon(Icons.vpn_lock),
                    label: const Text('Connect'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: isTesting ? 'Testing…' : 'Test now',
                  onPressed: isTesting
                      ? null
                      : () => _configController.testSingleConfig(config),
                  icon: isTesting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.bolt, size: 28),
                ),
                IconButton(
                  icon: const Icon(Icons.edit_note, size: 28),
                  tooltip: 'Edit & Share QR',
                  onPressed: () {
                    Get.back();
                    Get.to(() => ConfigEditorScreen(config: config));
                  },
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Get.back();
                      _handleDelete(config);
                    },
                    icon: const Icon(Icons.delete),
                    label: const Text('Delete'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
      }),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
    );
  }

  Future<void> _handleConnect(Config config) async {
    final result = _configController.testResults[config.getHash()];
    final success = await _connectionController.connect(
      config,
      testResult: result,
    );

    if (success) {
      Get.snackbar(
        'Connected',
        'Switched to ${config.displayName}',
        backgroundColor: Colors.green,
        colorText: Colors.white,
      );
    } else {
      Get.snackbar(
        'Connection Failed',
        'Could not connect to ${config.displayName}',
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    }
  }

  Future<void> _handleDelete(Config config) async {
    final confirm = await Get.dialog<bool>(
          AlertDialog(
            title: const Text('Delete Config?'),
            content: Text('Remove ${config.displayName}?'),
            actions: [
              TextButton(
                onPressed: () => Get.back(result: false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Get.back(result: true),
                child: const Text('Delete',
                    style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
        ) ??
        false;

    if (confirm) {
      await _configController.deleteConfig(config);
      Get.snackbar(
        'Deleted',
        '${config.displayName} removed',
        backgroundColor: Colors.orange,
        colorText: Colors.white,
      );
    }
  }

  void _showAddCustomSourceDialog() {
    final nameController = TextEditingController();
    final ownerController = TextEditingController();
    final repoController = TextEditingController();
    final branchController = TextEditingController(text: 'main');

    Get.dialog(
      AlertDialog(
        title: const Text('Add Custom Source'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Source Name',
                hintText: 'e.g., My Configs',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ownerController,
              decoration: const InputDecoration(
                labelText: 'GitHub Owner',
                hintText: 'e.g., username',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: repoController,
              decoration: const InputDecoration(
                labelText: 'Repository',
                hintText: 'e.g., vpn-configs',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: branchController,
              decoration: const InputDecoration(
                labelText: 'Branch',
                hintText: 'e.g., main',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final success = await _configController.addCustomSource(
                name: nameController.text,
                owner: ownerController.text,
                repo: repoController.text,
                branch: branchController.text,
              );

              Get.back();

              if (success) {
                Get.snackbar(
                  'Source Added',
                  'Fetching configs...',
                  backgroundColor: Colors.green,
                  colorText: Colors.white,
                );
                // Fetch from new source
                final sources = _configController.sources;
                if (sources.isNotEmpty) {
                  await _configController
                      .fetchFromSource(sources.last);
                }
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }
}
