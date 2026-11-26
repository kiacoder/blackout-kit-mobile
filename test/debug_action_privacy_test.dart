import 'package:blackout_kit_mobile/services/debug_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('action logs retain aggregate fields but never free-form values', () {
    final debug = DebugService();
    debug.logAction('scan_verified', {
      'config': 'private-config-canary',
      'source': 'private-source-canary',
      'reason': 'private-error-canary',
      'hosts': ['private-host-canary'],
      'count': 3,
      'value': true,
      'attempted': 'private-counter-canary',
      'private-key-canary': 1,
    });
    for (final output in [
      debug.getLogsAsString(),
      debug.exportLogsAsText(),
      debug.getDebugInfo().toString(),
    ]) {
      expect(output, contains('scan_verified'));
      expect(output, contains('count=3'));
      expect(output, contains('value=true'));
      expect(output, isNot(contains('private-')));
    }
  });
}
