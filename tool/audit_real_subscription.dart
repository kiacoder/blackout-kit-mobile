/// Runs the REAL subscription payload through the app's own parser and
/// reports, per protocol, how many lines parse, how many pass validate(),
/// and what the failures look like. This is the data the phone actually
/// imports — any protocol that silently dies here is a protocol the user
/// can never connect to.
///
///   dart run tool/audit_real_subscription.dart <path-to-sub.txt>
library;

import 'dart:io';

import 'package:blackout_kit_mobile/models/config.dart';

void main(List<String> args) {
  final path = args.isNotEmpty ? args[0] : r'C:\Users\kiacoder\AppData\Local\Temp\bk_sub.txt';
  final text = File(path).readAsStringSync();

  final lines = text
      .split(RegExp(r'[\r\n]+'))
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .where((l) => !l.startsWith('#') && !l.startsWith('//'))
      .toList();

  stdout.writeln('total non-comment lines: ${lines.length}');

  // Per-protocol tallies.
  final parsedBy = <String, int>{};
  final validateFailedBy = <String, int>{};
  final unparsedBy = <String, int>{};
  final unparsedSamples = <String>[];
  final validateFailedSamples = <String, List<String>>{};

  for (final line in lines) {
    final config = ConfigParser.parse(line);
    if (config == null) {
      final scheme = line.contains('://')
          ? line.split('://').first.toLowerCase()
          : '(no scheme)';
      unparsedBy[scheme] = (unparsedBy[scheme] ?? 0) + 1;
      if (unparsedSamples.length < 8) unparsedSamples.add(line);
      continue;
    }
    if (!config.validate()) {
      final p = config.protocol;
      validateFailedBy[p] = (validateFailedBy[p] ?? 0) + 1;
      validateFailedSamples.putIfAbsent(p, () => []).add(line);
      continue;
    }
    parsedBy[config.protocol] = (parsedBy[config.protocol] ?? 0) + 1;
  }

  stdout.writeln('');
  stdout.writeln('protocol        parsed   validate-fail');
  final protocols = {...parsedBy.keys, ...validateFailedBy.keys}.toList()..sort();
  for (final p in protocols) {
    stdout.writeln(
        '${p.padRight(15)} ${"${parsedBy[p] ?? 0}".padLeft(6)}   ${validateFailedBy[p] ?? 0}');
  }

  stdout.writeln('');
  stdout.writeln('unparsed lines by scheme:');
  for (final entry in unparsedBy.entries) {
    stdout.writeln('  ${entry.key.padRight(14)} ${entry.value}');
  }

  if (unparsedSamples.isNotEmpty) {
    stdout.writeln('');
    stdout.writeln('unparsed samples (first 8):');
    for (final s in unparsedSamples) {
      stdout.writeln('  ${s.length > 140 ? "${s.substring(0, 140)}..." : s}');
    }
  }

  for (final entry in validateFailedSamples.entries) {
    stdout.writeln('');
    stdout.writeln('validate() FAILURES for ${entry.key} (up to 3):');
    for (final s in entry.value.take(3)) {
      stdout.writeln('  ${s.length > 160 ? "${s.substring(0, 160)}..." : s}');
    }
  }
}
