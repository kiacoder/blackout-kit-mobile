import 'package:blackout_kit_mobile/services/openvpn_credentials.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('auth material is bounded, redacted and clearable', () {
    final credentials = OpenVpnCredentials('fixture-user', 'fixture-secret');
    expect(credentials.valid, isTrue);
    expect(credentials.toString(), isNot(contains('fixture')));
    credentials.clear();
    expect(credentials.valid, isFalse);
    expect(credentials.username.every((byte) => byte == 0), isTrue);
    expect(credentials.password.every((byte) => byte == 0), isTrue);
  });

  test('empty, NUL and oversized UTF8 credentials rejected', () {
    for (final credentials in [
      OpenVpnCredentials('', 'fixture'),
      OpenVpnCredentials('fixture', 'bad\u0000value'),
      OpenVpnCredentials('fixture', 'é' * 2049),
    ]) {
      expect(credentials.valid, isFalse);
      credentials.clear();
    }
  });
}
