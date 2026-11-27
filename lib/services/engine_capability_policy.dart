import 'package:get/get.dart';
import 'package:logger/logger.dart';
import '../models/config.dart';
import 'localization_service.dart';
import 'vpn_service.dart';

/// Owns passive engine capability discovery and admission policy.
class EngineCapabilityPolicy {
  EngineCapabilityPolicy(this.vpnService, this._log);

  final VPNService vpnService;
  final Logger _log;
  final _engineAvailability = Rx<EngineAvailability?>(null);

  /// Drops configs whose protocol no bundled engine can serve.
  ///
  /// Fails open: if the capability probe errors, every config is returned and
  /// the native per-connect check still guards the actual attempt.
  Future<List<Config>> servableConfigs(List<Config> configs) async {
    try {
      _engineAvailability.value = await vpnService.getEngineInfo();
    } catch (e) {
      _log.w('Engine capability probe failed, testing all configs');
      return configs;
    }

    final availability = _engineAvailability.value!;
    if (!availability.isKnown) return configs;

    final servable =
        configs.where((c) => availability.canConnect(c.protocol)).toList();
    final skipped = configs.length - servable.length;
    if (skipped > 0) {
      _log.i('Skipped $skipped config(s) with no bundled engine');
    }
    return servable;
  }

  /// True when a bundled engine can serve [protocol].
  ///
  /// Fails open: until the capability probe has answered, everything is
  /// reported as supported, because refusing a connect that might have worked
  /// is worse than letting the native layer say no.
  bool isProtocolSupported(String protocol) {
    final availability = _engineAvailability.value;
    if (availability == null || !availability.isKnown) return true;
    return availability.canConnect(protocol);
  }

  /// Refreshes the passive engine capability inventory.
  ///
  /// The library calls this so its tiles can grey out protocols this build
  /// cannot run *before* the user taps Connect and gets a red error for
  /// something the app already knew.
  Future<void> ensureEngineAvailability() async {
    try {
      _engineAvailability.value = await vpnService.getEngineInfo();
    } catch (_) {
      _log.w('Engine capability probe failed');
    }
  }

  /// Returns a human-readable refusal when no bundled engine can serve
  /// [config]'s protocol, or null when the attempt should go ahead.
  ///
  /// Fails open on purpose: if the capability probe itself errors we return
  /// null and let the native layer produce the real diagnostic, rather than
  /// blocking a connection that might have worked.
  Future<String?> engineRefusal(Config config) async {
    try {
      _engineAvailability.value = await vpnService.getEngineInfo();
    } catch (e) {
      _log.w('Engine capability probe failed, continuing');
      return null;
    }

    // Transports the bundled Xray core has no package for. It resolves the
    // transport by name at start-up, so a config carrying one of these fails
    // with "Xray core rejected the configuration" - after the consent dialog
    // and after a wasted probe. The core's transport/internet packages are
    // grpc, httpupgrade, hysteria, kcp, reality, splithttp, tcp, tls, udp and
    // websocket; there is no quic and no http (h2).
    // Plaintext VLESS (security: none) to a raw public IP without a domain host
    // is refused upfront because Xray-core strictly prohibits it for security
    // (it leaks the UUID in cleartext over the wire).
    if (config is VlessConfig &&
        (config.security.isEmpty || config.security.toLowerCase() == 'none')) {
      final addr = config.address.trim();
      final isIp =
          RegExp(r'^\d+\.\d+\.\d+\.\d+$').hasMatch(addr) || addr.contains(':');
      final isPrivate = addr.startsWith('10.') ||
          addr.startsWith('192.168.') ||
          addr.startsWith('127.') ||
          addr.startsWith('172.16.') ||
          addr.startsWith('172.17.') ||
          addr.startsWith('172.18.') ||
          addr.startsWith('172.19.') ||
          addr.startsWith('172.2') ||
          addr.startsWith('172.30.') ||
          addr.startsWith('172.31.') ||
          addr == 'localhost';
      final hasDomainHost = config.host != null &&
          config.host!.isNotEmpty &&
          !RegExp(r'^\d+\.\d+\.\d+\.\d+$').hasMatch(config.host!);
      if (isIp && !isPrivate && !hasDomainHost) {
        return LocalizationService.t('vless_plaintext_public_ip_refusal');
      }
    }

    final network = switch (config) {
      VlessConfig c => c.network,
      VmessConfig c => c.network,
      TrojanConfig c => c.network,
      _ => null,
    };
    if (network == 'quic' || network == 'http' || network == 'h2') {
      return "'$network' transport is not supported by the bundled core. "
          'Use a ws, grpc, httpupgrade or xhttp link instead.';
    }

    final availability = _engineAvailability.value!;
    if (!availability.isKnown) return null;
    if (availability.canConnect(config.protocol)) return null;
    if (availability.restartRequiredProtocols.contains(config.protocol)) {
      return 'This engine is unavailable in the current process. Fully restart the app before switching runtime families.';
    }

    final supported = availability.supportedProtocols;
    final supportedLabel = supported.isEmpty
        ? 'none'
        : supported.map((p) => p.toUpperCase()).join(', ');
    return "'${config.protocol}' cannot be dialled by this build: no engine that "
        'serves it is bundled. Supported here: $supportedLabel.';
  }

}
