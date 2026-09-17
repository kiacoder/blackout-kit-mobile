import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../controllers/config_controller.dart';
import '../models/config.dart';

class ConfigImportScreen extends StatefulWidget {
  const ConfigImportScreen({Key? key}) : super(key: key);

  @override
  State<ConfigImportScreen> createState() => _ConfigImportScreenState();
}

class _ConfigImportScreenState extends State<ConfigImportScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  late final ConfigController _configController;
  final TextEditingController _textController = TextEditingController();
  final MobileScannerController _scannerController = MobileScannerController();

  Config? _parsedConfig;
  List<Config> _parsedMultiple = [];
  bool _isScanning = true;
  bool _torchEnabled = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _configController = Get.find<ConfigController>();

    _autoCheckClipboard();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _textController.dispose();
    _scannerController.dispose();
    super.dispose();
  }

  Future<void> _autoCheckClipboard() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      if (data != null && data.text != null && data.text!.isNotEmpty) {
        final text = data.text!.trim();
        final parsed = ConfigParser.parse(text);
        if (parsed != null) {
          setState(() {
            _textController.text = text;
            _parsedConfig = parsed;
          });
        }
      }
    } catch (_) {}
  }

  void _onScanDetect(BarcodeCapture capture) {
    if (!_isScanning) return;

    final barcodes = capture.barcodes;
    for (final barcode in barcodes) {
      if (barcode.rawValue != null && barcode.rawValue!.isNotEmpty) {
        final code = barcode.rawValue!.trim();
        final parsed = ConfigParser.parse(code);
        if (parsed != null) {
          setState(() {
            _isScanning = false;
            _parsedConfig = parsed;
            _textController.text = code;
          });
          HapticFeedback.heavyImpact();
          _showParsedDialog(parsed);
          break;
        }
      }
    }
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['conf', 'ovpn', 'txt', 'json'],
      );

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        String content = '';

        if (file.bytes != null) {
          content = String.fromCharCodes(file.bytes!);
        } else if (file.path != null) {
          content = await File(file.path!).readAsString();
        }

        if (content.isNotEmpty) {
          final filename = file.name;
          final multiple = ConfigParser.parseMultiple(content);
          final single = ConfigParser.parse(content, customName: filename);

          setState(() {
            _textController.text = content;
            _parsedConfig = single;
            _parsedMultiple = multiple;
          });

          if (single != null) {
            _showParsedDialog(single);
          } else if (multiple.isNotEmpty) {
            _showMultipleParsedDialog(multiple);
          } else {
            Get.snackbar(
              'Import Failed',
              'Could not parse a valid VPN config from file',
              backgroundColor: Colors.red,
              colorText: Colors.white,
            );
          }
        }
      }
    } catch (e) {
      Get.snackbar(
        'File Error',
        'Failed to read file: $e',
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    }
  }

  Future<void> _saveConfig(Config config) async {
    final success = await _configController.configService.saveConfig(config);
    if (success) {
      await _configController.loadConfigs();
      Get.back();
      Get.snackbar(
        'Config Saved',
        '${config.displayName} added to Library',
        backgroundColor: Colors.green,
        colorText: Colors.white,
      );
    } else {
      Get.snackbar(
        'Duplicate Config',
        'This configuration already exists in your library',
        backgroundColor: Colors.orange,
        colorText: Colors.white,
      );
    }
  }

  Future<void> _saveMultipleConfigs(List<Config> configs) async {
    final savedCount = await _configController.configService.saveConfigs(configs);
    await _configController.loadConfigs();
    Get.back();
    Get.snackbar(
      'Imported',
      'Successfully added $savedCount configs to Library',
      backgroundColor: Colors.green,
      colorText: Colors.white,
    );
  }

  void _showParsedDialog(Config config) {
    Get.dialog(
      AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.verified, color: Colors.green),
            const SizedBox(width: 8),
            const Text('Valid Config Detected'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              config.displayName,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Chip(
              label: Text(config.protocol.toUpperCase()),
              backgroundColor: Colors.indigo.withOpacity(0.15),
            ),
            const SizedBox(height: 8),
            Text(
              'Address: ${config.address}:${config.port}',
              style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              setState(() => _isScanning = true);
              Get.back();
            },
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            onPressed: () => _saveConfig(config),
            icon: const Icon(Icons.add),
            label: const Text('Add to Library'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  void _showMultipleParsedDialog(List<Config> configs) {
    Get.dialog(
      AlertDialog(
        title: Text('${configs.length} Configs Found'),
        content: SizedBox(
          width: double.maxFinite,
          height: 250,
          child: ListView.builder(
            itemCount: configs.length,
            itemBuilder: (context, index) {
              final c = configs[index];
              return ListTile(
                dense: true,
                title: Text(c.displayName),
                subtitle: Text(c.protocol.toUpperCase()),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => _saveMultipleConfigs(configs),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            child: Text('Import All (${configs.length})'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Import VPN Config'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.qr_code_scanner), text: 'Scan QR'),
            Tab(icon: Icon(Icons.paste), text: 'Clipboard & Text'),
            Tab(icon: Icon(Icons.file_present), text: 'Import File'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // 1. QR Code Scanner Tab
          _buildScannerTab(theme),
          // 2. Clipboard & Text Tab
          _buildClipboardTab(theme),
          // 3. File Import Tab
          _buildFileTab(theme),
        ],
      ),
    );
  }

  Widget _buildScannerTab(ThemeData theme) {
    return Stack(
      children: [
        MobileScanner(
          controller: _scannerController,
          onDetect: _onScanDetect,
        ),
        // Overlay target box
        Center(
          child: Container(
            width: 250,
            height: 250,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.indigoAccent, width: 3),
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
        // Controls bar
        Positioned(
          bottom: 24,
          left: 24,
          right: 24,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black87,
              borderRadius: BorderRadius.circular(30),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton(
                  icon: Icon(
                    _torchEnabled ? Icons.flash_on : Icons.flash_off,
                    color: Colors.white,
                  ),
                  onPressed: () {
                    _scannerController.toggleTorch();
                    setState(() => _torchEnabled = !_torchEnabled);
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.flip_camera_ios, color: Colors.white),
                  onPressed: () => _scannerController.switchCamera(),
                ),
                ElevatedButton.icon(
                  onPressed: () => setState(() => _isScanning = true),
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Rescan'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildClipboardTab(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Paste Configuration Text or URI',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              ElevatedButton.icon(
                onPressed: () async {
                  final data = await Clipboard.getData(Clipboard.kTextPlain);
                  if (data != null && data.text != null) {
                    _textController.text = data.text!;
                    final parsed = ConfigParser.parse(data.text!);
                    setState(() => _parsedConfig = parsed);
                  }
                },
                icon: const Icon(Icons.content_paste, size: 18),
                label: const Text('Paste'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _textController,
            maxLines: 8,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Paste ss://, WireGuard [Interface] config, or OpenVPN .ovpn content here...',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onChanged: (text) {
              final parsed = ConfigParser.parse(text);
              setState(() => _parsedConfig = parsed);
            },
          ),
          const SizedBox(height: 16),
          if (_parsedConfig != null) ...[
            Card(
              color: Colors.green.withOpacity(0.12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: Colors.green, width: 1.2),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle, color: Colors.green, size: 32),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _parsedConfig!.displayName,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            '${_parsedConfig!.protocol.toUpperCase()} • ${_parsedConfig!.address}:${_parsedConfig!.port}',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    ElevatedButton(
                      onPressed: () => _saveConfig(_parsedConfig!),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Import'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFileTab(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.file_open_outlined, size: 80, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            const Text(
              'Import Configuration File',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Supports WireGuard (.conf), OpenVPN (.ovpn), Shadowsocks (.json / .txt)',
              textAlign: TextAlign.center,
              style: TextStyle(color: theme.hintColor),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _pickFile,
              icon: const Icon(Icons.folder_open),
              label: const Text('Browse Files'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
