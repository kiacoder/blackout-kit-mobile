/// Library filter regressions.
///
/// Two bugs locked down here:
///  1. Filtering by source kept every config that merely had a stored test
///     result, so picking one repository still listed configs from all the
///     others.
///  2. "Recently added" was a no-op sort (`return 0`), so the option existed
///     in the menu and did nothing.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:blackout_kit_mobile/controllers/config_controller.dart';
import 'package:blackout_kit_mobile/models/config.dart';
import 'package:blackout_kit_mobile/models/config_source.dart';
import 'package:blackout_kit_mobile/models/test_result.dart';
import 'package:blackout_kit_mobile/services/config_service.dart';
import 'package:blackout_kit_mobile/services/github_service.dart';
import 'package:blackout_kit_mobile/services/tester_service.dart';

Config vless(String host, String name) => ConfigParser.parse(
      'vless://11111111-1111-1111-1111-111111111111@$host:443?security=none&type=tcp#$name',
    )!;

void main() {
  late Directory tempDir;
  late ConfigService service;
  late ConfigController controller;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('bk_filter_test');
    Hive.init(tempDir.path);
  });

  tearDownAll(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  setUp(() async {
    service = ConfigService();
    await service.initialize();
    controller = ConfigController(
      configService: service,
      githubService: GitHubService(),
      testerService: TesterService(),
    );
    controller.sources.value = [
      const ConfigSource(id: 's1', name: 'Source One', owner: 'a', repo: 'a'),
      const ConfigSource(id: 's2', name: 'Source Two', owner: 'b', repo: 'b'),
    ];
  });

  test('source filter shows only that source, even for tested configs',
      () async {
    final fromOne = vless('one.example.com', 'One');
    final fromTwo = vless('two.example.com', 'Two');
    final manual = vless('manual.example.com', 'Manual');

    await service.saveConfig(fromOne, sourceId: 's1');
    await service.saveConfig(fromTwo, sourceId: 's2');
    await service.saveConfig(manual);

    controller.allConfigs.value = [fromOne, fromTwo, manual];
    controller.sourceIdByHash.value = {
      fromOne.getHash(): 's1',
      fromTwo.getHash(): 's2',
    };
    // A tested config from another source used to leak into every filter.
    controller.testResults[fromTwo.getHash()] =
        TestResult.success(configHash: fromTwo.getHash(), latencyMs: 30);

    controller.filterSource.value = 's1';
    final filtered = controller.getFilteredConfigs();

    expect(filtered.map((c) => c.displayName), ['One']);
  });

  test('recently added sorts newest first, unknown dates last', () async {
    final older = vless('old.example.com', 'Older');
    final newer = vless('new.example.com', 'Newer');
    final unknown = vless('unknown.example.com', 'Unknown');

    controller.allConfigs.value = [older, newer, unknown];
    controller.savedAtByHash.value = {
      older.getHash(): DateTime(2026, 1, 1),
      newer.getHash(): DateTime(2026, 6, 1),
    };
    controller.sortBy.value = 'recently_added';

    final filtered = controller.getFilteredConfigs();
    expect(
      filtered.map((c) => c.displayName).toList(),
      ['Newer', 'Older', 'Unknown'],
    );
  });

  test('savedAt is persisted and reloaded for ordering', () async {
    final config = vless('persisted.example.com', 'Persisted');
    await service.saveConfig(config, sourceId: 's1');

    final map = service.loadHashToSavedAt();
    expect(map.containsKey(config.getHash()), isTrue);
    expect(map[config.getHash()], isA<DateTime>());
  });
}
