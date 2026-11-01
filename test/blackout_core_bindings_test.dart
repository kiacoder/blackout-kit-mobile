import 'package:flutter_test/flutter_test.dart';
import 'package:blackout_kit_mobile/services/blackout_core_bindings.dart';

void main() {
  group('BlackoutCoreBindings FFI Architecture', () {
    test('bindings instantiate safely in test environment without crash', () {
      final bindings = BlackoutCoreBindings();
      // On desktop unit tests, dynamic library falls back gracefully to unloaded
      expect(bindings.isAvailable, isFalse);
      expect(bindings.getVersion(), 'unloaded');
      expect(bindings.isRunning(), isFalse);
      expect(bindings.init(), -99);
      expect(bindings.stop(), 0);
    });
  });
}
