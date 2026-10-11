/// Regression tests for the reachability probe's treatment of refused
/// connections.
///
/// The probe used to count ECONNREFUSED as "reachable" on the theory that a
/// RST proves the host is alive — which made censors' instant-RST behaviour
/// the *most attractive* result in the ranking: the fastest server in the list
/// was the one the censor had just refused. Refused is now a failure.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:blackout_kit_mobile/models/config.dart';
import 'package:blackout_kit_mobile/services/tester_service.dart';

Config _config(String host, int port) {
  final parsed = ConfigParser.parseMultiple(
    'ss://YWVzLTI1Ni1nY206cGFzc3dvcmQ@$host:$port#probe-test',
  );
  return parsed.single;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ServerSocket server;
  late int openPort;

  setUpAll(() async {
    server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    openPort = server.port;
  });

  tearDownAll(() async {
    await server.close();
  });

  test('a listening TCP port measures as working', () async {
    final tester = TesterService();
    final result = await tester.testConfig(
      _config('127.0.0.1', openPort),
      attempts: 1,
    );

    expect(result.isWorking, isTrue, reason: result.error);
    expect(result.latencyMs, isNotNull);
  });

  test('a refused connection is a failure, not "reachable"', () async {
    // Grab a port, then release it: connecting back to it is refused
    // immediately on loopback, which is exactly the RST the censor sends.
    final raw = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final closedPort = raw.port;
    await raw.close();

    final tester = TesterService();
    final result = await tester.testConfig(
      _config('127.0.0.1', closedPort),
      attempts: 1,
    );

    expect(result.isWorking, isFalse,
        reason: 'a refused port must not rank as a working server');
    expect(result.error, isNotNull);
  });
}
