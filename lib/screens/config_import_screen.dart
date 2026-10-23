import 'dart:convert';
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
  bool _isScanning = true;
  bool _torchEnabled = false;
  // Scanner discipline: the camera stream fires continuously while a QR is
  // in view, so every dialog/save path must be single-flight and gated, or
  // dialogs stack on each other faster than they can be dismissed.
  bool _dialogOpen = false;
  bool _saving = false;
  String? _lastCode;
  DateTime? _lastHandledAt;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_handleTabChange);
    _configController = Get.find<ConfigController>();

    _autoCheckClipboard();
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabChange);
    _pauseCamera();
    _scannerController.dispose();
    _tabController.dispose();
    _textController.dispose();
    super.dispose();
  }

  /// Camera helpers. Stopping the camera while a dialog is open is the core
  /// of the stacking fix: a stopped controller emits no detection events, so
  /// nothing can re-pop a dialog while the user is reading or tapping it.
  Future<void> _pauseCamera() async {
    try {
      await _scannerController.stop();
    } catch (_) {}
  }

  Future<void> _resumeCamera() async {
    try {
      await _scannerController.start();
    } catch (_) {}
  }

  /// The scan tab keeps its MobileScanner alive while other tabs are shown;
  /// leaving the tab must pause the camera or detections fire while the user
  /// types on the text tab.
  void _handleTabChange() {
    if (_tabController.indexIsChanging) return;
    if (_tabController.index != 0) {
      _pauseCamera();
    } else if (_isScanning && !_dialogOpen) {
      _resumeCamera();
    }
  }

  /// One entry point for every import path (QR, clipboard, file).
  ///
  /// A QR code can carry a single link, a newline-separated list, a base64
  /// subscription, a `sub://` wrapper, a JSON array of links, or a Markdown
  /// blob with links embedded — [ConfigParser.parseMultiple] understands all of
  /// them, so the scan path uses it first and only falls back to single-parse.
  List<Config> _parsePayload(String code) {
    final multi = ConfigParser.parseMultiple(code);
    if (multi.isNotEmpty) return multi;
    final single = ConfigParser.parse(code);
    return single != null ? <Config>[single] : <Config>[];
  }

  Future<void> _autoCheckClipboard() async {
    if (_dialogOpen || _saving) return;
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      // The clipboard read is an await; the screen can be gone by now.
      if (!mounted) return;
      if (data != null && data.text != null && data.text!.isNotEmpty) {
        final text = data.text!.trim();
        final configs = _parsePayload(text);
        if (configs.length == 1) {
          setState(() {
            _textController.text = text;
            _parsedConfig = configs.first;
          });
        } else if (configs.length > 1) {
          setState(() {
            _textController.text = text;
            _parsedConfig = configs.first;
          });
          // Same single-flight rule the scanner uses: the clipboard is polled
          // on tab changes and resume, so an open dialog plus one more tick
          // stacked a second copy of the same list.
          if (!_dialogOpen && !_saving) {
            _dialogOpen = true;
            _showMultipleParsedDialog(configs).whenComplete(() {
              if (mounted) _dialogOpen = false;
            });
          }
        }
      }
    } catch (_) {}
  }

  void _onScanDetect(BarcodeCapture capture) {
    // Every gate below exists because the camera stream fires continuously
    // while a QR is in view: without them each dismissal instantly spawned
    // the next popup and the dialogs stacked faster than they could be
    // dismissed.
    if (!_isScanning || _dialogOpen || _saving) return;
    if (_tabController.index != 0) return; // scan tab not visible

    final barcodes = capture.barcodes;
    for (final barcode in barcodes) {
      if (barcode.rawValue != null && barcode.rawValue!.isNotEmpty) {
        final code = barcode.rawValue!.trim();

        // The camera is still pointed at the payload we just handled:
        // re-popping the same dialog immediately is the stacking bug. The
        // cooldown only blocks re-detection of the identical payload; a
        // different config, or a deliberate Rescan (which clears it), works.
        final now = DateTime.now();
        if (code == _lastCode &&
            _lastHandledAt != null &&
            now.difference(_lastHandledAt!) < const Duration(seconds: 5)) {
          return;
        }

        final configs = _parsePayload(code);
        if (configs.isEmpty) continue; // not a config — keep scanning

        _lastCode = code;
        _lastHandledAt = now;
        _dialogOpen = true;
        setState(() {
          _isScanning = false;
          _parsedConfig = configs.first;
          _textController.text = code;
        });
        _pauseCamera();
        HapticFeedback.heavyImpact();
        if (configs.length == 1) {
          _showParsedDialog(configs.first);
        } else {
          _showMultipleParsedDialog(configs);
        }
        return;
      }
    }
  }

  Future<void> _pickFile() async {
    if (_dialogOpen || _saving) return; // one import dialog at a time
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['conf', 'ovpn', 'txt', 'json'],
      );

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        String content = '';

        if (file.bytes != null) {
          // String.fromCharCodes maps every byte to a code point, which mangles
          // any UTF-8 config (a Persian or Chinese node name became mojibake
          // before it was ever parsed).
          content = utf8.decode(file.bytes!, allowMalformed: true);
        } else if (file.path != null) {
          content = await File(file.path!).readAsString();
        }

        // Parsing is synchronous and runs on the UI isolate: a huge file would
        // freeze the app. 5 MB is far beyond any real subscription.
        const maxImportBytes = 5 * 1024 * 1024;
        if (content.length > maxImportBytes) {
          if (!mounted) return;
          Get.snackbar(
            'File Too Large',
            'This file is larger than 5 MB - paste the configs instead',
            backgroundColor: Colors.red,
            colorText: Colors.white,
          );
          return;
        }

        if (content.isNotEmpty) {
          // The picker and the file read are both awaits: the user can leave
          // this screen while the system dialog is up, and setState on a
          // disposed State throws.
          if (!mounted) return;
          final filename = file.name;
          final multiple = ConfigParser.parseMultiple(content);
          // A subscription file starts with a URI; parse() then happily treats
          // the ENTIRE multiline payload as one URI, so the first server was
          // offered with the rest of the file swallowed into its raw URI and
          // every other server silently dropped. Multi wins when it finds more.
          final single = multiple.length > 1
              ? null
              : ConfigParser.parse(content, customName: filename);

          setState(() {
            _textController.text = content;
            _parsedConfig = single ?? (multiple.isNotEmpty ? multiple.first : null);
          });

          if (multiple.length > 1) {
            _showMultipleParsedDialog(multiple);
          } else if (single != null) {
            _showParsedDialog(single);
          } else if (multiple.isNotEmpty) {
            _showParsedDialog(multiple.first);
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
    if (_saving) return; // double-tap guard: one save per dialog
    _saving = true;
    try {
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
      // saveConfig() returns false for a duplicate AND for a failed write.
      // Look at what is actually stored before blaming the user for a dupe.
      final alreadyStored = _configController.allConfigs
          .any((c) => c.getHash() == config.getHash());
      Get.snackbar(
        alreadyStored ? 'Duplicate Config' : 'Save Failed',
        alreadyStored
            ? 'This configuration already exists in your library'
            : 'The config could not be written to storage - try again',
        backgroundColor: Colors.orange,
        colorText: Colors.white,
      );
    }
    } finally {
      _saving = false;
    }
  }

  Future<void> _saveMultipleConfigs(List<Config> configs) async {
    if (_saving) return; // double-tap guard
    _saving = true;
    try {
      final savedCount = await _configController.configService.saveConfigs(configs);
      await _configController.loadConfigs();
      Get.back();
      if (savedCount == 0) {
        // Every entry already existed. The old message still said
        // "Successfully added 0 configs", which reads like a success.
        Get.snackbar(
          'Already in Library',
          'All ${configs.length} configs were duplicates - nothing was added',
          backgroundColor: Colors.orange,
          colorText: Colors.white,
        );
        return;
      }
      Get.snackbar(
        'Imported',
        savedCount == configs.length
            ? 'Added $savedCount configs to Library'
            : 'Added $savedCount of ${configs.length} configs '
                '(${configs.length - savedCount} were already in your library)',
        backgroundColor: Colors.green,
        colorText: Colors.white,
      );
    } finally {
      _saving = false;
    }
  }

  Future<void> _showParsedDialog(Config config) async {
    await Get.dialog(
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
            // Scanning stays off after Cancel: the camera is paused and the
            // QR is probably still in view - Rescan resumes deliberately.
            onPressed: () => Get.back(),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            onPressed: _saving ? null : () => _saveConfig(config),
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
    // The dialog is closed (added, imported or cancelled): allow the next one.
    _dialogOpen = false;
    if (mounted) setState(() {});
  }

  Future<void> _showMultipleParsedDialog(List<Config> configs) async {
    await Get.dialog(
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
            onPressed: _saving ? null : () => _saveMultipleConfigs(configs),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            child: Text('Import All (${configs.length})'),
          ),
        ],
      ),
    );
    _dialogOpen = false;
    if (mounted) setState(() {});
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
                  // Toggling the torch on a stopped controller throws.
                  onPressed: (_isScanning && !_dialogOpen)
                      ? () async {
                          // toggleTorch throws on a stopped controller or a
                          // device without a flash unit; the old code flipped
                          // the icon anyway, so the UI claimed a torch that was
                          // never on.
                          try {
                            await _scannerController.toggleTorch();
                            if (!mounted) return;
                            setState(() => _torchEnabled = !_torchEnabled);
                          } catch (_) {
                            if (!mounted) return;
                            setState(() => _torchEnabled = false);
                            Get.snackbar(
                              'Torch Unavailable',
                              'This camera does not expose a torch',
                              backgroundColor: Colors.orange,
                              colorText: Colors.white,
                              duration: const Duration(seconds: 2),
                            );
                          }
                        }
                      : null,
                ),
                IconButton(
                  icon: const Icon(Icons.flip_camera_ios, color: Colors.white),
                  onPressed: (_isScanning && !_dialogOpen)
                      ? () async {
                          try {
                            await _scannerController.switchCamera();
                          } catch (_) {
                            if (!mounted) return;
                            Get.snackbar(
                              'Camera Unavailable',
                              'Could not switch camera',
                              backgroundColor: Colors.orange,
                              colorText: Colors.white,
                              duration: const Duration(seconds: 2),
                            );
                          }
                        }
                      : null,
                ),
                ElevatedButton.icon(
                  onPressed: () {
                    _lastCode = null;
                    _lastHandledAt = null;
                    _dialogOpen = false;
                    setState(() => _isScanning = true);
                    _resumeCamera();
                  },
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
                  final text = data?.text?.trim() ?? '';
                  if (text.isEmpty) return;
                  // This button parsed with ConfigParser.parse(), so a
                  // clipboard holding several links collapsed to the first one
                  // (or to nothing). The text field and the auto-detect path
                  // already use _parsePayload; paste must too.
                  final configs = _parsePayload(text);
                  _textController.text = text;
                  if (configs.isEmpty) {
                    setState(() => _parsedConfig = null);
                    return;
                  }
                  setState(() => _parsedConfig = configs.first);
                  if (configs.length > 1 && !_dialogOpen && !_saving) {
                    _dialogOpen = true;
                    _showMultipleParsedDialog(configs).whenComplete(() {
                      if (mounted) _dialogOpen = false;
                    });
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
              // parseMultiple, not parse: pasting a list of links used to
              // produce ONE config whose raw URI was the whole blob, so every
              // link after the first was silently dropped.
              final configs = _parsePayload(text);
              if (configs.length > 1) {
                setState(() => _parsedConfig = configs.first);
                if (!_dialogOpen && !_saving) {
                  _dialogOpen = true;
                  _showMultipleParsedDialog(configs).whenComplete(() {
                    if (mounted) _dialogOpen = false;
                  });
                }
              } else {
                setState(() =>
                    _parsedConfig = configs.isEmpty ? null : configs.first);
              }
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
