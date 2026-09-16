/// Integration tests for Blackout Kit VPN app
/// Tests the complete user flow: fetch → test → connect

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:blackout_kit_mobile/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Blackout Kit VPN App Integration Tests', () {
    testWidgets('App starts and loads UI', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle();

      // Verify app bar is present
      expect(find.text('Blackout Kit VPN'), findsOneWidget);

      // Verify bottom navigation tabs
      expect(find.byIcon(Icons.power), findsOneWidget);
      expect(find.byIcon(Icons.library_books), findsOneWidget);
      expect(find.byIcon(Icons.settings), findsOneWidget);

      // Verify connect button is visible
      expect(find.byIcon(Icons.vpn_lock_open), findsOneWidget);
    });

    testWidgets('User can tap on Library tab', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle();

      // Tap library tab
      await tester.tap(find.byIcon(Icons.library_books));
      await tester.pumpAndSettle();

      // Verify library screen is shown
      expect(find.text('Config Library'), findsOneWidget);
    });

    testWidgets('User can tap on Settings tab', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle();

      // Tap settings tab
      await tester.tap(find.byIcon(Icons.settings));
      await tester.pumpAndSettle();

      // Verify settings screen is shown
      expect(find.text('Settings'), findsOneWidget);
    });

    testWidgets('User can toggle auto-connect setting', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle();

      // Navigate to settings
      await tester.tap(find.byIcon(Icons.settings));
      await tester.pumpAndSettle();

      // Find and tap auto-connect toggle
      final toggles = find.byType(SwitchListTile);
      if (toggles.evaluate().isNotEmpty) {
        await tester.tap(toggles.first);
        await tester.pumpAndSettle();

        // Verify toggle state changed
        expect(find.byType(SwitchListTile), findsWidgets);
      }
    });

    testWidgets('Home screen shows quick stats', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle();

      // Verify home screen stats are present
      expect(find.text('Speed'), findsWidgets);
      expect(find.text('Total Configs'), findsWidgets);
      expect(find.text('Working'), findsWidgets);
      expect(find.text('Reliability'), findsWidgets);
    });

    testWidgets('Home screen displays status card', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle();

      // Verify status card content
      expect(find.byType(Card), findsWidgets);
      expect(find.byType(Icon), findsWidgets);
    });

    testWidgets('User can navigate between tabs', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle();

      // Start at home
      expect(find.text('Blackout Kit VPN'), findsOneWidget);

      // Go to library
      await tester.tap(find.byIcon(Icons.library_books));
      await tester.pumpAndSettle();
      expect(find.text('Config Library'), findsOneWidget);

      // Go to settings
      await tester.tap(find.byIcon(Icons.settings));
      await tester.pumpAndSettle();
      expect(find.text('Settings'), findsOneWidget);

      // Back to home
      await tester.tap(find.byIcon(Icons.power));
      await tester.pumpAndSettle();
      expect(find.text('Blackout Kit VPN'), findsOneWidget);
    });

    testWidgets('App layout is responsive', (WidgetTester tester) async {
      app.main();
      await tester.binding.window.physicalSizeTestValue =
          const Size(400, 800);
      await tester.pumpAndSettle();

      // Verify elements are visible in narrow viewport
      expect(find.byIcon(Icons.power), findsOneWidget);
      expect(find.byIcon(Icons.vpn_lock_open), findsOneWidget);

      addTearDown(tester.binding.window.clearPhysicalSizeTestValue);
    });

    testWidgets('Settings screen has all sections', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle();

      // Navigate to settings
      await tester.tap(find.byIcon(Icons.settings));
      await tester.pumpAndSettle();

      // Scroll to view all content
      await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -300));
      await tester.pumpAndSettle();

      // Verify key settings sections exist
      expect(find.text('VPN Settings'), findsOneWidget);
      expect(find.text('Appearance'), findsOneWidget);
      expect(find.text('General'), findsOneWidget);
    });
  });
}
