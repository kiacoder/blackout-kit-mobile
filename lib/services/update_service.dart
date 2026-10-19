/// Blackout Kit Mobile - in-app self-updater.
///
/// Checks GitHub Releases for a newer beta build, downloads the arm64 APK
/// into the app-specific external files dir, and hands it to Android's
/// package installer through the UpdatePlugin platform channel.
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:package_info_plus/package_info_plus.dart';

class AppUpdate {
  AppUpdate({
    required this.tagName,
    required this.buildNumber,
    required this.notes,
    required this.apkUrl,
    required this.apkSize,
  });

  final String tagName; // e.g. v1.0.0-beta.31
  final int buildNumber; // 31
  final String notes;
  final String apkUrl;
  final int apkSize;

  /// Only beta-tagged builds carry a comparable build number; anything else
  /// (1.0.0 stable, typos) returns null instead of guessing.
  static AppUpdate? fromReleaseJson(Map<String, dynamic> json) {
    final tag = (json['tag_name'] as String? ?? '').trim();
    final m = RegExp(r'beta\.(\d+)$').firstMatch(tag);
    if (m == null) return null;
    final assets =
        (json['assets'] as List? ?? []).whereType<Map<String, dynamic>>().toList();
    Map<String, dynamic>? apk;
    for (final a in assets) {
      if ((a['name'] as String? ?? '') == 'app-arm64-v8a-release.apk') {
        apk = a;
        break;
      }
    }
    apk ??= assets
        .cast<Map<String, dynamic>?>()
        .firstWhere((a) => (a?['name'] as String? ?? '').endsWith('.apk'),
            orElse: () => null);
    if (apk == null) return null;
    return AppUpdate(
      tagName: tag,
      buildNumber: int.parse(m.group(1)!),
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

  Future<int> installedBuildNumber() async {
    final info = await PackageInfo.fromPlatform();
    return int.tryParse(info.buildNumber) ?? 0;
  }

  /// AppUpdate when the latest release build is newer than the installed one.
  Future<AppUpdate?> checkForUpdate() async {
    try {
      final res = await Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 20),
      )).get<Map<String, dynamic>>(
        _apiLatest,
        options: Options(headers: {'User-Agent': 'blackout-kit-mobile'}),
      );
      final update = AppUpdate.fromReleaseJson(res.data ?? <String, dynamic>{});
      if (update == null) return null;
      if (update.buildNumber <= await installedBuildNumber()) return null;
      return update;
    } catch (_) {
      return null; // offline / API down — silently fine
    }
  }

  /// Downloads the arm64 APK into the FileProvider-mapped updates dir.
  Future<String> downloadApk(AppUpdate update) async {
    final dirs = await getExternalStorageDirectories();
    if (dirs == null || dirs.isEmpty) {
      throw const FileSystemException('no external files dir available');
    }
    final updatesDir = Directory('${dirs.first.path}/updates')
      ..createSync(recursive: true);
    final file = File('${updatesDir.path}/blackout-${update.tagName}.apk');

    status.value = 'Downloading ${update.tagName}...';
    await Dio().download(
      update.apkUrl,
      file.path,
      onReceiveProgress: (done, total) {
        if (total > 0) progress.value = done / total;
      },
      options: Options(headers: {'User-Agent': 'blackout-kit-mobile'}),
    );
    status.value = 'Download complete';
    return file.path;
  }

  /// Hands the APK to Android's package installer (user confirms the install).
  Future<void> installApk(String path) async {
    try {
      await _channel.invokeMethod('installApk', {'path': path});
    } on PlatformException catch (e) {
      throw Exception(e.message ?? 'install failed');
    }
  }
}
