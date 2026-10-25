/// Reproduces the Samsung FATAL: `start dns/https[bootstrap-dns]: detour to
/// an empty direct outbound makes no sense` — only when DNS leak prevention
/// is ON, only for sing-box protocols.
///
///   dart run tool/repro_dns_fatal.dart
library;

import 'dart:io';

import 'package:blackout_kit_mobile/models/config.dart';
import 'package:blackout_kit_mobile/services/singbox_config.dart';

Future<void> main() async {
  const uri =
      'anytls://secretpass@185.208.172.212:39007?sni=a.com&insecure=0#SRV2-AnyTLS';
  final config = ConfigParser.parse(uri)!;

  for (final leakPrevention in [false, true]) {
    final json = SingboxConfigBuilder(
      routeDnsThroughProxy: leakPrevention,
    ).buildJson(config);
    final file = File(
      '${Directory.systemTemp.path}/sb_leak_$leakPrevention.json',
    )..writeAsStringSync(json);

    final proc = await Process.run(
      r'C:\Users\kiacoder\.blackout-kit\bins\sing-box.exe',
      ['check', '-c', file.path],
    );
    stdout.writeln(
        'leakPrevention=$leakPrevention -> exit ${proc.exitCode} '
        '${proc.exitCode == 0 ? "(ok)" : ""}');
    if (proc.exitCode != 0) {
      final err = '${proc.stdout}${proc.stderr}'.trim();
      for (final line in err.split('\n').take(6)) {
        stdout.writeln('  | $line');
      }
    }
  }
}
