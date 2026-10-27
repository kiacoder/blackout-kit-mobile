import Libbox
import NetworkExtension

/// The packet tunnel: an app extension process that owns the TUN interface
/// and the libbox core. The main app never touches packets — it arms this
/// extension with the engine JSON through `providerConfiguration` and the
/// system launches us.
///
/// Every signature below was written against the ACTUAL generated ObjC
/// header of the Libbox.xcframework we ship (v1.11.4 gomobile bindings:
/// method-style accessors, `LibboxSetupOptions`, boxed DNS string) — not
/// against any client source.
///
/// The engine JSON MUST carry a tun inbound with auto_route — the Dart
/// builder emits one in libboxMode, and the core calls openTun from it.
final class PacketTunnelProvider: NEPacketTunnelProvider {

    private var boxService: LibboxBoxService?
    private let queue = DispatchQueue(label: "com.blackoutkit.vpn.tunnel")

    /// App Group storage for engine state. Falls back to tmp when the App
    /// Groups entitlement is absent (free-account builds) — the tunnel still
    /// runs; shared-state features degrade.
    static var workingDirectory: URL {
        let base = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.blackoutkit.vpn"
        ) ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("engine", isDirectory: true)
    }

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
            cancelTunnelWithError(Self.error("No engine configuration was provided to the tunnel."))
            return
        }

        queue.async { [weak self] in
            guard let self = self else { return }
            do {
                try self.startEngine(engineJson)
                completionHandler(nil)
            } catch {
                self.boxService = nil
                completionHandler(error)
            }
        }
    }

    private func startEngine(_ engineJson: String) throws {
        let fileManager = FileManager.default
        let workingDir = Self.workingDirectory
        try fileManager.createDirectory(at: workingDir, withIntermediateDirectories: true)
        let cacheDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]

        // BOOL LibboxSetup(LibboxSetupOptions* options, NSError** error) —
        // gomobile FUNCTION bindings keep the NSErrorPointer style (unlike
        // class methods, which import as throws).
        let setupOptions = LibboxSetupOptions()
        setupOptions.basePath = workingDir.path
        setupOptions.workingPath = workingDir.path
        setupOptions.tempPath = cacheDir.path
        var setupError: NSError?
        LibboxSetup(setupOptions, &setupError)
        if let setupError = setupError {
            throw setupError
        }

        // LibboxBoxService* LibboxNewService(NSString* configContent,
        //     id<LibboxPlatformInterface> platformInterface, NSError** error)
        var serviceError: NSError?
        let service = LibboxNewService(engineJson, TunnelPlatformInterface(self), &serviceError)
        if let serviceError = serviceError {
            throw serviceError
        }
        guard let service = service else {
            throw Self.error("The engine returned no service instance.")
        }

        // - (BOOL)start:(NSError**)error
        try service.start()
        boxService = service
    }

    // MARK: - Stop

    override func stopTunnel(
        with reason: NEProviderStopReason,
        completionHandler: @escaping () -> Void
    ) {
        queue.async { [weak self] in
            if let service = self?.boxService {
                do {
                    try service.close()
                } catch {
                    NSLog("(blackout-tunnel) engine close error: \(error.localizedDescription)")
                }
            }
            self?.boxService = nil
            completionHandler()
        }
    }

    // MARK: - App message

    override func handleAppMessage(
        _ messageData: Data,
        completionHandler: ((Data?) -> Void)? = nil
    ) {
        // Minimal status probe: the app may ask "is the core alive?".
        let status = boxService != nil ? "running" : "stopped"
        completionHandler?(Data(status.utf8))
    }

    static func error(_ message: String) -> NSError {
        NSError(
            domain: "com.blackoutkit.vpn.tunnel",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: NSLocalizedString(message, comment: "PacketTunnelProvider")]
        )
    }
}

/// The Go->Swift platform bridge, conforming to the generated
/// LibboxPlatformInterfaceProtocol exactly. The core calls openTun during
/// start with the tun inbound's options; everything else is the minimal
/// honest implementation.
final class TunnelPlatformInterface: NSObject, LibboxPlatformInterfaceProtocol {

    private unowned let tunnel: PacketTunnelProvider

    init(_ tunnel: PacketTunnelProvider) {
        self.tunnel = tunnel
    }

    /// Builds the system tunnel settings from the core's tun options and
    /// hands the flow's file descriptor back to Go.
    func openTun(
        _ options: (any LibboxTunOptionsProtocol)?,
        ret0_: UnsafeMutablePointer<Int32>?
    ) throws {
        guard let options = options else {
            throw PacketTunnelProvider.error("openTun: nil options")
        }
        guard let ret0_ = ret0_ else {
            throw PacketTunnelProvider.error("openTun: nil return pointer")
        }

        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")
        if options.getAutoRoute() {
            settings.mtu = NSNumber(value: options.getMTU())

            // getDNSServerAddress returns a boxed string in these bindings.
            let dnsBox = try options.getDNSServerAddress()
            settings.dnsSettings = NEDNSSettings(servers: [dnsBox.value])

            var ipv4Address: [String] = []
            var ipv4Mask: [String] = []
            guard let ipv4Iterator = options.getInet4Address() else { throw PacketTunnelProvider.error("openTun: nil getInet4Address") }
            while ipv4Iterator.hasNext() {
                let prefix = ipv4Iterator.next()!
                ipv4Address.append(prefix.address())
                ipv4Mask.append(prefix.mask())
            }
            let ipv4Settings = NEIPv4Settings(addresses: ipv4Address, subnetMasks: ipv4Mask)
            var ipv4Routes: [NEIPv4Route] = []
            guard let ipv4RouteIterator = options.getInet4RouteAddress() else { throw PacketTunnelProvider.error("openTun: nil getInet4RouteAddress") }
            if ipv4RouteIterator.hasNext() {
                while ipv4RouteIterator.hasNext() {
                    let prefix = ipv4RouteIterator.next()!
                    ipv4Routes.append(
                        NEIPv4Route(destinationAddress: prefix.address(), subnetMask: prefix.mask())
                    )
                }
            } else {
                ipv4Routes.append(NEIPv4Route.default())
            }
            for (index, address) in ipv4Address.enumerated() {
                ipv4Routes.append(NEIPv4Route(destinationAddress: address, subnetMask: ipv4Mask[index]))
            }
            ipv4Settings.includedRoutes = ipv4Routes
            settings.ipv4Settings = ipv4Settings

            var ipv6Address: [String] = []
            var ipv6Prefixes: [NSNumber] = []
            guard let ipv6Iterator = options.getInet6Address() else { throw PacketTunnelProvider.error("openTun: nil getInet6Address") }
            while ipv6Iterator.hasNext() {
                let prefix = ipv6Iterator.next()!
                ipv6Address.append(prefix.address())
                ipv6Prefixes.append(NSNumber(value: prefix.prefix()))
            }
            let ipv6Settings = NEIPv6Settings(addresses: ipv6Address, networkPrefixLengths: ipv6Prefixes)
            var ipv6Routes: [NEIPv6Route] = []
            guard let ipv6RouteIterator = options.getInet6RouteAddress() else { throw PacketTunnelProvider.error("openTun: nil getInet6RouteAddress") }
            if ipv6RouteIterator.hasNext() {
                while ipv6RouteIterator.hasNext() {
                    let prefix = ipv6RouteIterator.next()!
                    ipv6Routes.append(
                        NEIPv6Route(
                            destinationAddress: prefix.address(),
                            networkPrefixLength: NSNumber(value: prefix.prefix())
                        )
                    )
                }
            } else {
                ipv6Routes.append(NEIPv6Route.default())
            }
            ipv6Settings.includedRoutes = ipv6Routes
            settings.ipv6Settings = ipv6Settings
        }

        try runBlocking { [self] in
            try await tunnel.setTunnelNetworkSettings(settings)
        }

        // The TUN fd: KVC into the flow's private socket, with the libbox
        // helper (reads the fd the core registered) as the fallback.
        if let tunFd = tunnel.packetFlow.value(forKeyPath: "socket.fileDescriptor") as? Int32 {
            ret0_.pointee = tunFd
            return
        }
        let tunFdFromCore = LibboxGetTunnelFileDescriptor()
        if tunFdFromCore != -1 {
            ret0_.pointee = tunFdFromCore
            return
        }
        throw PacketTunnelProvider.error("openTun: could not obtain the tunnel file descriptor")
    }

    // MARK: - Protocol stubs (minimal honest implementations)

    func autoDetectControl(_ fd: Int32) throws {}

    func clearDNSCache() {}

    func closeDefaultInterfaceMonitor(_ listener: (any LibboxInterfaceUpdateListenerProtocol)?) throws {}

    func findConnectionOwner(
        _ ipProtocol: Int32,
        sourceAddress _: String?,
        sourcePort _: Int32,
        destinationAddress _: String?,
        destinationPort _: Int32,
        ret0_ _: UnsafeMutablePointer<Int32>?
    ) throws {
        throw PacketTunnelProvider.error("not implemented")
    }

    func getInterfaces() throws -> any LibboxNetworkInterfaceIteratorProtocol {
        throw PacketTunnelProvider.error("not implemented")
    }

    func includeAllNetworks() -> Bool { false }

    func packageName(byUid _: Int32, error: NSErrorPointer) -> String { "" }

    func readWIFIState() -> LibboxWIFIState? { nil }

    func send(_ notification: LibboxNotification?) throws {}

    func startDefaultInterfaceMonitor(_ listener: (any LibboxInterfaceUpdateListenerProtocol)?) throws {}

    func uid(byPackageName packageName _: String?, ret0_ _: UnsafeMutablePointer<Int32>?) throws {
        throw PacketTunnelProvider.error("not implemented")
    }

    func underNetworkExtension() -> Bool { true }

    func usePlatformAutoDetectControl() -> Bool { true }

    func useProcFS() -> Bool { false }

    func writeLog(_ message: String?) {
        guard let message = message else { return }
        NSLog("(blackout-tunnel) \(message)")
    }
}

/// Runs an async body to completion on a side task; libbox's callbacks are
/// synchronous, and setTunnelNetworkSettings is async-only.
private final class ThrownError: @unchecked Sendable {
    var error: Error?
}

private func runBlocking(_ body: @escaping () async throws -> Void) throws {
    let box = ThrownError()
    let semaphore = DispatchSemaphore(value: 0)
    Task {
        do {
            try await body()
        } catch {
            box.error = error
        }
        semaphore.signal()
    }
    semaphore.wait()
    if let error = box.error {
        throw error
    }
}
