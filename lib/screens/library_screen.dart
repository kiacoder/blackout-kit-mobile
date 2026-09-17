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
          // Filter bar
          _buildFilterBar(context),
          // Config list
          Expanded(
            child: Obx(() {
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
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
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

  Widget _buildFilterBar(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final containerColor = isDark
        ? theme.cardColor
        : Colors.grey.shade100;

    return Container(
      padding: const EdgeInsets.all(12),
      color: containerColor,
      child: Column(
        children: [
          // Protocol filter
          Obx(() => SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildFilterChip(
                  label: 'All',
                  selected: _configController.filterProtocol.value == 'all',
                  onSelected: () =>
                    _configController.filterProtocol.value = 'all',
                ),
                _buildFilterChip(
                  label: 'WireGuard',
                  selected:
                    _configController.filterProtocol.value == 'wireguard',
                  onSelected: () =>
                    _configController.filterProtocol.value = 'wireguard',
                ),
                _buildFilterChip(
                  label: 'OpenVPN',
                  selected:
                    _configController.filterProtocol.value == 'openvpn',
                  onSelected: () =>
                    _configController.filterProtocol.value = 'openvpn',
                ),
                _buildFilterChip(
                  label: 'Shadowsocks',
                  selected:
                    _configController.filterProtocol.value == 'shadowsocks',
                  onSelected: () =>
                    _configController.filterProtocol.value = 'shadowsocks',
                ),
              ],
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
                    color: result?.isWorking == true
                        ? Colors.green.withOpacity(0.2)
                        : Colors.grey.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    result?.isWorking == true ? '✓ Working' : '✗ Untested',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: result?.isWorking == true
                          ? Colors.green
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
                        result.speedMbps != null
                            ? '${result.speedMbps!.toStringAsFixed(1)} Mbps'
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
                const SizedBox(width: 12),
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
      ),
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
