import NetworkExtension
import Libbox

/// The packet tunnel: an app extension process that owns the TUN interface
/// and the libbox core. The main app never touches packets — it arms this
/// extension with the engine JSON through `providerConfiguration` and the
/// system launches us.
///
/// Lifecycle per connection attempt:
///   startTunnel(options:)  -> read the engine JSON, create the libbox box,
///                             set the TUN fd, start it, flush routes
///   stopTunnel             -> close the box
///   cancelTunnelWithError  -> report a readable failure to Settings.app
///
/// All work happens off the main queue; PacketTunnelProvider callbacks are
/// already asynchronous from the system's point of view.
final class PacketTunnelProvider: NEPacketTunnelProvider {

    private var box: Libbox.Box?
    private let queue = DispatchQueue(label: "com.blackoutkit.vpn.tunnel")

    // MARK: - Start

    override func startTunnel(
        options _: [String: NSObject]? = nil,
        completionHandler: @escaping (Error?) -> Void
    ) {
        guard let config = protocolConfiguration as? NETunnelProviderProtocol,
              let providerConfig = config.providerConfiguration,
              let engineJson = providerConfig["engineJson"] as? String,
              !engineJson.isEmpty
        else {
            cancelTunnelWithError(
                NSError(
                    domain: "com.blackoutkit.vpn",
                    code: 1,
                    userInfo: [
                        NSLocalizedDescriptionKey: NSLocalizedString(
                            "No engine configuration was provided to the tunnel.",
                            comment: "PacketTunnelProvider"
                        )
                    ]
                )
            )
            return
        }

        queue.async { [weak self] in
            self?.startEngine(engineJson, completionHandler: completionHandler)
        }
    }

    private func startEngine(
        _ engineJson: String,
        completionHandler: @escaping (Error?) -> Void
    ) {
        do {
            let configContent = Libbox.NewConfigContent()
            try configContent.Unmarshal([]byte(engineJson))
            // Bypass the system DNS during bootstrap; the core's DNS section
            // (built Dart-side) owns resolution once the box is up.
            try Libbox.Setup(
                configContent,
                Libbox.Options(
                    WorkingDir: nil,
                    Debug: false,
                    DisableMonitor: false
                )
            )
            let box = try Libbox.New(configContent)
            self.box = box

            // Route everything into the TUN. The address pool must not
            // collide with the loopback the core listens on, and IPv4+IPv6
            // defaults mirror the Android builder.
            let network = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "10.111.222.1")
            network.mtu = 9000
            network.ipv4 = NEIPv4Settings(addresses: ["10.111.222.1"], subnetMasks: ["255.255.255.0"])
            network.ipv4?.includedRoutes = [NEIPv4Route(defaultRouteDestination())]
            network.ipv6 = NEIPv6Settings(addresses: ["fd6b:b40a:9e6a::1"], networkPrefixLengths: [64])
            network.ipv6?.includedRoutes = [NEIPv6Route(defaultRouteDestination())]
            // DNS hand-off: point the device resolver at the tunnel; the
            // core answers over its own listeners per the engine JSON.
            network.dnsSettings = NEDNSSettings(servers: ["10.111.222.1"])

            setTunnelNetworkSettings(network) { [weak self] error in
                guard let self = self else { return }
                if let error = error {
                    self.cancelTunnelWithError(error)
                    return
                }
                do {
                    try box.Start()
                    // File descriptors only after the settings are accepted.
                    let tun = box.Tun()  // libbox owns the fd lifecycle here
                    _ = tun
                    self.flushPacketFlow()
                    completionHandler(nil)
                } catch {
                    self.cancelTunnelWithError(error)
                }
            }
        } catch {
            // sing-box names the offending field — pass it through verbatim,
            // same honesty rule as the Android surface.
            cancelTunnelWithError(error)
        }
    }

    private func flushPacketFlow() {
        // libbox reads/writes the packet flow itself once started (it takes
        // the NEPacketTunnelFlow through its own iOS integration); nothing
        // further to pump here.
    }

    private func defaultRouteDestination() -> NEIPv4Route {
        NEIPv4Route(destinationAddress: "0.0.0.0", subnetMask: "0.0.0.0")
    }

    private func defaultRouteDestinationV6() -> NEIPv6Route {
        NEIPv6Route(destinationAddress: "::", networkPrefixLength: 0)
    }

    // MARK: - Stop

    override func stopTunnel(
        with reason: NEProviderStopReason,
        completionHandler: @escaping () -> Void
    ) {
        queue.async { [weak self] in
            guard let self = self else { return }
            if let box = self.box {
                box.Close()
            }
            self.box = nil
            completionHandler()
        }
    }

    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)? = nil) {
        // A tiny status query the app could use later; keep it deterministic.
        let status = box != nil ? "running" : "stopped"
        completionHandler?(Data(status.utf8))
    }
}

extension String {
    /// Swift->Go bridge helper: `[]byte(engineJson)` in Go. libbox's Swift
    /// overlay accepts [Uint8] arrays for Go byte slices.
    var goBytes: [UInt8] { Array(utf8) }
}
