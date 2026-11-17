import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:blackout_kit_mobile/models/config.dart';
import 'package:blackout_kit_mobile/screens/profile_export_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const link = 'vless://00000000-0000-4000-8000-000000000001@example.com:443?security=tls';

  testWidgets('clipboard remains untouched until explicit confirmation', (tester) async {
    final writes = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') writes.add((call.arguments as Map)['text'] as String);
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await tester.pumpWidget(MaterialApp(home: ProfileExportScreen(profiles: [ConfigParser.parse(link)!])));
    expect(writes, isEmpty);
    await tester.tap(find.text('Copy export…'));
    await tester.pumpAndSettle();
    expect(writes, isEmpty);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(writes, isEmpty);
    await tester.tap(find.text('Copy export…'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copy plaintext'));
    await tester.pumpAndSettle();
    expect(writes, hasLength(1));
    expect(writes.single, contains(link));
  });

  testWidgets('empty library cannot copy a misleading export', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: ProfileExportScreen(profiles: [])));
    final button = find.byWidgetPredicate((widget) => widget is FilledButton);
    expect(tester.widget<FilledButton>(button).onPressed, isNull);
  });
}
