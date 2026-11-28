import 'dart:convert';
import 'dart:typed_data';

/// One-attempt authentication material. No printable secrets. Persistence is explicitly managed by the encrypted library.
class OpenVpnCredentials {
  static const maxBytes = 4096;
  final Uint8List username;
  final Uint8List password;
  final Uint8List keyPassword;
  final bool remember;

  OpenVpnCredentials(String user, String secret,
      {String keySecret = '', this.remember = false})
      : username = Uint8List.fromList(utf8.encode(user)),
        password = Uint8List.fromList(utf8.encode(secret)),
        keyPassword = Uint8List.fromList(utf8.encode(keySecret));

  bool get valid => validFor(interactive: true, encryptedKey: false);

  bool validFor({required bool interactive, required bool encryptedKey}) =>
      (interactive
          ? _valid(username) && _valid(password)
          : username.isEmpty && password.isEmpty) &&
      (encryptedKey ? _valid(keyPassword) : keyPassword.isEmpty);

  static bool _valid(Uint8List bytes) =>
      bytes.isNotEmpty && bytes.length <= maxBytes && !bytes.contains(0);

  void clear() {
    username.fillRange(0, username.length, 0);
    password.fillRange(0, password.length, 0);
    keyPassword.fillRange(0, keyPassword.length, 0);
  }

  @override
  String toString() => 'OpenVpnCredentials(redacted)';
}
