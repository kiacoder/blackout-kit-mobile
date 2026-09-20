import 'dart:io';

import 'package:get/get.dart';
import 'package:logger/logger.dart';

import '../controllers/settings_controller.dart';
import '../models/vpn_session_options.dart';

/// DNS leak prevention: make sure queries cannot escape to the carrier.
///
/// ## What actually stops a leak
///
/// Two things, and the old code did neither:
///
/// 1. `VpnService.Builder.addDnsServer(...)` — the tunnel advertises our
///    resolvers, so the system has no reason to fall back to the carrier's.
/// 2. Sending DNS through the proxy and resolving inside the core — this is
///    what stops the *destination* from seeing queries at all. A DNS server
///    address on its own only redirects them.
///
/// Both are builder-time decisions, so they are expressed as
/// [VpnSessionOptions] and applied before `establish()`.
///
/// The old implementation called `enableDNSLeakPrevention`,
/// `activateDNSLeakPrevention` and `testDNSLeaks` on a channel with no native
/// handler, and its leak "test" always reported success because the exception
/// was swallowed and an empty list returned. That is worse than no test: it
/// told the user they were safe. [probeResolvers] below is a real reachability
/// check and is named as one.
class DNSLeakPreventionService extends GetxService {
  final _logger = Logger();

  final lastError = Rxn<String>();
  final isProbing = RxBool(false);

  /// Public resolvers offered in the UI.
  static const secureDNSServers = {
    'cloudflare': '1.1.1.1',
    'quad9': '9.9.9.9',
    'adguard': '94.140.14.14',
    'nextdns': '45.90.28.0',
    'opendns': '208.67.222.222',
  };

  SettingsController? get _settings =>
      Get.isRegistered<SettingsController>() ? Get.find<SettingsController>() : null;

  bool get isEnabled => _settings?.dnsLeakPreventionEnabled.value ?? false;

  String get customDnsServer => _settings?.customDnsServer.value ?? '1.1.1.1';

  /// Resolvers the tunnel will advertise and the core will use.
  List<String> get resolvers {
    if (!isEnabled) return const ['1.1.1.1'];
    return [customDnsServer];
  }

  Future<void> setEnabled(bool enabled) async {
    _settings?.toggleDnsLeakPrevention(enabled);
  }

  Future<void> setCustomDnsServer(String server) async {
    if (!_isIpLiteral(server)) {
      lastError.value =
          '"$server" is not an IP address. Android only accepts literal IPs.';
      return;
    }
    _settings?.setCustomDnsServer(server);
    lastError.value = null;
  }

  /// Feeds the DNS decision into the builder-time options.
  VpnSessionOptions applyTo(VpnSessionOptions options) => options.copyWith(
        dnsServers: resolvers,
        // Resolving inside the core is what hides queries from the network.
        routeDnsThroughProxy: isEnabled,
      );

  /// Opens a TCP connection to port 53 on each resolver and reports which ones
  /// answered.
  ///
  /// This is a **reachability probe**, not a leak detector. A resolver can be
  /// reachable and the device can still leak through a second interface; a
  /// resolver can also be unreachable while DNS works fine over UDP. It is
  /// reported as what it is so the UI can label it correctly.
  Future<Map<String, bool>> probeResolvers({
    Duration timeout = const Duration(seconds: 3),
  }) async {
    if (isProbing.value) return const {};

    isProbing.value = true;
    final results = <String, bool>{};
    try {
      for (final server in resolvers) {
        results[server] = await _canConnect(server, 53, timeout);
      }
      _logger.i('Resolver probe: $results');
      return results;
    } finally {
      isProbing.value = false;
    }
  }

  Future<bool> _canConnect(String host, int port, Duration timeout) async {
    try {
      final socket = await Socket.connect(host, port, timeout: timeout);
      socket.destroy();
      return true;
    } catch (e) {
      _logger.w('Resolver $host:$port did not answer: $e');
      return false;
    }
  }

  static bool _isIpLiteral(String value) {
    if (value.isEmpty) return false;
    if (value.contains(':')) return true; // IPv6
    final parts = value.split('.');
    if (parts.length != 4) return false;
    for (final part in parts) {
      final n = int.tryParse(part);
      if (n == null || n < 0 || n > 255) return false;
    }
    return true;
  }

  /// Human-readable summary for settings screens.
  String describe() {
    if (!isEnabled) return 'Off - the system resolver is used';
    return 'On - queries resolved inside the tunnel via $customDnsServer';
  }
}
