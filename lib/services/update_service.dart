/// Blackout Kit Mobile - in-app self-updater.
///
/// Checks GitHub Releases for a newer release, downloads the APK that
/// matches this device's ABI into the app's internal files dir, and hands it
/// to Android's package installer through the UpdatePlugin platform channel.
///
/// Internal storage is deliberate: FileProvider maps `filesDir/updates/`
/// through `res/xml/file_paths.xml`, whereas the external app dir is not
/// always the volume that gets mapped ("Failed to find configured root").
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:get/get.dart';
import 'package:package_info_plus/package_info_plus.dart';

class AppUpdate {
  AppUpdate({
    required this.tagName,
    required this.buildNumber,
    required this.version,
    required this.notes,
    required this.apkUrl,
    required this.apkSize,
  });

  final String tagName; // e.g. v1.12.3
  final int buildNumber; // major*10000 + minor*100 + patch
  final String version; // the semver part of the tag, e.g. 1.12.1
  final String notes;
  final String apkUrl;
  final int apkSize;

  /// Monotonic build number for a release tag.
  ///
  /// A v1.12.1 tag becomes major*10000 + minor*100 + patch. The pre-1.12
  /// `beta.N` scheme is still understood, only so that a device already
  /// running an old beta compares correctly once; no such tag exists any more.
  static int _buildNumberFromTag(String tag, Match m) {
    if (tag.contains('beta.')) {
      final legacy = RegExp(r'beta\.(\d+)$').firstMatch(tag);
      if (legacy != null) return int.parse(legacy.group(1)!);
    }
    final major = int.parse(m.group(1)!);
    final minor = int.parse(m.group(2)!);
    final patch = int.parse(m.group(3)!);
    return major * 10000 + minor * 100 + patch;
  }

  static AppUpdate? fromReleaseJson(
    Map<String, dynamic> json, {
    String abi = 'arm64-v8a',
  }) {
    final tag = (json['tag_name'] as String? ?? '').trim();
    // Accept both the v1.12.x scheme and the old beta numbering. Matching
    // only `beta.(\d+)$` meant every release after the version scheme changed
    // parsed as null, so the updater could never see an update at all.
    final m = RegExp(r'v?(\d+)\.(\d+)\.(\d+)').firstMatch(tag);
    if (m == null) return null;
    final assets =
        (json['assets'] as List? ?? []).whereType<Map<String, dynamic>>().toList();
    if (assets.isEmpty) return null;

    String nameOf(Map<String, dynamic> a) => (a['name'] as String? ?? '');

    // Prefer the asset for this device's ABI. A 32-bit phone cannot install the
    // arm64 APK (INSTALL_FAILED_NO_MATCHING_ABIS), and picking by name alone
    // would hand it exactly that file.
    // The release workflow names assets `blackout-kit-<tag>-<abi>.apk` plus a
    // `-universal.apk`. This used to look for `app-<abi>-release.apk`, which
    // never matches, and then fell back to the first .apk that was universal
    // OR matched the ABI - so a phone downloaded the 115 MB universal build
    // instead of its own 60 MB split.
    Map<String, dynamic>? apk;
    final wanted = abi.toLowerCase();
    for (final a in assets) {
      final name = nameOf(a).toLowerCase();
      if (!name.endsWith('.apk')) continue;
      // Exact ABI match first, in any of the names this project has used.
      if (name.contains(wanted) ||
          name == 'app-$wanted-release.apk' ||
          name.contains('-$wanted')) {
        apk = a;
        break;
      }
    }
    if (apk == null) {
      // Fall back ONLY to an APK this device can actually install. The old
      // fallback took any .apk, so a 32-bit phone could be offered the arm64
      // build and fail with INSTALL_FAILED_NO_MATCHING_ABIS after downloading.
      apk = assets.cast<Map<String, dynamic>?>().firstWhere(
            (a) {
              final name = nameOf(a!).toLowerCase();
              if (!name.endsWith('.apk')) return false;
              // universal / fat APKs carry no ABI token and install anywhere.
              return name.contains('universal') || name.contains('fat');
            },
            orElse: () => null,
          );
    }
    if (apk == null) return null;
    return AppUpdate(
      tagName: tag,
      buildNumber: _buildNumberFromTag(tag, m),
      version: '${m.group(1)}.${m.group(2)}.${m.group(3)}',
      notes: (json['body'] as String? ?? ''),
      apkUrl: apk['browser_download_url'] as String,
      apkSize: (apk['size'] as num? ?? 0).toInt(),
    );
  }
}

class UpdateService extends GetxService {
  static const _repo = 'kiacoder/blackout-kit-mobile';
  static const _apiLatest = 'https://api.github.com/repos/$_repo/releases/latest';
  static const _channel = MethodChannel('com.blackoutkit.vpn/update');

  final status = RxString('');
  final progress = RxDouble(0.0);

  /// The ABI the native side reports, used to choose the right APK asset.
  Future<String> deviceAbi() async {
    try {
      final abi = await _channel.invokeMethod<String>('deviceAbi');
      if (abi != null && abi.isNotEmpty) return abi;
    } catch (_) {
      // Older builds / non-Android: fall through to the common case.
    }
    return 'arm64-v8a';
  }

  Future<int> installedBuildNumber() async {
    final info = await PackageInfo.fromPlatform();
    return int.tryParse(info.buildNumber) ?? 0;
  }

  /// True when [release] is a newer version than what is installed.
  ///
  /// Compares the semver strings rather than build numbers: the release tags
  /// moved from `beta.N` to `v1.12.x`, and a build number means something
  /// different on each side of that change - comparing them made the updater
  /// offer the very version already installed, forever.
  Future<bool> _isNewerThanInstalled(AppUpdate release) async {
    final info = await PackageInfo.fromPlatform();
    return _compareSemver(release.version, info.version) > 0;
  }

  /// Test seam for the semver ordering (the real comparison reads PackageInfo).
  static int compareForTest(String a, String b) => _compareSemver(a, b);

  /// Standard semver ordering: numeric fields first, then prerelease, where a
  /// release outranks its own prerelease (1.12.1 > 1.12.1-beta.3).
  static int _compareSemver(String a, String b) {
    final coreA = a.split('-')[0].split('+')[0];
    final coreB = b.split('-')[0].split('+')[0];
    final preA = a.contains('-') ? a.split('-')[1] : '';
    final preB = b.contains('-') ? b.split('-')[1] : '';

    final partsA = coreA.split('.').map(int.tryParse).toList();
    final partsB = coreB.split('.').map(int.tryParse).toList();
    for (var i = 0; i < 3; i++) {
      final na = i < partsA.length ? (partsA[i] ?? 0) : 0;
      final nb = i < partsB.length ? (partsB[i] ?? 0) : 0;
      if (na != nb) return na.compareTo(nb);
    }
    if (preA == preB) return 0;
    if (preA.isEmpty) return 1; // release beats prerelease
    if (preB.isEmpty) return -1;
    return preA.compareTo(preB);
  }

  /// AppUpdate when the latest release build is newer than the installed one.
  ///
  /// Returns null ONLY when the app really is up to date. Everything else
  /// throws with the reason: swallowing failures made every network error, rate
  /// limit or missing asset look like "App is up to date", which is
  /// indistinguishable from the updater being broken.
  Future<AppUpdate?> checkForUpdate() async {
    final abi = await deviceAbi();
    final res = await Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 25),
    )).get<Map<String, dynamic>>(
      _apiLatest,
      options: Options(
        headers: {'User-Agent': 'blackout-kit-mobile'},
        // GitHub answers 403 (rate limit) or 404 with an error body; treat
        // anything non-200 as a failure instead of parsing it as a release.
        validateStatus: (code) => code == 200,
      ),
    );
    final data = res.data;
    if (data == null) {
      throw Exception('GitHub returned an empty release document.');
    }
    final update = AppUpdate.fromReleaseJson(data, abi: abi);
    if (update == null) {
      throw Exception(
        'The latest release has no APK asset for this device ($abi).',
      );
    }
    if (!await _isNewerThanInstalled(update)) return null;
    return update;
  }

  /// Downloads the APK into the FileProvider-mapped internal updates dir.
  Future<String> downloadApk(AppUpdate update) async {
    // getApplicationSupportDirectory() is filesDir on Android, which is what
    // <files-path> in file_paths.xml maps. No permissions involved.
    final base = await getApplicationSupportDirectory();
    final updatesDir = Directory('${base.path}/updates')
      ..createSync(recursive: true);
    final file = File('${updatesDir.path}/blackout-${update.tagName}.apk');

    // A stale or partial file from an earlier attempt must not be installed.
    if (await file.exists()) {
      try {
        await file.delete();
      } catch (_) {}
    }

    status.value = 'Downloading ${update.tagName}...';
    progress.value = 0;
    await Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(minutes: 5),
    )).download(
      update.apkUrl,
      file.path,
      onReceiveProgress: (done, total) {
        if (total > 0) progress.value = done / total;
      },
      options: Options(headers: {'User-Agent': 'blackout-kit-mobile'}),
    );

    // GitHub answers a rate-limited or failed download with HTML, not an APK.
    // Catching that here produces "not a valid APK" instead of the installer's
    // "problem parsing the package".
    final size = await file.length();
    if (update.apkSize > 0 && size != update.apkSize) {
      throw Exception(
        'Download incomplete: $size of ${update.apkSize} bytes. Try again.',
      );
    }
    if (size < 1024 * 1024) {
      throw Exception(
        'The downloaded file is only $size bytes — the server did not send an APK.',
      );
    }
    status.value = 'Download complete';
    return file.path;
  }

  /// Hands the APK to Android's package installer (user confirms the install).
  Future<void> installApk(String path) async {
    try {
      await _channel.invokeMethod('installApk', {'path': path});
    } on PlatformException catch (e) {
      // The native side already explains ALLOW_UNKNOWN_SOURCES and BAD_APK;
      // keep that wording instead of flattening it into a generic failure.
      throw Exception(e.message ?? 'install failed (${e.code})');
    }
  }
}
