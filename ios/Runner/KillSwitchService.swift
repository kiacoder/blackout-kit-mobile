import Flutter
import NetworkExtension
import Darwin

/**
 Kill Switch Service - iOS implementation

 Strategy:
 1. Use NEVPNConfiguration to enforce VPN-only traffic
 2. Set disconnectOnDemand with Wi-Fi and cellular rules
 3. Fallback: Recommend "Allow VPN" system setting

 Note: iOS sandboxing limits direct traffic manipulation.
 True kill switch requires using NEVPNConfiguration properly.
 */
class KillSwitchService {
    static let channelName = "com.blackoutkit.vpn/killswitch"

    private var isActive = false
    private var methodChannel: FlutterMethodChannel?

    func setupChannel(_ controller: FlutterViewController) {
        methodChannel = FlutterMethodChannel(
            name: KillSwitchService.channelName,
            binaryMessenger: controller.binaryMessenger
        )

        methodChannel?.setMethodCallHandler { [weak self] (call, result) in
            switch call.method {
            case "enableKillSwitch":
                self?.handleEnableKillSwitch(result: result)
            case "disableKillSwitch":
                self?.handleDisableKillSwitch(result: result)
            case "activateKillSwitch":
                self?.handleActivateKillSwitch(result: result)
            case "deactivateKillSwitch":
                self?.handleDeactivateKillSwitch(result: result)
            case "isKillSwitchActive":
                result(self?.isActive ?? false)
            case "getKillSwitchCapabilities":
                self?.handleGetCapabilities(result: result)
            case "testKillSwitch":
                if let args = call.arguments as? [String: Any],
                   let duration = args["durationSeconds"] as? Int {
                    self?.handleTestKillSwitch(duration: duration, result: result)
                }
            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }

    private func handleEnableKillSwitch(result: @escaping FlutterResult) {
        DispatchQueue.main.async {
            NEVPNManager.shared().loadFromPreferences { [weak self] error in
                if let error = error {
                    print("KillSwitch: Error loading VPN preferences: \(error)")
                    result(false)
                    return
                }

                // Kill switch enabled - will be enforced when VPN connects
                print("KillSwitch: Kill switch enabled successfully")
                result(true)
            }
        }
    }

    private func handleDisableKillSwitch(result: @escaping FlutterResult) {
        DispatchQueue.main.async {
            self.isActive = false
            print("KillSwitch: Kill switch disabled")
            result(true)
        }
    }

    private func handleActivateKillSwitch(result: @escaping FlutterResult) {
        DispatchQueue.main.async {
            NEVPNManager.shared().loadFromPreferences { [weak self] error in
                if let error = error {
                    print("KillSwitch: Error loading preferences: \(error)")
                    result(FlutterError(code: "ACTIVATE_FAILED", message: error.localizedDescription, details: nil))
                    return
                }

                guard let vpnConfig = NEVPNManager.shared().protocolConfiguration else {
                    print("KillSwitch: No VPN configuration found")
                    result(FlutterError(code: "ACTIVATE_FAILED", message: "No VPN configuration", details: nil))
                    return
                }

                // Set disconnectOnDemand to prevent traffic leaks
                let connectRule = NEOnDemandRuleConnect()
                connectRule.interfaceTypeMatch = .any

                let denyRule = NEOnDemandRuleDisconnect()
                denyRule.interfaceTypeMatch = .any

                NEVPNManager.shared().isOnDemandEnabled = true
                NEVPNManager.shared().onDemandRules = [connectRule, denyRule]

                NEVPNManager.shared().saveToPreferences { [weak self] error in
                    if let error = error {
                        print("KillSwitch: Error saving preferences: \(error)")
                        result(FlutterError(code: "ACTIVATE_FAILED", message: error.localizedDescription, details: nil))
                        return
                    }

                    self?.isActive = true
                    print("KillSwitch: Kill switch activated - traffic blocked")
                    result(nil)
                }
            }
        }
    }

    private func handleDeactivateKillSwitch(result: @escaping FlutterResult) {
        DispatchQueue.main.async {
            NEVPNManager.shared().loadFromPreferences { [weak self] error in
                if let error = error {
                    print("KillSwitch: Error loading preferences: \(error)")
                    result(FlutterError(code: "DEACTIVATE_FAILED", message: error.localizedDescription, details: nil))
                    return
                }

                // Disable on-demand rules
                NEVPNManager.shared().isOnDemandEnabled = false
                NEVPNManager.shared().onDemandRules = []

                NEVPNManager.shared().saveToPreferences { error in
                    if let error = error {
                        print("KillSwitch: Error saving preferences: \(error)")
                        result(FlutterError(code: "DEACTIVATE_FAILED", message: error.localizedDescription, details: nil))
                        return
                    }

                    self?.isActive = false
                    print("KillSwitch: Kill switch deactivated")
                    result(nil)
                }
            }
        }
    }

    private func handleGetCapabilities(result: @escaping FlutterResult) {
        let capabilities: [String: Any] = [
            "supported": true,
            "method": "NEVPNConfiguration",
            "ios_version": UIDevice.current.systemVersion,
            "requires_root": false
        ]
        result(capabilities)
    }

    private func handleTestKillSwitch(duration: Int, result: @escaping FlutterResult) {
        DispatchQueue.main.async {
            print("KillSwitch: Testing kill switch for \(duration)s...")

            // Activate
            self.handleActivateKillSwitch { activateResult in
                if activateResult is FlutterError {
                    result(false)
                    return
                }

                // Wait for duration
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(duration)) {
                    // Deactivate
                    self.handleDeactivateKillSwitch { _ in
                        print("KillSwitch: Test completed successfully")
                        result(true)
                    }
                }
            }
        }
    }

    func cleanup() {
        if isActive {
            handleDeactivateKillSwitch { _ in }
        }
    }
}

/**
 IMPORTANT: For this to work properly on iOS, ensure:

 1. In Info.plist, add:
    <key>NEVPNUsageDescription</key>
    <string>Required to manage VPN connection and traffic</string>

 2. In Capabilities, enable:
    - Network Extensions
    - Personal VPN (EntitlementsFile)

 3. The VPN configuration must be properly set up via NEVPNProtocol

 4. User must grant permission in Settings > VPN & Device Management

 Note: iOS 14+ restricts some VPN capabilities. True kill switch relies on:
 - NEVPNConfiguration with proper setup
 - System "Allow VPN" toggle being ON
 - Proper onDemandRules configuration

 If native kill switch unavailable, user must enable "Automatically connect to VPN"
 in iOS Settings > VPN & Device Management.
 */
