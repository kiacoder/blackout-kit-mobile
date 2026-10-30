import 'package:flutter/services.dart';

/// Receives configs handed to the app from outside: "Open with" on a
/// .conf/.ovpn attachment (ACTION_VIEW), or a shared vless:// link from the
/// browser share sheet (ACTION_SEND).
///
/// The native side (MainActivity) copies content:// documents into the app
/// cache while the provider grant is still live and hands over a real path —
/// content URIs are NOT filesystem paths and must never reach dart:io.
/// Poll, don't stream: the cold-start payload is queued in a static holder
/// before the Flutter engine exists, and warm intents (singleTop onNewIntent)
/// land in the same slot, so a single `consumePending` call on launch and on
/// every app-resume covers both.
class IntentService {
  IntentService._();

  static const MethodChannel _channel =
      MethodChannel('com.blackoutkit.vpn/intent');

  /// Returns and clears the pending payload, or null.
  /// Shapes: {'type': 'text', 'text': 'vless://…'} or
  /// {'type': 'file', 'path': '/data/.../cache/import-….cfg'}.
  static Future<Map<String, String>?> consumePending() async {
    try {
      final result = await _channel.invokeMethod('consumePending');
      if (result is Map) {
        return result.map((k, v) => MapEntry(k.toString(), v.toString()));
      }
      return null;
    } on PlatformException {
      return null;
    } on MissingPluginException {
      // Web/tests or a native build without the channel.
      return null;
    }
  }
}
