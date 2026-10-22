/// IP identity: what the user's address and location are BEFORE the tunnel
/// and what they are NOW (through the exit).
///
/// ## Why two lookups
///
/// - **Home (before)**: fetched directly, no tunnel. While the VPN is up the
///   app is a disallowed application of its own tunnel, so a direct fetch
///   still reports the real, unprotected address — exactly what "before"
///   means on the home screen. Fetched at startup and refreshed whenever the
///   tunnel comes down, then cached in Hive: during a blockade the last
///   known home location must still be visible.
/// - **Exit (now)**: fetched THROUGH the tunnel via the core's loopback SOCKS
///   inbound (`VPNService.tunnelFetch`). A direct request would describe the
///   wrong place; only a request that leaves through the exit can say where
///   the exit is.
///
/// ## The lookup service
///
/// `https://ipwho.is` is used because it is free, keyless, returns a small
/// JSON document (ip, city, country, country_code) and answers over HTTPS.
/// It is a diagnostic display, not a security boundary: the app never sends
/// user data there beyond the IP round trip itself.
library;

import 'dart:convert';
import 'dart:io';

import 'package:hive/hive.dart';
import 'package:logger/logger.dart';

import 'vpn_service.dart';

/// One resolved identity: address + place.
class IpInfo {
  final String ip;
  final String city;
  final String country;
  final String countryCode;
  final bool ok;

  const IpInfo({
    required this.ip,
    this.city = '',
    this.country = '',
    this.countryCode = '',
    this.ok = false,
  });

  factory IpInfo.unresolved() => const IpInfo(ip: '');

  factory IpInfo.fromJson(Map<String, dynamic> json) {
    final success = json['success'] == true;
    final ip = json['ip']?.toString() ?? '';
    if (!success || ip.isEmpty) return IpInfo.unresolved();
    return IpInfo(
      ip: ip,
      city: json['city']?.toString() ?? '',
      country: json['country']?.toString() ?? '',
      countryCode: json['country_code']?.toString() ?? '',
      ok: true,
    );
  }

  factory IpInfo.fromCached(Map<dynamic, dynamic> map) => IpInfo(
        ip: map['ip']?.toString() ?? '',
        city: map['city']?.toString() ?? '',
        country: map['country']?.toString() ?? '',
        countryCode: map['country_code']?.toString() ?? '',
        ok: map['ok'] == true,
      );

  Map<String, dynamic> toCache() => {
        'ip': ip,
        'city': city,
        'country': country,
        'country_code': countryCode,
        'ok': ok,
      };

  bool get isEmpty => !ok || ip.isEmpty;

  /// Two-letter flag emoji from the ISO country code (ⓐ + regional indicator).
  String get flag {
    if (countryCode.length != 2) return '';
    final base = 0x1F1E6;
    final a = countryCode.toUpperCase().codeUnitAt(0) - 0x41;
    final b = countryCode.toUpperCase().codeUnitAt(1) - 0x41;
    if (a < 0 || a > 25 || b < 0 || b > 25) return '';
    return String.fromCharCode(base + a) + String.fromCharCode(base + b);
  }

  /// "Tehran, Iran 🇮🇷" style label; falls back to whatever is known.
  String get placeLabel {
    final parts = [if (city.isNotEmpty) city, if (country.isNotEmpty) country];
    final label = parts.join(', ');
    return flag.isEmpty ? label : '$label $flag';
  }
}

/// Resolves and caches home/exit identities.
class IpInfoService {
  static const String _boxName = 'ipinfo';
  static const String _homeKey = 'home';
  static const String _exitKey = 'exit';
  static const String _lookupUrl = 'https://ipwho.is';

  final VPNService _vpnService;
  final Logger _log;
  Box? _box;

  IpInfoService({required VPNService vpnService, Logger? logger})
      : _vpnService = vpnService,
        _log = logger ?? Logger();

  Future<void> initialize() async {
    try {
      _box = await Hive.openBox(_boxName);
    } catch (e) {
      _log.e('Could not open the ipinfo box: $e');
    }
  }

  /// Last known home identity from cache (survives restarts and blockades).
  IpInfo cachedHome() {
    final data = _box?.get(_homeKey);
    if (data is! Map) return IpInfo.unresolved();
    return IpInfo.fromCached(data);
  }

  /// Last known exit identity from cache.
  IpInfo cachedExit() {
    final data = _box?.get(_exitKey);
    if (data is! Map) return IpInfo.unresolved();
    return IpInfo.fromCached(data);
  }

  /// Whether lookups are allowed to leave the device at all.
  ///
  /// The privacy copy says the app does not phone home, and then it silently
  /// queried a third-party IP service on connect. Off by default; the user
  /// opts in with the "Show my location" switch in Settings.
  bool _lookupsEnabled = false;

  /// Test/diagnostic hook: true when a lookup was actually attempted (i.e. the
  /// opt-in switch is on). Never true while lookups are disabled.
  bool get lastLookupAttempted => _lookupsEnabled && _lookupAttempted;
  bool _lookupAttempted = false;

  void setLookupsEnabled(bool enabled) {
    _lookupsEnabled = enabled;
    if (!enabled) {
      // Drop anything already resolved so turning the switch off really means
      // "no third-party data on this device".
      _box?.delete(_homeKey);
      _box?.delete(_exitKey);
    }
  }

  /// Resolves the user's direct (pre-tunnel) address and location.
  Future<IpInfo> fetchHome() async {
    if (!_lookupsEnabled) return IpInfo.unresolved();
    _lookupAttempted = true;
    final info = await _directLookup();
    if (!info.isEmpty) _cache(_homeKey, info);
    return info;
  }

  /// Resolves the exit address and location by asking THROUGH the tunnel.
  /// Returns [IpInfo.unresolved] when the tunnel cannot carry the lookup —
  /// callers hide the row rather than show a wrong place.
  Future<IpInfo> fetchExit() async {
    if (!_lookupsEnabled) return IpInfo.unresolved();
    try {
      final body = await _vpnService.tunnelFetch(
        _lookupUrl,
        timeout: const Duration(seconds: 8),
      );
      final info = body == null ? IpInfo.unresolved() : _parse(body);
      if (!info.isEmpty) _cache(_exitKey, info);
      return info;
    } catch (e) {
      _log.w('Exit lookup failed: $e');
      return IpInfo.unresolved();
    }
  }

  /// Direct HTTPS lookup, deliberately NOT through the tunnel.
  Future<IpInfo> _directLookup() async {
    try {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 8);
      try {
        final request =
            await client.getUrl(Uri.parse(_lookupUrl)).timeout(
                  const Duration(seconds: 8),
                );
        final response = await request.close().timeout(
              const Duration(seconds: 8),
            );
        if (response.statusCode != 200) {
          return IpInfo.unresolved();
        }
        final body = await response.transform(utf8.decoder).join();
        final info = _parse(body);
        if (info.isEmpty) return IpInfo.unresolved();
        return info;
      } finally {
        client.close(force: true);
      }
    } catch (e) {
      _log.w('Home lookup failed: $e');
      return IpInfo.unresolved();
    }
  }

  IpInfo _parse(String body) {
    try {
      return IpInfo.fromJson(
        jsonDecode(body) as Map<String, dynamic>,
      );
    } catch (e) {
      _log.w('Could not parse lookup response: $e');
      return IpInfo.unresolved();
    }
  }

  void _cache(String key, IpInfo info) {
    try {
      _box?.put(key, info.toCache());
    } catch (e) {
      _log.w('Could not cache $key identity: $e');
    }
  }
}
