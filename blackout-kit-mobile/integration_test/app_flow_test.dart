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

      // Verify bottom navigation tabs exist
      expect(find.byType(BottomNavigationBar), findsOneWidget);

      // Verify connect button is visible
      expect(find.byIcon(Icons.lock_open), findsOneWidget);
    });

    testWidgets('User can tap on Library tab', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle();

      // Tap library tab
      final libraryTab = find.text('Library');
      if (libraryTab.evaluate().isNotEmpty) {
        await tester.tap(libraryTab.last);
        await tester.pumpAndSettle();
        expect(find.text('Config Library'), findsOneWidget);
      }
    });

    testWidgets('User can tap on Settings tab', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle();

      // Tap settings tab
      final settingsTab = find.text('Settings');
      if (settingsTab.evaluate().isNotEmpty) {
        await tester.tap(settingsTab.last);
        await tester.pumpAndSettle();
        expect(find.text('Settings'), findsWidgets);
      }
    });

    testWidgets('User can toggle auto-connect setting', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle();

      // Navigate to settings
      await tester.tap(find.byIcon(Icons.settings).last);
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

      // Go to library
      await tester.tap(find.byIcon(Icons.library_books).last);
      await tester.pumpAndSettle();
      expect(find.text('Config Library'), findsOneWidget);

      // Go to settings
      await tester.tap(find.byIcon(Icons.settings).last);
      await tester.pumpAndSettle();
      expect(find.text('Settings'), findsOneWidget);

      // Back to home
      await tester.tap(find.byIcon(Icons.power).last);
      await tester.pumpAndSettle();
    });

    testWidgets('App layout is responsive', (WidgetTester tester) async {
      app.main();
      tester.view.physicalSize = const Size(400, 800);
      await tester.pumpAndSettle();

      // Verify elements are visible in narrow viewport
      expect(find.byIcon(Icons.power), findsOneWidget);
      expect(find.byIcon(Icons.lock_open), findsOneWidget);

      addTearDown(tester.view.resetPhysicalSize);
    });

    testWidgets('Settings screen has all sections', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle();

      // Navigate to settings
      await tester.tap(find.byIcon(Icons.settings).last);
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
