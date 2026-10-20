/// The library badge must show what actually happened.
///
/// The bug this locks down: the tile collapsed five statuses into two, so a
/// config that had never been tested — or whose probe failed once before the
/// tunnel worked — was labelled "✗ Failed" even while it carried traffic.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:blackout_kit_mobile/models/config.dart';
import 'package:blackout_kit_mobile/models/test_result.dart';
import 'package:blackout_kit_mobile/widgets/config_tile.dart';

Config sampleConfig() => ConfigParser.parse(
      'vless://11111111-1111-1111-1111-111111111111@example.com:443#Sample',
    )!;

Future<void> pumpTile(WidgetTester tester, TestResult? result) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ConfigTile(
          config: sampleConfig(),
          testResult: result,
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  final hash = sampleConfig().getHash();

  testWidgets('no result renders "Not Tested", never "Failed"', (tester) async {
    await pumpTile(tester, null);
    expect(find.text('Not Tested'), findsOneWidget);
    expect(find.text('✗ Failed'), findsNothing);
  });

  testWidgets('notTested status renders "Not tested"', (tester) async {
    await pumpTile(tester, TestResult(configHash: hash));
    expect(find.text('Not tested'), findsOneWidget);
    expect(find.text('✗ Failed'), findsNothing);
  });

  testWidgets('success renders "Working"', (tester) async {
    await pumpTile(tester, TestResult.success(configHash: hash, latencyMs: 42));
    expect(find.text('✓ Working'), findsOneWidget);
  });

  testWidgets('a genuine failure renders "Failed"', (tester) async {
    await pumpTile(tester, TestResult.failed(configHash: hash, error: 'refused'));
    expect(find.text('✗ Failed'), findsOneWidget);
  });

  testWidgets('a timeout is not reported as a failure', (tester) async {
    await pumpTile(
      tester,
      TestResult.failed(configHash: hash, status: TestStatus.timeout),
    );
    expect(find.text('⏱ Timeout'), findsOneWidget);
    expect(find.text('✗ Failed'), findsNothing);
  });

  testWidgets('a running test shows progress, not failure', (tester) async {
    await pumpTile(
      tester,
      TestResult.failed(configHash: hash, status: TestStatus.testing),
    );
    expect(find.text('Testing…'), findsOneWidget);
    expect(find.text('✗ Failed'), findsNothing);
  });
}
