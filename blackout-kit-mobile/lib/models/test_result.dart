/// Test result for config speed and reliability testing.

enum TestStatus {
  notTested,
  testing,
  success,
  timeout,
  failed,
}

class TestResult {
  final String configHash;
  final TestStatus status;
  final DateTime? testedAt;
  final int? latencyMs;
  final double? speedMbps;
  final int? successCount;
  final int? totalCount;
  final String? error;

  const TestResult({
    required this.configHash,
    this.status = TestStatus.notTested,
    this.testedAt,
    this.latencyMs,
    this.speedMbps,
    this.successCount,
    this.totalCount,
    this.error,
  });

  /// Whether config is working
  bool get isWorking => status == TestStatus.success;

  /// Reliability percentage (if tested)
  double get reliability {
    if (successCount == null || totalCount == null || totalCount == 0) return 0;
    return (successCount! / totalCount!) * 100;
  }

  /// Whether test needs refresh
  bool get needsRefresh {
    if (testedAt == null) return true;
    final duration = DateTime.now().difference(testedAt!);
    return duration.inHours >= 12; // Refresh every 12 hours
  }

  /// Copy with modifications
  TestResult copyWith({
    String? configHash,
    TestStatus? status,
    DateTime? testedAt,
    int? latencyMs,
    double? speedMbps,
    int? successCount,
    int? totalCount,
    String? error,
  }) {
    return TestResult(
      configHash: configHash ?? this.configHash,
      status: status ?? this.status,
      testedAt: testedAt ?? this.testedAt,
      latencyMs: latencyMs ?? this.latencyMs,
      speedMbps: speedMbps ?? this.speedMbps,
      successCount: successCount ?? this.successCount,
      totalCount: totalCount ?? this.totalCount,
      error: error ?? this.error,
    );
  }

  /// Create a "testing" state
  factory TestResult.testing(String configHash) {
    return TestResult(
      configHash: configHash,
      status: TestStatus.testing,
      testedAt: DateTime.now(),
    );
  }

  /// Create a success result
  factory TestResult.success({
    required String configHash,
    int? latencyMs,
    double? speedMbps,
    int? successCount,
    int? totalCount,
  }) {
    return TestResult(
      configHash: configHash,
      status: TestStatus.success,
      testedAt: DateTime.now(),
      latencyMs: latencyMs,
      speedMbps: speedMbps,
      successCount: successCount,
      totalCount: totalCount,
    );
  }

  /// Create a failure result
  factory TestResult.failed({
    required String configHash,
    String? error,
    TestStatus status = TestStatus.failed,
  }) {
    return TestResult(
      configHash: configHash,
      status: status,
      testedAt: DateTime.now(),
      error: error,
    );
  }

  @override
  String toString() =>
    'TestResult(hash=$configHash, status=$status, speed=${speedMbps?.toStringAsFixed(2)}Mbps)';

  /// Convert to JSON for local storage
  Map<String, dynamic> toJson() => {
    'configHash': configHash,
    'status': status.toString(),
    'testedAt': testedAt?.toIso8601String(),
    'latencyMs': latencyMs,
    'speedMbps': speedMbps,
    'successCount': successCount,
    'totalCount': totalCount,
    'error': error,
  };

  /// Create from JSON
  factory TestResult.fromJson(Map<String, dynamic> json) {
    return TestResult(
      configHash: json['configHash'] as String,
      status: _parseTestStatus(json['status'] as String?),
      testedAt: json['testedAt'] != null
          ? DateTime.parse(json['testedAt'] as String)
          : null,
      latencyMs: json['latencyMs'] as int?,
      speedMbps: (json['speedMbps'] as num?)?.toDouble(),
      successCount: json['successCount'] as int?,
      totalCount: json['totalCount'] as int?,
      error: json['error'] as String?,
    );
  }
}

TestStatus _parseTestStatus(String? status) {
  if (status == null) return TestStatus.notTested;
  return TestStatus.values.firstWhere(
    (e) => e.toString() == 'TestStatus.$status',
    orElse: () => TestStatus.notTested,
  );
}

/// Config ranking by speed (for quick connect)
class ConfigRanking {
  final String configHash;
  final int rank; // 1 = fastest
  final double? speedMbps;
  final bool isWorking;

  const ConfigRanking({
    required this.configHash,
    required this.rank,
    this.speedMbps,
    this.isWorking = true,
  });

  @override
  String toString() =>
    'ConfigRanking(rank=$rank, hash=${configHash.substring(0, 8)}..., speed=$speedMbps)';
}
