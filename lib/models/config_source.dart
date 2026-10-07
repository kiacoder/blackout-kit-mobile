/// Config source model (GitHub repo or manual configs).
/// Tracks where configs come from and their metadata.

class ConfigSource {
  final String id;
  final String name;
  final String owner;
  final String repo;
  final String? branch;
  /// Path inside the repo that holds the configs, when it is known.
  ///
  /// Without it the fetcher has to guess through a list of common filenames,
  /// which is up to eight HTTP requests per branch and 404s for every repo
  /// that does not happen to use one of those names.
  final String? filePath;
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
    this.filePath,
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
    String? filePath,
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
      filePath: filePath ?? this.filePath,
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
    'filePath': filePath,
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
      filePath: json['filePath'] as String?,
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

/// Built-in config sources shipped with the app.
///
/// The previous entries were invented placeholders — `free-vpn-configs/configs`
/// and `open-vpn-community/free-configs` — that were never checked against the
/// network. Both return HTTP 404 from the GitHub API, so every fetch quietly
/// produced zero configs and the app looked like fetching was broken.
///
/// Every entry below was verified before being added: the repository responds
/// 200 on `https://api.github.com/repos/<owner>/<repo>`, the `branch` is the
/// repo's real default branch, and `filePath` was downloaded and confirmed to
/// contain parseable config URIs (scheme counts observed at the time of
/// checking are in the comments). Re-check with curl before editing.
class TrustedSources {
  static const List<ConfigSource> sources = [
    ConfigSource(
      id: 'trusted-barry-far',
      name: 'barry-far V2Ray Configs',
      owner: 'barry-far',
      repo: 'V2ray-Config',
      branch: 'main',
      filePath: 'All_Configs_Sub.txt',
      // ~7.6k lines: vless, ss, trojan, vmess, hy2, hysteria2.
    ),
    ConfigSource(
      id: 'trusted-v2ray-aggregator',
      name: 'V2Ray Aggregator',
      owner: 'mahdibland',
      repo: 'V2RayAggregator',
      // This repo's default branch is `master`, not `main`; the raw URL 404s
      // on `main`.
      branch: 'master',
      filePath: 'Eternity.txt',
      // ~200 lines: ss, trojan, vmess.
    ),
  ];

  /// IDs of the built-in sources, so stored user state can be matched to them.
  static Set<String> get ids => sources.map((s) => s.id).toSet();
}
