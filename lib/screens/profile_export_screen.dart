import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/config.dart';
import '../services/profile_export_service.dart';

/// Explicit plaintext disclosure; never exports on opening the library.
class ProfileExportScreen extends StatefulWidget {
  final List<Config> profiles;
  const ProfileExportScreen({super.key, required this.profiles});

  @override
  State<ProfileExportScreen> createState() => _ProfileExportScreenState();
}

class _ProfileExportScreenState extends State<ProfileExportScreen> {
  bool _v2rayN = false;
  ProfileExport? _export;
  String? _error;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  void _prepare() {
    try {
      _export = ProfileExportService.build(widget.profiles, v2rayN: _v2rayN);
      _error = null;
    } on FormatException catch (error) {
      _export = null;
      _error = error.message;
    }
  }

  Future<void> _copy() async {
    final export = _export;
    if (export == null || export.included == 0) return;
    final consent = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Copy private configurations?'),
        content: const Text('This includes passwords and private keys. Clipboard history '
            'and other apps may retain them. Only paste into a trusted destination.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Copy plaintext')),
        ],
      ),
    );
    if (consent != true || !mounted) return;
    try {
      await Clipboard.setData(ClipboardData(text: export.content));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Copied. Clear clipboard history after importing.')),
      );
    } on PlatformException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Clipboard export failed.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Batch export')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Exports contain secrets. Nothing is copied until you confirm. '
            'This exports profiles, not connection test results or subscription metadata.'),
        const SizedBox(height: 16),
        DropdownButtonFormField<bool>(
          value: _v2rayN,
          items: const [
            DropdownMenuItem(value: false, child: Text('Blackout JSON profile list')),
            DropdownMenuItem(value: true, child: Text('v2rayN share-link list')),
          ],
          onChanged: (value) => setState(() {
            _v2rayN = value ?? false;
            _prepare();
          }),
        ),
        const SizedBox(height: 16),
        if (_v2rayN)
          const Text('Includes VLESS, VMess, Trojan and Shadowsocks links only. '
              'Your v2rayN/core version must support the transport and cipher. '
              'Use the JSON list or offline factory for omitted profiles; '
              'WireGuard, AmneziaWG and OpenVPN are not converted to proxy links.'),
        if (_error != null) Text(_error!),
        if (_export != null)
          Text('${_export!.included} unique profiles included; ${_export!.omitted} omitted.'),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _export != null && _export!.included > 0 ? _copy : null,
          icon: const Icon(Icons.copy),
          label: const Text('Copy export…'),
        ),
      ],
    ),
  );
}
