import 'package:get/get.dart';
import 'package:logger/logger.dart';
import 'dart:developer' as developer;
import 'package:intl/intl.dart';

/// Circular log buffer entry
class LogEntry {
  final DateTime timestamp;
  final Level level;
  final String message;
  final String? stackTrace;

  LogEntry({
    required this.timestamp,
    required this.level,
    required this.message,
    this.stackTrace,
  });

  String get formattedTime {
    return DateFormat('HH:mm:ss.SSS').format(timestamp);
  }

  String get levelName {
    return level.toString().split('.').last.toUpperCase();
  }

  @override
  String toString() {
    return '[$formattedTime] $levelName: $message';
  }
}

/// Debug service for in-app logging and diagnostics
class DebugService extends GetxService {
  static const int maxLogEntries = 500; // Circular buffer size

  final _logger = Logger();
  final _logBuffer = RxList<LogEntry>();
  final isDebugMode = false.obs;

  /// Get all log entries
  List<LogEntry> get logEntries => _logBuffer.toList();

  /// Get log entry count
  int get logCount => _logBuffer.length;

  @override
  void onInit() {
    super.onInit();
    _logger.i('Debug service initialized');
  }

  /// Log a message at specified level
  void log(
    String message, {
    required Level level,
    String? stackTrace,
  }) {
    final entry = LogEntry(
      timestamp: DateTime.now(),
      level: level,
      message: message,
      stackTrace: stackTrace,
    );

    _logBuffer.add(entry);

    // Maintain circular buffer size
    if (_logBuffer.length > maxLogEntries) {
      _logBuffer.removeAt(0);
    }

    // Also log to system
    developer.log(
      message,
      level: level.value,
      name: 'blackout_kit',
      stackTrace: stackTrace,
    );
  }

  /// Log info level
  void logInfo(String message) {
    log(message, level: Level.info);
    _logger.i(message);
  }

  /// Log warning level
  void logWarning(String message, {String? stackTrace}) {
    log(message, level: Level.warning, stackTrace: stackTrace);
    _logger.w(message);
  }

  /// Log error level
  void logError(String message, {String? stackTrace}) {
    log(message, level: Level.error, stackTrace: stackTrace);
    _logger.e(message);
  }

  /// Log debug level
  void logDebug(String message) {
    log(message, level: Level.debug);
    _logger.d(message);
  }

  /// Clear all logs
  void clearLogs() {
    _logBuffer.clear();
    logInfo('Log buffer cleared');
  }

  /// Get logs as formatted string
  String getLogsAsString() {
    return _logBuffer.map((entry) => entry.toString()).join('\n');
  }

  /// Get debug information
  Map<String, dynamic> getDebugInfo() {
    return {
      'app_name': 'Blackout Kit',
      'version': '1.0.0', // TODO: Get from pubspec
      'timestamp': DateTime.now().toIso8601String(),
      'log_count': _logBuffer.length,
      'debug_mode': isDebugMode.value,
      'logs': _logBuffer
          .map((e) => {
                'timestamp': e.timestamp.toIso8601String(),
                'level': e.levelName,
                'message': e.message,
              })
          .toList(),
    };
  }

  /// Export logs as formatted text
  String exportLogsAsText() {
    final buffer = StringBuffer();
    buffer.writeln('=== Blackout Kit Debug Logs ===');
    buffer.writeln('Exported: ${DateTime.now().toIso8601String()}');
    buffer.writeln('Total Entries: ${_logBuffer.length}');
    buffer.writeln('');
    buffer.writeln(getLogsAsString());
    return buffer.toString();
  }

  /// Get recent logs (last N entries)
  List<LogEntry> getRecentLogs({int count = 50}) {
    final startIndex = (_logBuffer.length - count).clamp(0, _logBuffer.length);
    return _logBuffer.sublist(startIndex);
  }

  /// Get logs filtered by level
  List<LogEntry> getLogsByLevel(Level level) {
    return _logBuffer.where((entry) => entry.level == level).toList();
  }

  /// Get logs filtered by time range
  List<LogEntry> getLogsByTimeRange(DateTime start, DateTime end) {
    return _logBuffer
        .where((entry) =>
            entry.timestamp.isAfter(start) && entry.timestamp.isBefore(end))
        .toList();
  }

  /// Get error logs only
  List<LogEntry> getErrorLogs() {
    return getLogsByLevel(Level.error);
  }

  /// Get warning logs only
  List<LogEntry> getWarningLogs() {
    return getLogsByLevel(Level.warning);
  }

  /// Toggle debug mode
  void toggleDebugMode() {
    isDebugMode.toggle();
    logInfo('Debug mode: ${isDebugMode.value}');
  }

  /// Cleanup
  @override
  void onClose() {
    logInfo('Debug service closing');
    super.onClose();
  }
}
