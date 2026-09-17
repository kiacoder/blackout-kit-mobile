import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../controllers/config_controller.dart';
import '../models/config.dart';

class ConfigEditorScreen extends StatefulWidget {
  final Config config;

  const ConfigEditorScreen({
    Key? key,
    required this.config,
  }) : super(key: key);

  @override
  State<ConfigEditorScreen> createState() => _ConfigEditorScreenState();
}

class _ConfigEditorScreenState extends State<ConfigEditorScreen> {
  late final ConfigController _configController;
  late final TextEditingController _textController;

  bool _isValid = true;

  @override
  void initState() {
    super.initState();
    _configController = Get.find<ConfigController>();
    _textController = TextEditingController(text: widget.config.rawUri);

    _validateContent(_textController.text);
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  void _validateContent(String text) {
    final parsed = ConfigParser.parse(text);
    setState(() {
      _isValid = parsed != null || text.trim().isNotEmpty;
    });
  }

  Future<void> _saveChanges() async {
    final newText = _textController.text.trim();
    if (newText.isEmpty) {
      Get.snackbar(
        'Empty Config',
        'Config text cannot be empty',
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
      return;
    }

    final parsed = ConfigParser.parse(newText);
    if (parsed == null) {
      Get.snackbar(
        'Invalid Syntax',
        'Could not parse configuration syntax',
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
      return;
    }

    // Delete old config hash and save new one
    await _configController.deleteConfig(widget.config);
    await _configController.configService.saveConfig(parsed);
    await _configController.loadConfigs();

    Get.back();
    Get.snackbar(
      'Config Updated',
      'Saved changes for ${parsed.displayName}',
      backgroundColor: Colors.green,
      colorText: Colors.white,
    );
  }

  void _showQrDialog() {
    final content = _textController.text.trim();
    if (content.isEmpty) return;

    Get.dialog(
      AlertDialog(
        title: Text('QR Code - ${widget.config.displayName}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: QrImageView(
                data: content,
                version: QrVersions.auto,
                size: 220.0,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Scan with Blackout Kit or any VPN app to import',
              style: TextStyle(fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: const Text('Close'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: content));
              Get.back();
              Get.snackbar(
                'Copied',
                'Config URI copied to clipboard',
                backgroundColor: Colors.green,
                colorText: Colors.white,
              );
            },
            icon: const Icon(Icons.copy),
            label: const Text('Copy Config'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text('Edit: ${widget.config.displayName}'),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_2),
            tooltip: 'Share QR Code',
            onPressed: _showQrDialog,
          ),
          IconButton(
            icon: const Icon(Icons.copy),
            tooltip: 'Copy config text',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _textController.text));
              Get.snackbar(
                'Copied',
                'Configuration copied to clipboard',
                backgroundColor: Colors.green,
                colorText: Colors.white,
                duration: const Duration(seconds: 2),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.save),
            tooltip: 'Save changes',
            onPressed: _saveChanges,
          ),
        ],
      ),
      body: Column(
        children: [
          // Status bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: isDark ? theme.cardColor : Colors.grey.shade100,
            child: Row(
              children: [
                Icon(
                  _isValid ? Icons.check_circle : Icons.warning_amber_rounded,
                  color: _isValid ? Colors.green : Colors.red,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Text(
                  _isValid ? 'Syntax Valid' : 'Syntax Warning',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: _isValid ? Colors.green : Colors.red,
                  ),
                ),
                const Spacer(),
                Chip(
                  label: Text(widget.config.protocol.toUpperCase(), style: const TextStyle(fontSize: 10)),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
          // Code editor field
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(12),
              color: isDark ? Colors.black45 : Colors.grey.shade50,
              child: TextField(
                controller: _textController,
                maxLines: null,
                keyboardType: TextInputType.multiline,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13,
                  height: 1.4,
                ),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  hintText: 'Enter raw configuration text...',
                ),
                onChanged: _validateContent,
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(12),
        color: isDark ? theme.cardColor : Colors.white,
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _showQrDialog,
                icon: const Icon(Icons.qr_code),
                label: const Text('Show QR Code'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _saveChanges,
                icon: const Icon(Icons.save),
                label: const Text('Save Config'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
