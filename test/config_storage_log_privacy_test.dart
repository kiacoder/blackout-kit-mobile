import 'dart:io';

import 'package:blackout_kit_mobile/models/config.dart';
import 'package:blackout_kit_mobile/models/config_source.dart';
import 'package:blackout_kit_mobile/services/config_service.dart';
import 'package:blackout_kit_mobile/services/secure_vault.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:logger/logger.dart';

class _Capture extends LogOutput {
  final lines = <String>[];

  @override
  void output(OutputEvent event) => lines.addAll(event.lines);
}

class _AlwaysLog extends LogFilter {
  @override
  bool shouldLog(LogEvent event) => true;
}

void main() {
  late Directory dir;
  late ConfigService service;
  late _Capture capture;
  late Logger logger;

  setUp(() async {
    await Hive.close();
    dir = await Directory.systemTemp.createTemp('bk_log_privacy');
    Hive.init(dir.path);
    capture = _Capture();
    logger =
        Logger(filter: _AlwaysLog(), output: capture, printer: SimplePrinter());
    service = ConfigService(logger: logger, keyStore: MemoryKeyStore());
    await service.initialize();
  });

  tearDown(() async {
    await logger.close();
    await Hive.close();
    await dir.delete(recursive: true);
  });

  test('config and source operations do not log identifying values', () async {
    const name = 'private-config-label-canary';
    const id = 'private-source-id-canary';
    const sourceName = 'private-source-label-canary';
    final config = ConfigParser.parse(
      'vless://11111111-1111-1111-1111-111111111111@fixture.example:443?security=none&type=tcp#$name',
    )!;
    expect(await service.saveConfig(config, sourceId: id), isTrue);
    expect(await service.saveConfig(config, sourceId: id), isFalse);
    expect(
        await service.saveSource(const ConfigSource(
          id: id,
          name: sourceName,
          owner: 'fixture',
          repo: 'fixture',
        )),
        isTrue);
    expect(await service.deleteConfig(config.getHash()), isTrue);
    expect(await service.deleteSource(id), isTrue);
    final logs = capture.lines.join('\n');
    for (final secret in [
      name,
      id,
      sourceName,
      config.getHash(),
      config.rawUri
    ]) {
      expect(logs, isNot(contains(secret)));
    }
    expect(logs, contains('Saved config'));
    expect(logs, contains('Duplicate config detected'));
    expect(logs, contains('Saved source'));
    expect(logs, contains('Deleted config'));
    expect(logs, contains('Deleted source'));
  });

  test('malformed stored records do not log keys or exception payloads',
      () async {
    const id = 'private-record-key-canary';
    const payload = 'private-malformed-date-canary';
    await Hive.box<Map>('sources_v2').put(id, {
      'id': id,
      'name': 'fixture',
      'owner': 'fixture',
      'repo': 'fixture',
      'lastFetched': payload,
    });
    await Hive.box<Map>('test_results_v2').put(id, {
      'configHash': id,
      'testedAt': payload,
    });
    expect(service.getAllSources(), isEmpty);
    expect(service.getSource(id), isNull);
    expect(service.loadTestResults(), isEmpty);
    final logs = capture.lines.join('\n');
    expect(logs, isNot(contains(id)));
    expect(logs, isNot(contains(payload)));
    expect(logs, contains('Skipping unreadable source'));
    expect(logs, contains('Error loading source'));
    expect(logs, contains('Skipping unreadable test result'));
  });
}
