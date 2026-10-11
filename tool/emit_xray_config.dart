// Emits Xray JSON documents exactly as the app builds them, for validation
// against a real xray binary: `xray run -test -c <file>`.
import 'dart:io';
import 'package:blackout_kit_mobile/models/config.dart';
import 'package:blackout_kit_mobile/services/xray_config.dart';

void main(List<String> args) {
  final samples = [
    // REALITY over TCP — the most common barry-far shape
    'vless://8f3c2a1b-1234-4321-abcd-9e8d7c6b5a4f@1.2.3.4:443?'
        'type=tcp&security=reality&pbk=SbVKOEMjK0sIlbwg4akyBg5mL5KZwwB-ed4eEE7YnRQ'
        '&fp=chrome&sni=www.microsoft.com&sid=6ba85179&flow=xtls-rprx-vision#reality-tcp',
    // WS + TLS
    'vless://8f3c2a1b-1234-4321-abcd-9e8d7c6b5a4f@5.6.7.8:443?'
        'type=ws&security=tls&sni=cdn.example.com&host=cdn.example.com&path=%2Fws#ws-tls',
    // Plain TCP, no TLS
    'vless://8f3c2a1b-1234-4321-abcd-9e8d7c6b5a4f@9.9.9.9:80?type=tcp&security=none#plain',
    // gRPC + TLS
    'vless://8f3c2a1b-1234-4321-abcd-9e8d7c6b5a4f@3.3.3.3:443?'
        'type=grpc&security=tls&sni=grpc.example.com&serviceName=grpcsvc#grpc-tls',
    // VMess ws
    'vmess://eyJhZGQiOiI3LjcuNy43IiwicG9ydCI6IjQ0MyIsImlkIjoiOGYzYzJhMWItMTIzNC00MzIxLWFiY2QtOWU4ZDdjNmI1YTRmIiwic2VjdXJpdHkiOiJ0bHMiLCJuZXQiOiJ3cyIsInBhdGgiOiIvd3MiLCJob3N0IjoiY2RuLmV4YW1wbGUuY29tIn0=',
    // Shadowsocks
    'ss://YWVzLTI1Ni1nY206cGFzc3dvcmQ@4.4.4.4:8388#ss-sample',
  ];

  final outDir = args.isEmpty ? 'build/xray_validation' : args[0];
  Directory(outDir).createSync(recursive: true);

  for (final uri in samples) {
    final config = ConfigParser.parse(uri);
    if (config == null) {
      stderr.writeln('PARSE-FAIL: $uri');
      continue;
    }
    final name = (config.displayName.isEmpty ? 'config' : config.displayName)
        .replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final json = XrayConfigBuilder().buildJson(config);
    File('$outDir/$name.json').writeAsStringSync(json);
    stdout.writeln('WROTE: $outDir/$name.json (${config.protocol})');
  }
}
