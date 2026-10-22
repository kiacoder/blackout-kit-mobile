import 'package:flutter_test/flutter_test.dart';
import 'package:blackout_kit_mobile/models/config.dart';
import 'package:blackout_kit_mobile/services/xray_config.dart';

void main() {
  test('ENG-X01: shadowsocks streamSettings', () {
    final ss = ConfigParser.parse(
      'ss://YWVzLTI1Ni1nY206cGFzcw==@example.com:8388#n',
    )!;
    final doc = const XrayConfigBuilder().build(ss);
    final out = (doc['outbounds'] as List).first as Map;
    final stream = out['streamSettings'];
    print('SS_PROTOCOL=${ss.protocol}');
    print('SS_STREAM=$stream');
  });

  test('ENG-X04: vless allowInsecure', () {
    final v = ConfigParser.parse(
      'vless://11111111-1111-1111-1111-111111111111@a.com:443?security=tls&allowInsecure=1#x',
    )!;
    final doc = const XrayConfigBuilder().build(v);
    final stream = ((doc['outbounds'] as List).first as Map)['streamSettings'] as Map;
    print('VLESS_STREAM=$stream');
  });

  test('ENG-X05: vmess tls none', () {
    // vmess base64: {"v":"2","ps":"t","add":"a.com","port":"443","id":"11111111-1111-1111-1111-111111111111","aid":"0","scy":"auto","net":"ws","type":"none","host":"","path":"/","tls":"none"}
    const b64 = 'eyJ2IjoiMiIsInBzIjoidCIsImFkZCI6ImEuY29tIiwicG9ydCI6IjQ0MyIsImlkIjoiMTExMTExMTEtMTExMS0xMTExLTExMTEtMTExMTExMTExMTExIiwiYWlkIjoiMCIsInNjeSI6ImF1dG8iLCJuZXQiOiJ3cyIsInR5cGUiOiJub25lIiwiaG9zdCI6IiIsInBhdGgiOiIvIiwidGxzIjoibm9uZSJ9';
    final vm = ConfigParser.parse('vmess://$b64');
    print('VMESS_PARSED=${vm?.runtimeType}');
    if (vm != null) {
      final doc = const XrayConfigBuilder().build(vm);
      final stream = ((doc['outbounds'] as List).first as Map)['streamSettings'] as Map;
      print('VMESS_STREAM=$stream');
    }
  });
}
