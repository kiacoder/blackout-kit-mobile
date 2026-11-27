import 'dart:async';

import 'package:blackout_kit_mobile/services/scanner_operation_queue.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('stop waits for pending start', () async {
    final queue = ScannerOperationQueue();
    final started = Completer<void>();
    final release = Completer<void>();
    final events = <String>[];
    final start = queue.run(() async {
      events.add('start');
      started.complete();
      await release.future;
      events.add('started');
    });
    await started.future;
    final stop = queue.run(() async => events.add('stop'));
    expect(events, ['start']);
    release.complete();
    await Future.wait([start, stop]);
    expect(events, ['start', 'started', 'stop']);
  });

  test('failure does not block subsequent cleanup', () async {
    final queue = ScannerOperationQueue();
    final failure = queue.run(() async => throw StateError('camera failed'));
    await expectLater(failure, throwsStateError);
    var cleaned = false;
    await queue.run(() async => cleaned = true);
    expect(cleaned, isTrue);
  });

  test('close drops queued operations and waits for active work', () async {
    final queue = ScannerOperationQueue();
    final started = Completer<void>();
    final release = Completer<void>();
    final events = <String>[];
    final active = queue.run(() async {
      started.complete();
      await release.future;
      events.add('finished');
    });
    await started.future;
    final queued = queue.run(() async => events.add('stale start'));
    final closed = queue.close(() async => events.add('disposed'));
    await queue.run(() async => events.add('late start'));
    expect(events, isEmpty);
    release.complete();
    await Future.wait([active, queued, closed]);
    expect(events, ['finished', 'disposed']);
  });

  test('close is idempotent', () async {
    final queue = ScannerOperationQueue();
    var calls = 0;
    final first = queue.close(() async { calls++; });
    final second = queue.close(() async { calls++; });
    await Future.wait([first, second]);
    expect(calls, 1);
  });
}
