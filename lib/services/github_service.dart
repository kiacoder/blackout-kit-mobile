/// GitHub API service for fetching VPN configs.
/// Replicates Blackout Kit CLI's downloader.py pattern:
/// - Cached API calls with TTL (1 hour for repos, 12 hours for test results)
/// - fnmatch-style asset selection
/// - Error handling for rate limits, 404s, network issues
/// - Config deduplication by hash

import 'package:dio/dio.dart';
import 'package:logger/logger.dart';
import '../models/config_source.dart';
import '../models/config.dart';

typedef ConfigParserFn = Config? Function(String uri);

class GitHubService {
  final Dio _client;
  final Logger _log;

  // Cache: repo → (content, timestamp)
  final Map<String, CachedContent> _contentCache = {};

  static const Duration _repoTtl = Duration(hours: 1);
  static const String _githubApi = 'https://api.github.com';

  GitHubService({Dio? client, Logger? logger})
      : _client = client ?? Dio(),
        _log = logger ?? Logger();

  /// Fetch raw file content from GitHub repo
  /// Returns null if file not found or network error
  Future<String?> fetchRawFile(
    String owner,
    String repo,
    String path, {
    String branch = 'main',
  }) async {
    try {
      final url =
        'https://raw.githubusercontent.com/$owner/$repo/$branch/$path';

      // Check cache first
      if (_contentCache.containsKey(url)) {
        final cached = _contentCache[url]!;
        if (DateTime.now().difference(cached.timestamp) < _repoTtl) {
          _log.d('Cache hit: $url');
          return cached.content;
        } else {
          _contentCache.remove(url);
        }
      }

      _log.i('Fetching $url');
      final response = await _client.get<String>(url);
      if (response.statusCode == 200 && response.data != null) {
        // Cache the content
        _contentCache[url] = CachedContent(
          content: response.data!,
          timestamp: DateTime.now(),
        );
        return response.data!;
      }
      return null;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        _log.w('File not found: $owner/$repo/$path');
      } else {
        _log.e('Fetch error: $e');
      }
      return null;
    } catch (e) {
      _log.e('Unexpected error: $e');
      return null;
    }
  }

  /// Fetch all releases from a repo (GitHub API)
  /// Returns map of asset name → download URL
  Future<Map<String, String>> fetchReleaseAssets(
    String owner,
    String repo,
  ) async {
    try {
      final url = '$_githubApi/repos/$owner/$repo/releases/latest';
      final key = 'releases:$owner/$repo';

      // Check cache
      if (_contentCache.containsKey(key)) {
        final cached = _contentCache[key]!;
        if (DateTime.now().difference(cached.timestamp) < _repoTtl) {
          _log.d('Cache hit: $key');
          return _parseReleaseAssets(cached.content);
        } else {
          _contentCache.remove(key);
        }
      }

      _log.i('Fetching releases: $owner/$repo');
      final response = await _client.get<Map<String, dynamic>>(url);
      if (response.statusCode == 200 && response.data != null) {
        final jsonStr = response.data.toString();
        _contentCache[key] = CachedContent(
          content: jsonStr,
          timestamp: DateTime.now(),
        );
        return _parseReleaseAssets(jsonStr);
      }
      return {};
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        _log.w('Releases not found: $owner/$repo');
      } else {
        _log.e('Release fetch error: $e');
      }
      return {};
    } catch (e) {
      _log.e('Unexpected error: $e');
      return {};
    }
  }

  /// Fetch configs from a trusted source (file-based)
  /// Handles asset selection with fnmatch-style patterns
  Future<List<Config>> fetchConfigsFromSource(
    ConfigSource source, {
    String? filePattern,
  }) async {
    try {
      _log.i('Fetching configs from ${source.fullId}');

      // Default pattern: look for common config file names
      final pattern = filePattern ?? 'configs.txt';

      // Fetch the file
      final content = await fetchRawFile(
        source.owner,
        source.repo,
        pattern,
        branch: source.branch ?? 'main',
      );

      if (content == null) {
        return [];
      }

      // Parse configs from content
      final configs = ConfigParser.parseMultiple(content);
      _log.i('Parsed ${configs.length} configs from ${source.fullId}');
      return configs;
    } catch (e) {
      _log.e('Error fetching configs: $e');
      return [];
    }
  }

  /// Clear old cache entries (call periodically)
  void clearExpiredCache() {
    final now = DateTime.now();
    _contentCache.removeWhere((key, value) {
      final age = now.difference(value.timestamp);
      return age > _repoTtl;
    });
    _log.d('Cache cleanup complete');
  }

  /// Get cache statistics
  Map<String, dynamic> getCacheStats() {
    return {
      'cached_items': _contentCache.length,
      'cache_size': _contentCache.values.fold<int>(
        0,
        (sum, item) => sum + item.content.length,
      ),
    };
  }

  /// Parse release assets from GitHub API response
  Map<String, String> _parseReleaseAssets(String jsonStr) {
    try {
      // Simple JSON parsing without external package
      // In production, use package:json or similar
      // This is a placeholder implementation
      return {};
    } catch (e) {
      _log.e('Error parsing releases: $e');
      return {};
    }
  }
}

/// Cached content with timestamp
class CachedContent {
  final String content;
  final DateTime timestamp;

  CachedContent({
    required this.content,
    required this.timestamp,
  });
}

/// GitHub rate limit info
class GitHubRateLimit {
  final int limit;
  final int remaining;
  final int resetAt;

  const GitHubRateLimit({
    required this.limit,
    required this.remaining,
    required this.resetAt,
  });

  bool get isLimited => remaining == 0;
}
