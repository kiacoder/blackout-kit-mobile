import 'package:blackout_kit_mobile/main.dart';
import 'package:blackout_kit_mobile/services/localization_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('recovery screen follows device locale and switches languages',
      (tester) async {
    tester.binding.platformDispatcher.localesTestValue = const [Locale('fa')];
    addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
    await tester.pumpWidget(const StorageRecoveryApp());
    await tester.pumpAndSettle();
    final title = find.text(LocalizationService.translate(
      'storage_recovery_title', language: 'fa',
    ));
    expect(title, findsOneWidget);
    expect(Directionality.of(tester.element(title)), TextDirection.rtl);

    for (final language in ['zh', 'en']) {
      final dropdown = tester.widget<DropdownButton<String>>(
        find.byKey(const Key('recovery-language')),
      );
      dropdown.onChanged!(language);
      await tester.pumpAndSettle();
      final localized = find.text(LocalizationService.translate(
        'storage_recovery_body', language: language,
      ));
      expect(localized, findsOneWidget);
      expect(Directionality.of(tester.element(localized)), TextDirection.ltr);
    }
  });

  testWidgets('recovery fits small display with enlarged text', (tester) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    tester.binding.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.binding.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(const StorageRecoveryApp());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(SingleChildScrollView), findsWidgets);
  });
}
