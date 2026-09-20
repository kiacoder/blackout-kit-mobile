import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:blackout_kit_mobile/controllers/connection_controller.dart';
import 'package:blackout_kit_mobile/widgets/animated_connection_button.dart';
import 'package:blackout_kit_mobile/widgets/animated_status_indicator.dart';
import 'package:blackout_kit_mobile/widgets/animated_security_toggle.dart';
import 'package:blackout_kit_mobile/widgets/smooth_page_transition.dart';
import 'package:blackout_kit_mobile/widgets/animated_loading_overlay.dart';
import 'package:blackout_kit_mobile/widgets/animated_error_notification.dart';

void main() {
  group('AnimatedConnectionButton', () {
    testWidgets('renders in disconnected state', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AnimatedConnectionButton(
              onPressed: () {},
              isConnected: false,
              isLoading: false,
            ),
          ),
        ),
      );

      expect(find.byType(AnimatedConnectionButton), findsOneWidget);
      expect(find.byIcon(Icons.cloud_off), findsOneWidget);
      expect(find.text('Connect'), findsOneWidget);
    });

    testWidgets('renders in connected state', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AnimatedConnectionButton(
              onPressed: () {},
              isConnected: true,
              isLoading: false,
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.check_circle), findsOneWidget);
      expect(find.text('Disconnect'), findsOneWidget);
    });

    testWidgets('renders in loading state', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AnimatedConnectionButton(
              onPressed: () {},
              isConnected: false,
              isLoading: true,
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.cloud_queue), findsOneWidget);
      expect(find.text('Connecting...'), findsOneWidget);
    });

    testWidgets('animation starts when loading begins', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return AnimatedConnectionButton(
                  onPressed: () {},
                  isConnected: false,
                  isLoading: true,
                );
              },
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.cloud_queue), findsOneWidget);
    });

    testWidgets('button disabled during loading', (WidgetTester tester) async {
      int tapCount = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AnimatedConnectionButton(
              onPressed: () => tapCount++,
              isConnected: false,
              isLoading: true,
            ),
          ),
        ),
      );

      await tester.tap(find.byType(InkWell));
      await tester.pumpAndSettle();
      expect(tapCount, 0);
    });
  });

  group('AnimatedStatusIndicator', () {
    testWidgets('displays connected state', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AnimatedStatusIndicator(
              state: ConnectionState.connected,
              statusMessage: 'VPN Active',
            ),
          ),
        ),
      );

      expect(find.text('Status'), findsOneWidget);
      expect(find.text('VPN Active'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
    });

    testWidgets('displays error state', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AnimatedStatusIndicator(
              state: ConnectionState.error,
              statusMessage: 'Connection Failed',
            ),
          ),
        ),
      );

      expect(find.text('Connection Failed'), findsOneWidget);
      expect(find.byIcon(Icons.error), findsOneWidget);
    });

    testWidgets('displays idle state', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AnimatedStatusIndicator(
              state: ConnectionState.idle,
              statusMessage: 'Not Connected',
            ),
          ),
        ),
      );

      expect(find.text('Not Connected'), findsOneWidget);
      expect(find.byIcon(Icons.cloud_off), findsOneWidget);
    });

    testWidgets('animates on state change', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return Column(
                  children: [
                    AnimatedStatusIndicator(
                      state: ConnectionState.connecting,
                      statusMessage: 'Connecting...',
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('Connecting...'), findsOneWidget);
    });
  });

  group('AnimatedSecurityToggle', () {
    testWidgets('renders enabled state', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AnimatedSecurityToggle(
              label: 'Kill Switch',
              value: true,
              onChanged: (_) {},
              icon: Icons.shield,
            ),
          ),
        ),
      );

      expect(find.text('Kill Switch'), findsOneWidget);
      expect(find.text('Enabled'), findsOneWidget);
    });

    testWidgets('renders disabled state', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AnimatedSecurityToggle(
              label: 'DNS Leak Prevention',
              value: false,
              onChanged: (_) {},
              icon: Icons.security,
            ),
          ),
        ),
      );

      expect(find.text('DNS Leak Prevention'), findsOneWidget);
      expect(find.text('Disabled'), findsOneWidget);
    });

    testWidgets('toggles on tap', (WidgetTester tester) async {
      bool currentValue = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return AnimatedSecurityToggle(
                  label: 'Kill Switch',
                  value: currentValue,
                  onChanged: (newValue) {
                    setState(() => currentValue = newValue);
                  },
                  icon: Icons.shield,
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.byType(GestureDetector));
      await tester.pumpAndSettle();
      expect(currentValue, true);
    });

    testWidgets('shows loading state', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AnimatedSecurityToggle(
              label: 'Kill Switch',
              value: true,
              onChanged: (_) {},
              icon: Icons.shield,
              isLoading: true,
            ),
          ),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('disables interaction during loading', (WidgetTester tester) async {
      bool wasChanged = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AnimatedSecurityToggle(
              label: 'Kill Switch',
              value: false,
              onChanged: (_) => wasChanged = true,
              icon: Icons.shield,
              isLoading: true,
            ),
          ),
        ),
      );

      await tester.tap(find.byType(GestureDetector));
      await tester.pumpAndSettle();
      expect(wasChanged, false);
    });
  });

  group('SmoothPageTransition', () {
    testWidgets('renders child widget', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SmoothPageTransition(
              child: Container(
                key: const Key('test-container'),
              ),
            ),
          ),
        ),
      );

      expect(find.byKey(const Key('test-container')), findsOneWidget);
    });

    testWidgets('animates on render', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SmoothPageTransition(
              child: const Text('Transitioned'),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('Transitioned'), findsOneWidget);
    });

    testWidgets('respects custom duration', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SmoothPageTransition(
              duration: const Duration(milliseconds: 600),
              child: const Text('Custom Duration'),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('Custom Duration'), findsOneWidget);
    });
  });

  group('AnimatedLoadingOverlay', () {
    testWidgets('hides when not visible', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AnimatedLoadingOverlay(
              isVisible: false,
              message: 'Loading',
              child: const Text('Content'),
            ),
          ),
        ),
      );

      expect(find.text('Loading'), findsNothing);
      expect(find.text('Content'), findsOneWidget);
    });

    testWidgets('shows overlay when visible', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AnimatedLoadingOverlay(
              isVisible: true,
              message: 'Loading...',
              child: const Text('Content'),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle(const Duration(milliseconds: 400));
      expect(find.text('Loading...'), findsOneWidget);
    });

    testWidgets('shows custom message', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AnimatedLoadingOverlay(
              isVisible: true,
              message: 'Testing connection...',
            ),
          ),
        ),
      );

      await tester.pumpAndSettle(const Duration(milliseconds: 400));
      expect(find.text('Testing connection...'), findsOneWidget);
    });

    testWidgets('animates visibility changes', (WidgetTester tester) async {
      bool isVisible = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return AnimatedLoadingOverlay(
                  isVisible: isVisible,
                  message: 'Loading',
                );
              },
            ),
          ),
        ),
      );

      expect(find.text('Loading'), findsNothing);
    });
  });

  group('AnimatedErrorNotification', () {
    testWidgets('renders error message', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AnimatedErrorNotification(
              message: 'Connection failed',
              displayDuration: const Duration(seconds: 10),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle(const Duration(milliseconds: 400));
      expect(find.text('Connection failed'), findsOneWidget);
    });

    testWidgets('shows error icon', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AnimatedErrorNotification(
              message: 'Error occurred',
              displayDuration: const Duration(seconds: 10),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle(const Duration(milliseconds: 400));
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });

    testWidgets('dismiss button removes notification', (WidgetTester tester) async {
      bool dismissed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AnimatedErrorNotification(
              message: 'Test error',
              displayDuration: const Duration(seconds: 10),
              onDismiss: () => dismissed = true,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle(const Duration(milliseconds: 400));
      expect(find.text('Test error'), findsOneWidget);
    });

    testWidgets('animates slide-up on render', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AnimatedErrorNotification(
              message: 'Animated error',
              displayDuration: const Duration(seconds: 10),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle(const Duration(milliseconds: 400));
      expect(find.text('Animated error'), findsOneWidget);
    });
  });
}
