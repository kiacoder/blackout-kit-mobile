/// Tests for the in-app updater's release parsing.
///
/// The bug this locks down: the updater used to pick the arm64 asset by name,
/// so a 32-bit phone downloaded an APK it could never install
/// (INSTALL_FAILED_NO_MATCHING_ABIS) and the install "just failed".
library;

import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:blackout_kit_mobile/services/update_service.dart';

Map<String, dynamic> releaseWith(Map<String, int> assets, {String tag = 'v1.0.0-beta.42'}) => {
      'tag_name': tag,
      'body': 'notes',
      'assets': [
        for (final e in assets.entries)
          {
            'name': e.key,
            'size': e.value,
            'browser_download_url': 'https://example.invalid/${e.key}',
          },
      ],
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('Update download integrity', () {
    AppUpdate update({
      String url = 'https://github.com/kiacoder/blackout-kit-mobile/releases/download/v1.2.3/test.apk',
      int size = UpdateDownloadPolicy.minBytes,
      String? digest,
    }) => AppUpdate(
      tagName: 'v1.2.3',
      buildNumber: 10203,
      version: '1.2.3',
      notes: '',
      apkUrl: url,
      apkSize: size,
      apkDigest: digest,
    );

    final data = List<int>.filled(UpdateDownloadPolicy.minBytes, 42);
    final expected = 'sha256:${sha256.convert(data)}';

    test('rejects missing digest and wrong download origins', () {
      expect(() => UpdateDownloadPolicy.validate(update()), throwsFormatException);
      for (final url in [
        'http://github.com/kiacoder/blackout-kit-mobile/releases/download/v1.2.3/test.apk',
        'https://github.com/another/repo/releases/download/v1.2.3/test.apk',
        'https://github.com/kiacoder/blackout-kit-mobile/releases/download/v1.2.4/test.apk',
      ]) {
        expect(() => UpdateDownloadPolicy.validate(update(url: url, digest: expected)),
            throwsFormatException);
      }
      expect(() => UpdateDownloadPolicy.validate(update(size: 1, digest: expected)),
          throwsFormatException);
    });

    test('accepts exact digest, rejects same-size corruption and truncation', () async {
      final folder = await Directory.systemTemp.createTemp('update-integrity-');
      addTearDown(() => folder.delete(recursive: true));
      final file = File('${folder.path}/fixture.part');
      await file.writeAsBytes(data);
      await UpdateDownloadPolicy.verify(file, update(digest: expected));
      await file.writeAsBytes(List<int>.filled(data.length, 43));
      await expectLater(UpdateDownloadPolicy.verify(file, update(digest: expected)),
          throwsFormatException);
      await file.writeAsBytes([42]);
      await expectLater(UpdateDownloadPolicy.verify(file, update(digest: expected)),
          throwsFormatException);
    });

    test('permission retry rechecks bytes and preserves platform error code', () async {
      final folder = await Directory.systemTemp.createTemp('update-retry-');
      addTearDown(() => folder.delete(recursive: true));
      final file = File('${folder.path}/fixture.apk');
      await file.writeAsBytes(data);
      const channel = MethodChannel('com.blackoutkit.vpn/update');
      final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      var installerCalls = 0;
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'installApk');
        expect(call.arguments, {
          'tag': 'v1.2.3',
          'size': data.length,
          'digest': expected,
        });
        installerCalls++;
        if (installerCalls == 1) {
          throw PlatformException(code: 'ALLOW_UNKNOWN_SOURCES');
        }
        return true;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final service = UpdateService();
      final release = update(digest: expected);
      await expectLater(service.installApk(file.path, release),
          throwsA(isA<PlatformException>().having((e) => e.code, 'code', 'ALLOW_UNKNOWN_SOURCES')));
      await file.writeAsBytes(List<int>.filled(data.length, 43));
      await expectLater(service.installApk(file.path, release), throwsFormatException);
      expect(installerCalls, 1);
      await file.writeAsBytes(data);
      await service.installApk(file.path, release);
      expect(installerCalls, 2);
    });

    test('explicit session cancellation uses only the native cancellation method', () async {
      const channel = MethodChannel('com.blackoutkit.vpn/update');
      final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      var calls = 0;
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'cancelPendingUpdate');
        expect(call.arguments, isNull);
        calls++;
        if (calls == 1) throw PlatformException(code: 'CANCEL_FAILED');
        return true;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final service = UpdateService();
      await expectLater(service.cancelPendingUpdate(),
          throwsA(isA<PlatformException>().having((e) => e.code, 'code', 'CANCEL_FAILED')));
      await service.cancelPendingUpdate();
      expect(calls, 2);
    });

    test('parses official GitHub SHA-256 metadata', () {
      final release = releaseWith({'app-arm64-v8a-release.apk': data.length});
      (release['assets'] as List).first['digest'] = expected;
      expect(AppUpdate.fromReleaseJson(release)!.apkDigest, expected);
    });
  });

  group('AppUpdate.fromReleaseJson', () {
    test('picks the arm64 asset on a 64-bit device', () {
      final u = AppUpdate.fromReleaseJson(
        releaseWith({
          'app-arm64-v8a-release.apk': 44000000,
          'app-armeabi-v7a-release.apk': 45000000,
        }),
        abi: 'arm64-v8a',
      )!;
      expect(u.apkUrl, endsWith('app-arm64-v8a-release.apk'));
      expect(u.buildNumber, 42);
    });

    test('picks the armv7 asset on a 32-bit device', () {
      final u = AppUpdate.fromReleaseJson(
        releaseWith({
          'app-arm64-v8a-release.apk': 44000000,
          'app-armeabi-v7a-release.apk': 45000000,
        }),
        abi: 'armeabi-v7a',
      )!;
      // Downloading the arm64 file here is exactly what made installs fail.
      expect(u.apkUrl, endsWith('app-armeabi-v7a-release.apk'));
    });

    test('falls back to any apk when the ABI-named asset is missing', () {
      final u = AppUpdate.fromReleaseJson(
        releaseWith({'blackout-universal.apk': 90000000}),
        abi: 'arm64-v8a',
      )!;
      expect(u.apkUrl, endsWith('blackout-universal.apk'));
    });

    // This test used to assert that a plain `v1.0.0` tag was REJECTED, which
    // was the bug: once the release scheme moved to v1.12.x, every real
    // release failed to parse and the updater could never see an update.
    test('accepts a plain semver tag', () {
      final u = AppUpdate.fromReleaseJson(
        releaseWith({'app-arm64-v8a-release.apk': 1}, tag: 'v1.0.0'),
      );
      expect(u, isNotNull);
      expect(u!.version, '1.0.0');
    });

    test('rejects a tag with no version in it at all', () {
      expect(
        AppUpdate.fromReleaseJson(
          releaseWith({'app-arm64-v8a-release.apk': 1}, tag: 'nightly'),
        ),
        isNull,
      );
    });

    test('rejects malformed and path-bearing release tags', () {
      for (final tag in [
        'prefix-v1.0.0',
        'v1.0.0/../../other',
        'v1.0.0-beta.42/extra',
        'v1.0.0-suffix',
      ]) {
        expect(AppUpdate.fromReleaseJson(
          releaseWith({'app-arm64-v8a-release.apk': 1}, tag: tag),
        ), isNull, reason: tag);
      }
    });

    test('ignores a release with no apk asset', () {
      expect(AppUpdate.fromReleaseJson(releaseWith({})), isNull);
    });

    test('build numbers compare numerically, not lexically', () {
      final u = AppUpdate.fromReleaseJson(
        releaseWith({'app-arm64-v8a-release.apk': 1}, tag: 'v1.0.0-beta.100'),
      )!;
      expect(u.buildNumber, 100);
      expect(u.buildNumber > 99, isTrue);
    });
  });

  group('release tag parsing', () {
    Map<String, dynamic> release(String tag) => {
          'tag_name': tag,
          'body': 'notes',
          'assets': [
            {
              'name': 'app-arm64-v8a-release.apk',
              'browser_download_url': 'https://example.test/a.apk',
              'size': 1234,
            }
          ],
        };

    test('a v1.12.x tag parses (the beta-only regex did not)', () {
      final update = AppUpdate.fromReleaseJson(release('v1.12.1'),
          abi: 'arm64-v8a');
      expect(update, isNotNull);
      expect(update!.version, '1.12.1');
      expect(update.tagName, 'v1.12.1');
    });

    test('an older beta tag still parses', () {
      final update = AppUpdate.fromReleaseJson(release('v1.0.0-beta.43'),
          abi: 'arm64-v8a');
      expect(update, isNotNull);
      expect(update!.version, '1.0.0');
      expect(update.buildNumber, 43);
    });

    test('a non-version tag is still rejected', () {
      expect(AppUpdate.fromReleaseJson(release('nightly'), abi: 'arm64-v8a'),
          isNull);
    });
  });

  group('version comparison', () {
    int cmp(String a, String b) => UpdateService.compareForTest(a, b);

    test('numeric ordering', () {
      expect(cmp('1.12.1', '1.12.0'), greaterThan(0));
      expect(cmp('1.13.0', '1.12.9'), greaterThan(0));
      expect(cmp('2.0.0', '1.99.99'), greaterThan(0));
      expect(cmp('1.12.0', '1.12.0'), 0);
    });

    test('a release outranks its own prerelease', () {
      expect(cmp('1.12.1', '1.12.1-beta.3'), greaterThan(0));
      expect(cmp('1.12.1-beta.3', '1.12.1'), lessThan(0));
    });

    test('the installed version is not offered as an update', () {
      // The regression: build numbers from two schemes cannot be compared, so
      // the updater offered the version already installed.
      expect(cmp('1.12.1', '1.12.1'), 0);
    });
  });
}
