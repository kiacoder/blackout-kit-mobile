import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controllers/config_controller.dart';
import '../controllers/connection_controller.dart';
import '../models/engine_capability.dart';

class EngineHubScreen extends StatefulWidget {
  const EngineHubScreen({Key? key}) : super(key: key);

  @override
  State<EngineHubScreen> createState() => _EngineHubScreenState();
}

class _EngineHubScreenState extends State<EngineHubScreen> {
  late final ConfigController _configController;

  String _selectedCategory = 'All';

  @override
  void initState() {
    super.initState();
    _configController = Get.find<ConfigController>();
  }

  Map<String, List<EngineCapability>> _getGroupedEngines() {
    final allEngines = EngineRegistry.getAll();
    final map = <String, List<EngineCapability>>{};

    for (final engine in allEngines) {
      if (_selectedCategory != 'All' && engine.category != _selectedCategory) {
        continue;
      }
      map.putIfAbsent(engine.category, () => []).add(engine);
    }
    return map;
  }

  int _getConfigCountForEngine(EngineCapability engine) {
    return _configController.allConfigs.where((c) {
      return engine.compatibleProtocols.contains(c.protocol);
    }).length;
  }

  Color _getCategoryColor(String category) {
    switch (category) {
      case 'Core VPN':
        return Colors.blue;
      case 'Proxy Core':
        return Colors.purple;
      case 'DPI Obfuscation':
        return Colors.orange;
      case 'Relay / Mesh':
        return Colors.teal;
      default:
        return Colors.indigo;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final groupedEngines = _getGroupedEngines();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Blackout Engine Hub'),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'Engine information',
            onPressed: () {
              Get.snackbar(
                'Blackout Kit Engines',
                'All 10 circumvention engines from Blackout CLI are supported',
                backgroundColor: theme.colorScheme.primary,
                colorText: theme.colorScheme.onPrimary,
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Header summary card
          Container(
            padding: const EdgeInsets.all(16),
            color: isDark ? theme.cardColor : Colors.indigo.withOpacity(0.06),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.memory, color: theme.colorScheme.primary, size: 28),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '10 CLI Bypass Engines',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          Text(
                            'Full parity with Blackout Kit desktop & Linux CLI',
                            style: TextStyle(fontSize: 12, color: theme.hintColor),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Filter Categories
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildCategoryChip('All'),
                      _buildCategoryChip('Core VPN'),
                      _buildCategoryChip('Proxy Core'),
                      _buildCategoryChip('DPI Obfuscation'),
                      _buildCategoryChip('Relay / Mesh'),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Engine Cards List
          Expanded(
            child: Obx(() {
              return ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  for (final entry in groupedEngines.entries) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
                      child: Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: _getCategoryColor(entry.key),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            entry.key,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: _getCategoryColor(entry.key),
                            ),
                          ),
                        ],
                      ),
                    ),
                    for (final engine in entry.value) ...[
                      _buildEngineCard(context, engine),
                      const SizedBox(height: 8),
                    ],
                  ],
                ],
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryChip(String label) {
    final selected = _selectedCategory == label;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: ChoiceChip(
        label: Text(label, style: const TextStyle(fontSize: 12)),
        selected: selected,
        onSelected: (val) {
          if (val) setState(() => _selectedCategory = label);
        },
      ),
    );
  }

  Widget _buildEngineCard(BuildContext context, EngineCapability engine) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final configCount = _getConfigCountForEngine(engine);
    final catColor = _getCategoryColor(engine.category);

    return Card(
      elevation: isDark ? 2 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: configCount > 0 ? catColor.withOpacity(0.4) : Colors.transparent,
          width: 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showEngineDetails(context, engine),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: catColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      engine.key.substring(0, 2).toUpperCase(),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: catColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              engine.displayName,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (engine.version != null) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: theme.disabledColor.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  'v${engine.version}',
                                  style: TextStyle(fontSize: 10, color: theme.hintColor),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          engine.description,
                          style: TextStyle(fontSize: 12, color: theme.hintColor),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: configCount > 0 ? Colors.green.withOpacity(0.15) : theme.disabledColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '$configCount Configs',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: configCount > 0 ? Colors.green : theme.hintColor,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Wrap(
                    spacing: 4,
                    children: engine.compatibleProtocols.map((p) {
                      return Chip(
                        label: Text(p.toUpperCase(), style: const TextStyle(fontSize: 9)),
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      );
                    }).toList(),
                  ),
                  Icon(Icons.chevron_right, size: 18, color: theme.hintColor),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showEngineDetails(BuildContext context, EngineCapability engine) {
    final theme = Theme.of(context);
    final configCount = _getConfigCountForEngine(engine);

    Get.bottomSheet(
      Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: theme.cardColor,
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
                        engine.displayName,
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'Category: ${engine.category}',
                        style: TextStyle(fontSize: 12, color: theme.hintColor),
                      ),
                    ],
                  ),
                ),
                if (engine.version != null)
                  Chip(label: Text('v${engine.version}')),
              ],
            ),
            const SizedBox(height: 16),
            Text(engine.description, style: const TextStyle(fontSize: 14)),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 12),
            const Text('Supported Protocols:', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: engine.compatibleProtocols.map((p) => Chip(label: Text(p.toUpperCase()))).toList(),
            ),
            const SizedBox(height: 12),
            const Text('Requirements:', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            for (final req in engine.requirements)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    const Icon(Icons.check, size: 16, color: Colors.green),
                    const SizedBox(width: 8),
                    Text(req, style: const TextStyle(fontSize: 12)),
                  ],
                ),
              ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Get.back();
                  _configController.filterProtocol.value = engine.compatibleProtocols.first;
                  Get.snackbar(
                    'Filter Applied',
                    'Filtered library by ${engine.displayName}',
                    backgroundColor: Colors.indigo,
                    colorText: Colors.white,
                  );
                },
                icon: const Icon(Icons.filter_list),
                label: Text('Filter Library by ${engine.displayName} ($configCount configs)'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.colorScheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
