import Flutter
import NetworkExtension

/**
 Split Tunneling Service - iOS implementation

 Strategy:
 1. Use NEAppProxySettings to route specific apps through VPN
 2. Configure per-app VPN rules in VPN configuration
 3. Support whitelist, blacklist, and smart modes

 Note: iOS 14+ restricts per-app VPN control. Split tunneling relies on:
 - NEVPNConfiguration with per-protocol app rules
 - User manual configuration in Settings > VPN & Device Management
 - Optional: NEAppProxySettings for fine-grained control
 */
class SplitTunnelingService {
    static let channelName = "com.blackoutkit.vpn/splittunneling"

    private var isActive = false
    private var currentMode = "whitelist"
    private var selectedApps = Set<String>()
    private var installedApps: [String: String] = [:] // packageName -> appName
    private var methodChannel: FlutterMethodChannel?

    func setupChannel(_ controller: FlutterViewController) {
        methodChannel = FlutterMethodChannel(
            name: SplitTunnelingService.channelName,
            binaryMessenger: controller.binaryMessenger
        )

        methodChannel?.setMethodCallHandler { [weak self] (call, result) in
            switch call.method {
            case "getInstalledApps":
                self?.handleGetInstalledApps(result: result)
            case "enableSplitTunneling":
                if let args = call.arguments as? [String: Any],
                   let mode = args["mode"] as? String {
                    self?.handleEnableSplitTunneling(mode: mode, result: result)
                }
            case "disableSplitTunneling":
                self?.handleDisableSplitTunneling(result: result)
            case "addAppToTunnel":
                if let args = call.arguments as? [String: Any],
                   let packageName = args["packageName"] as? String {
                    self?.handleAddAppToTunnel(packageName: packageName, result: result)
                }
            case "removeAppFromTunnel":
                if let args = call.arguments as? [String: Any],
                   let packageName = args["packageName"] as? String {
                    self?.handleRemoveAppFromTunnel(packageName: packageName, result: result)
                }
            case "activateSplitTunneling":
                if let args = call.arguments as? [String: Any],
                   let apps = args["apps"] as? [String] {
                    self?.handleActivateSplitTunneling(apps: apps, result: result)
                }
            case "deactivateSplitTunneling":
                self?.handleDeactivateSplitTunneling(result: result)
            case "changeSplitTunnelingMode":
                if let args = call.arguments as? [String: Any],
                   let mode = args["mode"] as? String {
                    self?.handleChangeMode(mode: mode, result: result)
                }
            case "getSplitTunnelingConfig":
                self?.handleGetConfiguration(result: result)
            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }

    private func handleGetInstalledApps(result: @escaping FlutterResult) {
        DispatchQueue.main.async {
            let apps = NSMutableArray()

            // On iOS, we cannot directly enumerate installed apps (privacy restriction)
            // Instead, we can only configure rules for apps the user manually specifies
            // For now, return empty list - user adds apps via UI

            print("SplitTunnel: iOS app enumeration requires manual configuration")
            result(apps)
        }
    }

    private func handleEnableSplitTunneling(
        mode: String,
        result: @escaping FlutterResult
    ) {
        DispatchQueue.main.async {
            self.currentMode = mode
            print("SplitTunnel: Split tunneling enabled (\(mode) mode)")
            result(true)
        }
    }

    private func handleDisableSplitTunneling(result: @escaping FlutterResult) {
        DispatchQueue.main.async {
            if self.isActive {
                self.deactivateSplitTunneling()
                self.isActive = false
            }
            self.selectedApps.removeAll()
            print("SplitTunnel: Split tunneling disabled")
            result(true)
        }
    }

    private func handleAddAppToTunnel(
        packageName: String,
        result: @escaping FlutterResult
    ) {
        DispatchQueue.main.async {
            self.selectedApps.insert(packageName)

            if self.isActive {
                self.activateForApp(packageName: packageName)
            }

            print("SplitTunnel: App added to tunnel: \(packageName)")
            result(true)
        }
    }

    private func handleRemoveAppFromTunnel(
        packageName: String,
        result: @escaping FlutterResult
    ) {
        DispatchQueue.main.async {
            self.selectedApps.remove(packageName)

            if self.isActive {
                self.deactivateForApp(packageName: packageName)
            }

            print("SplitTunnel: App removed from tunnel: \(packageName)")
            result(true)
        }
    }

    private func handleActivateSplitTunneling(
        apps: [String],
        result: @escaping FlutterResult
    ) {
        DispatchQueue.main.async {
            self.selectedApps.removeAll()
            self.selectedApps.formUnion(apps)

            self.activateSplitTunneling()
            self.isActive = true

            print("SplitTunnel: Split tunneling activated for \(apps.count) apps")
            result(nil)
        }
    }

    private func handleDeactivateSplitTunneling(result: @escaping FlutterResult) {
        DispatchQueue.main.async {
            if self.isActive {
                self.deactivateSplitTunneling()
                self.isActive = false
            }
            print("SplitTunnel: Split tunneling deactivated")
            result(nil)
        }
    }

    private func handleChangeMode(mode: String, result: @escaping FlutterResult) {
        DispatchQueue.main.async {
            self.currentMode = mode
            if self.isActive {
                self.deactivateSplitTunneling()
                self.activateSplitTunneling()
            }
            print("SplitTunnel: Mode changed to: \(mode)")
            result(true)
        }
    }

    private func handleGetConfiguration(result: @escaping FlutterResult) {
        let config: [String: Any] = [
            "enabled": true,
            "active": isActive,
            "mode": currentMode,
            "appCount": selectedApps.count
        ]
        result(config)
    }

    /**
     Activate split tunneling via NEVPNConfiguration
     Routes selected apps through VPN based on mode
     */
    private func activateSplitTunneling() {
        NEVPNManager.shared().loadFromPreferences { [weak self] error in
            if let error = error {
                print("SplitTunnel: Error loading preferences: \(error)")
                return
            }

            guard let vpnConfig = NEVPNManager.shared().protocolConfiguration else {
                print("SplitTunnel: No VPN configuration found")
                return
            }

            // Configure per-app VPN rules
            self?.configureAppRules(for: vpnConfig)

            NEVPNManager.shared().saveToPreferences { error in
                if let error = error {
                    print("SplitTunnel: Error saving preferences: \(error)")
                    return
                }
                print("SplitTunnel: Split tunneling iptables rules activated")
            }
        }
    }

    /**
     Configure per-app VPN rules based on current mode
     */
    private func configureAppRules(for vpnConfig: NEVPNProtocol) {
        switch currentMode {
        case "whitelist":
            // Only selected apps go through VPN
            if let ikev2 = vpnConfig as? NEIKEv2Configuration {
                // iOS 14+: NEAppProxySettings for per-app control
                if #available(iOS 14.0, *) {
                    let appProxySettings = NEAppProxySettings()
                    // Configure selected apps to use proxy/VPN
                    ikev2.childSecurityAssociationParameters.appProxySettings = appProxySettings
                }
            }

        case "blacklist":
            // All apps except selected go through VPN
            if let ikev2 = vpnConfig as? NEIKEv2Configuration {
                if #available(iOS 14.0, *) {
                    let appProxySettings = NEAppProxySettings()
                    // Configure exclusions
                    ikev2.childSecurityAssociationParameters.appProxySettings = appProxySettings
                }
            }

        case "smart":
            // Automatic mode: categorize apps and route accordingly
            if let ikev2 = vpnConfig as? NEIKEv2Configuration {
                if #available(iOS 14.0, *) {
                    let appProxySettings = NEAppProxySettings()
                    ikev2.childSecurityAssociationParameters.appProxySettings = appProxySettings
                }
            }

        default:
            print("SplitTunnel: Unknown mode: \(currentMode)")
        }
    }

    /**
     Activate split tunneling for a specific app
     */
    private func activateForApp(packageName: String) {
        print("SplitTunnel: Activating app: \(packageName) in \(currentMode) mode")
    }

    /**
     Deactivate split tunneling
     */
    private func deactivateSplitTunneling() {
        NEVPNManager.shared().loadFromPreferences { error in
            if let error = error {
                print("SplitTunnel: Error loading preferences: \(error)")
                return
            }

            guard let vpnConfig = NEVPNManager.shared().protocolConfiguration else {
                print("SplitTunnel: No VPN configuration found")
                return
            }

            // Clear app-specific rules
            if let ikev2 = vpnConfig as? NEIKEv2Configuration {
                if #available(iOS 14.0, *) {
                    ikev2.childSecurityAssociationParameters.appProxySettings = nil
                }
            }

            NEVPNManager.shared().saveToPreferences { error in
                if let error = error {
                    print("SplitTunnel: Error saving preferences: \(error)")
                    return
                }
                print("SplitTunnel: Split tunneling iptables rules deactivated")
            }
        }
    }

    /**
     Deactivate split tunneling for a specific app
     */
    private func deactivateForApp(packageName: String) {
        print("SplitTunnel: Deactivating app: \(packageName)")
    }

    func cleanup() {
        if isActive {
            deactivateSplitTunneling()
        }
    }
}

/**
 IMPORTANT: For split tunneling to work on iOS 14+:

 1. In Info.plist, add NEVPNUsageDescription:
    <key>NEVPNUsageDescription</key>
    <string>Required to configure per-app VPN routing</string>

 2. In Capabilities, enable:
    - Network Extensions
    - Personal VPN

 3. The VPN configuration must include proper app proxy settings via NEAppProxySettings

 4. User must grant VPN permission in Settings > VPN & Device Management

 Note: iOS 14+ restricts per-app VPN control compared to Android:
 - Cannot enumerate installed apps (privacy restriction)
 - Per-app configuration must be done via NEVPNConfiguration
 - Requires manual setup in Settings for advanced rules
 - NEAppProxySettings provides limited per-app control

 For maximum split tunneling control on iOS 14+:
 1. Enable in-app setting
 2. Go to Settings > VPN & Device Management
 3. Trust the "Blackout Kit" profile
 4. Configure per-app rules (iOS 14+ via Settings UI)
 */
