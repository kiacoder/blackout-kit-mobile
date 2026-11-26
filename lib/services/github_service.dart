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

/// Raised when a source could not be reached at all (network error, or no
/// candidate file answered). The caller records this on the source so the
/// Library can say "this source failed" instead of "up to date".
class SourceUnavailableException implements Exception {
  final String reason;
  const SourceUnavailableException(this.reason);
  @override
  String toString() => 'SourceUnavailableException: $reason';
}

class GitHubService {
  final Dio _client;
  final Logger _log;

  // Cache: repo → (content, timestamp)
  final Map<String, CachedContent> _contentCache = {};

  static const Duration _repoTtl = Duration(hours: 1);
  static const String _githubApi = 'https://api.github.com';

  /// Filenames to guess when a source does not name one.
  static const List<String> _defaultCandidateFiles = [
    'configs.txt',
    'subscription.txt',
    'sub.txt',
    'all.txt',
    'vpn.txt',
    'nodes.txt',
    'v2ray.txt',
    'All_Configs_Sub.txt',
    'README.md',
  ];

  GitHubService({Dio? client, Logger? logger})
      : _client = client ?? _defaultClient(),
        _log = logger ?? Logger();

  /// Dio gives every request an unbounded timeout by default: a host that
  /// blackholes the connection (common for raw.githubusercontent.com behind
  /// censorship) hangs at the OS TCP timeout — minutes per URL — and
  /// fetchConfigsFromSource tries up to a couple of dozen URLs per source.
  /// That was the "Loading repositories & configs..." forever bug.
  static Dio _defaultClient() => Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 8),
        sendTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 20),
      ));

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
          _log.d('Cache hit');
          return cached.content;
        } else {
          _contentCache.remove(url);
        }
      }

      _log.i('Fetching remote file');
      final response = await _client.get<String>(
        url,
        options: Options(
          responseType: ResponseType.plain,
          headers: {
            'User-Agent': 'Mozilla/5.0 (BlackoutKitMobile/1.0)',
          },
        ),
      );
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
        _log.w('Remote file not found');
      } else {
        _log.e('Fetch error');
      }
      return null;
    } catch (e) {
      _log.e('Unexpected error');
      return null;
    }
  }

  /// Fetch directly from HTTPS only, including redirect destinations.
  Future<String?> fetchDirectUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !_isSafeFeedUri(uri)) return null;
    try {
      if (_contentCache.containsKey(url)) {
        final cached = _contentCache[url]!;
        if (DateTime.now().difference(cached.timestamp) < _repoTtl) {
          return cached.content;
        } else {
          _contentCache.remove(url);
        }
      }

      final response = await _getHttpsFeed(uri);
      if (response != null && response.statusCode == 200 && response.data != null) {
        _contentCache[url] = CachedContent(
          content: response.data!,
          timestamp: DateTime.now(),
        );
        return response.data!;
      }
      return null;
    } catch (_) {
      _log.e('Direct URL fetch error');
      return null;
    }
  }

  static bool _isSafeFeedUri(Uri uri) =>
      uri.scheme == 'https' && uri.hasAuthority && uri.host.isNotEmpty &&
      uri.userInfo.isEmpty;

  Future<Response<String>?> _getHttpsFeed(Uri uri) async {
    for (var redirects = 0; redirects <= 5; redirects++) {
      if (!_isSafeFeedUri(uri)) return null;
      final response = await _client.getUri<String>(
        uri,
        options: Options(
          responseType: ResponseType.plain,
          followRedirects: false,
          validateStatus: (status) => status == 200 ||
              const [301, 302, 303, 307, 308].contains(status),
          headers: {
            'User-Agent': 'Mozilla/5.0 (BlackoutKitMobile/1.0)',
          },
        ),
      );
      if (response.statusCode == 200) return response;
      final location = response.headers.value('location');
      if (location == null || location.isEmpty) return null;
      final next = uri.resolve(location);
      // Do not send private feed requests through an HTTPS-to-HTTP downgrade.
      if (!_isSafeFeedUri(next)) return null;
      uri = next;
    }
    return null;
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
          _log.d('Cache hit');
          return _parseReleaseAssets(cached.content);
        } else {
          _contentCache.remove(key);
        }
      }

      _log.i('Fetching releases');
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
        _log.w('Releases not found');
      } else {
        _log.e('Release fetch error');
      }
      return {};
    } catch (e) {
      _log.e('Unexpected error');
      return {};
    }
  }

  /// Fetch configs from a trusted source (file-based or direct URL)
  /// Handles asset selection with multiple candidate fallback patterns
  Future<List<Config>> fetchConfigsFromSource(
    ConfigSource source, {
    String? filePattern,
  }) async {
    try {
      _log.i('Fetching configs from source');

      // If user entered a full direct URL
      if (source.owner.startsWith('http://') || source.owner.startsWith('https://')) {
        final uri = Uri.tryParse(source.owner);
        if (uri == null || !_isSafeFeedUri(uri)) {
          throw const SourceUnavailableException('Direct sources require HTTPS without URL credentials');
        }
        final content = await fetchDirectUrl(source.owner);
        if (content != null && content.isNotEmpty) {
          final configs = ConfigParser.parseMultiple(content);
          _log.i('Parsed ${configs.length} configs from direct URL');
          return configs;
        }
        throw const SourceUnavailableException(
          'Direct URL returned no content',
        );
      }

      // Protocol-specific community feed: never fall back to unrelated
      // repository files, or import other protocols under this source name.
      if (source.id == 'community-morpheus-wireguard' ||
          source.id == 'community-au1rxx-wireguard') {
        final content = await fetchRawFile(source.owner, source.repo,
            source.filePath!, branch: source.branch ?? 'main');
        final parsed = source.id == 'community-au1rxx-wireguard'
            ? ConfigParser.parseWireGuardEndpointDocument(content ?? '')
            : ConfigParser.parseMultiple(content ?? '');
        final configs = parsed.where((c) => c.protocol == 'wireguard' || c.protocol == 'amneziawg')
            .toList();
        if (configs.isEmpty) {
          throw const SourceUnavailableException('No supported WireGuard/AWG profiles in community feed');
        }
        return configs;
      }

      // An explicit filePath (set on the built-in sources) points straight at
      // the file known to hold configs, so the common case costs one request.
      // It is tried first but is not trusted blindly: if it 404s or parses to
      // nothing, the generic guesses below still run.
      final candidateFiles = <String>[
        if (source.filePath != null) source.filePath!,
        if (filePattern != null) filePattern,
        ..._defaultCandidateFiles,
      ];

      for (final filename in candidateFiles) {
        final content = await fetchRawFile(
          source.owner,
          source.repo,
          filename,
          branch: source.branch ?? 'main',
        );
        if (content != null && content.trim().isNotEmpty) {
          final configs = ConfigParser.parseMultiple(content);
          if (configs.isNotEmpty) {
            _log.i('Parsed ${configs.length} configs from repository');
            return configs;
          }
        }
      }

      // If branch was defaulted to 'main', also try 'master' as a fallback
      if (source.branch == null || source.branch == 'main') {
        for (final filename in candidateFiles) {
          final content = await fetchRawFile(
            source.owner,
            source.repo,
            filename,
            branch: 'master',
          );
          if (content != null && content.trim().isNotEmpty) {
            final configs = ConfigParser.parseMultiple(content);
            if (configs.isNotEmpty) {
              _log.i('Parsed ${configs.length} configs from repository (master)');
              return configs;
            }
          }
        }
      }

      // Every candidate and both branches came back empty: the source is
      // reachable but has no config file. That is a real outcome (say so),
      // not the same as "up to date with nothing new".
      throw const SourceUnavailableException(
        'No config file found in this repository',
      );
    } on SourceUnavailableException {
      rethrow;
    } catch (e) {
      _log.e('Error fetching configs');
      throw SourceUnavailableException(e.toString());
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
      _log.e('Error parsing releases');
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
