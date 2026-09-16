import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:blackout_kit_mobile/services/debug_service.dart';

void main() {
  late DebugService debugService;

  setUp(() {
    debugService = DebugService();
    debugService.onInit();
  });

  group('DebugService', () {
    test('initializes with empty logs', () {
      expect(debugService.logCount, 0);
      expect(debugService.logEntries.isEmpty, true);
    });

    test('logs info level message', () {
      debugService.logInfo('Test info message');
      expect(debugService.logCount, 1);
      expect(debugService.logEntries[0].message, 'Test info message');
      expect(debugService.logEntries[0].level, Level.info);
    });

    test('logs warning level message', () {
      debugService.logWarning('Test warning message');
      expect(debugService.logCount, 1);
      expect(debugService.logEntries[0].message, 'Test warning message');
      expect(debugService.logEntries[0].level, Level.warning);
    });

    test('logs error level message', () {
      debugService.logError('Test error message');
      expect(debugService.logCount, 1);
      expect(debugService.logEntries[0].message, 'Test error message');
      expect(debugService.logEntries[0].level, Level.error);
    });

    test('logs debug level message', () {
      debugService.logDebug('Test debug message');
      expect(debugService.logCount, 1);
      expect(debugService.logEntries[0].message, 'Test debug message');
      expect(debugService.logEntries[0].level, Level.debug);
    });

    test('logs with custom level', () {
      debugService.log('Custom message', level: Level.verbose);
      expect(debugService.logCount, 1);
      expect(debugService.logEntries[0].message, 'Custom message');
      expect(debugService.logEntries[0].level, Level.verbose);
    });

    test('logs include timestamp', () {
      final beforeLog = DateTime.now();
      debugService.logInfo('Test message');
      final afterLog = DateTime.now();

      final entry = debugService.logEntries[0];
      expect(entry.timestamp.isAfter(beforeLog), true);
      expect(entry.timestamp.isBefore(afterLog.add(const Duration(seconds: 1))),
          true);
    });

    test('clears all logs', () {
      debugService.logInfo('Message 1');
      debugService.logInfo('Message 2');
      expect(debugService.logCount, 2);

      debugService.clearLogs();
      expect(debugService.logCount, 1); // clearLogs itself logs a message
    });

    test('maintains circular buffer size limit', () {
      // Log more than max entries
      for (int i = 0; i < 510; i++) {
        debugService.logInfo('Message $i');
      }

      expect(debugService.logCount, 500);
    });

    test('circular buffer discards oldest entries', () {
      for (int i = 0; i < 502; i++) {
        debugService.logInfo('Message $i');
      }

      // First message should be gone, second should be at index 0
      final entries = debugService.logEntries;
      expect(entries.length, 500);
      expect(entries[0].message, 'Message 2');
    });

    test('gets logs as formatted string', () {
      debugService.logInfo('Test message');
      debugService.logWarning('Warning message');

      final logsString = debugService.getLogsAsString();
      expect(logsString.contains('Test message'), true);
      expect(logsString.contains('WARNING'), true);
    });

    test('gets recent logs', () {
      for (int i = 0; i < 100; i++) {
        debugService.logInfo('Message $i');
      }

      final recent = debugService.getRecentLogs(count: 10);
      expect(recent.length, 10);
      expect(recent.last.message, 'Message 99');
    });

    test('gets logs filtered by level', () {
      debugService.logInfo('Info message');
      debugService.logWarning('Warning message');
      debugService.logError('Error message');

      final errorLogs = debugService.getLogsByLevel(Level.error);
      expect(errorLogs.length, 1);
      expect(errorLogs[0].level, Level.error);
    });

    test('gets error logs', () {
      debugService.logInfo('Info message');
      debugService.logError('Error 1');
      debugService.logError('Error 2');

      final errorLogs = debugService.getErrorLogs();
      expect(errorLogs.length, 2);
      expect(errorLogs[0].message, 'Error 1');
      expect(errorLogs[1].message, 'Error 2');
    });

    test('gets warning logs', () {
      debugService.logInfo('Info message');
      debugService.logWarning('Warning 1');
      debugService.logWarning('Warning 2');

      final warningLogs = debugService.getWarningLogs();
      expect(warningLogs.length, 2);
      expect(warningLogs[0].message, 'Warning 1');
      expect(warningLogs[1].message, 'Warning 2');
    });

    test('gets logs filtered by time range', () {
      final now = DateTime.now();
      debugService.logInfo('Message 1');

      final future = now.add(const Duration(seconds: 5));
      final past = now.subtract(const Duration(seconds: 5));

      final logsInRange = debugService.getLogsByTimeRange(past, future);
      expect(logsInRange.length > 0, true);
    });

    test('gets empty list for logs outside time range', () {
      debugService.logInfo('Message 1');

      final future = DateTime.now().add(const Duration(seconds: 1));
      final farFuture = future.add(const Duration(hours: 1));

      final logsInRange = debugService.getLogsByTimeRange(future, farFuture);
      expect(logsInRange.isEmpty, true);
    });

    test('exports logs as formatted text', () {
      debugService.logInfo('Test message');
      debugService.logError('Error message');

      final exported = debugService.exportLogsAsText();
      expect(exported.contains('Blackout Kit Debug Logs'), true);
      expect(exported.contains('Test message'), true);
      expect(exported.contains('Error message'), true);
      expect(exported.contains('Total Entries'), true);
    });

    test('gets debug info', () {
      debugService.logInfo('Test message');
      debugService.logError('Error message');

      final debugInfo = debugService.getDebugInfo();
      expect(debugInfo['app_name'], 'Blackout Kit');
      expect(debugInfo['version'], '1.0.0');
      expect(debugInfo['log_count'], greaterThan(0));
      expect(debugInfo['debug_mode'], false);
      expect(debugInfo['logs'], isA<List>());
      expect(debugInfo.containsKey('timestamp'), true);
    });

    test('debug mode toggle', () {
      expect(debugService.isDebugMode.value, false);
      debugService.toggleDebugMode();
      expect(debugService.isDebugMode.value, true);
      debugService.toggleDebugMode();
      expect(debugService.isDebugMode.value, false);
    });

    test('debug mode toggle logs changes', () {
      final initialCount = debugService.logCount;
      debugService.toggleDebugMode();
      expect(debugService.logCount, greaterThan(initialCount));
    });

    test('log entry formatted time', () {
      debugService.logInfo('Test message');
      final entry = debugService.logEntries.last;
      expect(entry.formattedTime, isNotEmpty);
      // Format should be HH:mm:ss.SSS
      expect(
        RegExp(r'^\d{2}:\d{2}:\d{2}\.\d{3}$').hasMatch(entry.formattedTime),
        true,
      );
    });

    test('log entry level name', () {
      debugService.logInfo('Info');
      debugService.logWarning('Warning');
      debugService.logError('Error');
      debugService.logDebug('Debug');

      final entries = debugService.logEntries;
      expect(entries[0].levelName, 'INFO');
      expect(entries[1].levelName, 'WARNING');
      expect(entries[2].levelName, 'ERROR');
      expect(entries[3].levelName, 'DEBUG');
    });

    test('log entry to string includes timestamp and level', () {
      debugService.logInfo('Test message');
      final entry = debugService.logEntries.last;
      final entryString = entry.toString();

      expect(entryString.contains('['), true);
      expect(entryString.contains(']'), true);
      expect(entryString.contains('INFO'), true);
      expect(entryString.contains('Test message'), true);
    });

    test('multiple log levels in sequence', () {
      debugService.logInfo('Info');
      debugService.logWarning('Warning');
      debugService.logError('Error');
      debugService.logDebug('Debug');

      expect(debugService.logCount, 4);
      expect(debugService.getErrorLogs().length, 1);
      expect(debugService.getWarningLogs().length, 1);
    });

    test('stack trace is captured when provided', () {
      const stackTrace = 'at main() in main.dart:42';
      debugService.logError('Error with trace', stackTrace: stackTrace);

      final entry = debugService.logEntries.last;
      expect(entry.stackTrace, stackTrace);
    });

    test('observable log count updates on new log', () {
      int updateCount = 0;
      debugService.logEntries.listen((_) {
        updateCount++;
      });

      debugService.logInfo('Test message');
      expect(updateCount > 0, true);
    });

    test('closes cleanly', () {
      debugService.logInfo('Before close');
      debugService.onClose();
      expect(debugService.logCount > 0, true);
    });
  });
}
