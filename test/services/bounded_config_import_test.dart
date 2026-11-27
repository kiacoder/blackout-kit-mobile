import 'dart:convert';

import 'package:blackout_kit_mobile/services/bounded_config_import.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('preserves UTF-8 sequences across stream chunks at exact byte limit',
      () async {
    final bytes = utf8.encode('فارسی 中文');
    final chunks = bytes.map((byte) => [byte]);
    expect(
      await readBoundedConfigText(Stream.fromIterable(chunks),
          maxBytes: bytes.length),
      'فارسی 中文',
    );
  });

  test('rejects excess actual bytes and cancels consumption', () async {
    var finished = false;
    Stream<List<int>> input() async* {
      try {
        yield [1, 2];
        yield [3, 4];
        fail('No additional chunks should be consumed');
      } finally {
        finished = true;
      }
    }

    await expectLater(
      readBoundedConfigText(input(), maxBytes: 3),
      throwsA(isA<ConfigImportTooLarge>()),
    );
    expect(finished, isTrue);
  });

  test('rejects invalid UTF-8 and accepts empty input', () async {
    await expectLater(
      readBoundedConfigText(Stream.value([0xc3, 0x28])),
      throwsFormatException,
    );
    expect(await readBoundedConfigText(Stream.value(<int>[]), maxBytes: 0), '');
  });
}
