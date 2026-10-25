/// Empirical engine-grammar validation for every protocol the app can dial.
///
/// Parses representative share-link shapes with the app's own [ConfigParser],
/// builds the engine JSON with the app's own builders, and hands each document
/// to the real desktop engines (`xray run -test`, `sing-box check`). A config
/// the real core refuses is a config the phone's core will refuse too — this
/// catches grammar bugs the unit tests cannot see because they only assert on
/// the JSON we *meant* to emit.
///
/// Run from the repo root:
///   dart run tool/validate_engines.dart
library;

import 'dart:convert';
import 'dart:io';

import 'package:blackout_kit_mobile/models/config.dart';
import 'package:blackout_kit_mobile/services/singbox_config.dart';
import 'package:blackout_kit_mobile/services/xray_config.dart';

const uuid = '11111111-1111-1111-1111-111111111111';

/// One candidate per real-world shape (mirrors what barry-far-style
/// subscriptions actually emit for each protocol).
final candidates = <String, String>{
  'vless/tcp/plain': 'vless://$uuid@a.com:443?type=tcp#v1',
  'vless/tcp/tls': 'vless://$uuid@a.com:443?security=tls&sni=a.com&fp=chrome&type=tcp#v2',
  'vless/reality': 'vless://$uuid@a.com:443?security=reality&pbk=AbCdEf_GHIJ1234567890abcdefghij1234567890KLm&sid=123456&fp=chrome&sni=www.microsoft.com&flow=xtls-rprx-vision&type=tcp#v3',
  'vless/ws/tls': 'vless://$uuid@a.com:443?security=tls&sni=a.com&type=ws&path=%2Fws&host=cdn.example.com#v4',
  'vless/grpc/tls': 'vless://$uuid@a.com:443?security=tls&type=grpc&serviceName=grpcsvc&mode=gun#v5',
  'vless/httpupgrade': 'vless://$uuid@a.com:443?security=tls&type=httpupgrade&path=%2Fup&host=cdn.example.com#v6',
  'vless/splithttp': 'vless://$uuid@a.com:443?security=tls&type=xhttp&path=%2Fsp&host=cdn.example.com#v7',
  'vmess/ws/tls': 'vmess://${base64.encode(utf8.encode(jsonEncode({"v": "2", "ps": "m1", "add": "a.com", "port": "443", "id": uuid, "aid": "0", "scy": "auto", "net": "ws", "type": "none", "host": "cdn.example.com", "path": "/ws", "tls": "tls", "sni": "a.com"})))}#m1',
  'vmess/tcp/plain': 'vmess://${base64.encode(utf8.encode(jsonEncode({"v": "2", "ps": "m2", "add": "a.com", "port": "80", "id": uuid, "aid": "0", "scy": "auto", "net": "tcp", "type": "none", "host": "", "path": "", "tls": ""})))}#m2',
  'vmess/grpc': 'vmess://${base64.encode(utf8.encode(jsonEncode({"v": "2", "ps": "m3", "add": "a.com", "port": "443", "id": uuid, "aid": "0", "scy": "auto", "net": "grpc", "type": "none", "host": "", "path": "grpcsvc", "tls": "tls"})))}#m3',
  'trojan/tcp/tls': 'trojan://pw123@a.com:443?security=tls&sni=a.com&fp=chrome&type=tcp#t1',
  'trojan/ws/tls': 'trojan://pw123@a.com:443?security=tls&sni=a.com&type=ws&path=%2Fws&host=cdn.example.com#t2',
  'trojan/grpc/tls': 'trojan://pw123@a.com:443?security=tls&sni=a.com&type=grpc&path=grpcsvc#t3',
  'ss/aes-256-gcm': 'ss://${base64.encode(utf8.encode('aes-256-gcm:secretpass'))}@a.com:8388#s1',
  'ss/plain-creds': 'ss://aes-256-gcm:secretpass@a.com:8388?sni=a.com#s2',
  'hy2': 'hy2://secretpass@a.com:443?sni=a.com&insecure=1#h1',
  'tuic': 'tuic://$uuid:secretpass@a.com:443?sni=a.com&congestion_control=bbr&alpn=h3#u1',
  'anytls': 'anytls://secretpass@a.com:443?sni=a.com#y1',
};

/// A wg-quick profile shaped like the ones wgcf generates.
const wireGuardConf = '''
[Interface]
PrivateKey = 6BqQKsDXmKZ5lM+7ZXYa3GZZQbG0vXbH0Yy6fZpXk1A=
Address = 172.16.0.2/32
DNS = 1.1.1.1
MTU = 1280

[Peer]
PublicKey = bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=
AllowedIPs = 0.0.0.0/0, ::/0
Endpoint = engage.cloudflareclient.com:2408
''';

Future<void> main() async {
  final tmp = await Directory.systemTemp.createTemp('bk_validate');
  var failures = 0;

  final xrayBin = _findBinary(['xray.exe', 'xray']);
  final singboxBin = _findBinary(['sing-box.exe', 'sing-box']);
  stdout.writeln('xray    : ${xrayBin ?? "NOT FOUND"}');
  stdout.writeln('sing-box: ${singboxBin ?? "NOT FOUND"}');
  stdout.writeln('');

  for (final entry in candidates.entries) {
    final config = ConfigParser.parse(entry.value, customName: entry.key);
    if (config == null) {
      stdout.writeln('PARSE-FAIL  ${entry.key}: parser returned null');
      failures++;
      continue;
    }
    if (!config.validate()) {
      stdout.writeln('VALIDATE-FAIL  ${entry.key}: validate() false');
      failures++;
      continue;
    }

    if (isXrayProtocol(config.protocol)) {
      if (xrayBin == null) continue;
      final json = const XrayConfigBuilder(tunEnabled: false).buildJson(config);
      final ok = await _runEngine(
        xrayBin, ['run', '-test', '-c'], json, tmp, entry.key,
      );
      if (!ok) failures++;
    } else if (isSingboxProtocol(config.protocol)) {
      if (singboxBin == null) continue;
      final json =
          const SingboxConfigBuilder().buildJson(config);
      final ok = await _runEngine(
        singboxBin, ['check', '-c'], json, tmp, entry.key,
      );
      if (!ok) failures++;
    } else {
      stdout.writeln('SKIP        ${entry.key} (${config.protocol})');
    }
  }

  // WireGuard rides the Xray core's wireguard outbound.
  if (xrayBin != null) {
    final wg = WireGuardConfig.fromUri(wireGuardConf, customName: 'wg');
    if (wg == null || !wg.validate()) {
      stdout.writeln('VALIDATE-FAIL  wireguard: parse/validate failed');
      failures++;
    } else {
      final json = const XrayConfigBuilder(tunEnabled: false).buildJson(wg);
      final ok = await _runEngine(
        xrayBin, ['run', '-test', '-c'], json, tmp, 'wireguard',
      );
      if (!ok) failures++;
    }
  }

  await tmp.delete(recursive: true);
  stdout.writeln('');
  stdout.writeln(failures == 0
      ? 'ALL CONFIGS ACCEPTED BY THE REAL ENGINES'
      : '$failures config(s) REJECTED — see above');
  exit(failures == 0 ? 0 : 1);
}

String? _findBinary(List<String> names) {
  const dirs = [
    r'C:\Users\kiacoder\.blackout-kit\bins',
    r'C:\Users\kiacoder\blackout-kit\bins',
  ];
  for (final dir in dirs) {
    for (final name in names) {
      final f = File('$dir\\$name');
      if (f.existsSync()) return f.path;
    }
  }
  return null;
}

Future<bool> _runEngine(
  String bin,
  List<String> args,
  String json,
  Directory tmp,
  String label,
) async {
  final file = File('${tmp.path}\\${label.replaceAll(RegExp(r'[^a-z0-9]', caseSensitive: false), '_')}.json');
  await file.writeAsString(json);

  final proc = await Process.run(bin, [...args, file.path]);
  final ok = proc.exitCode == 0;
  if (ok) {
    stdout.writeln('OK          $label');
  } else {
    stdout.writeln('REJECTED    $label (exit ${proc.exitCode})');
    final err = '${proc.stdout}${proc.stderr}'.trim();
    for (final line in err.split('\n').take(12)) {
      stdout.writeln('            | $line');
    }
    stdout.writeln('            | config: ${file.path} (kept for inspection)');
  }
  return ok;
}
