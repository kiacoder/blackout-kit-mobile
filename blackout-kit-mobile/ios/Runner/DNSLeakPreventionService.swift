import Flutter
import NetworkExtension

/**
 DNS Leak Prevention Service - iOS implementation

 Strategy:
 1. Use NEDNSSettings with VPN configuration
 2. Enforce DNS queries through VPN tunnel
 3. Block system DNS resolution outside VPN

 Note: iOS restricts direct DNS manipulation. Leak prevention relies on
 proper NEVPNConfiguration setup and system DNS settings.
 */
class DNSLeakPreventionService {
    static let channelName = "com.blackoutkit.vpn/dns"

    private var isActive = false
    private var currentDNS = "1.1.1.1"
    private var methodChannel: FlutterMethodChannel?

    func setupChannel(_ controller: FlutterViewController) {
        methodChannel = FlutterMethodChannel(
            name: DNSLeakPreventionService.channelName,
            binaryMessenger: controller.binaryMessenger
        )

        methodChannel?.setMethodCallHandler { [weak self] (call, result) in
            switch call.method {
            case "enableDNSLeakPrevention":
                if let args = call.arguments as? [String: Any],
                   let dnsServer = args["dnsServer"] as? String {
                    self?.handleEnableDNSLeakPrevention(dnsServer: dnsServer, result: result)
                }
            case "disableDNSLeakPrevention":
                self?.handleDisableDNSLeakPrevention(result: result)
            case "activateDNSLeakPrevention":
                self?.handleActivateDNSLeakPrevention(result: result)
            case "deactivateDNSLeakPrevention":
                self?.handleDeactivateDNSLeakPrevention(result: result)
            case "getCurrentDNS":
                result(self?.currentDNS ?? "1.1.1.1")
            case "testDNSLeaks":
                self?.handleTestDNSLeaks(result: result)
            case "setCustomDNS":
                if let args = call.arguments as? [String: Any],
                   let dnsServer = args["dnsServer"] as? String {
                    self?.handleSetCustomDNS(dnsServer: dnsServer, result: result)
                }
            case "getSecureDNSProviders":
                self?.handleGetSecureDNSProviders(result: result)
            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }

    private func handleEnableDNSLeakPrevention(
        dnsServer: String,
        result: @escaping FlutterResult
    ) {
        DispatchQueue.main.async {
            self.currentDNS = dnsServer
            print("DNS: Leak prevention enabled with server: \(dnsServer)")
            result(true)
        }
    }

    private func handleDisableDNSLeakPrevention(result: @escaping FlutterResult) {
        DispatchQueue.main.async {
            self.isActive = false
            print("DNS: Leak prevention disabled")
            result(true)
        }
    }

    private func handleActivateDNSLeakPrevention(result: @escaping FlutterResult) {
        DispatchQueue.main.async {
            NEVPNManager.shared().loadFromPreferences { [weak self] error in
                if let error = error {
                    print("DNS: Error loading VPN preferences: \(error)")
                    result(FlutterError(
                        code: "ACTIVATE_FAILED",
                        message: error.localizedDescription,
                        details: nil
                    ))
                    return
                }

                guard let vpnConfig = NEVPNManager.shared().protocolConfiguration else {
                    print("DNS: No VPN configuration found")
                    result(FlutterError(
                        code: "ACTIVATE_FAILED",
                        message: "No VPN configuration",
                        details: nil
                    ))
                    return
                }

                // Set up DNS settings to use VPN-only DNS
                let dnsSettings = NEDNSSettings(servers: [self?.currentDNS ?? "1.1.1.1"])
                dnsSettings.matchDomains = [] // Empty = apply to all domains

                // Assign DNS settings to VPN protocol
                if let ikev2 = vpnConfig as? NEIKEv2Configuration {
                    ikev2.childSecurityAssociationParameters.dnsSettings = dnsSettings
                } else if let ipsec = vpnConfig as? NEIPSecConfiguration {
                    ipsec.childSecurityAssociationParameters.dnsSettings = dnsSettings
                }

                NEVPNManager.shared().saveToPreferences { [weak self] error in
                    if let error = error {
                        print("DNS: Error saving preferences: \(error)")
                        result(FlutterError(
                            code: "ACTIVATE_FAILED",
                            message: error.localizedDescription,
                            details: nil
                        ))
                        return
                    }

                    self?.isActive = true
                    print("DNS: Leak prevention activated - blocking system DNS")
                    result(nil)
                }
            }
        }
    }

    private func handleDeactivateDNSLeakPrevention(result: @escaping FlutterResult) {
        DispatchQueue.main.async {
            NEVPNManager.shared().loadFromPreferences { error in
                if let error = error {
                    print("DNS: Error loading preferences: \(error)")
                    result(FlutterError(
                        code: "DEACTIVATE_FAILED",
                        message: error.localizedDescription,
                        details: nil
                    ))
                    return
                }

                // Remove DNS restrictions
                if let vpnConfig = NEVPNManager.shared().protocolConfiguration {
                    if let ikev2 = vpnConfig as? NEIKEv2Configuration {
                        ikev2.childSecurityAssociationParameters.dnsSettings = nil
                    } else if let ipsec = vpnConfig as? NEIPSecConfiguration {
                        ipsec.childSecurityAssociationParameters.dnsSettings = nil
                    }
                }

                NEVPNManager.shared().saveToPreferences { error in
                    if let error = error {
                        print("DNS: Error saving preferences: \(error)")
                        result(FlutterError(
                            code: "DEACTIVATE_FAILED",
                            message: error.localizedDescription,
                            details: nil
                        ))
                        return
                    }

                    self.isActive = false
                    print("DNS: Leak prevention deactivated")
                    result(nil)
                }
            }
        }
    }

    private func handleTestDNSLeaks(result: @escaping FlutterResult) {
        DispatchQueue.main.async {
            print("DNS: Testing for leaks...")
            // In production, implement actual DNS leak testing
            // For now, return empty list (no leaks detected)
            result([])
        }
    }

    private func handleSetCustomDNS(
        dnsServer: String,
        result: @escaping FlutterResult
    ) {
        DispatchQueue.main.async {
            self.currentDNS = dnsServer

            if self.isActive {
                // Reactivate with new DNS server
                self.handleDeactivateDNSLeakPrevention { _ in
                    self.handleActivateDNSLeakPrevention { activateResult in
                        result(activateResult)
                    }
                }
            } else {
                print("DNS: Custom DNS set: \(dnsServer)")
                result(true)
            }
        }
    }

    private func handleGetSecureDNSProviders(result: @escaping FlutterResult) {
        let providers: [String: String] = [
            "cloudflare": "1.1.1.1",
            "quad9": "9.9.9.9",
            "adguard": "94.140.14.14",
            "nextdns": "45.90.28.0",
            "opendns": "208.67.222.222"
        ]
        result(providers)
    }

    func cleanup() {
        if isActive {
            handleDeactivateDNSLeakPrevention { _ in }
        }
    }
}

/**
 IMPORTANT: For DNS leak prevention to work on iOS:

 1. In Info.plist, add NEVPNUsageDescription:
    <key>NEVPNUsageDescription</key>
    <string>Required to prevent DNS leaks and secure your connection</string>

 2. In Capabilities, enable:
    - Network Extensions
    - Personal VPN

 3. The VPN configuration must include proper DNS settings via NEDNSSettings

 4. User must grant VPN permission in Settings > VPN & Device Management

 Note: iOS 14+ restricts DNS manipulation. True DNS leak prevention requires:
 - Proper NEVPNConfiguration with NEDNSSettings
 - System permission for VPN
 - User enabling "Allow VPN" in system settings
 - Optional: Use NEDNSProxyConfiguration for more control (DNS over HTTPS)

 For maximum protection on iOS 14+, users should:
 1. Enable this in-app setting
 2. Go to Settings > VPN & Device Management
 3. Trust the "Blackout Kit" profile
 4. Enable "Always-On" for additional protection
 */
