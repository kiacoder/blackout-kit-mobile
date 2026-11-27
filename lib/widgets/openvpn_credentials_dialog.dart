import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../services/openvpn_credentials.dart';

Future<OpenVpnCredentials?> requestOpenVpnCredentials(BuildContext context) =>
    showDialog<OpenVpnCredentials>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _OpenVpnCredentialsDialog(),
    );

class _OpenVpnCredentialsDialog extends StatefulWidget {
  const _OpenVpnCredentialsDialog();

  @override
  State<_OpenVpnCredentialsDialog> createState() =>
      _OpenVpnCredentialsDialogState();
}

class _OpenVpnCredentialsDialogState extends State<_OpenVpnCredentialsDialog> {
  final _user = TextEditingController();
  final _password = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _user.clear();
    _password.clear();
    _user.dispose();
    _password.dispose();
    super.dispose();
  }

  void _submit() {
    final credentials = OpenVpnCredentials(_user.text, _password.text);
    if (!credentials.valid) {
      credentials.clear();
      setState(() => _error = 'openvpn_auth_invalid'.tr);
      return;
    }
    Navigator.of(context).pop(credentials);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text('openvpn_auth_title'.tr),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('openvpn_auth_once'.tr),
              TextField(
                controller: _user,
                decoration:
                    InputDecoration(labelText: 'openvpn_auth_username'.tr),
                autocorrect: false,
                enableSuggestions: false,
                maxLength: 4096,
              ),
              TextField(
                controller: _password,
                decoration:
                    InputDecoration(labelText: 'openvpn_auth_password'.tr),
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                maxLength: 4096,
                onSubmitted: (_) => _submit(),
              ),
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
