import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// The pinned wakelock plugin uses Pigeon, not the old MethodChannel.
// Provide the real void-reply envelope in VM tests, where no host exists.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(
      'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle',
      (message) async {
        expect(message, isNotNull);
        return const StandardMessageCodec().encodeMessage(<Object?>[null]);
      },
    );
  });
  await testMain();
}
