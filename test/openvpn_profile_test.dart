import 'package:blackout_kit_mobile/models/config.dart';
import 'package:blackout_kit_mobile/models/openvpn_profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('quoted remote and profile port are parsed without changing raw data',
      () {
    const source = 'client\ndev tun\nremote "vpn.example" # comment\nrport 443';
    final profile = OpenVpnConfig.fromUri(source)!;
    expect(profile.address, 'vpn.example');
    expect(profile.port, 443);
    expect(profile.rawUri, source);
    expect(profile.validate(), isTrue);
  });

  test('connection blocks and multiple remotes retain first endpoint', () {
    const source = 'client\n<connection>\nremote vpn.example 443 tcp\n'
        '</connection>\n<connection>\nremote other.example 1194 udp\n</connection>';
    final profile = OpenVpnProfile.parse(source)!;
    expect(profile.host, 'vpn.example');
    expect(profile.port, 443);
  });

  test('remote-looking inline certificate text is not an endpoint', () {
    expect(OpenVpnProfile.parse('client\n<ca>\nremote fake.example 443\n</ca>'),
        isNull);
  });

  test('invalid ports and unterminated input are rejected', () {
    for (final source in [
      'remote vpn.example 0',
      'remote vpn.example 65536',
      'remote vpn.example nope',
      'remote vpn.example\n<ca>\nunfinished',
      'remote "vpn.example',
      'remote vpn.example\n<connection>',
    ]) {
      expect(OpenVpnProfile.parse(source), isNull);
    }
  });

  test('IPv6 remote and inline key blocks are preserved', () {
    const source = 'remote 2001:db8::1 443\n<key>\nfixture\n</key>';
    final profile = OpenVpnProfile.parse(source)!;
    expect(profile.host, '2001:db8::1');
    expect(profile.inlineBlocks, {'key'});
  });

  test('import cannot report a successful OpenVPN connection', () async {
    final profile = OpenVpnConfig.fromUri('client\nremote vpn.example 1194')!;
    expect(await profile.connect(), isFalse);
    expect(await profile.isRunning(), isFalse);
  });
}
