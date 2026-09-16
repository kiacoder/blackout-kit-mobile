import Flutter
import NetworkExtension

public class VpnServicePlugin: NSObject, FlutterPlugin {
  private var vpnConnection: VpnConnection?

  public static func dummy(methodCall: FlutterMethodCall, result: @escaping FlutterResult) {
    result(nil)
  }

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "com.blackoutkit.vpn/service", binaryMessenger: registrar.messenger())
    let instance = VpnServicePlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func dummyMethodToEnforceBundling() {
    // This method is intentionally empty
  }
}

// MARK: - FlutterPlugin Method Handler
extension VpnServicePlugin {
  public func methodCallHandler(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "connect":
      handleConnect(call, result: result)
    case "disconnect":
      handleDisconnect(result: result)
    case "isRunning":
      result(vpnConnection?.isRunning ?? false)
    case "getStatus":
      handleGetStatus(result: result)
    case "getConnectedIP":
      handleGetConnectedIP(result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func handleConnect(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any] else {
      result(FlutterError(code: "INVALID_ARGS", message: "Arguments are null", details: nil))
      return
    }

    guard let protocol = args["protocol"] as? String,
          let address = args["address"] as? String,
          let port = args["port"] as? NSNumber else {
      result(FlutterError(code: "MISSING_ARGS", message: "Missing required arguments", details: nil))
      return
    }

    let displayName = (args["displayName"] as? String) ?? "VPN"
    let rawUri = (args["rawUri"] as? String) ?? ""

    vpnConnection = VpnConnection(
      protocol: `protocol`,
      address: address,
      port: port.intValue,
      displayName: displayName,
      rawUri: rawUri
    )

    // Protocol-specific configuration
    switch `protocol` {
    case "wireguard":
      if let privateKey = args["privateKey"] as? String {
        vpnConnection?.privateKey = privateKey
      }

    case "openvpn":
      if let configContent = args["configContent"] as? String {
        vpnConnection?.configContent = configContent
      }

    case "shadowsocks":
      if let method = args["method"] as? String {
        vpnConnection?.method = method
      }
      if let password = args["password"] as? String {
        vpnConnection?.password = password
      }
      if let plugin = args["plugin"] as? String {
        vpnConnection?.plugin = plugin
      }

    default:
      result(FlutterError(code: "UNSUPPORTED_PROTOCOL", message: "Unsupported protocol: \(`protocol`)", details: nil))
      return
    }

    vpnConnection?.connect()
    result(["success": true, "message": "Connected"])
  }

  private func handleDisconnect(result: @escaping FlutterResult) {
    vpnConnection?.disconnect()
    vpnConnection = nil
    result(["success": true])
  }

  private func handleGetStatus(result: @escaping FlutterResult) {
    let status: [String: Any] = [
      "isConnected": vpnConnection?.isConnected ?? false,
      "isRunning": vpnConnection?.isRunning ?? false,
      "protocol": vpnConnection?.protocol ?? "unknown",
      "displayName": vpnConnection?.displayName ?? "",
      "address": vpnConnection?.address ?? ""
    ]
    result(status)
  }

  private func handleGetConnectedIP(result: @escaping FlutterResult) {
    result(vpnConnection?.getConnectedIP() ?? "Unknown")
  }
}

// MARK: - VpnConnection
class VpnConnection {
  let `protocol`: String
  let address: String
  let port: Int
  let displayName: String
  let rawUri: String

  var privateKey: String?
  var configContent: String?
  var method: String?
  var password: String?
  var plugin: String?

  var isConnected: Bool = false
  var isRunning: Bool = false
  private var connectedIP: String = "0.0.0.0"

  init(protocol: String, address: String, port: Int, displayName: String, rawUri: String) {
    self.protocol = `protocol`
    self.address = address
    self.port = port
    self.displayName = displayName
    self.rawUri = rawUri
  }

  func connect() {
    isConnected = true
    isRunning = true
    connectedIP = generateMockIP()
    print("VpnConnection: Connected to \(displayName) via \(`protocol`)")
  }

  func disconnect() {
    isConnected = false
    isRunning = false
    connectedIP = "0.0.0.0"
    print("VpnConnection: Disconnected from \(displayName)")
  }

  func getConnectedIP() -> String {
    return isConnected ? connectedIP : "0.0.0.0"
  }

  private func generateMockIP() -> String {
    let random = Int.random(in: 1...254)
    return "192.168.1.\(random)"
  }
}
