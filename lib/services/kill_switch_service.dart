import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:logger/logger.dart';

import '../controllers/settings_controller.dart';
import '../models/vpn_session_options.dart';

/// Android's own always-on VPN state, as reported by the system.
class SystemKillSwitchState {
  /// Package the user nominated for always-on VPN, or null if none.
  final String? alwaysOnPackage;

  /// True when this app is the nominated always-on VPN.
  final bool isAlwaysOnForThisApp;

  /// True when "Block connections without VPN" is enabled.
  final bool lockdownEnabled;

  /// The combination that actually blocks traffic when the tunnel drops.
  bool get systemKillSwitchActive => isAlwaysOnForThisApp && lockdownEnabled;

  /// True when the user still has to change something in system settings.
  bool get requiresUserAction => !systemKillSwitchActive;

  const SystemKillSwitchState({
    this.alwaysOnPackage,
    this.isAlwaysOnForThisApp = false,
    this.lockdownEnabled = false,
  });

  static const unknown = SystemKillSwitchState();

  factory SystemKillSwitchState.fromMap(Map<dynamic, dynamic> map) =>
      SystemKillSwitchState(
        alwaysOnPackage: map['alwaysOnPackage'] as String?,
        isAlwaysOnForThisApp: map['isAlwaysOnForThisApp'] == true,
        lockdownEnabled: map['lockdownEnabled'] == true,
      );
}

/// Kill switch: keep traffic off the wire when the tunnel is not carrying it.
///
/// ## What an unrooted Android app can and cannot do
///
/// The previous implementation called `activateKillSwitch` /
/// `deactivateKillSwitch` on a method channel with no native handler, and its
/// documentation claimed iptables. iptables needs root. Neither existed.
///
/// There are exactly two mechanisms available, and this service uses both:
///
/// 1. **In-app (always available).** Hold the TUN interface open when the proxy
///    engine dies, instead of tearing it down. The interface has a default
///    route and nothing behind it, so packets are dropped rather than escaping
///    onto the unprotected network. This is what [holdTunnelOnEngineFailure]
///    feeds into [VpnSessionOptions].
///
/// 2. **System always-on VPN + lockdown (needs the user).** This is the only
///    thing that survives the app being killed or the device rebooting. There
///    is no API to enable it — the user has to do it in Settings. This service
///    reports the real state and offers a deep link.
///
/// Anything claiming more than that on a stock device is not telling the truth.
class KillSwitchService extends GetxService {
  static const platform = MethodChannel('com.blackoutkit.vpn/network');

  final _logger = Logger();

  final systemState = SystemKillSwitchState.unknown.obs;
  final lastError = Rxn<String>();

  SettingsController? get _settings =>
      Get.isRegistered<SettingsController>() ? Get.find<SettingsController>() : null;

  bool get isEnabled => _settings?.killSwitchEnabled.value ?? false;

  @override
  void onInit() {
    super.onInit();
    refreshSystemState();
  }

  /// Reads the real always-on VPN configuration from the system.
  Future<SystemKillSwitchState> refreshSystemState() async {
    try {
      final result = await platform.invokeMethod<Map>('getKillSwitchState');
      if (result == null) {
        systemState.value = SystemKillSwitchState.unknown;
        return systemState.value;
      }
      systemState.value =
          SystemKillSwitchState.fromMap(Map<dynamic, dynamic>.from(result));
      return systemState.value;
    } on MissingPluginException {
      systemState.value = SystemKillSwitchState.unknown;
      _logger.w('getKillSwitchState has no handler on this platform');
      return systemState.value;
    } catch (e) {
      lastError.value = 'Could not read the system kill switch state: $e';
      _logger.e('Kill switch state read failed: $e');
      return systemState.value;
    }
  }

  /// Opens Android's VPN settings so the user can enable always-on VPN and
  /// "Block connections without VPN". There is no API to set either.
  Future<bool> openSystemSettings() async {
    try {
      final ok = await platform.invokeMethod<bool>('openVpnSettings');
      return ok == true;
    } on MissingPluginException {
      lastError.value = 'VPN settings cannot be opened on this platform.';
      return false;
    } catch (e) {
      lastError.value = 'Could not open VPN settings: $e';
      _logger.e('openVpnSettings failed: $e');
      return false;
    }
  }

  Future<void> setEnabled(bool enabled) async {
    _settings?.toggleKillSwitch(enabled);
    if (enabled) {
      // The system half is the user's to enable, so re-read it to keep the
      // guidance current.
      await refreshSystemState();
    }
  }

  /// Feeds the kill switch decision into the builder-time options.
  VpnSessionOptions applyTo(VpnSessionOptions options) => options.copyWith(
        holdTunnelOnEngineFailure: isEnabled,
      );

  /// What is protecting the user right now, in plain language.
  String describe() {
    if (!isEnabled) return 'Off';

    final state = systemState.value;
    if (state.systemKillSwitchActive) {
      return 'On - blocks traffic if the tunnel drops, including after a reboot';
    }
    if (state.isAlwaysOnForThisApp) {
      return 'On - blocks traffic while the app runs. Turn on "Block connections '
          'without VPN" in system settings for full protection';
    }
    return 'On - blocks traffic while the app runs. Set this app as always-on '
        'VPN in system settings to also cover reboots and force-stops';
  }

  /// Whether the user still needs to visit system settings for full coverage.
  bool get needsUserAction =>
      isEnabled && systemState.value.requiresUserAction;
}
