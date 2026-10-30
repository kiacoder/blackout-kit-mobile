import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:blackout_kit_mobile/models/config.dart';
import 'package:blackout_kit_mobile/services/xray_config.dart';

void main() {
  group('2026-10-30 verified-bug regressions', () {
    test('DATA-01: hash uses UTF-8 bytes, not UTF-16 code units', () {
      // ي (U+064A) and J (U+004A) share a low byte — the old codeUnits hash
      // collided on exactly the Persian/Arabic names in subscription lists.
      final a = ConfigParser.parse('vless://11111111-1111-1111-1111-111111111111@a.com:443#Server ي')!;
      final b = ConfigParser.parse('vless://11111111-1111-1111-1111-111111111111@a.com:443#Server J')!;
      expect(a.getHash(), isNot(b.getHash()));
    });

    test('ENG-02: empty security= stays plaintext', () {
      final c = ConfigParser.parse('vless://11111111-1111-1111-1111-111111111111@a.com:80?type=ws&security=&path=%2F')!;
      final json = (XrayConfigBuilder().build(c)['outbounds'] as List).first as Map;
      expect(json['streamSettings']['security'], 'none');
    });

    test('ENG-08: trojan security=none is respected', () {
      final c = ConfigParser.parse('trojan://pw@a.com:80?security=none&type=ws&path=%2F')!;
      final json = (XrayConfigBuilder().build(c)['outbounds'] as List).first as Map;
      expect(json['streamSettings']['security'], 'none');
    });

    test('ENG-01: headerType=http emits tcpSettings.header', () {
      final c = ConfigParser.parse(
          'vless://11111111-1111-1111-1111-111111111111@a.com:80?type=tcp&headerType=http&host=speedtest.net&path=%2F')!;
      final json = (XrayConfigBuilder().build(c)['outbounds'] as List).first as Map;
      final header = json['streamSettings']['tcpSettings']['header'];
      expect(header['type'], 'http');
      expect(header['request']['headers']['Host'], contains('speedtest.net'));
    });

    test('ENG-06: TLS vless with host but no sni still sends SNI', () {
      final c = ConfigParser.parse(
          'vless://11111111-1111-1111-1111-111111111111@1.2.3.4:443?type=ws&security=tls&host=cdn.a.com')!;
      final json = (XrayConfigBuilder().build(c)['outbounds'] as List).first as Map;
      expect(json['streamSettings']['tlsSettings']['serverName'], 'cdn.a.com');
    });

    test('ENG-14: fully percent-encoded ss-2022 userinfo parses', () {
      final c = ConfigParser.parse(
          'ss://2022-blake3-aes-128-gcm%3AAAAAAAAAAAAAAAAAAAAAAA%3D%3D@a.com:8388#x')!;
      expect(c, isNotNull);
      expect((c as ShadowsocksConfig).password, isNotEmpty);
    });

    test('ENG-15: port 99999 fails validation', () {
      final c = ConfigParser.parse('vless://11111111-1111-1111-1111-111111111111@a.com:99999#x')!;
      expect(c.validate(), isFalse);
    });

    test('ENG-16: hysteria2 range authority imports with hop ports', () {
      final c = ConfigParser.parse('hysteria2://pw@a.com:20000-30000?sni=a.com')!;
      expect(c, isNotNull);
      expect((c as Hysteria2Config).hopPorts, '20000-30000');
      expect(c.port, 20000);
    });

    test('ENG-16: hysteria2 mport= list form is kept', () {
      final c = ConfigParser.parse('hysteria2://pw@a.com:443?mport=20000-30000')!;
      expect((c as Hysteria2Config).hopPorts, '20000-30000');
    });

    test('wrapped-base64 vmess blob (email line-wrap) parses', () {
      final payload = base64Encode(
          utf8.encode('{"v":"2","ps":"wrapped","add":"a.com","port":"443","id":"11111111-1111-1111-1111-111111111111","aid":"0","net":"tcp","type":"none"}'));
      // break it into two lines like an email client does
      final half = payload.length ~/ 2;
      final wrapped = 'vmess://${payload.substring(0, half)}\n${payload.substring(half)}';
      final c = ConfigParser.parse(wrapped);
      expect(c, isNotNull);
    });

    test('DATA-02: form-encoded + in fragment renders as space', () {
      final c = ConfigParser.parse('vless://11111111-1111-1111-1111-111111111111@a.com:443#DE+Frankfurt')!;
      expect(c.displayName, 'DE Frankfurt');
    });
  });
}
