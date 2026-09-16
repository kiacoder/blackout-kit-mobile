package com.blackoutkit.vpn

import android.app.Service
import android.content.Intent
import android.net.VpnService
import android.os.Binder
import android.os.IBinder
import android.os.ParcelFileDescriptor
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.MethodCall
import android.util.Log

/// VPN Service for Blackout Kit - manages VPN connection on Android
class VpnServicePlugin : FlutterPlugin, MethodCallHandler, ActivityAware {
    private lateinit var channel: MethodChannel
    private var vpnConnection: VpnConnection? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "connect" -> handleConnect(call, result)
            "disconnect" -> handleDisconnect(result)
            "isRunning" -> result.success(vpnConnection?.isRunning ?: false)
            "getStatus" -> handleGetStatus(result)
            "getConnectedIP" -> handleGetConnectedIP(result)
            else -> result.notImplemented()
        }
    }

    private fun handleConnect(call: MethodCall, result: Result) {
        try {
            val protocol = call.argument<String>("protocol") ?: return
            val address = call.argument<String>("address") ?: return
            val port = call.argument<Int>("port") ?: return
            val displayName = call.argument<String>("displayName") ?: "VPN"
            val rawUri = call.argument<String>("rawUri") ?: ""

            vpnConnection = VpnConnection(
                protocol = protocol,
                address = address,
                port = port,
                displayName = displayName,
                rawUri = rawUri
            )

            // For WireGuard
            if (protocol == "wireguard") {
                val privateKey = call.argument<String>("privateKey") ?: ""
                vpnConnection?.privateKey = privateKey
            }

            // For OpenVPN
            if (protocol == "openvpn") {
                val configContent = call.argument<String>("configContent") ?: ""
                vpnConnection?.configContent = configContent
            }

            // For Shadowsocks
            if (protocol == "shadowsocks") {
                val method = call.argument<String>("method") ?: "aes-256-gcm"
                val password = call.argument<String>("password") ?: ""
                val plugin = call.argument<String>("plugin")
                vpnConnection?.method = method
                vpnConnection?.password = password
                vpnConnection?.plugin = plugin
            }

            vpnConnection?.connect()
            result.success(mapOf("success" to true, "message" to "Connected"))
        } catch (e: Exception) {
            Log.e(TAG, "Connection error", e)
            result.error("CONNECT_ERROR", e.message, null)
        }
    }

    private fun handleDisconnect(result: Result) {
        try {
            vpnConnection?.disconnect()
            vpnConnection = null
            result.success(mapOf("success" to true))
        } catch (e: Exception) {
            Log.e(TAG, "Disconnect error", e)
            result.error("DISCONNECT_ERROR", e.message, null)
        }
    }

    private fun handleGetStatus(result: Result) {
        val status = mapOf(
            "isConnected" to (vpnConnection?.isConnected ?: false),
            "isRunning" to (vpnConnection?.isRunning ?: false),
            "protocol" to (vpnConnection?.protocol ?: "unknown"),
            "displayName" to (vpnConnection?.displayName ?: ""),
            "address" to (vpnConnection?.address ?: "")
        )
        result.success(status)
    }

    private fun handleGetConnectedIP(result: Result) {
        try {
            val ip = vpnConnection?.getConnectedIP() ?: "Unknown"
            result.success(ip)
        } catch (e: Exception) {
            result.error("IP_ERROR", e.message, null)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {}
    override fun onDetachedFromActivity() {}
    override fun onReattachedToActivity(binding: ActivityPluginBinding) {}
    override fun onDetachedFromActivityForConfigChanges() {}
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {}

    companion object {
        private const val CHANNEL = "com.blackoutkit.vpn/service"
        private const val TAG = "VpnServicePlugin"
    }
}

/// VPN Connection - represents active VPN connection
class VpnConnection(
    val protocol: String,
    val address: String,
    val port: Int,
    val displayName: String,
    val rawUri: String
) {
    var privateKey: String? = null
    var configContent: String? = null
    var method: String? = null
    var password: String? = null
    var plugin: String? = null

    var isConnected = false
    var isRunning = false
    private var connectedIP: String = "0.0.0.0"

    fun connect() {
        // Simulate connection
        isConnected = true
        isRunning = true
        connectedIP = generateMockIP()
        Log.i("VpnConnection", "Connected to $displayName via $protocol")
    }

    fun disconnect() {
        isConnected = false
        isRunning = false
        connectedIP = "0.0.0.0"
        Log.i("VpnConnection", "Disconnected from $displayName")
    }

    fun getConnectedIP(): String {
        return if (isConnected) connectedIP else "0.0.0.0"
    }

    private fun generateMockIP(): String {
        // Mock: Return a different IP each time (would be actual IP in real implementation)
        val random = (1..254).random()
        return "192.168.1.$random"
    }
}
