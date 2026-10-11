/// Regression tests for test-result persistence.
///
/// Measurements used to live only in an in-memory RxMap: every app restart
/// wiped the tester back to "Untested" for the whole library, rankings and the
/// fastest-config banner vanished, and connectFastest had to probe blind.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:blackout_kit_mobile/models/config.dart';
import 'package:blackout_kit_mobile/models/test_result.dart';
import 'package:blackout_kit_mobile/services/config_service.dart';

void main() {
  late ConfigService service;
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('bk_hive_test');
    Hive.init(tempDir.path);
  });

  tearDownAll(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  setUp(() async {
    service = ConfigService();
    await service.initialize();
  });

  TestResult _success(String hash) => TestResult.success(
        configHash: hash,
        latencyMs: 42,
        successCount: 3,
        totalCount: 3,
      );

  test('a saved result round-trips through storage', () async {
    await service.saveTestResult(_success('hash-a'));

    final loaded = service.loadTestResults();
    expect(loaded['hash-a'], isNotNull);
    expect(loaded['hash-a']!.isWorking, isTrue);
    expect(loaded['hash-a']!.latencyMs, 42);
  });

  test('a failed result keeps its error and status', () async {
    await service.saveTestResult(TestResult.failed(
      configHash: 'hash-b',
      error: 'Connection refused',
    ));

    final loaded = service.loadTestResults();
    expect(loaded['hash-b']!.isWorking, isFalse);
    expect(loaded['hash-b']!.error, 'Connection refused');
  });

  test('deleting a config removes its result', () async {
    await service.saveTestResult(_success('hash-c'));
    await service.deleteTestResult('hash-c');

    expect(service.loadTestResults().containsKey('hash-c'), isFalse);
  });

  test('countConfigsBySource counts live records per sourceId', () async {
    final parsed = ConfigParser.parseMultiple(
      'ss://YWVzLTI1Ni1nY206cGFzc3dvcmQ@10.0.0.1:8001#a\n'
      'ss://YWVzLTI1Ni1nY206cGFzc3dvcmQ@10.0.0.2:8002#b',
    );
    expect(parsed.length, 2);
    await service.saveConfigs(parsed, sourceId: 'src-live');

    final counts = service.countConfigsBySource();
    expect(counts['src-live'], 2);
  });

  test('re-saving an existing config under a new source re-attributes it',
      () async {
    final parsed = ConfigParser.parseMultiple(
      'ss://YWVzLTI1Ni1nY206cGFzc3dvcmQ@10.0.0.3:8003#c',
    );
    await service.saveConfigs(parsed, sourceId: 'old-source');
    // Same config arrives again, but the old source was retired/renamed.
    await service.saveConfigs(parsed, sourceId: 'new-source');

    final counts = service.countConfigsBySource();
    expect(counts['old-source'], isNull,
        reason: 'the stale attribution must not linger');
    expect(counts['new-source'], 1);
  });
}
