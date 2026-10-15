package com.blackoutkit.vpn

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.util.Patterns
import java.io.File
import java.net.HttpURLConnection
import java.net.InetSocketAddress
import java.net.Proxy
import java.net.URL
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Bridges `com.blackoutkit.vpn/service` to [BlackoutVpnService].
 *
 * connect() resolves only after establish() has genuinely succeeded or failed,
 * so Dart never reports "connected" while the tunnel is still coming up.
 */
class VpnPlugin : FlutterPlugin, MethodChannel.MethodCallHandler, ActivityAware {

    private var channel: MethodChannel? = null
    private var appContext: Context? = null
    private var activity: Activity? = null

    private var pendingPrepare: MethodChannel.Result? = null
    private var pendingConnect: MethodChannel.Result? = null

    /// Loopback SOCKS port of the most recent connect, used to dial the core
    /// for the exit-IP fetch. Matches VpnService.defaultSocksPort.
    private var lastSocksPort: Int = BlackoutVpnService.DEFAULT_SOCKS_PORT

    private val main = Handler(Looper.getMainLooper())

    companion object {
        private const val TAG = "VpnPlugin"
        private const val CHANNEL = "com.blackoutkit.vpn/service"
        private const val PREPARE_REQUEST = 0xB10C
        private const val CONNECT_TIMEOUT_MS = 20_000L
        private const val IP_ECHO_URL = "https://api.ipify.org"
        private const val IP_FETCH_TIMEOUT_MS = 8_000
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL).also {
            it.setMethodCallHandler(this)
        }
        BlackoutVpnService.statusListener = { status ->
            // Carry the failure reason with the status so Dart can show the
            // real error (e.g. why the engine died) instead of a generic one.
            main.post {
                channel?.invokeMethod(
                    "onStatusChanged",
                    mapOf("status" to status, "error" to BlackoutVpnService.lastError)
                )
            }
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        BlackoutVpnService.statusListener = null
        channel?.setMethodCallHandler(null)
        channel = null
        appContext = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "prepare" -> handlePrepare(result)
            "connect" -> handleConnect(call, result)
            "disconnect" -> handleDisconnect(result)
            "isRunning" -> result.success(BlackoutVpnService.isRunning)
            "getStatus" -> result.success(statusMap())
            // The exit address of the tunnel, fetched THROUGH the core's
            // loopback SOCKS inbound.
            //
            // Why the tunnel and not a direct request: this app is a
            // disallowed application of its own VPN (addDisallowedApplication),
            // so a plain HTTP fetch from the app bypasses the tunnel and would
            // report the *unprotected* address — worse than showing nothing.
            // Dialing 127.0.0.1:<socksPort> instead sends the request through
            // the core, which forwards it via the configured outbound.
            //
            // Both engine families expose that inbound with noauth: the Xray
            // config's "socks" inbound and the sing-box config's socks inbound,
            // each built on VpnService.defaultSocksPort (10808).
            //
            // Known trade-off, documented in PHASES.md: the echo hostname is
            // resolved by the system resolver (visible to the local network)
            // before the connection is dialed through SOCKS. The check is
            // user-triggered (once per connect), so it leaks one hostname on
            // demand rather than passively leaking browsing DNS.
            "getConnectedIP" -> handleGetConnectedIP(result)
            "getEngineInfo" -> result.success(engineInfoMap())
            else -> result.notImplemented()
        }
    }

    /**
     * Reports which engine is actually available on this build.
     *
     * The UI uses this so it can stop advertising protocols that have no
     * bundled engine — a config list full of protocols that can never connect
     * is worse than an honest shorter list.
     *
     * `wireguard` is listed under the Xray core rather than as unavailable:
     * the bundled `libgojni.so` contains `xray.proxy.wireguard`, so a
     * WireGuard profile is served in-process by the same core that carries
     * VLESS/VMess/Trojan/Shadowsocks. It does not need the sing-box binary,
     * and therefore does not pull in sing-box's GPL-3.0 licence.
     *
     * `warp` stays unavailable. Cloudflare WARP is WireGuard underneath, so a
     * `wgcf`-generated profile works once imported as a WireGuard `.conf`, but
     * [WarpConfig] itself has no registration flow and cannot mint the key
     * pair WARP requires.
     */
    private fun engineInfoMap(): Map<String, Any?> {
        val xrayVersion = XrayEngine.version()
        // sing-box runs as a subprocess engine, which needs its .so inside the
        // APK's nativeLibraryDir. Reporting it available without the binary
        // made the Dart pre-flight pass hysteria2/tuic/amneziawg/warp configs,
        // which then failed instantly inside EngineRunner — "engines start to
        // fail". Gate the claim on the file actually being present.
        val singboxSo = File(
            appContext?.applicationInfo?.nativeLibraryDir ?: "",
            "libsingbox.so"
        )
        val singboxAvailable = singboxSo.exists()
        return mapOf(
            "xrayAvailable" to (xrayVersion != null),
            "xrayVersion" to xrayVersion,
            "xrayProtocols" to
                listOf("vless", "vmess", "trojan", "shadowsocks", "wireguard"),
            "singboxAvailable" to singboxAvailable,
            "singboxProtocols" to
                if (singboxAvailable) listOf("hysteria2", "tuic", "amneziawg", "warp")
                else emptyList<String>(),
            "unavailableProtocols" to
                (listOf("openvpn", "psiphon") +
                    if (singboxAvailable) emptyList()
                    else listOf("hysteria2", "tuic", "amneziawg", "warp"))
        )
    }

    private fun statusMap(): Map<String, Any?> = mapOf(
        "isConnected" to BlackoutVpnService.isRunning,
        "isRunning" to BlackoutVpnService.isRunning,
        "error" to BlackoutVpnService.lastError
    )

    private fun handlePrepare(result: MethodChannel.Result) {
        val ctx = appContext
        if (ctx == null) {
            result.error("NO_CONTEXT", "Plugin is not attached to a Flutter engine", null)
            return
        }

        // Null means consent was already granted for this app.
        val consent = VpnService.prepare(ctx)
        if (consent == null) {
            result.success(true)
            return
        }

        val act = activity
        if (act == null) {
            result.error("NO_ACTIVITY", "VPN consent needs a foreground Activity", null)
            return
        }

        pendingPrepare = result
        act.startActivityForResult(consent, PREPARE_REQUEST)
    }

    private fun handleConnect(call: MethodCall, result: MethodChannel.Result) {
        val ctx = appContext
        if (ctx == null) {
            result.error("NO_CONTEXT", "Plugin is not attached to a Flutter engine", null)
            return
        }
        if (VpnService.prepare(ctx) != null) {
            result.error("NOT_PREPARED", "VPN consent has not been granted - call prepare() first", null)
            return
        }
        if (pendingConnect != null) {
            result.error("BUSY", "A connect attempt is already in flight", null)
            return
        }

        pendingConnect = result
        BlackoutVpnService.connectResultCallback = { ok -> resolveConnect(ok) }

        // Remember the port the core's SOCKS inbound listens on so
        // getConnectedIP can dial the tunnel later.
        lastSocksPort = call.argument<Int>("socksPort") ?: BlackoutVpnService.DEFAULT_SOCKS_PORT

        val intent = Intent(ctx, BlackoutVpnService::class.java).apply {
            action = BlackoutVpnService.ACTION_CONNECT
            putExtra(BlackoutVpnService.EXTRA_PROTOCOL, call.argument<String>("protocol"))
            putExtra(BlackoutVpnService.EXTRA_DISPLAY_NAME, call.argument<String>("displayName"))
            putExtra(
                BlackoutVpnService.EXTRA_SOCKS_PORT,
                call.argument<Int>("socksPort") ?: BlackoutVpnService.DEFAULT_SOCKS_PORT
            )
            putExtra(BlackoutVpnService.EXTRA_DNS, call.argument<String>("dns"))
            putStringArrayListExtra(
                BlackoutVpnService.EXTRA_DNS_SERVERS,
                ArrayList(call.argument<List<String>>("dnsServers") ?: emptyList())
            )
            putExtra(
                BlackoutVpnService.EXTRA_HOLD_ON_ENGINE_FAILURE,
                call.argument<Boolean>("holdTunnelOnEngineFailure") ?: false
            )
            // Present only for Xray-family protocols; its presence is what
            // selects the in-process core over the subprocess runner.
            putExtra(
                BlackoutVpnService.EXTRA_XRAY_CONFIG,
                call.argument<String>("xrayConfig")
            )
            putExtra(
                BlackoutVpnService.EXTRA_SINGBOX_CONFIG,
                call.argument<String>("singboxConfig")
            )
            putStringArrayListExtra(
                BlackoutVpnService.EXTRA_ALLOWED_APPS,
                ArrayList(call.argument<List<String>>("allowedApps") ?: emptyList())
            )
            putStringArrayListExtra(
                BlackoutVpnService.EXTRA_DISALLOWED_APPS,
                ArrayList(call.argument<List<String>>("disallowedApps") ?: emptyList())
            )
        }

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                ctx.startForegroundService(intent)
            } else {
                ctx.startService(intent)
            }
        } catch (e: Exception) {
            resolveConnect(false, "Could not start the VPN service: ${e.message}")
            return
        }

        main.postDelayed({
            if (pendingConnect != null) {
                // Stop the service too: establish() may still complete after
                // this and would otherwise leave a live tunnel whose Dart
                // state already reported failure — UI and reality diverged.
                ctx.startService(
                    Intent(ctx, BlackoutVpnService::class.java).apply {
                        action = BlackoutVpnService.ACTION_DISCONNECT
                    }
                )
                resolveConnect(false, "Timed out waiting for the tunnel to come up")
            }
        }, CONNECT_TIMEOUT_MS)
    }

    private fun resolveConnect(ok: Boolean, message: String? = null) {
        val result = pendingConnect ?: return
        pendingConnect = null
        BlackoutVpnService.connectResultCallback = null

        if (ok) {
            result.success(true)
        } else {
            val reason = message
                ?: BlackoutVpnService.lastError
                ?: "The tunnel failed to come up"
            Log.w(TAG, "connect failed: $reason")
            result.error("CONNECT_FAILED", reason, null)
        }
    }

    private fun handleDisconnect(result: MethodChannel.Result) {
        val ctx = appContext
        if (ctx == null) {
            result.error("NO_CONTEXT", "Plugin is not attached to a Flutter engine", null)
            return
        }
        try {
            ctx.startService(
                Intent(ctx, BlackoutVpnService::class.java).apply {
                    action = BlackoutVpnService.ACTION_DISCONNECT
                }
            )
            result.success(true)
        } catch (e: Exception) {
            result.error("DISCONNECT_FAILED", e.message, null)
        }
    }

    // ─────────────────────────── exit IP ───────────────────────────────────

    /**
     * Fetches the tunnel's exit address off the Flutter platform thread and
     * resolves with the address, or null when it cannot be determined.
     *
     * The request goes through the core's loopback SOCKS inbound (see the
     * getConnectedIP dispatch comment): a direct fetch would bypass the
     * tunnel because this app is a disallowed application of its own VPN and
     * would report the unprotected address instead.
     */
    private fun handleGetConnectedIP(result: MethodChannel.Result) {
        if (!BlackoutVpnService.isRunning) {
            // Nothing to ask — the tunnel is not up.
            result.success(null)
            return
        }
        val socksPort = lastSocksPort
        Thread {
            val ip = fetchExitIpThroughTunnel(socksPort)
            main.post {
                if (ip != null) {
                    result.success(ip)
                } else {
                    result.success(null)
                }
            }
        }.start()
    }

    private fun fetchExitIpThroughTunnel(socksPort: Int): String? {
        if (socksPort <= 0 || socksPort > 65535) {
            Log.w(TAG, "Refusing to dial an out-of-range SOCKS port: $socksPort")
            return null
        }
        var conn: HttpURLConnection? = null
        return try {
            val proxy = Proxy(Proxy.Type.SOCKS, InetSocketAddress("127.0.0.1", socksPort))
            conn = (URL(IP_ECHO_URL).openConnection(proxy) as HttpURLConnection).apply {
                connectTimeout = IP_FETCH_TIMEOUT_MS
                readTimeout = IP_FETCH_TIMEOUT_MS
                requestMethod = "GET"
                doInput = true
                instanceFollowRedirects = false
            }
            val code = conn.responseCode
            if (code !in 200..299) {
                Log.w(TAG, "Exit-IP echo returned HTTP $code")
                return null
            }
            val body = conn.inputStream.bufferedReader().use { it.readText() }.trim()
            if (looksLikeIp(body)) body else run {
                Log.w(TAG, "Exit-IP echo returned a non-address body")
                null
            }
        } catch (e: Exception) {
            // A failed probe must never surface as an error to the UI: the
            // status row simply stays hidden, which is the honest degradation.
            Log.w(TAG, "Exit-IP fetch failed: ${e.javaClass.simpleName}: ${e.message}")
            null
        } finally {
            conn?.disconnect()
        }
    }

    /** True for an IPv4 literal (or a colon-separated IPv6 literal). */
    private fun looksLikeIp(value: String): Boolean {
        if (value.isEmpty()) return false
        if (Patterns.IP_ADDRESS.matcher(value).matches()) return true
        // IPv6 from the echo service on a v6-only exit: hex groups joined by
        // colons. Deliberately narrow — no zone ids, no embedded IPv4.
        if (!value.contains(':')) return false
        val groups = value.split(':')
        if (groups.size < 3 || groups.size > 8) return false
        return groups.all { group ->
            (group.isEmpty() && value.contains("::")) ||
                (group.isNotEmpty() && group.length <= 4 && group.all { it.isDigit() || it in 'a'..'f' || it in 'A'..'F' })
        }
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        binding.addActivityResultListener { requestCode, resultCode, _ ->
            if (requestCode == PREPARE_REQUEST) {
                pendingPrepare?.success(resultCode == Activity.RESULT_OK)
                pendingPrepare = null
                true
            } else {
                false
            }
        }
    }

    override fun onDetachedFromActivity() {
        activity = null
        pendingPrepare?.success(false)
        pendingPrepare = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        onAttachedToActivity(binding)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        onDetachedFromActivity()
    }
}
