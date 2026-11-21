import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
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
        title: Text('Copy private configurations?'.tr),
        content: Text('export_secret_warning'.tr),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text('Cancel'.tr)),
          TextButton(onPressed: () => Navigator.pop(context, true), child: Text('Copy plaintext'.tr)),
        ],
      ),
    );
    if (consent != true || !mounted) return;
    try {
      await Clipboard.setData(ClipboardData(text: export.content));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Copied. Clear clipboard history after importing.'.tr)),
      );
    } on PlatformException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Clipboard export failed.'.tr)),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('Batch export'.tr)),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('export_scope_warning'.tr),
        const SizedBox(height: 16),
        DropdownButtonFormField<bool>(
          value: _v2rayN,
          items: [
            DropdownMenuItem(value: false, child: Text('Blackout JSON profile list'.tr)),
            DropdownMenuItem(value: true, child: Text('v2rayN share-link list'.tr)),
          ],
          onChanged: (value) => setState(() {
            _v2rayN = value ?? false;
            _prepare();
          }),
        ),
        const SizedBox(height: 16),
        if (_v2rayN)
          Text('export_v2rayn_limitations'.tr),
        if (_error != null) Text(_error!),
        if (_export != null)
          Text('${_export!.included} unique profiles included; ${_export!.omitted} omitted.'),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _export != null && _export!.included > 0 ? _copy : null,
          icon: const Icon(Icons.copy),
          label: Text('Copy export…'.tr),
        ),
      ],
    ),
  );
}
