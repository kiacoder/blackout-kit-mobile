/// Engine hub - shows which circumvention engines this build can actually run.
///
/// The [EngineRegistry] describes ten engines because that is the catalogue the
/// desktop CLI ships. Only a subset has a runtime bundled into this APK. This
/// screen asks the native layer which protocols are really served and marks the
/// rest as unavailable, instead of presenting the catalogue as if every entry
/// were wired up.
library;
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controllers/config_controller.dart';
import '../models/engine_capability.dart';
import '../services/vpn_service.dart';

class EngineHubScreen extends StatefulWidget {
  const EngineHubScreen({super.key});

  @override
  State<EngineHubScreen> createState() => _EngineHubScreenState();
}

class _EngineHubScreenState extends State<EngineHubScreen> {
  late final ConfigController _configController;

  String _selectedCategory = 'All';

  /// Native capability report. `null` while the query is still in flight.
  EngineAvailability? _availability;

  @override
  void initState() {
    super.initState();
    _configController = Get.find<ConfigController>();
    _loadAvailability();
  }

  Future<void> _loadAvailability() async {
    try {
      final info = await Get.find<VPNService>().getEngineInfo().timeout(const Duration(seconds: 5));
      if (!mounted) return;
      setState(() => _availability = info);
    } catch (_) {
      // The channel is absent on platforms without a native layer. Fall back to
      // "unknown" so the screen degrades to the plain catalogue rather than
      // asserting that everything is broken.
      if (!mounted) return;
      setState(() => _availability = const EngineAvailability.unknown());
    }
  }

  /// True when we have no capability report and therefore cannot judge.
  bool get _capabilityUnknown => _availability == null || !_availability!.isKnown;

  /// An engine is runnable only when this build can serve **every** protocol
  /// the engine advertises. See [engineIsRunnable] for why `any` was wrong.
  bool _isRunnable(EngineCapability engine) {
    if (_capabilityUnknown) return true;
    return engineIsRunnable(engine, _availability!.canConnect);
  }

  /// Real version string for engines whose runtime we ship; the registry's
  /// hardcoded version is only shown when we have nothing better.
  String? _versionFor(EngineCapability engine) {
    if (engine.engine == EngineType.xray && _availability?.xrayVersion != null) {
      return _availability!.xrayVersion;
    }
    if (engine.engine == EngineType.singboxProxy && _availability?.singboxVersion != null) {
      return _availability!.singboxVersion;
    }
    if (_availability?.packagedCapabilities == true) return null;
    return engine.version;
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

  bool _isEndpointGated(EngineCapability engine) {
    final gated = _availability?.endpointGatedProtocols ?? const <String>[];
    return engine.compatibleProtocols.any(gated.contains);
  }

  String _engineStatusDescription(EngineCapability engine) {
    final configurable = _availability?.configurableProtocols ?? const <String>[];
    final endpointGated = _availability?.endpointGatedProtocols ?? const <String>[];
    if (engine.key == 'sni' && configurable.contains('sni')) {
      return endpointGated.contains('sni')
          ? 'SNI relay profiles can be configured; a compatible endpoint/runtime is not available in this build.'.tr
          : 'SNI relay configuration is supported.'.tr;
    }
    if (engine.key == 'mhrv' && configurable.contains('mhrv')) {
      return endpointGated.contains('mhrv')
          ? 'MHRV relay profiles can be configured; a compatible endpoint contract/runtime is not available in this build.'.tr
          : 'MHRV relay configuration is supported.'.tr;
    }
    return engine.description;
  }

  String _engineUnavailableMessage(EngineCapability engine) {
    if (_isEndpointGated(engine)) {
      return 'This profile format is configurable, but this build cannot connect it until a compatible endpoint and runtime are available.'.tr;
    }
    if (engine.compatibleProtocols.any((_availability?.restartRequiredProtocols ?? const <String>[]).contains)) {
      return 'This runtime may require a full app restart before switching engine families.'.tr;
    }
    return 'This engine is not bundled in this build, so it cannot connect. Configs are still listed so you can review them.'.tr;
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

    final allEngines = EngineRegistry.getAll();
    final runnableCount = allEngines.where(_isRunnable).length;

    return Scaffold(
      appBar: AppBar(
        title: Text('engine_hub'.tr),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'Engine information'.tr,
            onPressed: () {
              Get.snackbar(
                'Bundled engines'.tr,
                _availability?.summary ??
                    'Checking which engines are bundled in this build...'.tr,
                backgroundColor: theme.colorScheme.primary,
                colorText: theme.colorScheme.onPrimary,
                duration: const Duration(seconds: 6),
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
            color: isDark ? theme.cardColor : Colors.indigo.withValues(alpha: 0.06),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.memory, color: theme.colorScheme.primary, size: 28),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _availability == null
                                ? 'Checking bundled engines...'.tr
                                : '$runnableCount of ${allEngines.length} Engines Available',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          Text(
                            _capabilityUnknown
                                ? 'Engine support could not be determined on this platform'.tr
                                : _availability?.runtimeRestartRequired == true
                                    ? 'Fully restart the app before switching VPN runtime families.'.tr
                                    : _availability?.packagedCapabilities == true
                                        ? 'Packaged engines; runtime checked at connection.'.tr
                                        : 'Engines without a bundled runtime are shown greyed out'.tr,
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
              // Subscribe even when the selected category has no entries.
              final counts = <String, int>{};
              for (final config in _configController.allConfigs.toList()) {
                counts.update(config.protocol, (count) => count + 1, ifAbsent: () => 1);
              }
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
                      _buildEngineCard(context, engine, counts),
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
        label: Text(label.tr, style: const TextStyle(fontSize: 12)),
        selected: selected,
        onSelected: (val) {
          if (val) setState(() => _selectedCategory = label);
        },
      ),
    );
  }

  Widget _buildEngineCard(BuildContext context, EngineCapability engine, Map<String, int> counts) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final configCount = engine.compatibleProtocols.toSet().fold<int>(0, (sum, protocol) => sum + (counts[protocol] ?? 0));
    final runnable = _isRunnable(engine);
    final catColor = runnable ? _getCategoryColor(engine.category) : theme.disabledColor;
    final version = _versionFor(engine);

    return Card(
      elevation: isDark ? 2 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: runnable && configCount > 0
              ? catColor.withValues(alpha: 0.4)
              : Colors.transparent,
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
                      color: catColor.withValues(alpha: 0.12),
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
                            Flexible(
                              child: Text(
                                engine.localizedName,
                                // Ellipsis alone does not stop soft wrapping:
                                // once the Row squeezes this below one line's
                                // worth of width the name stacks one glyph per
                                // line. Cap it at a single line.
                                maxLines: 1,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: runnable ? null : theme.hintColor,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (!runnable)
                              Flexible(child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: theme.disabledColor.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  _isEndpointGated(engine) ? 'Endpoint gated'.tr : 'Unavailable'.tr,
                                  style: TextStyle(fontSize: 10, color: theme.hintColor),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ))
                            else if (version != null)
                              Flexible(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: theme.disabledColor.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    'v$version',
                                    style: TextStyle(fontSize: 10, color: theme.hintColor),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _engineStatusDescription(engine),
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
                      color: runnable && configCount > 0
                          ? Colors.green.withValues(alpha: 0.15)
                          : theme.disabledColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '$configCount Configs',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: runnable && configCount > 0 ? Colors.green : theme.hintColor,
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
                  Expanded(child: Wrap(
                    spacing: 4,
                    children: engine.compatibleProtocols.map((p) {
                      final protocolServed = !_capabilityUnknown && _availability!.canConnect(p);
                      return Chip(
                        label: Text(
                          p.toUpperCase(),
                          style: TextStyle(
                            fontSize: 9,
                            decoration: protocolServed || _capabilityUnknown
                                ? null
                                : TextDecoration.lineThrough,
                          ),
                        ),
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      );
                    }).toList(),
                  )),
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
    final runnable = _isRunnable(engine);
    final version = _versionFor(engine);

    Get.bottomSheet(
      Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: SingleChildScrollView(
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
                          engine.localizedName,
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'Category: ${engine.category}',
                          style: TextStyle(fontSize: 12, color: theme.hintColor),
                        ),
                      ],
                    ),
                  ),
                  if (runnable && version != null) Chip(label: Text('v$version')),
                ],
              ),
              if (!runnable) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.disabledColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.block, size: 18, color: theme.hintColor),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _engineUnavailableMessage(engine),
                          style: TextStyle(fontSize: 12, color: theme.hintColor),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Text(engine.description, style: const TextStyle(fontSize: 14)),
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 12),
              Text('supported_protocols'.tr, style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                children: engine.compatibleProtocols.map((p) {
                  final served = !_capabilityUnknown && _availability!.canConnect(p);
                  return Chip(
                    label: Text(
                      p.toUpperCase(),
                      style: TextStyle(
                        decoration: served || _capabilityUnknown
                            ? null
                            : TextDecoration.lineThrough,
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
              Text('requirements'.tr, style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              for (final req in engine.requirements)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Icon(
                        runnable ? Icons.check : Icons.close,
                        size: 16,
                        color: runnable ? Colors.green : theme.disabledColor,
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: Text(req, style: const TextStyle(fontSize: 12))),
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
                      'Filter Applied'.tr,
                      'Filtered library by ${engine.localizedName}',
                      backgroundColor: Colors.indigo,
                      colorText: Colors.white,
                    );
                  },
                  icon: const Icon(Icons.filter_list),
                  label: Text(
                    'Filter Library by ${engine.localizedName} ($configCount configs)',
                  ),
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
      ),
    );
  }
}
