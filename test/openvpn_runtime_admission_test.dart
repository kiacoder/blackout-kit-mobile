import 'package:blackout_kit_mobile/models/openvpn_profile.dart';
import 'package:flutter_test/flutter_test.dart';

const base = 'client\ndev tun\nproto udp\nremote vpn.example 1194\n'
    'remote-cert-tls server\nverify-x509-name fixture name\n<ca>\nfixture\n</ca>\n';

void main() {
  test('self-contained certificate profile with interactive auth admitted', () {
    expect(OpenVpnProfile.admitsRuntime(base), isTrue);
    expect(OpenVpnProfile.admitsRuntime('${base}auth-user-pass'), isTrue);
    expect(OpenVpnProfile.admitsRuntime('$base<key>\nfixture\n</key>'), isTrue);
  });

  test('import remains broader than runtime admission', () {
    for (final directive in [
      'up /tmp/test',
      'plugin external.so',
      'script-security 2',
      'config other.ovpn',
      'ca other.crt',
      'key other.key',
      'auth-user-pass credentials.txt',
      'auth-user-pass ""',
      'management 127.0.0.1 8080',
      'unknown-option yes',
      'dev tap',
      'remote-cert-tls client',
      '<auth-user-pass>\nfixture\n</auth-user-pass>',
      '<ca>\nsecond\n</ca>',
      '<connection>\nremote other.example 443\nremote-cert-tls server\n</connection>',
    ]) {
      final profile = '$base$directive';
      expect(OpenVpnProfile.parse(profile), isNotNull);
      expect(OpenVpnProfile.admitsRuntime(profile), isFalse, reason: directive);
    }
  });

  test('no unverified server or empty certificate accepted', () {
    for (final profile in [
      'client\ndev tun\nremote vpn.example 443',
      base.replaceFirst('remote-cert-tls server\n', ''),
      base.replaceFirst('verify-x509-name fixture name\n', ''),
      base.replaceFirst('fixture name', 'fixture name-prefix'),
      base.replaceFirst('<ca>\nfixture\n</ca>', '<ca>\n</ca>'),
      base.replaceFirst('dev tun', 'dev tap'),
    ]) {
      expect(OpenVpnProfile.admitsRuntime(profile), isFalse);
    }
  });
}
