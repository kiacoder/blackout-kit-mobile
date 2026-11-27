import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../services/openvpn_credentials.dart';

Future<OpenVpnCredentials?> requestOpenVpnCredentials(
  BuildContext context, {
  required bool interactive,
  required bool encryptedKey,
  required bool canRemember,
  OpenVpnCredentials? saved,
}) =>
    showDialog<OpenVpnCredentials>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _OpenVpnCredentialsDialog(
        interactive: interactive,
        encryptedKey: encryptedKey,
        canRemember: canRemember,
        saved: saved,
      ),
    );

class _OpenVpnCredentialsDialog extends StatefulWidget {
  final bool interactive;
  final bool encryptedKey;
  final bool canRemember;
  final OpenVpnCredentials? saved;

  const _OpenVpnCredentialsDialog({
    required this.interactive,
    required this.encryptedKey,
    required this.canRemember,
    this.saved,
  });

  @override
  State<_OpenVpnCredentialsDialog> createState() =>
      _OpenVpnCredentialsDialogState();
}

class _OpenVpnCredentialsDialogState extends State<_OpenVpnCredentialsDialog> {
  late final TextEditingController _user;
  late final TextEditingController _password;
  final _keyPassword = TextEditingController();
  late bool _remember;
  String? _error;

  @override
  void initState() {
    super.initState();
    final saved = widget.saved;
    _user = TextEditingController(
        text: saved == null ? '' : utf8.decode(saved.username));
    _password = TextEditingController(
        text: saved == null ? '' : utf8.decode(saved.password));
    _remember = widget.canRemember && saved != null;
  }

  @override
  void dispose() {
    for (final controller in [_user, _password, _keyPassword]) {
      controller.clear();
      controller.dispose();
    }
    super.dispose();
  }

  void _submit() {
    final credentials = OpenVpnCredentials(_user.text, _password.text,
        keySecret: _keyPassword.text, remember: _remember);
    if (!credentials.validFor(
        interactive: widget.interactive, encryptedKey: widget.encryptedKey)) {
      credentials.clear();
      setState(() => _error = 'openvpn_auth_invalid'.tr);
      return;
    }
    Navigator.of(context).pop(credentials);
  }

  Widget _field(TextEditingController controller, String label,
          {bool secret = true}) =>
      TextField(
        controller: controller,
        decoration: InputDecoration(labelText: label.tr),
        obscureText: secret,
        autocorrect: false,
        enableSuggestions: false,
        maxLength: 4096,
      );

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text('openvpn_auth_title'.tr),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.interactive) ...[
                _field(_user, 'openvpn_auth_username', secret: false),
                _field(_password, 'openvpn_auth_password'),
                if (widget.canRemember)
                  CheckboxListTile(
                    value: _remember,
                    title: Text('openvpn_auth_remember'.tr),
                    onChanged: (value) =>
                        setState(() => _remember = value ?? false),
                  )
                else
                  Text('openvpn_auth_once'.tr),
              ],
              if (widget.encryptedKey) ...[
                _field(_keyPassword, 'openvpn_auth_key_password'),
                Text('openvpn_auth_key_once'.tr),
              ],
              if (_error != null) Text(_error!),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('cancel'.tr),
          ),
          FilledButton(onPressed: _submit, child: Text('connect'.tr)),
        ],
      );
}
