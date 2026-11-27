import 'package:blackout_kit_mobile/services/openvpn_credentials.dart';
import 'package:blackout_kit_mobile/models/openvpn_profile.dart';
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

  test('key password only and combined login are distinct modes', () {
    final key = OpenVpnCredentials('', '', keySecret: 'fixture-key');
    expect(key.validFor(interactive: false, encryptedKey: true), isTrue);
    expect(key.validFor(interactive: true, encryptedKey: true), isFalse);
    expect(key.valid, isFalse);
    key.clear();
    expect(key.keyPassword.every((byte) => byte == 0), isTrue);
    final both = OpenVpnCredentials('fixture', 'secret', keySecret: 'key');
    expect(both.validFor(interactive: true, encryptedKey: true), isTrue);
    expect(both.valid, isFalse);
    both.clear();
  });

  test('detects encrypted PEM only within key block', () {
    expect(
        OpenVpnProfile.needsKeyPassword(
            '<key>\n-----BEGIN ENCRYPTED PRIVATE KEY-----\n</key>'),
        isTrue);
    expect(
        OpenVpnProfile.needsKeyPassword(
            '<key>\n-----BEGIN RSA PRIVATE KEY-----\nProc-Type: 4,ENCRYPTED\n</key>'),
        isTrue);
    expect(
        OpenVpnProfile.needsKeyPassword(
            '<ca>\n-----BEGIN ENCRYPTED PRIVATE KEY-----\n</ca>'),
        isFalse);
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
