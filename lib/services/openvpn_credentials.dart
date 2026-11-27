import 'dart:convert';
import 'dart:typed_data';

/// One-attempt authentication material. No persistence or printable secrets.
class OpenVpnCredentials {
  static const maxBytes = 4096;
  final Uint8List username;
  final Uint8List password;

  OpenVpnCredentials(String user, String secret)
      : username = Uint8List.fromList(utf8.encode(user)),
        password = Uint8List.fromList(utf8.encode(secret));

  bool get valid => _valid(username) && _valid(password);

  static bool _valid(Uint8List bytes) =>
      bytes.isNotEmpty && bytes.length <= maxBytes && !bytes.contains(0);

  void clear() {
    username.fillRange(0, username.length, 0);
    password.fillRange(0, password.length, 0);
  }

  @override
  String toString() => 'OpenVpnCredentials(redacted)';
}
