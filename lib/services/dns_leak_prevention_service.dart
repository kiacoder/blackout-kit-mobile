import 'dart:io';

import 'package:get/get.dart';
import 'package:logger/logger.dart';

import '../controllers/settings_controller.dart';
import '../models/dns_provider.dart';
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

  /// The selectable resolver catalogue (sanctions / speed / extra).
  ///
  /// Each entry is a *pair*: primary and secondary. The tunnel advertises both,
  /// so a dead primary falls through to the secondary instead of to the
  /// carrier's resolver.
  List<DnsProvider> get providers => DnsCatalog.all;

  SettingsController? get _settings =>
      Get.isRegistered<SettingsController>() ? Get.find<SettingsController>() : null;

  bool get isEnabled => _settings?.dnsLeakPreventionEnabled.value ?? false;

  String get customDnsServer => _settings?.customDnsServer.value ?? '1.1.1.1';

  /// Catalogue key of the active pair, or `'custom'` when the user typed an
  /// address by hand.
  String get providerKey => _settings?.dnsProviderKey.value ?? 'cloudflare';

  /// The selected pair, or null when the choice is a custom address.
  DnsProvider? get selectedProvider => DnsCatalog.byKey(providerKey);

  /// Resolvers the tunnel will advertise and the core will use.
  ///
  /// Primary first, secondary second — that ordering is the whole point of a
  /// pair. A single custom address yields a one-element list.
  List<String> get resolvers {
    if (!isEnabled) return const ['1.1.1.1'];
    final provider = selectedProvider;
    if (provider != null) return provider.servers;
    final secondary = _settings?.dnsSecondaryServer.value ?? '';
    return [customDnsServer, if (secondary.isNotEmpty) secondary];
  }

  Future<void> setEnabled(bool enabled) async {
    _settings?.toggleDnsLeakPrevention(enabled);
  }

  /// Select a catalogue pair by key.
  Future<void> selectProvider(String key) async {
    if (DnsCatalog.byKey(key) == null) {
      lastError.value = 'Unknown DNS provider "$key".';
      return;
    }
    _settings?.setDnsProvider(key);
    lastError.value = null;
  }

  Future<void> setCustomDnsServer(String server) async {
    final trimmed = server.trim();
    // One validator, not three. This used to be a local `contains(':')` check
    // that accepted "a:b" and "http://x" as IPv6, so garbage reached the
    // settings file and only failed later, at connect time.
    if (!VpnSessionOptions.isIpLiteral(trimmed)) {
      lastError.value =
          '"$server" is not an IP address. Android only accepts literal IPs.';
      return;
    }
    if (!VpnSessionOptions.isTunnelDns(trimmed)) {
      lastError.value = '"$server" is IPv6, and this tunnel has no IPv6 '
          'address (v6 is black-holed on purpose), so it could never answer. '
          'Use an IPv4 resolver.';
      return;
    }
    _settings?.setCustomDnsServer(trimmed);
    lastError.value = null;
  }

  /// Feeds the DNS decision into the builder-time options.
  ///
  /// Only an ENABLED leak-prevention choice replaces the resolver list: the
  /// options the caller built already carry the config's own DNS (a WireGuard
  /// profile's [Interface] DNS), and overwriting it with `1.1.1.1` while the
  /// feature is off silently discarded that resolver on every connect.
  VpnSessionOptions applyTo(VpnSessionOptions options) => isEnabled
      ? options.copyWith(
          dnsServers: resolvers,
          // Resolving inside the core is what hides queries from the network.
          routeDnsThroughProxy: true,
        )
      : options.copyWith(routeDnsThroughProxy: false);

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

  /// Human-readable summary for settings screens.
  String describe() {
    if (!isEnabled) return 'Off - the system resolver is used';
    final provider = selectedProvider;
    final label = provider?.name ?? 'Custom';
    return 'On - queries resolved inside the tunnel via $label '
        '(${resolvers.join(", ")})';
  }
}
