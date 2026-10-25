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
    private var pendingNotificationPermission: MethodChannel.Result? = null
    private var pendingConnect: MethodChannel.Result? = null

    /**
     * The timeout watchdog of the connect currently in flight. Kept so
     * [resolveConnect] can cancel it: the runnable checks `pendingConnect`,
     * and a later connect that starts within CONNECT_TIMEOUT_MS of an earlier
     * one would otherwise be judged — and killed — by the earlier attempt's
     * leftover timer.
     */
    private var connectTimeoutRunnable: Runnable? = null

    /// Loopback SOCKS port of the most recent connect, used to dial the core
    /// for the exit-IP fetch. Matches VpnService.defaultSocksPort.
    private var lastSocksPort: Int = BlackoutVpnService.DEFAULT_SOCKS_PORT

    private val main = Handler(Looper.getMainLooper())

    companion object {
        private const val TAG = "VpnPlugin"
        private const val CHANNEL = "com.blackoutkit.vpn/service"
        private const val PREPARE_REQUEST = 0xB10C
        private const val NOTIFICATION_PERMISSION_REQUEST = 9101
        // A cold start on a slow device has to fit: sing-box `check`,
        // the 3s engine startup window, the 2s SOCKS readiness probe and
        // the tun2socks launch. 20s left no headroom and reported a
        // timeout for tunnels that were about to succeed.
        private const val CONNECT_TIMEOUT_MS = 35_000L
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
        // A re-attached engine (the Flutter process was killed and the app
        // reopened) has missed every status transition. Tell it the current
        // truth immediately so its UI does not disagree with the notification.
        if (BlackoutVpnService.isRunning) {
            main.post {
                channel?.invokeMethod(
                    "onStatusChanged",
                    mapOf("status" to "connected", "error" to null)
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
            // Android 13+ silently drops the VPN status notification without a
            // runtime grant; the permission was declared but never asked for.
            "requestNotificationPermission" -> handleNotificationPermission(result)
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
            "tunnelFetch" -> handleTunnelFetch(call, result)
            "probeStart" -> handleProbeStart(call, result)
            "probeStop" -> handleProbeStop(result)
            "probeSites" -> handleProbeSites(call, result)
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
            // amneziawg is NOT here on purpose: the bundled libsingbox.so is a
            // vanilla build (no `amnezia` option anywhere in the binary), so an
            // AmneziaWG profile is rejected at config decode time. Advertising
            // it produced a cryptic "unknown field amnezia" from sing-box
            // instead of an honest "this build cannot dial it". The desktop CLI
            // serves AWG through its own native core; mobile does not.
            // Only the protocols the DART side can actually describe.
            //
            // shadowtls and warp used to be listed here because libsingbox.so
            // contains the outbound types, but Dart cannot build a config for
            // either: a shadowtls outbound is only a TLS camouflage layer and
            // needs an inner proxy as its `detour`, which a shadowtls:// link
            // does not carry, and there is no warp:// parser at all. Listing
            // them made a shadowtls config parse, validate, show as available
            // and "connect" - while startEngine received no config document
            // and simply ran whatever singbox.json was left over from the
            // previous session. That is a false tunnel state, not a failure.
            "singboxProtocols" to
                if (singboxAvailable)
                    listOf("hysteria2", "tuic", "anytls")
                else emptyList<String>(),
            "unavailableProtocols" to
                (listOf("openvpn", "psiphon", "amneziawg", "shadowtls", "warp") +
                    if (singboxAvailable) emptyList()
                    else listOf("hysteria2", "tuic", "anytls"))
        )
    }

    private fun statusMap(): Map<String, Any?> = mapOf(
        "isConnected" to BlackoutVpnService.isRunning,
        "isRunning" to BlackoutVpnService.isRunning,
        "error" to BlackoutVpnService.lastError,
        // Identity of the live tunnel: lets a reopened app adopt a tunnel that
        // outlived its Flutter process instead of showing "not connected".
        "protocol" to BlackoutVpnService.activeProtocolId,
        "name" to BlackoutVpnService.activeDisplayName,
        "connectedAtMs" to BlackoutVpnService.connectedAtMs,
        "socksPort" to lastSocksPort
    )

    private fun handleNotificationPermission(result: MethodChannel.Result) {
        val act = activity
        if (act == null) {
            // No foreground activity to prompt with: report the failure rather
            // than claiming a grant the user never gave.
            result.success(false)
            return
        }
        if (android.os.Build.VERSION.SDK_INT < android.os.Build.VERSION_CODES.TIRAMISU) {
            result.success(true) // install-time permission before 13
            return
        }
        val granted = act.checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) ==
            android.content.pm.PackageManager.PERMISSION_GRANTED
        if (granted) {
            result.success(true)
            return
        }
        pendingNotificationPermission?.success(false)
        pendingNotificationPermission = result
        act.requestPermissions(
            arrayOf(android.Manifest.permission.POST_NOTIFICATIONS),
            NOTIFICATION_PERMISSION_REQUEST,
        )
    }

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

        // A second consent request must not orphan the first: complete the
        // previous one with an error so its Dart Future settles instead of
        // hanging forever (the caller's await never returned).
        pendingPrepare?.error(
            "CONSENT_SUPERSEDED",
            "A newer VPN consent request replaced this one",
            null,
        )
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

        val timeout = Runnable {
            if (pendingConnect != null) {
                // Stop the service too: establish() may still complete after
                // this and would otherwise leave a live tunnel whose Dart
                // state already reported failure — UI and reality diverged.
                // The app can be in the BACKGROUND by now (the user gave up
                // waiting), where a plain startService throws
                // IllegalStateException — and this runnable runs on the main
                // thread, so the throw would take the app down.
                try {
                    ctx.startService(
                        Intent(ctx, BlackoutVpnService::class.java).apply {
                            action = BlackoutVpnService.ACTION_DISCONNECT
                        }
                    )
                } catch (e: Exception) {
                    Log.w(TAG, "could not stop the service after the connect timeout: ${e.message}")
                }
                resolveConnect(false, "Timed out waiting for the tunnel to come up")
            }
        }
        connectTimeoutRunnable = timeout
        main.postDelayed(timeout, CONNECT_TIMEOUT_MS)
    }

    private fun resolveConnect(ok: Boolean, message: String? = null) {
        // Cancel this attempt's watchdog FIRST: once pendingConnect is cleared
        // a later connect could already be in flight, and firing the stale
        // timer after that would tear down the new attempt.
        connectTimeoutRunnable?.let { main.removeCallbacks(it) }
        connectTimeoutRunnable = null

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
            // Acknowledge only after teardown. Returning true immediately told
            // Dart the tunnel was gone while the interface was still up, so the
            // UI showed "disconnected" while traffic was still routed.
            var settled = false
            BlackoutVpnService.onTeardownComplete = {
                if (!settled) {
                    settled = true
                    // Drop the callback once it has fired. It used to stay
                    // assigned, so the NEXT teardown invoked it again and
                    // replied to a result that was already completed -
                    // IllegalStateException on the main thread.
                    BlackoutVpnService.onTeardownComplete = null
                    result.success(true)
                }
            }
            ctx.startService(
                Intent(ctx, BlackoutVpnService::class.java).apply {
                    action = BlackoutVpnService.ACTION_DISCONNECT
                }
            )
            // Fail loudly rather than leaving the Dart Future hanging forever
            // if the service never reports back.
            android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                if (!settled) {
                    settled = true
                    // Same leak from the other side: a teardown that finishes
                    // after this timeout would call the stale callback and
                    // throw. Clear it before reporting the timeout.
                    BlackoutVpnService.onTeardownComplete = null
                    result.error("DISCONNECT_TIMEOUT", "The tunnel did not close in time", null)
                }
            }, 8000)
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
        val body = fetchBodyThroughSocks(IP_ECHO_URL, socksPort, IP_FETCH_TIMEOUT_MS)
            ?: return null
        return if (looksLikeIp(body)) body else run {
            Log.w(TAG, "Exit-IP echo returned a non-address body")
            null
        }
    }

    /**
     * GETs [urlStr] through the loopback SOCKS inbound and returns the body.
     *
     * Used for the exit-IP echo and for the geo lookup of the exit address —
     * the request must leave THROUGH the tunnel or it describes the wrong
     * location. A null return means "could not fetch"; callers degrade to
     * hiding the row rather than showing an error.
     */
    fun fetchBodyThroughSocks(urlStr: String, socksPort: Int, timeoutMs: Int): String? {
        if (socksPort <= 0 || socksPort > 65535) {
            Log.w(TAG, "Refusing to dial an out-of-range SOCKS port: $socksPort")
            return null
        }
        var conn: HttpURLConnection? = null
        return try {
            val proxy = Proxy(Proxy.Type.SOCKS, InetSocketAddress("127.0.0.1", socksPort))
            conn = (URL(urlStr).openConnection(proxy) as HttpURLConnection).apply {
                connectTimeout = timeoutMs
                readTimeout = timeoutMs
                requestMethod = "GET"
                doInput = true
                instanceFollowRedirects = true
            }
            val code = conn.responseCode
            if (code !in 200..299) {
                Log.w(TAG, "Tunnel fetch returned HTTP $code for $urlStr")
                return null
            }
            conn.inputStream.bufferedReader().use { it.readText() }
        } catch (e: Exception) {
            // A failed probe must never surface as an error to the UI: the
            // status row simply stays hidden, which is the honest degradation.
            Log.w(TAG, "Tunnel fetch failed: ${e.javaClass.simpleName}: ${e.message}")
            null
        } finally {
            conn?.disconnect()
        }
    }

    /**
     * Fetches [url] through the live tunnel's loopback SOCKS inbound and
     * returns the response body, or null on any failure. Powers the
     * "where is the exit" geo lookup on the home screen — the same request
     * made directly would report the UNPROTECTED address, because this app
     * is a disallowed application of its own VPN.
     */
    private fun handleTunnelFetch(call: MethodCall, result: MethodChannel.Result) {
        val urlStr = call.argument<String>("url") ?: ""
        val socksPort = call.argument<Int>("socksPort")
            ?: BlackoutVpnService.DEFAULT_SOCKS_PORT
        val timeoutMs = (call.argument<Int>("timeoutMs") ?: 10_000)
            .coerceIn(1_000, 30_000)
        if (urlStr.isBlank()) {
            result.error("BAD_ARGS", "url is required", null)
            return
        }
        Thread {
            val body = fetchBodyThroughSocks(urlStr, socksPort, timeoutMs)
            main.post { result.success(body) }
        }.start()
    }

    // ── Headless probe engine (site check) ────────────────────────────────
    //
    // A candidate config is judged by more than a TCP handshake: Dart builds
    // a SOCKS-only Xray config (no tun inbound), this side runs it in the
    // bundled core with tunFd = 0, and the check URLs are then fetched
    // THROUGH the core's loopback SOCKS inbound. The core never touches the
    // device's routing — no VpnService, no consent dialog, no interface.

    /** One headless core instance at a time; guarded against the live tunnel. */
    private val probeLock = Any()

    /** The headless sing-box instance started by [handleProbeStart], if any. */
    private var probeProcess: Process? = null
    private var probeLog: File? = null

    /**
     * Runs a sing-box config with no TUN, for the site check.
     *
     * The probe used to be Xray-only: `probeStart` accepted an `xrayConfig` and
     * called `XrayEngine.startProxyOnly`, so a hysteria2/tuic/anytls config had
     * nothing to send and the site check reported it "unsupported". That is
     * why scanning and pinging only ever worked for the Xray-family protocols.
     *
     * The sing-box document this app builds already has only a loopback
     * `mixed` inbound - tun2socks bridges the real tunnel to it - so running
     * it here needs no tun descriptor and no second process.
     */
    private fun startSingboxProbe(
        ctx: Context,
        configJson: String,
        socksPort: Int,
    ): String? {
        val enginePath = File(ctx.applicationInfo.nativeLibraryDir, "libsingbox.so")
        if (!enginePath.exists()) {
            return "libsingbox.so is not bundled in this build, so this protocol " +
                "cannot be probed here"
        }
        val dir = EngineRunner.configDirectory(ctx)
        val configFile = File(dir, "singbox-probe.json")
        try {
            configFile.writeText(configJson)
        } catch (e: Exception) {
            return "Could not write the probe config: ${e.message}"
        }

        // Validate first: sing-box names the offending field, which is far more
        // useful than a readiness timeout.
        try {
            val check = ProcessBuilder(
                listOf(enginePath.absolutePath, "check", "-c", configFile.absolutePath)
            ).redirectErrorStream(true).start()
            // Same shape as EngineRunner.start: the output is drained on a
            // side thread so a wedged checker cannot hang this read past the
            // process deadline below.
            val outputFuture = java.util.concurrent.CompletableFuture.supplyAsync {
                try {
                    check.inputStream.bufferedReader().use { it.readText() }
                } catch (_: Exception) {
                    ""
                }
            }
            if (!check.waitFor(20, java.util.concurrent.TimeUnit.SECONDS)) {
                check.destroyForcibly()
                return "sing-box check timed out after 20s"
            }
            val output = try {
                outputFuture.get(2, java.util.concurrent.TimeUnit.SECONDS)
            } catch (_: Exception) {
                ""
            }
            if (check.exitValue() != 0) {
                return "sing-box rejected the probe config: " + output.takeLast(300)
            }
        } catch (e: Exception) {
            return "Could not run sing-box check: ${e.message}"
        }

        val log = File(dir, "singbox-probe.log")
        probeLog = log
        val process = try {
            ProcessBuilder(
                listOf(enginePath.absolutePath, "run", "-c", configFile.absolutePath)
            ).redirectErrorStream(true)
                .redirectOutput(ProcessBuilder.Redirect.appendTo(log))
                .start()
        } catch (e: Exception) {
            return "Could not start sing-box: ${e.message}"
        }
        probeProcess = process

        // Poll until it binds, the process dies, or the deadline passes.
        val ready = LocalSocksReadiness.await("127.0.0.1", socksPort, 8000)
        if (!ready) {
            val died = !process.isAlive
            stopSingboxProbe()
            val tail = try {
                log.readText().takeLast(300)
            } catch (_: Exception) {
                ""
            }
            return if (died) {
                "sing-box exited during startup. $tail"
            } else {
                "sing-box did not open 127.0.0.1:$socksPort within 8s. $tail"
            }
        }
        return null
    }

    private fun stopSingboxProbe() {
        val process = probeProcess
        probeProcess = null
        if (process == null) return
        try {
            process.destroy()
            if (!process.waitFor(2, java.util.concurrent.TimeUnit.SECONDS)) {
                process.destroyForcibly()
            }
        } catch (_: Exception) {
            process.destroyForcibly()
        }
    }

    private fun handleProbeStart(call: MethodCall, result: MethodChannel.Result) {
        val ctx = appContext
        if (ctx == null) {
            result.error("NO_CONTEXT", "Plugin is not attached to a Flutter engine", null)
            return
        }
        if (BlackoutVpnService.isRunning) {
            result.error(
                "BUSY",
                "The VPN tunnel is up - the site check needs the core exclusively. " +
                    "Disconnect first, or skip the site check.",
                null
            )
            return
        }
        val xrayConfig = call.argument<String>("xrayConfig")
        val singboxConfig = call.argument<String>("singboxConfig")
        val socksPort = call.argument<Int>("socksPort") ?: 10809
        if (xrayConfig.isNullOrBlank() && singboxConfig.isNullOrBlank()) {
            result.error(
                "BAD_ARGS",
                "xrayConfig or singboxConfig is required",
                null
            )
            return
        }

        Thread {
            // One probe at a time. handleProbeStop already held probeLock, but
            // this did not, so two concurrent site checks could each spawn a
            // core on the same port: the second failed to bind, or worse, the
            // first one's stop tore down the second one's core.
            synchronized(probeLock) {
                if (probeProcess != null || XrayEngine.isRunning) {
                    // A previous probe was never stopped (the caller crashed or
                    // timed out); clear it rather than refusing forever.
                    stopSingboxProbe()
                    XrayEngine.stop()
                }
                if (!singboxConfig.isNullOrBlank()) {
                    val error = startSingboxProbe(ctx, singboxConfig, socksPort)
                    main.post {
                        if (error == null) {
                            result.success(true)
                        } else {
                            result.error("PROBE_START_FAILED", error, null)
                        }
                    }
                    return@synchronized
                }
                // startLoop blocks until the core is up or has thrown; off the
                // main thread, same as the service path.
                val ok = XrayEngine.startProxyOnly(ctx, xrayConfig!!)
                main.post {
                    if (ok) {
                        result.success(true)
                    } else {
                        result.error(
                            "PROBE_START_FAILED",
                            XrayEngine.lastError ?: "The Xray core failed to start",
                            null
                        )
                    }
                }
            }
        }.start()
    }

    private fun handleProbeStop(result: MethodChannel.Result) {
        synchronized(probeLock) {
            try {
                stopSingboxProbe()
                XrayEngine.stop()
                result.success(true)
            } catch (t: Throwable) {
                result.error("PROBE_STOP_FAILED", t.message, null)
            }
        }
    }

    private fun handleProbeSites(call: MethodCall, result: MethodChannel.Result) {
        val socksPort = call.argument<Int>("socksPort") ?: 0
        val urls = call.argument<List<String>>("urls") ?: emptyList()
        val timeoutMs = (call.argument<Int>("timeoutMs") ?: 10_000)
            .coerceIn(1_000, 30_000)

        if (socksPort <= 0 || socksPort > 65535) {
            result.error("BAD_ARGS", "socksPort is out of range", null)
            return
        }
        if (urls.isEmpty()) {
            result.error("BAD_ARGS", "urls must not be empty", null)
            return
        }

        Thread {
            // Fetch the hosts in parallel: sequential fetching made the site
            // check cost N x timeout (8 hosts x 10 s = 80 s per candidate),
            // which across a batched scan of hundreds of candidates turned a
            // minute of work into an hour. Parallel, the whole set costs
            // about one host's time.
            val pool = java.util.concurrent.Executors.newFixedThreadPool(
                minOf(urls.size, 8)
            )
            val outcomes = try {
                val futures = urls.map { url ->
                    pool.submit(java.util.concurrent.Callable {
                        probeSiteThroughSocks(url, socksPort, timeoutMs)
                    })
                }
                futures.map { future ->
                    try {
                        future.get(
                            timeoutMs + 2_000L,
                            java.util.concurrent.TimeUnit.MILLISECONDS
                        )
                    } catch (e: Exception) {
                        mapOf(
                            "host" to "",
                            "ok" to false,
                            "statusCode" to null,
                            "latencyMs" to null,
                            "error" to (e.message ?: e.javaClass.simpleName),
                        )
                    }
                }
            } finally {
                pool.shutdownNow()
            }
            main.post { result.success(outcomes) }
        }.start()
    }

    /**
     * Fetches one URL through the loopback SOCKS inbound.
     *
     * Any HTTP response counts as a pass — the point of the check is whether
     * traffic *flows through the config*, and even a 403 or a captive-portal
     * 302 proves the round trip completed through the remote exit. Only
     * connect failures and timeouts count as failures, because those are the
     * cases where the config demonstrably cannot carry traffic.
     */
    private fun probeSiteThroughSocks(
        host: String,
        socksPort: Int,
        timeoutMs: Int
    ): Map<String, Any?> {
        var conn: HttpURLConnection? = null
        val startedAt = System.currentTimeMillis()
        return try {
            val proxy = Proxy(Proxy.Type.SOCKS, InetSocketAddress("127.0.0.1", socksPort))
            conn = (URL("https://$host").openConnection(proxy) as HttpURLConnection).apply {
                connectTimeout = timeoutMs
                readTimeout = timeoutMs
                requestMethod = "GET"
                doInput = true
                instanceFollowRedirects = false
            }
            val code = conn.responseCode
            // Drain a little so the connection is fully established and the
            // timing reflects a real round trip, then release it.
            try {
                conn.inputStream.use { it.read() }
            } catch (_: Throwable) {
                // Error-stream bodies (403 pages and the like) are fine too.
                try {
                    conn.errorStream?.use { it.read() }
                } catch (_: Throwable) {
                }
            }
            mapOf(
                "host" to host,
                "ok" to true,
                "statusCode" to code,
                "latencyMs" to (System.currentTimeMillis() - startedAt),
                "error" to null,
            )
        } catch (e: Exception) {
            Log.w(TAG, "Site check failed for $host: ${e.javaClass.simpleName}: ${e.message}")
            mapOf(
                "host" to host,
                "ok" to false,
                "statusCode" to null,
                "latencyMs" to null,
                "error" to (e.message ?: e.javaClass.simpleName),
            )
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

    /**
     * The listeners registered on the current activity binding. Every re-attach
     * (including the config-change re-attach, which goes through
     * [onReattachedToActivityForConfigChanges]) used to add a NEW anonymous
     * listener without ever removing the previous one, so they stacked for the
     * lifetime of the process.
     */
    private var activityBinding: ActivityPluginBinding? = null
    private var prepareResultListener: io.flutter.plugin.common.PluginRegistry.ActivityResultListener? = null
    private var permissionResultListener: io.flutter.plugin.common.PluginRegistry.RequestPermissionsResultListener? = null

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        // Idempotent re-attach: drop the previous registration before adding a
        // fresh one, so a binding that is handed to us twice never ends up with
        // two copies of the same listener.
        activityBinding?.let { previous ->
            prepareResultListener?.let { previous.removeActivityResultListener(it) }
            permissionResultListener?.let { previous.removeRequestPermissionsResultListener(it) }
        }

        val resultListener = io.flutter.plugin.common.PluginRegistry.ActivityResultListener { requestCode, resultCode, _ ->
            if (requestCode == PREPARE_REQUEST) {
                pendingPrepare?.success(resultCode == Activity.RESULT_OK)
                pendingPrepare = null
                true
            } else {
                false
            }
        }
        prepareResultListener = resultListener
        binding.addActivityResultListener(resultListener)

        // Runtime permission results arrive here, not through
        // onActivityResult - ActivityAware has no such override.
        val permListener = io.flutter.plugin.common.PluginRegistry.RequestPermissionsResultListener { requestCode, _, grantResults ->
            if (requestCode == NOTIFICATION_PERMISSION_REQUEST) {
                val granted = grantResults.isNotEmpty() &&
                    grantResults[0] == android.content.pm.PackageManager.PERMISSION_GRANTED
                pendingNotificationPermission?.success(granted)
                pendingNotificationPermission = null
                true
            } else {
                false
            }
        }
        permissionResultListener = permListener
        binding.addRequestPermissionsResultListener(permListener)

        activityBinding = binding
    }

    override fun onDetachedFromActivity() {
        // Remove what we added; leaving them attached made the listener set
        // grow by one on every activity re-creation (rotation, theme change).
        activityBinding?.let { binding ->
            prepareResultListener?.let { binding.removeActivityResultListener(it) }
            permissionResultListener?.let { binding.removeRequestPermissionsResultListener(it) }
        }
        activityBinding = null
        prepareResultListener = null
        permissionResultListener = null
        activity = null
        pendingPrepare?.success(false)
        pendingPrepare = null
        // Never leave a permission request hanging: the caller cannot prompt
        // again without an activity, so report the failure.
        pendingNotificationPermission?.success(false)
        pendingNotificationPermission = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        onAttachedToActivity(binding)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        onDetachedFromActivity()
    }
}
