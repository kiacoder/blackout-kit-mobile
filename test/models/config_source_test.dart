/// Tests for ConfigSource error recording.
///
/// The Library screen distinguishes "every fetch failed" from "there are no
/// configs" using the per-source `error` field: a failed fetch records a
/// reason, a successful one must clear it. `copyWith` used to coalesce
/// `error: null` back to the old value, so a source that failed once kept
/// showing its stale error forever — `clearError` is the explicit way out.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:blackout_kit_mobile/models/config_source.dart';

void main() {
  ConfigSource buildSource({String? error}) {
    return ConfigSource(
      id: 'test',
      name: 'Test Source',
      owner: 'owner',
      repo: 'repo',
      branch: 'main',
      filePath: 'configs.txt',
      type: SourceType.github,
      error: error,
    );
  }

  test('copyWith records a fetch error', () {
    final source = buildSource();
    final failed = source.copyWith(error: 'SocketException: connection refused');

    expect(failed.error, 'SocketException: connection refused');
  });

  test('copyWith with error null does NOT clear a recorded error', () {
    // Documents the coalescing quirk that motivated clearError.
    final source = buildSource(error: 'rate limited');
    final attempted = source.copyWith(error: null);

    expect(attempted.error, 'rate limited');
  });

  test('clearError clears a recorded error', () {
    final source = buildSource(error: 'rate limited');
    final recovered = source.copyWith(clearError: true);

    expect(recovered.error, isNull);
  });

  test('clearError leaves other fields intact', () {
    final source = buildSource(error: 'rate limited')
        .copyWith(configCount: 42, lastFetched: DateTime.utc(2026, 10, 15));
    final recovered = source.copyWith(clearError: true);

    expect(recovered.error, isNull);
    expect(recovered.configCount, 42);
    expect(recovered.lastFetched, DateTime.utc(2026, 10, 15));
  });

  test('copyWith preserves the error when only other fields change', () {
    final source = buildSource(error: 'timeout');
    final updated = source.copyWith(configCount: 7);

    expect(updated.error, 'timeout');
    expect(updated.configCount, 7);
  });
}
