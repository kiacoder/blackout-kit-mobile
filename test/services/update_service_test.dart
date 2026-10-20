/// Tests for the in-app updater's release parsing.
///
/// The bug this locks down: the updater used to pick the arm64 asset by name,
/// so a 32-bit phone downloaded an APK it could never install
/// (INSTALL_FAILED_NO_MATCHING_ABIS) and the install "just failed".
import 'package:flutter_test/flutter_test.dart';
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

    test('ignores releases that are not beta.N tags', () {
      expect(
        AppUpdate.fromReleaseJson(
          releaseWith({'app-arm64-v8a-release.apk': 1}, tag: 'v1.0.0'),
        ),
        isNull,
      );
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
}
