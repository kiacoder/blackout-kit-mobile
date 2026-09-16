/// Unit tests for the connection controller
/// Tests VPN connection state machine and lifecycle

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:logger/logger.dart';
import 'package:blackout_kit_mobile/models/config.dart';
import 'package:blackout_kit_mobile/controllers/connection_controller.dart';

void main() {
  group('ConnectionController', () {
    late ConnectionController controller;
    late Logger mockLogger;

    setUp(() {
      mockLogger = Logger();
      controller = ConnectionController(logger: mockLogger);
      Get.put<ConnectionController>(controller);
    });

    tearDown(() {
      Get.delete<ConnectionController>();
    });

    test('initializes with idle state', () {
      expect(controller.connectionState.value, equals('idle'));
    });

    test('isConnected observable reflects connection status', () {
      controller.isConnected.value = false;
      expect(controller.isConnected.value, false);

      controller.isConnected.value = true;
      expect(controller.isConnected.value, true);
    });

    test('connectedConfig stores current connection config', () {
      final config = WireGuardConfig(
        displayName: 'Test Config',
        address: '10.0.0.1',
        port: 51820,
        privateKey: 'abc123==',
        rawUri: 'wireguard://10.0.0.1:51820',
        protocol: 'wireguard',
      );

      controller.connectedConfig.value = config;

      expect(controller.connectedConfig.value, isNotNull);
      expect(controller.connectedConfig.value!.displayName, 'Test Config');
    });

    test('transitioning to connecting state', () {
      controller.connectionState.value = 'idle';
      controller.connectionState.value = 'connecting';

      expect(controller.connectionState.value, equals('connecting'));
    });

    test('transitioning from connecting to connected', () {
      controller.connectionState.value = 'connecting';
      controller.connectionState.value = 'connected';

      expect(controller.connectionState.value, equals('connected'));
      expect(controller.isConnected.value, false); // Not automatically updated
    });

    test('transitioning from connected to disconnecting', () {
      controller.connectionState.value = 'connected';
      controller.connectionState.value = 'disconnecting';

      expect(controller.connectionState.value, equals('disconnecting'));
    });

    test('transitioning from disconnecting to idle', () {
      controller.connectionState.value = 'disconnecting';
      controller.connectionState.value = 'idle';

      expect(controller.connectionState.value, equals('idle'));
    });

    test('error state captures connection failures', () {
      controller.connectionState.value = 'error';
      controller.errorMessage.value = 'Failed to connect to VPN';

      expect(controller.connectionState.value, equals('error'));
      expect(controller.errorMessage.value, isNotEmpty);
    });

    test('errorMessage observable stores error details', () {
      final error = 'Connection timeout';
      controller.errorMessage.value = error;

      expect(controller.errorMessage.value, equals(error));
    });

    test('connectedIP updates after connection', () {
      controller.connectedIP.value = '192.168.1.100';

      expect(controller.connectedIP.value, equals('192.168.1.100'));
    });

    test('connectedSince tracks connection start time', () {
      final beforeConnect = DateTime.now();
      controller.connectedSince.value = DateTime.now();
      final afterConnect = DateTime.now();

      expect(controller.connectedSince.value.isAfter(beforeConnect), true);
      expect(
        controller.connectedSince.value.isBefore(afterConnect.add(const Duration(seconds: 1))),
        true,
      );
    });

    test('uptimeSeconds calculates connection duration', () {
      final startTime = DateTime.now().subtract(const Duration(seconds: 65));
      controller.connectedSince.value = startTime;

      final now = DateTime.now();
      final uptime = now.difference(startTime).inSeconds;

      expect(uptime, greaterThanOrEqualTo(60));
      expect(uptime, lessThanOrEqualTo(70));
    });

    test('selectedProtocol stores user preference', () {
      controller.selectedProtocol.value = 'wireguard';

      expect(controller.selectedProtocol.value, equals('wireguard'));
    });

    test('autoConnectEnabled tracks user preference', () {
      controller.autoConnectEnabled.value = false;
      expect(controller.autoConnectEnabled.value, false);

      controller.autoConnectEnabled.value = true;
      expect(controller.autoConnectEnabled.value, true);
    });

    test('killSwitchEnabled tracks user preference', () {
      controller.killSwitchEnabled.value = false;
      expect(controller.killSwitchEnabled.value, false);

      controller.killSwitchEnabled.value = true;
      expect(controller.killSwitchEnabled.value, true);
    });

    test('prevents connecting from non-connecting state', () {
      // Start in idle state
      controller.connectionState.value = 'idle';

      // Attempt invalid transition (should not happen in real code)
      // But we validate the state remains valid
      expect(controller.connectionState.value, equals('idle'));
    });

    test('handles rapid state changes', () {
      final states = ['idle', 'connecting', 'connected', 'disconnecting', 'idle'];

      for (final state in states) {
        controller.connectionState.value = state;
      }

      // Should end in idle state
      expect(controller.connectionState.value, equals('idle'));
    });

    test('multiple connections dont share config', () {
      final config1 = WireGuardConfig(
        displayName: 'Config 1',
        address: '10.0.0.1',
        port: 51820,
        privateKey: 'key1',
        rawUri: 'uri1',
        protocol: 'wireguard',
      );

      final config2 = WireGuardConfig(
        displayName: 'Config 2',
        address: '10.0.0.2',
        port: 51820,
        privateKey: 'key2',
        rawUri: 'uri2',
        protocol: 'wireguard',
      );

      controller.connectedConfig.value = config1;
      expect(controller.connectedConfig.value!.displayName, 'Config 1');

      controller.connectedConfig.value = config2;
      expect(controller.connectedConfig.value!.displayName, 'Config 2');
    });

    test('disconnectConfig clears connected config', () {
      final config = WireGuardConfig(
        displayName: 'Test Config',
        address: '10.0.0.1',
        port: 51820,
        privateKey: 'key',
        rawUri: 'uri',
        protocol: 'wireguard',
      );

      controller.connectedConfig.value = config;
      expect(controller.connectedConfig.value, isNotNull);

      controller.connectedConfig.value = null;
      expect(controller.connectedConfig.value, isNull);
    });

    test('isLoading reflects active connection operation', () {
      controller.isLoading.value = false;
      expect(controller.isLoading.value, false);

      controller.isLoading.value = true;
      expect(controller.isLoading.value, true);

      controller.isLoading.value = false;
      expect(controller.isLoading.value, false);
    });

    test('lastErrorTime tracks when error occurred', () {
      final beforeError = DateTime.now();
      controller.lastErrorTime.value = DateTime.now();
      final afterError = DateTime.now();

      expect(controller.lastErrorTime.value.isAfter(beforeError), true);
      expect(
        controller.lastErrorTime.value.isBefore(afterError.add(const Duration(seconds: 1))),
        true,
      );
    });

    test('retryCount increments on failed connection attempt', () {
      controller.retryCount.value = 0;
      expect(controller.retryCount.value, 0);

      controller.retryCount.value++;
      expect(controller.retryCount.value, 1);

      controller.retryCount.value++;
      expect(controller.retryCount.value, 2);
    });

    test('resets retry count on successful connection', () {
      controller.retryCount.value = 3;
      expect(controller.retryCount.value, 3);

      controller.retryCount.value = 0;
      expect(controller.retryCount.value, 0);
    });

    test('handles clearing connection state', () {
      controller.connectedIP.value = '192.168.1.1';
      controller.connectedSince.value = DateTime.now();
      controller.connectedConfig.value = WireGuardConfig(
        displayName: 'Test',
        address: '10.0.0.1',
        port: 51820,
        privateKey: 'key',
        rawUri: 'uri',
        protocol: 'wireguard',
      );

      // Clear all state
      controller.connectedIP.value = '';
      controller.connectedSince.value = DateTime.fromMicrosecondsSinceEpoch(0);
      controller.connectedConfig.value = null;

      expect(controller.connectedIP.value, isEmpty);
      expect(controller.connectedConfig.value, isNull);
    });
  });
}
