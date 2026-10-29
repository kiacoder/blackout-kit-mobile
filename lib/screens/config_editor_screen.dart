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
  // Parsing and validating are different questions. `_isValid` used to mean
  // "the text parses", so a config missing its password still showed a green
  // "Syntax Valid" tick and was only rejected later, with the wrong reason.
  bool _parses = true;

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
      // "non-empty" is not "valid": the old expression ORed the two, so any
      // garbage typed into the box still showed a green "Syntax Valid" tick.
      _parses = parsed != null;
      _isValid = parsed != null && parsed.validate();
    });
  }

  Future<void> _saveChanges() async {
    final newText = _textController.text.trim();
    if (newText.isEmpty) {
      Get.snackbar(
        'Empty Config'.tr,
        'Config text cannot be empty'.tr,
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
      return;
    }

    final parsed = ConfigParser.parse(newText);
    if (parsed == null) {
      Get.snackbar(
        'Invalid Syntax'.tr,
        'Could not parse configuration syntax'.tr,
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
      return;
    }

    // saveConfig() returns false for "duplicate", "invalid" and "storage
    // error" alike, and the caller reported every one of them as "Duplicate
    // Config". Catch the invalid case here, where the reason is known.
    if (!parsed.validate()) {
      Get.snackbar(
        'Incomplete Config'.tr,
        'This config parses but is missing required fields - check the address, the port, and the credentials for this protocol. Nothing was saved.'.tr,
        backgroundColor: Colors.orange,
        colorText: Colors.white,
      );
      return;
    }

    // Nothing actually changed (whitespace-only edit): closing is the honest
    // outcome. Rewriting would churn savedAt and the "recently added" order.
    if (parsed.getHash() == widget.config.getHash()) {
      Get.back();
      return;
    }

    // Order matters. The old code deleted first and saved second: when the
    // save failed (the edited config matched another one already in the
    // library, or the Hive write errored) the original was already gone and
    // the snackbar still claimed success. Store the replacement first, then
    // remove the old record - a failed delete leaves a duplicate, not a loss.
    // Carry the original's attribution over. Saving without it turned an
    // imported config into a "manual" one the moment it was edited.
    final originalSource = _configController.configService.sourceIdFor(widget.config);
    final isDuplicate = _configController.allConfigs
        .any((c) => c.getHash() == parsed.getHash());

    final stored = await _configController.configService
        .saveConfig(parsed, sourceId: originalSource);
    if (!stored) {
      // The two remaining causes are distinguishable now that validation ran
      // above: either the library already holds this exact config, or the
      // write itself failed.
      Get.snackbar(
        isDuplicate ? 'Duplicate Config'.tr : 'Could Not Save'.tr,
        isDuplicate
            ? 'Another config in your library is identical - the original was left untouched'.tr
            : 'The config could not be written to storage. The original was left untouched.'.tr,
        backgroundColor: Colors.orange,
        colorText: Colors.white,
      );
      return;
    }

    await _configController.deleteConfig(widget.config);
    await _configController.loadConfigs();

    Get.back();
    Get.snackbar(
      'Config Updated'.tr,
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
        title: Text('${'qr_code'.tr} - ${widget.config.displayName}'),
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
                // Content too long for one symbol caught nothing before: the
                // widget rendered a blank white square with no explanation, so
                // sharing a long config just produced a useless picture.
                errorStateBuilder: (context, error) {
                  return SizedBox(
                    width: 220,
                    height: 220,
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.qr_code_2,
                                size: 40, color: Colors.orange),
                            const SizedBox(height: 8),
                            Text(
                              'Too long for a QR code'.tr,
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: Colors.orange),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Copy the text and share it instead'.tr,
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Scan with Blackout Kit or any VPN app to import'.tr,
              style: TextStyle(fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: Text('close'.tr),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: content));
              Get.back();
              Get.snackbar(
                'Copied',
                'Config URI copied to clipboard'.tr,
                backgroundColor: Colors.green,
                colorText: Colors.white,
              );
            },
            icon: const Icon(Icons.copy),
            label: Text('copy_config'.tr),
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
        title: Text('${'edit_config'.tr}: ${widget.config.displayName}'),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_2),
            tooltip: 'Share QR Code'.tr,
            onPressed: _showQrDialog,
          ),
          IconButton(
            icon: const Icon(Icons.copy),
            tooltip: 'Copy config text'.tr,
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _textController.text));
              Get.snackbar(
                'Copied',
                'Configuration copied to clipboard'.tr,
                backgroundColor: Colors.green,
                colorText: Colors.white,
                duration: const Duration(seconds: 2),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.save),
            tooltip: 'Save changes'.tr,
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
                  _isValid
                      ? Icons.check_circle
                      : (_parses
                          ? Icons.info_outline
                          : Icons.warning_amber_rounded),
                  color: _isValid
                      ? Colors.green
                      : (_parses ? Colors.orange : Colors.red),
                  size: 18,
                ),
                const SizedBox(width: 8),
                Text(
                  _isValid
                      ? 'Valid Config'.tr
                      : (_parses ? 'Parses, but incomplete'.tr : 'Syntax Error'.tr),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: _isValid
                        ? Colors.green
                        : (_parses ? Colors.orange : Colors.red),
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
                decoration: InputDecoration(
                  border: InputBorder.none,
                  hintText: 'Enter raw configuration text...'.tr,
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
                label: Text('show_qr'.tr),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _saveChanges,
                icon: const Icon(Icons.save),
                label: Text('save_config'.tr),
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
