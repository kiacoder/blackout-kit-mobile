/// Config source model (GitHub repo or manual configs).
/// Tracks where configs come from and their metadata.

class ConfigSource {
  final String id;
  final String name;
  final String owner;
  final String repo;
  final String? branch;
  final SourceType type;
  final DateTime? lastFetched;
  final int configCount;
  final bool isEnabled;
  final String? error;

  const ConfigSource({
    required this.id,
    required this.name,
    required this.owner,
    required this.repo,
    this.branch = 'main',
    this.type = SourceType.githubRepo,
    this.lastFetched,
    this.configCount = 0,
    this.isEnabled = true,
    this.error,
  });

  /// GitHub API URL for this repo
  String get githubApiUrl =>
    'https://api.github.com/repos/$owner/$repo/contents';

  /// GitHub web URL
  String get githubWebUrl =>
    'https://github.com/$owner/$repo';

  /// Full source identifier
  String get fullId => '$owner/$repo';

  /// Whether source needs refresh
  bool get needsRefresh {
    if (lastFetched == null) return true;
    final duration = DateTime.now().difference(lastFetched!);
    return duration.inHours >= 1; // Refresh every hour
  }

  /// Copy with modifications
  ConfigSource copyWith({
    String? id,
    String? name,
    String? owner,
    String? repo,
    String? branch,
    SourceType? type,
    DateTime? lastFetched,
    int? configCount,
    bool? isEnabled,
    String? error,
  }) {
    return ConfigSource(
      id: id ?? this.id,
      name: name ?? this.name,
      owner: owner ?? this.owner,
      repo: repo ?? this.repo,
      branch: branch ?? this.branch,
      type: type ?? this.type,
      lastFetched: lastFetched ?? this.lastFetched,
      configCount: configCount ?? this.configCount,
      isEnabled: isEnabled ?? this.isEnabled,
      error: error ?? this.error,
    );
  }

  @override
  String toString() =>
    'ConfigSource(id=$id, name=$name, owner=$owner, repo=$repo, configs=$configCount)';

  /// Convert to JSON for local storage
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'owner': owner,
    'repo': repo,
    'branch': branch,
    'type': type.toString(),
    'lastFetched': lastFetched?.toIso8601String(),
    'configCount': configCount,
    'isEnabled': isEnabled,
    'error': error,
  };

  /// Create from JSON
  factory ConfigSource.fromJson(Map<String, dynamic> json) {
    return ConfigSource(
      id: json['id'] as String,
      name: json['name'] as String,
      owner: json['owner'] as String,
      repo: json['repo'] as String,
      branch: json['branch'] as String?,
      type: _parseSourceType(json['type'] as String?),
      lastFetched: json['lastFetched'] != null
          ? DateTime.parse(json['lastFetched'] as String)
          : null,
      configCount: json['configCount'] as int? ?? 0,
      isEnabled: json['isEnabled'] as bool? ?? true,
      error: json['error'] as String?,
    );
  }
}

enum SourceType {
  githubRepo,
  manual,
  userAdded,
}

SourceType _parseSourceType(String? type) {
  return SourceType.values.firstWhere(
    (e) => e.toString() == 'SourceType.$type',
    orElse: () => SourceType.githubRepo,
  );
}

/// Hardcoded trusted sources (from CLI)
class TrustedSources {
  static final List<ConfigSource> sources = [
    // Example trusted repos (populate with real repos)
    ConfigSource(
      id: 'trusted-1',
      name: 'Free VPN Configs (Official)',
      owner: 'free-vpn-configs',
      repo: 'configs',
      configCount: 0,
    ),
    ConfigSource(
      id: 'trusted-2',
      name: 'Community Configs',
      owner: 'open-vpn-community',
      repo: 'free-configs',
      configCount: 0,
    ),
    // Add more hardcoded trusted sources
  ];

  /// Get all enabled trusted sources
  static List<ConfigSource> getEnabled() =>
    sources.where((s) => s.isEnabled).toList();

  /// Find source by ID
  static ConfigSource? getById(String id) {
    try {
      return sources.firstWhere((s) => s.id == id);
    } catch (e) {
      return null;
    }
  }
}
