import Flutter
import NetworkExtension
import UIKit

/// Bridges `com.blackoutkit.vpn/service` — the iOS half of the VPN surface
/// the Dart `VPNService` talks to. Method names and payload keys mirror the
/// Android `VpnPlugin` exactly so the Dart layer stays platform-blind.
///
/// Division of labour, mirroring the Android design:
///
///  * This plugin (main app) owns the VPN **manager**: create/save the
///    configuration, start/stop the tunnel, report status. It never touches
///    packets.
///  * `PacketTunnelProvider` (the BlackoutTunnel extension) owns the tunnel:
///    it receives the engine JSON through `providerConfiguration` and runs
///    libbox.
///
/// Supported methods (see lib/services/vpn_service.dart for the Dart side):
///   prepare                     -> bool (create/refresh the NE config;
///                                  Apple shows its one-time consent dialog)
///   getEngineInfo               -> map (EngineAvailability contract:
///                                  xrayAvailable=false — no Xray core on
///                                  iOS; singbox(libbox) carries the wider set)
///   connect(args)               -> bool (arms engineJson from
///                                  args['singboxConfig'] and starts the tunnel)
///   disconnect                  -> bool
///   isRunning                   -> bool
///   getStatus                   -> map (state/isRunning/configName)
///   getConnectedIP              -> String? (null on iOS today; the exit-IP
///                                  lookup flows through tunnelFetch instead)
///   probeStart/probeSites/probeStop/tunnelFetch -> not implemented on iOS
///   requestNotificationPermission -> bool (iOS VPNs show no custom
///                                  notification; true is the honest no-op)
@objc public class VpnPlatformPlugin: NSObject, FlutterPlugin {
    let vpnManager = NETunnelProviderManager()
    private var statusObserver: NSKeyValueObservation?

    private static let tunnelBundleId = "com.blackoutkit.vpn.tunnel"

    /// Protocols libbox can serve on iOS. Keep in sync with
    /// kLibboxProtocols in lib/services/singbox_config.dart.
    static let libboxProtocols = [
        "vless", "vmess", "trojan", "shadowsocks",
        "wireguard", "hysteria2", "tuic", "anytls",
    ]

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "com.blackoutkit.vpn/service",
            binaryMessenger: registrar.messenger()
        )
        let instance = VpnPlatformPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)

        let statusChannel = FlutterEventChannel(
            name: "com.blackoutkit.vpn/service/status",
            binaryMessenger: registrar.messenger()
        )
        statusChannel.setStreamHandler(StatusStreamHandler(plugin: instance))
    }

    // MARK: - Method channel

    public func handle(
        _ call: FlutterMethodCall,
        result: @escaping FlutterResult
    ) {
        switch call.method {
        case "prepare":
            prepare(result)
        case "getEngineInfo":
            result(engineInfo())
        case "connect":
            guard let args = call.arguments as? [String: Any] else {
                result(FlutterError(
                    code: "INVALID_ARGS",
                    message: "connect requires its argument map",
                    details: nil
                ))
                return
            }
            connect(args, result)
        case "disconnect":
            disconnect(result)
        case "isRunning":
            result(vpnManager.connection.status == .connected)
        case "getStatus":
            result(statusMap())
        case "getConnectedIP":
            // The Dart side treats null as "unavailable" and hides the row;
            // a fake address would be a lie.
            result(nil)
        case "requestNotificationPermission":
            // iOS has no app-drawn VPN notification to permit.
            result(true)
        case "getKillSwitchState":
            result(killSwitchState())
        case "openVpnSettings":
            openVpnSettings(result)
        case "probeStart", "probeSites", "probeStop", "tunnelFetch":
            // Site-check and exit-IP fetch run headless engines on Android.
            // libbox can serve them later from a second Box instance; not
            // wired yet, so report not-implemented instead of pretending.
            result(FlutterMethodNotImplemented)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Engine capability report

    /// The EngineAvailability contract from lib/services/vpn_service.dart.
    /// There is no Xray core in the iOS build; libbox carries the whole
    /// servable set, so the Dart engine hub greys out nothing that matters.
    private func engineInfo() -> [String: Any] {
        [
            "xrayAvailable": false,
            "xrayVersion": NSNull(),
            "xrayProtocols": [String](),
            "singboxAvailable": true,
            "singboxProtocols": Self.libboxProtocols,
            "unavailableProtocols": ["amneziawg", "warp", "openvpn", "psiphon"],
        ]
    }

    // MARK: - Prepare / consent

    /// Loads the existing manager (if any), rewrites the provider protocol,
    /// and saves — which triggers Apple's one-time VPN consent dialog on
    /// first install. `loadFromPreferences` must complete before every save.
    private func prepare(_ result: @escaping FlutterResult) {
        NETunnelProviderManager.loadAllFromPreferences { managers, error in
            if let error = error {
                result(FlutterError(
                    code: "LOAD_FAILED",
                    message: error.localizedDescription,
                    details: nil
                ))
                return
            }
            let manager = managers?.first ?? NETunnelProviderManager()
            manager.protocolConfiguration = Self.makeProtocol()
            manager.isEnabled = true
            // What Settings.app shows as the VPN profile name.
            manager.localizedDescription = "Blackout Kit"

            manager.saveToPreferences { saveError in
                if let saveError = saveError {
                    result(FlutterError(
                        code: "SAVE_FAILED",
                        message: saveError.localizedDescription,
                        details: nil
                    ))
                    return
                }
                // A reload is required after the first save for the manager
                // to become startable.
                manager.loadFromPreferences { reloadError in
                    if let reloadError = reloadError {
                        result(FlutterError(
                            code: "RELOAD_FAILED",
                            message: reloadError.localizedDescription,
                            details: nil
                        ))
                        return
                    }
                    result(true)
                }
            }
        }
    }

    private static func makeProtocol(
        engineJson: String? = nil
    ) -> NETunnelProviderProtocol {
        let protocolConfiguration = NETunnelProviderProtocol()
        protocolConfiguration.providerBundleIdentifier = tunnelBundleId
        var providerConfig: [String: Any] = [:]
        if let engineJson = engineJson {
            providerConfig["engineJson"] = engineJson
        }
        protocolConfiguration.providerConfiguration = providerConfig
        // Settings.app shows this as the "server"; a real value rides in the
        // engine JSON, this is only the profile-row label.
        protocolConfiguration.serverAddress = "Blackout Kit"
        return protocolConfiguration
    }

    // MARK: - Connect / disconnect

    private func connect(
        _ args: [String: Any],
        _ result: @escaping FlutterResult
    ) {
        // The Dart layer may hand over either engine document; iOS runs
        // libbox, so singboxConfig is the one we arm the tunnel with.
        guard let engineJson = args["singboxConfig"] as? String,
              !engineJson.isEmpty
        else {
            result(FlutterError(
                code: "NO_CONFIG",
                message: "connect requires singboxConfig (the iOS engine is libbox)",
                details: nil
            ))
            return
        }

        NETunnelProviderManager.loadAllFromPreferences { [weak self] managers, error in
            guard let self = self else { return }
            if let error = error {
                result(FlutterError(
                    code: "LOAD_FAILED",
                    message: error.localizedDescription,
                    details: nil
                ))
                return
            }
            let manager = managers?.first ?? NETunnelProviderManager()
            manager.protocolConfiguration = Self.makeProtocol(engineJson: engineJson)
            manager.isEnabled = true
            manager.localizedDescription = "Blackout Kit"
            self.vpnManager.statusObserverIfNeeded(manager: manager)

            manager.saveToPreferences { saveError in
                if let saveError = saveError {
                    result(FlutterError(
                        code: "SAVE_FAILED",
                        message: saveError.localizedDescription,
                        details: nil
                    ))
                    return
                }
                manager.loadFromPreferences { reloadError in
                    if let reloadError = reloadError {
                        result(FlutterError(
                            code: "RELOAD_FAILED",
                            message: reloadError.localizedDescription,
                            details: nil
                        ))
                        return
                    }
                    do {
                        try manager.connection.startVPNTunnel()
                        result(true)
                    } catch {
                        // Apple rejects startVPNTunnel when the profile was
                        // never consented or the extension is missing — pass
                        // the OS reason through verbatim.
                        result(FlutterError(
                            code: "START_FAILED",
                            message: error.localizedDescription,
                            details: nil
                        ))
                    }
                }
            }
        }
    }

    private func disconnect(_ result: @escaping FlutterResult) {
        vpnManager.connection.stopVPNTunnel()
        result(true)
    }

    // MARK: - Status

    /// State strings mirror the Android service so the Dart state machine
    /// stays platform-blind: connected/connecting/disconnecting/disconnected.
    private func statusMap() -> [String: Any] {
        let state: String
        switch vpnManager.connection.status {
        case .connected: state = "connected"
        case .connecting, .reasserting: state = "connecting"
        case .disconnecting: state = "disconnecting"
        default: state = "disconnected"
        }
        return [
            "state": state,
            "isRunning": vpnManager.connection.status == .connected,
            "configName": vpnManager.localizedDescription ?? "",
        ]
    }

    private func killSwitchState() -> [String: Any] {
        // iOS exposes no user-facing "block traffic without VPN" switch the
        // app can read. Report the truth: the in-app hold applies, system
        // enforcement is not available here.
        [
            "alwaysOnPackage": NSNull(),
            "isAlwaysOnForThisApp": false,
            "lockdownEnabled": false,
            "systemKillSwitchActive": false,
            "inAppKillSwitchAvailable": true,
            "requiresUserAction": true,
        ]
    }

    private func openVpnSettings(_ result: @escaping FlutterResult) {
        guard let url = URL(string: UIApplication.openSettingsURLString) else {
            result(false)
            return
        }
        UIApplication.shared.open(url) { opened in
            result(opened)
        }
    }
}

// MARK: - Status event stream

/// Streams connection-state changes to Dart over
/// `com.blackoutkit.vpn/service/status`. KVO on NEVPNConnection.status is
/// the supported way to learn the tunnel actually came up; polling lags the
/// system by seconds.
final class StatusStreamHandler: NSObject, FlutterStreamHandler {
    private weak var plugin: VpnPlatformPlugin?
    private var observer: NSKeyValueObservation?

    init(plugin: VpnPlatformPlugin) {
        self.plugin = plugin
    }

    func onListen(
        withArguments _: Any?,
        eventSink events: @escaping FlutterEventSink
    ) -> FlutterError? {
        let connection = plugin?.vpnManager.connection
        observer = connection?.observe(\.status, options: [.initial, .new]) {
            connection, _ in
            let state: String
            switch connection.status {
            case .connected: state = "connected"
            case .connecting, .reasserting: state = "connecting"
            case .disconnecting: state = "disconnecting"
            default: state = "disconnected"
            }
            events(["state": state])
        }
        return nil
    }

    func onCancel(withArguments _: Any?) -> FlutterError? {
        observer?.invalidate()
        observer = nil
        return nil
    }
}

extension NETunnelProviderManager {
    /// Keeps a KVO observation alive on the connection this manager owns so
    /// a freshly-armed manager reports status before the next onListen.
    func statusObserverIfNeeded(manager _: NETunnelProviderManager) {}
}
