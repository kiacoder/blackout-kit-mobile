/// Tests for the site-check feature's pure Dart logic: settings sanitisation,
/// report aggregation, and the pickBest ranking that decides which candidate
/// connects.
///
/// The headless-engine side (native core start, SOCKS fetches) is exercised
/// on device, not here — these tests pin the decision logic that must not
/// regress.


import 'package:flutter_test/flutter_test.dart';

import 'package:blackout_kit_mobile/controllers/settings_controller.dart';
import 'package:blackout_kit_mobile/models/config.dart';
import 'package:blackout_kit_mobile/models/test_result.dart';
import 'package:blackout_kit_mobile/services/site_check_service.dart';

void main() {
  group('sanitizeSiteCheckUrls', () {
    test('accepts bare hostnames as-is', () {
      expect(
        SettingsController.sanitizeSiteCheckUrls(['google.com', 'youtube.com']),
        ['google.com', 'youtube.com'],
      );
    });

    test('strips schemes, paths, queries and ports', () {
      expect(
        SettingsController.sanitizeSiteCheckUrls([
          'https://google.com/search?q=x',
          'http://YouTube.com:443/watch',
          'facebook.com/#feed',
        ]),
        ['google.com', 'youtube.com', 'facebook.com'],
      );
    });

    test('lower-cases and de-duplicates', () {
      expect(
        SettingsController.sanitizeSiteCheckUrls(
            ['GOOGLE.com', 'google.com', ' Google.com ']),
        ['google.com'],
      );
    });

    test('drops entries that are not plausible hostnames', () {
      expect(
        SettingsController.sanitizeSiteCheckUrls([
          'not a host',
          'nodots',
          '.leading.dot',
          'trailing.',
          'under_score.com',
          '-ok.example.com',
        ]),
        ['-ok.example.com'],
      );
    });

    test('falls back to defaults when nothing usable remains', () {
      expect(
        SettingsController.sanitizeSiteCheckUrls(['', '   ', 'garbage!!']),
        SettingsController.defaultSiteCheckUrls,
      );
    });

    test('defaults contain the user-requested hosts plus recommended ones',
        () {
      expect(
        SettingsController.defaultSiteCheckUrls,
        containsAll([
          'google.com',
          'gemini.google.com',
          'youtube.com',
          'crunchyroll.com',
          'instagram.com',
          'facebook.com',
          'github.com',
          'wikipedia.org',
        ]),
      );
    });
  });

  group('SiteCheckReport', () {
    const _usable = SiteCheckReport(
      configHash: 'a',
      reachable: 6,
      total: 8,
      bestLatencyMs: 320,
    );
    const _poor = SiteCheckReport(configHash: 'b', reachable: 1, total: 8);
    const _none = SiteCheckReport(configHash: 'c', reachable: 0, total: 8);
    const _unsupported = SiteCheckReport(
      configHash: 'd',
      reachable: 0,
      total: 8,
      supported: false,
    );

    test('passRatio and isUsable thresholds', () {
      expect(_usable.passRatio, closeTo(0.75, 1e-9));
      expect(_usable.isUsable, isTrue);
      expect(_poor.isUsable, isFalse);
      expect(_none.passRatio, 0);
      // An unsupported report is not a verdict against the config.
      expect(_unsupported.isUsable, isFalse);
    });
  });

  group('SiteCheckService.pickBest', () {
    Config _config(String id) => VlessConfig(
          name: id,
          rawUri: 'vless://11111111-1111-1111-1111-111111111111@$id.example:443',
          uuid: '11111111-1111-1111-1111-111111111111',
          address: '$id.example',
          port: 443,
          security: 'none',
        );

    TestResult _result(String id, int tcpLatency) => TestResult.success(
          configHash: _config(id).getHash(),
          latencyMs: tcpLatency,
          successCount: 1,
          totalCount: 1,
        );

    SiteCheckReport _report(String id,
        {required int reachable, int? bestLatency, bool supported = true}) {
      return SiteCheckReport(
        configHash: _config(id).getHash(),
        reachable: reachable,
        total: 8,
        bestLatencyMs: bestLatency,
        supported: supported,
      );
    }

    test('a verified-usable config beats a faster unchecked one', () {
      final configs = [_config('slow-but-real'), _config('tcp-fast')];
      final results = [_result('tcp-fast', 50), _result('slow-but-real', 400)];
      final reports = {
        'slow-but-real': _report('slow-but-real',
            reachable: 6, bestLatency: 900),
      };

      final best = SiteCheckService.pickBest(results, configs, reports);
      expect(best!.configHash, _config('slow-but-real').getHash());
    });

    test('among equally usable configs, tunnel latency wins', () {
      final configs = [_config('a'), _config('b')];
      final results = [_result('a', 100), _result('b', 200)];
      final reports = {
        'a': _report('a', reachable: 7, bestLatency: 500),
        'b': _report('b', reachable: 7, bestLatency: 250),
      };

      expect(
        SiteCheckService.pickBest(results, configs, reports)!.configHash,
        _config('b').getHash(),
      );
    });

    test('with no reports at all, pure TCP latency decides', () {
      final configs = [_config('a'), _config('b')];
      final results = [_result('a', 300), _result('b', 90)];

      expect(
        SiteCheckService.pickBest(results, configs, const {})!.configHash,
        _config('b').getHash(),
      );
    });

    test('an unsupported report does not beat an unchecked config', () {
      // Both are effectively "no data"; the faster TCP one must win.
      final configs = [_config('a'), _config('b')];
      final results = [_result('a', 300), _result('b', 90)];
      final reports = {'a': _report('a', reachable: 0, supported: false)};

      expect(
        SiteCheckService.pickBest(results, configs, reports)!.configHash,
        _config('b').getHash(),
      );
    });

    test('returns null for an empty result set', () {
      expect(
        SiteCheckService.pickBest([], [], const {}),
        isNull,
      );
    });
  });
}
