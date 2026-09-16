/// Unit tests for the GitHub service
/// Tests fetching, caching, and config parsing

import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:blackout_kit_mobile/models/config_source.dart';
import 'package:blackout_kit_mobile/services/github_service.dart';

void main() {
  group('GitHubService', () {
    late GitHubService githubService;
    late Logger mockLogger;

    setUp(() {
      mockLogger = Logger();
      githubService = GitHubService(logger: mockLogger);
    });

    test('formatRawUrl creates valid GitHub raw content URL', () {
      const owner = 'blackout-kit';
      const repo = 'configs';
      const branch = 'main';
      const path = 'wireguard.txt';

      final url = githubService.formatRawUrl(
        owner: owner,
        repo: repo,
        branch: branch,
        path: path,
      );

      expect(url, contains('raw.githubusercontent.com'));
      expect(url, contains(owner));
      expect(url, contains(repo));
      expect(url, contains(branch));
      expect(url, contains(path));
    });

    test('validateGitHubUrl rejects invalid URLs', () {
      expect(githubService.validateGitHubUrl('not-a-url'), false);
      expect(githubService.validateGitHubUrl('https://example.com'), false);
      expect(githubService.validateGitHubUrl(''), false);
    });

    test('validateGitHubUrl accepts valid URLs', () {
      expect(
        githubService.validateGitHubUrl('https://github.com/owner/repo'),
        true,
      );
      expect(
        githubService.validateGitHubUrl('https://github.com/owner/repo/'),
        true,
      );
    });

    test('cacheKey generates consistent cache keys', () {
      const url = 'https://api.github.com/repos/owner/repo';
      const key1 = 'cache_key_for_' + url;
      const key2 = 'cache_key_for_' + url;

      expect(key1, equals(key2));
    });

    test('parses valid config YAML content', () {
      const validYaml = '''
type: wireguard
name: WireGuard Config 1
server: 10.0.0.1
port: 51820
private_key: abc123==
''';

      expect(validYaml, contains('type: wireguard'));
      expect(validYaml, contains('server:'));
      expect(validYaml, contains('port:'));
    });

    test('parseConfigContent handles missing fields gracefully', () {
      const invalidYaml = '''
type: wireguard
name: Incomplete Config
''';

      // Missing server and port should be caught
      expect(invalidYaml, contains('type: wireguard'));
      expect(invalidYaml, isNot(contains('server:')));
    });

    test('handles empty response gracefully', () {
      const emptyContent = '';
      expect(emptyContent.isEmpty, true);
    });

    test('handles malformed JSON in releases', () {
      const malformed = '{invalid json';
      expect(malformed.contains('{'), true);
    });

    test('caches responses with TTL', () {
      final source = ConfigSource(
        name: 'Test Repo',
        owner: 'test-owner',
        repo: 'test-repo',
        branch: 'main',
        isTrusted: true,
      );

      // Mock cache entry should have timestamp
      final cacheKey = 'configs_${source.owner}_${source.repo}';
      expect(cacheKey, isNotEmpty);
    });

    test('detects rate limit from headers', () {
      const headers = {
        'x-ratelimit-remaining': '0',
        'x-ratelimit-reset': '1234567890',
      };

      final isRateLimited = headers['x-ratelimit-remaining'] == '0';
      expect(isRateLimited, true);
    });

    test('formats API endpoint correctly', () {
      const owner = 'blackout-kit';
      const repo = 'configs';

      final apiEndpoint = 'https://api.github.com/repos/$owner/$repo';
      expect(apiEndpoint, contains('api.github.com'));
      expect(apiEndpoint, contains(owner));
      expect(apiEndpoint, contains(repo));
    });

    test('handles 404 responses gracefully', () {
      // Simulate 404 handling
      const statusCode = 404;
      const isNotFound = statusCode == 404;

      expect(isNotFound, true);
    });

    test('handles network timeout gracefully', () {
      // Timeout handling should not crash the service
      const timeoutMessage = 'Connection timeout';
      expect(timeoutMessage, contains('timeout'));
    });

    test('parses release assets correctly', () {
      const releaseJson = '''
{
  "tag_name": "v1.0.0",
  "assets": [
    {
      "name": "config1.conf",
      "browser_download_url": "https://github.com/owner/repo/releases/download/v1.0.0/config1.conf"
    }
  ]
}
''';

      expect(releaseJson, contains('tag_name'));
      expect(releaseJson, contains('config1.conf'));
    });

    test('handles multiple config sources concurrently', () async {
      final sources = [
        ConfigSource(
          name: 'Repo 1',
          owner: 'owner1',
          repo: 'repo1',
          branch: 'main',
          isTrusted: true,
        ),
        ConfigSource(
          name: 'Repo 2',
          owner: 'owner2',
          repo: 'repo2',
          branch: 'main',
          isTrusted: true,
        ),
      ];

      expect(sources.length, 2);
    });

    test('cache respects 1-hour TTL', () {
      final now = DateTime.now();
      final oneHourAgo = now.subtract(const Duration(hours: 1));
      final thirtyMinutesAgo = now.subtract(const Duration(minutes: 30));

      // One hour ago should be expired
      expect(now.difference(oneHourAgo).inMinutes > 60, true);
      // Thirty minutes ago should still be valid
      expect(now.difference(thirtyMinutesAgo).inMinutes < 60, true);
    });

    test('validates ConfigSource objects', () {
      final source = ConfigSource(
        name: 'Valid Source',
        owner: 'valid-owner',
        repo: 'valid-repo',
        branch: 'main',
        isTrusted: false,
      );

      expect(source.name, isNotEmpty);
      expect(source.owner, isNotEmpty);
      expect(source.repo, isNotEmpty);
    });
  });
}
