/// Options that must be decided *before* the tunnel is established.
///
/// ## Why this exists
///
/// The previous design treated the kill switch, split tunneling and DNS leak
/// prevention as things you "activate" after connecting, through three separate
/// method channels. That cannot work on Android. Every one of those features is
/// a `VpnService.Builder` decision:
///
///   split tunneling      -> addAllowedApplication / addDisallowedApplication
///   DNS leak prevention  -> addDnsServer
///   kill switch          -> whether the interface is held open when the engine dies
///
/// `Builder.establish()` freezes all of it into an immutable `ParcelFileDescriptor`.
/// There is no API to change a live tunnel's DNS server or app list — the only
/// way is to tear the interface down and build a new one. And iptables, which
/// the old code assumed, requires root and is unavailable to a normal app.
///
/// So the features are modelled here as *inputs to connect()*, not as switches
/// to flip afterwards.
library;

/// Immutable set of builder-time decisions for one VPN session.
class VpnSessionOptions {
  /// Apps that go **through** the tunnel. Non-empty means whitelist mode:
  /// Android then routes only these and sends everything else direct.
  final List<String> allowedApps;

  /// Apps that bypass the tunnel. Ignored when [allowedApps] is non-empty,
  /// because Android rejects a uid that appears in both lists.
  final List<String> disallowedApps;

  /// DNS servers written into the tunnel. When [routeDnsThroughProxy] is set
  /// these are also handed to the core's own resolver.
  final List<String> dnsServers;

  /// Send DNS through the proxy instead of resolving locally. This is what
  /// actually stops the ISP from seeing queries; [dnsServers] alone only
  /// redirects them.
  final bool routeDnsThroughProxy;

  /// Keep the TUN interface up when the proxy engine dies, so traffic is
  /// black-holed rather than silently falling back to the unprotected network.
  ///
  /// This is the only kill-switch behaviour an unrooted app can implement by
  /// itself. A true system-wide kill switch additionally needs the user to
  /// enable "Always-on VPN" + "Block connections without VPN" in Android
  /// settings; see `KillSwitchService`.
  final bool holdTunnelOnEngineFailure;

  const VpnSessionOptions({
    this.allowedApps = const [],
    this.disallowedApps = const [],
    this.dnsServers = const ['1.1.1.1'],
    this.routeDnsThroughProxy = false,
    this.holdTunnelOnEngineFailure = false,
  });

  /// Android's per-app list is not unbounded; beyond a few hundred entries
  /// `establish()` starts failing on many devices.
  static const int maxAppsPerList = 100;

  bool get hasSplitTunnel =>
      allowedApps.isNotEmpty || disallowedApps.isNotEmpty;

  bool get usesWhitelist => allowedApps.isNotEmpty;

  /// The list Android will actually receive, honouring whitelist precedence.
  List<String> get effectiveAppList =>
      allowedApps.isNotEmpty ? allowedApps : disallowedApps;

  /// Human-readable problem with this configuration, or null when it is sane.
  String? get validationError {
    if (allowedApps.length > maxAppsPerList) {
      return 'Too many apps in the tunnel list '
          '(${allowedApps.length} > $maxAppsPerList). Android will refuse to '
          'build the interface.';
    }
    if (disallowedApps.length > maxAppsPerList) {
      return 'Too many apps excluded from the tunnel '
          '(${disallowedApps.length} > $maxAppsPerList).';
    }
    if (dnsServers.isEmpty) {
      return 'At least one DNS server is required.';
    }
    for (final server in dnsServers) {
      if (!_looksLikeIp(server)) {
        return '"$server" is not an IP address. Android only accepts literal '
            'IPs for addDnsServer().';
      }
    }
    return null;
  }

  static bool _looksLikeIp(String value) {
    if (value.isEmpty) return false;
    // IPv4 dotted quad or anything containing a colon (IPv6).
    if (value.contains(':')) return true;
    final parts = value.split('.');
    if (parts.length != 4) return false;
    for (final part in parts) {
      final n = int.tryParse(part);
      if (n == null || n < 0 || n > 255) return false;
    }
    return true;
  }

  /// Payload for the `connect` platform call.
  Map<String, dynamic> toChannelMap() => {
        'allowedApps': allowedApps,
        'disallowedApps': disallowedApps,
        'dns': dnsServers.first,
        'dnsServers': dnsServers,
        'routeDnsThroughProxy': routeDnsThroughProxy,
        'holdTunnelOnEngineFailure': holdTunnelOnEngineFailure,
      };

  VpnSessionOptions copyWith({
    List<String>? allowedApps,
    List<String>? disallowedApps,
    List<String>? dnsServers,
    bool? routeDnsThroughProxy,
    bool? holdTunnelOnEngineFailure,
  }) =>
      VpnSessionOptions(
        allowedApps: allowedApps ?? this.allowedApps,
        disallowedApps: disallowedApps ?? this.disallowedApps,
        dnsServers: dnsServers ?? this.dnsServers,
        routeDnsThroughProxy: routeDnsThroughProxy ?? this.routeDnsThroughProxy,
        holdTunnelOnEngineFailure:
            holdTunnelOnEngineFailure ?? this.holdTunnelOnEngineFailure,
      );

  @override
  String toString() => 'VpnSessionOptions('
      'splitTunnel=${usesWhitelist ? "whitelist" : (hasSplitTunnel ? "blacklist" : "off")}, '
      'apps=${effectiveAppList.length}, dns=$dnsServers, '
      'dnsViaProxy=$routeDnsThroughProxy, killSwitch=$holdTunnelOnEngineFailure)';
}
