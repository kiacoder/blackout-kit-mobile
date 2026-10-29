/// Guards the "every place updates when the language changes" promise.
///
/// The app is not localised by magic: a string that is written as a literal in
/// a widget simply does not follow the language setting. This test walks the
/// UI sources and fails when a hardcoded English string appears, so the next
/// screen someone adds cannot quietly opt out.
///
/// It is a text scan, not a widget test — deliberately. It catches the case a
/// widget test cannot: a screen nobody wrote a test for yet.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Literals that are not UI copy and must not be translated.
const Set<String> _allowed = {
  'Blackout Kit', // product name, same in every language
  'github.com/kiacoder/blackout-kit-mobile', // URL
  'v\$version', // version label
  'tun0',
  // Switch labels: compared against `engine.category`, which is a constant.
  'Core VPN', 'Proxy Core', 'DPI Obfuscation', 'Relay / Mesh',
  // Fragments of literals passed to LocalizationService.t(key, params) —
  // the guard looks at one line at a time.
  'This tunnel keeps the resolvers it was built with. Disconnect and ',
  'connect again to use @summary.',
  'This opens a TCP connection to port 53. Many resolvers only ',
  'Could not check for updates: ',
  'Exception: ',
};

void main() {
  test('no hardcoded English copy in screens or widgets', () {
    // Deliberately blunt: any single-quoted literal with a space and letters
    // that is not followed by `.tr` is UI copy that will not follow the
    // language setting. The first version of this test only matched
    // `Text('...')` on one line, so it missed multi-line concatenations,
    // `hintText:`/`tooltip:`/`labelText:` and dialog bodies — 193 strings
    // stayed English while it passed.
    final offenders = <String>[];
    final literal = RegExp(r"'([^'\\\n]*(?:\\.[^'\\\n]*)*)'");

    for (final dir in ['lib/screens', 'lib/widgets']) {
      for (final file in Directory(dir).listSync(recursive: true)) {
        if (file is! File || !file.path.endsWith('.dart')) continue;
        final lines = file.readAsStringSync().split('\n');
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          if (line.trimLeft().startsWith('//')) continue;
          for (final match in literal.allMatches(line)) {
            final text = match.group(1)!;
            if (!text.contains(' ') || !RegExp(r'[A-Za-z]').hasMatch(text)) {
              continue;
            }
            if (_allowed.contains(text)) continue;
            // Interpolations are dynamic values, not copy: a translation
            // cannot reorder them without a placeholder key, and the few that
            // need one use LocalizationService.t(key, params) instead.
            if (text.contains(r'$')) continue;
            if (line.substring(match.end).startsWith('.tr')) continue;
            offenders.add('${file.path}:${i + 1} -> "$text"');
          }
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'These strings do not follow the language setting://n'
          '${offenders.join('\n')}',
    );
  });

  test('every screen that renders copy imports GetX', () {
    for (final dir in ['lib/screens', 'lib/widgets']) {
      for (final file in Directory(dir).listSync(recursive: true)) {
        if (file is! File || !file.path.endsWith('.dart')) continue;
        final source = file.readAsStringSync();
        if (!source.contains("Text('") || !source.contains('.tr')) continue;
        expect(source.contains("package:get/get.dart"), isTrue,
            reason: '${file.path} calls .tr without importing GetX');
      }
    }
  });

  test('no hardcoded status line in the controllers', () {
    // The status line is rendered on the home screen. It used to be ~20 English
    // literals set from ConnectionController, which meant a Persian user saw
    // "Connecting to X..." in the middle of an otherwise translated screen.
    final offenders = <String>[];
    // Negative lookahead: a key followed by .tr / .trParams is correct.
    final pattern = RegExp(r"statusMessage\.value = '([^']*)'(?!\.tr)");

    for (final file in Directory('lib/controllers').listSync()) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      final source = file.readAsStringSync();
      for (final match in pattern.allMatches(source)) {
        final literal = match.group(1)!;
        if (literal.contains('\$') || literal.trim().isEmpty) continue;
        final line = source.substring(0, match.start).split('\n').length;
        offenders.add('${file.path}:$line -> "$literal"');
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'Status messages must come from the catalogue://n'
          '${offenders.join('\n')}',
    );
  });

  test('describe() summaries are translated', () {
    // These are subtitles in Settings, not just log lines.
    final offenders = <String>[];
    for (final file in Directory('lib/services').listSync()) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      final source = file.readAsStringSync();
      final start = source.indexOf('String describe()');
      if (start == -1) continue;
      final end = source.indexOf('\n  }', start);
      if (end == -1) continue;
      final body = source.substring(start, end);
      for (final match in RegExp(r"return '([^']*)'(?!\.tr)").allMatches(body)) {
        final literal = match.group(1)!;
        if (!literal.contains(' ')) continue;
        offenders.add('${file.path} -> "$literal"');
      }
    }
    expect(offenders, isEmpty,
        reason: 'describe() must return catalogue strings://n'
            '${offenders.join('\n')}');
  });
}
