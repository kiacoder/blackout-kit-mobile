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
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import java.io.File
import java.net.HttpURLConnection
import java.net.InetSocketAddress
import java.net.Proxy
import java.net.URL

/**
 * Bridges `com.blackoutkit.vpn/service` to [BlackoutVpnService].
 *
 * connect() resolves only after establish() has genuinely succeeded or failed,
 * so Dart never reports "connected" while the tunnel is still coming up.
 */
class VpnPlugin :
    FlutterPlugin,
    MethodChannel.MethodCallHandler,
    ActivityAware {
    private var channel: MethodChannel? = null
    private var appContext: Context? = null
    private var activity: Activity? = null

    private val validationBusy =
        java.util.concurrent.atomic
            .AtomicBoolean(false)

    private var pendingPrepare: MethodChannel.Result? = null
    private var pendingNotificationPermission: MethodChannel.Result? = null
    private var pendingConnect: MethodChannel.Result? = null
    private var disconnectInFlight = false

    /**
     * The timeout watchdog of the connect currently in flight. Kept so
     * [resolveConnect] can cancel it: the runnable checks `pendingConnect`,
     * and a later connect that starts within CONNECT_TIMEOUT_MS of an earlier
     * one would otherwise be judged — and killed — by the earlier attempt's
     * leftover timer.
     */
    private var connectTimeoutRunnable: Runnable? = null

    // / Loopback SOCKS port of the most recent connect, used to dial the core
    // / for the exit-IP fetch. Matches VpnService.defaultSocksPort.
    private var lastSocksPort: Int = BlackoutVpnService.DEFAULT_SOCKS_PORT

    private val main = Handler(Looper.getMainLooper())

    companion object {
        private const val MAX_VALIDATION_CONFIG_BYTES = 1024 * 1024
        private const val DISCONNECT_TIMEOUT_MS = 8000L
        private const val MAX_PORT = 65535
        private const val HTTP_SUCCESS_MIN = 200
        private const val HTTP_SUCCESS_MAX = 299
        private const val DEFAULT_SITE_TIMEOUT_MS = 10_000
        private const val MIN_SITE_TIMEOUT_MS = 1_000
        private const val MAX_SITE_TIMEOUT_MS = 30_000
        private const val DEFAULT_PROBE_PORT = 10809
        private const val MIN_IPV6_TEXT_GROUPS = 3
        private const val MAX_IPV6_GROUPS = 8
        private const val MAX_IPV6_GROUP_LENGTH = 4

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
        channel =
            MethodChannel(binding.binaryMessenger, CHANNEL).also {
                it.setMethodCallHandler(this)
            }
        BlackoutVpnService.statusListener = { status ->
            // Carry the failure reason with the status so Dart can show the
            // real error (e.g. why the engine died) instead of a generic one.
            main.post {
                channel?.invokeMethod(
                    "onStatusChanged",
                    mapOf("status" to status, "error" to BlackoutVpnService.lastError),
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
                    mapOf("status" to "connected", "error" to null),
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

    override fun onMethodCall(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        when (call.method) {
            "prepare" -> handlePrepare(result)
            // Android 13+ silently drops the VPN status notification without a
            // runtime grant; the permission was declared but never asked for.
            "requestNotificationPermission" -> handleNotificationPermission(result)
            "connect" -> handleConnect(call, result)
            // DNS-only session: same consent, no core, no routes. Separate
            // entry point because it needs no config document at all.
            "connectDnsOnly" -> handleConnect(call, result, dnsOnly = true)
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
            "validateEngineConfig" -> handleValidateEngineConfig(call, result)
            "tunnelFetch" -> handleTunnelFetch(call, result)
            "probeStart" -> handleProbeStart(call, result)
            "probeStop" -> handleProbeStop(result)
            "probeSites" -> handleProbeSites(call, result)
            else -> result.notImplemented()
        }
    }

    private fun handleValidateEngineConfig(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        val context =
            appContext ?: run {
                result.error("NO_CONTEXT", "Plugin is detached", null)
                return
            }
        val spec =
            when (call.argument<String>("engine")) {
                "sing-box" -> EngineCommands.SING_BOX
                "mihomo" -> EngineCommands.MIHOMO
                else -> null
            }
        val text = call.argument<String>("config")
        if (spec == null ||
            text.isNullOrBlank() ||
            text.toByteArray(Charsets.UTF_8).size > MAX_VALIDATION_CONFIG_BYTES
        ) {
            result.error("BAD_ARGS", "Choose a supported checker and a configuration under 1 MiB", null)
            return
        }
        validateConfigAsync(context, spec, text, result)
    }

    private fun validateConfigAsync(
        context: Context,
        spec: EngineCommands,
        text: String,
        result: MethodChannel.Result,
    ) {
        if (!validationBusy.compareAndSet(false, true)) {
            result.error("BUSY", "A configuration check is already running", null)
            return
        }
        Thread({
            var file: File? = null
            val outcome =
                try {
                    file = File.createTempFile("native-check-", ".json", context.cacheDir)
                    file!!.writeText(text)
                    NativeConfigValidator().validate(
                        spec,
                        File(context.applicationInfo.nativeLibraryDir, spec.binary),
                        file!!,
                    )
                } catch (_: Exception) {
                    NativeValidation(
                        false,
                        "CHECK_FAILED",
                        "Native validation could not complete; raw diagnostics are withheld.",
                    )
                } finally {
                    file?.delete()
                    validationBusy.set(false)
                }
            main.post {
                result.success(
                    mapOf(
                        "valid" to outcome.valid,
                        "code" to outcome.code,
                        "message" to outcome.message,
                        "connectionTested" to false,
                    ),
                )
            }
        }, "blackout-config-check").start()
    }

    private fun engineInfoMap(): Map<String, Any?> =
        EngineCatalogue(
            appContext?.applicationInfo?.nativeLibraryDir?.let(::File),
            GoRuntimeAdmission.process.current(),
            BuildConfig.ENABLE_EXPERIMENTAL_NATIVE_TUNNELS,
            BuildConfig.ENABLE_EXPERIMENTAL_MIHOMO,
        ).report()

    private fun statusMap(): Map<String, Any?> =
        mapOf(
            "isConnected" to BlackoutVpnService.isRunning,
            "isRunning" to BlackoutVpnService.isRunning,
            "activeNativeTunnel" to BlackoutVpnService.activeNativeTunnel,
            "error" to BlackoutVpnService.lastError,
            // Identity of the live tunnel: lets a reopened app adopt a tunnel that
            // outlived its Flutter process instead of showing "not connected".
            "protocol" to BlackoutVpnService.activeProtocolId,
            "name" to BlackoutVpnService.activeDisplayName,
            "connectedAtMs" to BlackoutVpnService.connectedAtMs,
            "socksPort" to lastSocksPort,
        )

    private fun handleNotificationPermission(result: MethodChannel.Result) {
        val act = activity
        if (act == null) {
            // No foreground activity to prompt with: report the failure rather
            // than claiming a grant the user never gave.
            result.success(false)
            return
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            result.success(true)
        } else {
            requestNotificationPermission(act, result)
        }
    }

    @androidx.annotation.RequiresApi(Build.VERSION_CODES.TIRAMISU)
    private fun requestNotificationPermission(
        act: Activity,
        result: MethodChannel.Result,
    ) {
        val granted =
            act.checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) ==
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

        requestConsent(consent, result)
    }

    private fun requestConsent(
        consent: Intent,
        result: MethodChannel.Result,
    ) {
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

    private fun handleConnect(
        call: MethodCall,
        result: MethodChannel.Result,
        dnsOnly: Boolean = false,
    ) {
        val ctx = appContext
        if (ctx == null) {
            result.error("NO_CONTEXT", "Plugin is not attached to a Flutter engine", null)
            return
        }
        when {
            VpnService.prepare(ctx) != null ->
                result.error("NOT_PREPARED", "VPN consent has not been granted - call prepare() first", null)
            pendingConnect != null || disconnectInFlight ->
                result.error("BUSY", "A VPN lifecycle operation is already in flight", null)
            else -> beginConnect(ctx, call, result, dnsOnly)
        }
    }

    private fun beginConnect(
        ctx: Context,
        call: MethodCall,
        result: MethodChannel.Result,
        dnsOnly: Boolean,
    ) {
        pendingConnect = result
        BlackoutVpnService.connectResultCallback = { ok -> resolveConnect(ok) }

        // Remember the port the core's SOCKS inbound listens on so
        // getConnectedIP can dial the tunnel later.
        lastSocksPort = call.argument<Int>("socksPort") ?: BlackoutVpnService.DEFAULT_SOCKS_PORT

        val intent = connectIntent(ctx, call, dnsOnly)
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
        scheduleConnectTimeout(ctx)
    }

    private fun connectIntent(
        ctx: Context,
        call: MethodCall,
        dnsOnly: Boolean,
    ): Intent =
        Intent(ctx, BlackoutVpnService::class.java).apply {
            action = BlackoutVpnService.ACTION_CONNECT
            putExtra(BlackoutVpnService.EXTRA_PROTOCOL, call.argument<String>("protocol"))
            putExtra(BlackoutVpnService.EXTRA_DISPLAY_NAME, call.argument<String>("displayName"))
            putExtra(
                BlackoutVpnService.EXTRA_SOCKS_PORT,
                call.argument<Int>("socksPort") ?: BlackoutVpnService.DEFAULT_SOCKS_PORT,
            )
            putExtra(BlackoutVpnService.EXTRA_DNS, call.argument<String>("dns"))
            putStringArrayListExtra(
                BlackoutVpnService.EXTRA_DNS_SERVERS,
                ArrayList(call.argument<List<String>>("dnsServers") ?: emptyList()),
            )
            putExtra(
                BlackoutVpnService.EXTRA_HOLD_ON_ENGINE_FAILURE,
                call.argument<Boolean>("holdTunnelOnEngineFailure") ?: false,
            )
            // Present only for Xray-family protocols; its presence is what
            // selects the in-process core over the subprocess runner.
            putExtra(
                BlackoutVpnService.EXTRA_XRAY_CONFIG,
                call.argument<String>("xrayConfig"),
            )
            putExtra(
                BlackoutVpnService.EXTRA_SINGBOX_CONFIG,
                call.argument<String>("singboxConfig"),
            )
            putExtra(
                BlackoutVpnService.EXTRA_LIBBOX_CONFIG,
                call.argument<String>("libboxConfig"),
            )
            putStringArrayListExtra(
                BlackoutVpnService.EXTRA_ALLOWED_APPS,
                ArrayList(call.argument<List<String>>("allowedApps") ?: emptyList()),
            )
            putStringArrayListExtra(
                BlackoutVpnService.EXTRA_DISALLOWED_APPS,
                ArrayList(call.argument<List<String>>("disallowedApps") ?: emptyList()),
            )
            putExtra(BlackoutVpnService.EXTRA_NATIVE_TUNNEL_CONFIG, call.argument<String>("nativeTunnelConfig"))
            putExtra(BlackoutVpnService.EXTRA_MIHOMO_CONFIG, call.argument<String>("mihomoConfig"))
            putExtra(BlackoutVpnService.EXTRA_DNS_ONLY, dnsOnly)
        }

    private fun scheduleConnectTimeout(ctx: Context) {
        val timeout =
            Runnable {
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
                            },
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

    private fun resolveConnect(
        ok: Boolean,
        message: String? = null,
    ) {
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
            val reason =
                message
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
        if (disconnectInFlight) {
            result.error("BUSY", "A disconnect is already in flight", null)
            return
        }
        disconnectInFlight = true
        var settled = false
        var timeout: Runnable? = null
        lateinit var callback: (Boolean) -> Unit

        fun settle(
            cleaned: Boolean,
            code: String? = null,
            message: String? = null,
        ) {
            if (settled) return
            settled = true
            disconnectInFlight = false
            timeout?.let { main.removeCallbacks(it) }
            // Never clear a callback belonging to a different plugin/request.
            if (BlackoutVpnService.onTeardownComplete === callback) {
                BlackoutVpnService.onTeardownComplete = null
            }
            if (cleaned) {
                result.success(true)
            } else {
                result.error(
                    code ?: "DISCONNECT_FAILED",
                    message ?: "Native cleanup did not complete cleanly",
                    null,
                )
            }
        }
        callback = { cleaned -> settle(cleaned) }
        timeout =
            Runnable {
                settle(false, "DISCONNECT_TIMEOUT", "The tunnel did not close in time")
            }
        try {
            if (pendingConnect != null) resolveConnect(false, "Connection cancelled by disconnect")
            BlackoutVpnService.onTeardownComplete = callback
            ctx.startService(
                Intent(ctx, BlackoutVpnService::class.java).apply {
                    action = BlackoutVpnService.ACTION_DISCONNECT
                },
            )
            main.postDelayed(timeout, DISCONNECT_TIMEOUT_MS)
        } catch (_: Exception) {
            settle(false, "DISCONNECT_FAILED", "Could not request VPN shutdown")
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
        if (BlackoutVpnService.activeNativeTunnel) {
            // This IP tunnel has no SOCKS listener. Our excluded UID cannot
            // measure its exit IP with a direct request without bypassing it.
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
        val body =
            fetchBodyThroughSocks(IP_ECHO_URL, socksPort, IP_FETCH_TIMEOUT_MS)
                ?: return null
        return if (looksLikeIp(body)) {
            body
        } else {
            run {
                Log.w(TAG, "Exit-IP echo returned a non-address body")
                null
            }
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
    fun fetchBodyThroughSocks(
        urlStr: String,
        socksPort: Int,
        timeoutMs: Int,
    ): String? {
        if (socksPort <= 0 || socksPort > MAX_PORT) {
            Log.w(TAG, "Refusing to dial an out-of-range SOCKS port: $socksPort")
            return null
        }
        var conn: HttpURLConnection? = null
        return try {
            val proxy = Proxy(Proxy.Type.SOCKS, InetSocketAddress("127.0.0.1", socksPort))
            conn =
                (URL(urlStr).openConnection(proxy) as HttpURLConnection).apply {
                    connectTimeout = timeoutMs
                    readTimeout = timeoutMs
                    requestMethod = "GET"
                    doInput = true
                    instanceFollowRedirects = true
                }
            val code = conn.responseCode
            if (code !in HTTP_SUCCESS_MIN..HTTP_SUCCESS_MAX) {
                Log.w(TAG, "Tunnel fetch returned HTTP $code")
                null
            } else {
                conn.inputStream.bufferedReader().use { it.readText() }
            }
        } catch (e: Exception) {
            // A failed probe must never surface as an error to the UI: the
            // status row simply stays hidden, which is the honest degradation.
            Log.w(TAG, "Tunnel fetch failed: ${e.javaClass.simpleName}")
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
    private fun handleTunnelFetch(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        val urlStr = call.argument<String>("url") ?: ""
        val socksPort =
            call.argument<Int>("socksPort")
                ?: BlackoutVpnService.DEFAULT_SOCKS_PORT
        val timeoutMs =
            (call.argument<Int>("timeoutMs") ?: DEFAULT_SITE_TIMEOUT_MS)
                .coerceIn(MIN_SITE_TIMEOUT_MS, MAX_SITE_TIMEOUT_MS)
        if (urlStr.isBlank()) {
            result.error("BAD_ARGS", "url is required", null)
            return
        }
        if (BlackoutVpnService.activeNativeTunnel) {
            result.success(null)
            return
        }
        Thread {
            val body = fetchBodyThroughSocks(urlStr, socksPort, timeoutMs)
            main.post { result.success(body) }
        }.start()
    }

    private fun handleProbeStart(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        val ctx = appContext
        val xrayConfig = call.argument<String>("xrayConfig")
        val singboxConfig = call.argument<String>("singboxConfig")
        val socksPort = call.argument<Int>("socksPort") ?: DEFAULT_PROBE_PORT
        when {
            ctx == null -> result.error("NO_CONTEXT", "Plugin is detached", null)
            BlackoutVpnService.isRunning ->
                result.error(
                    "BUSY",
                    "Disconnect the VPN before starting a headless probe.",
                    null,
                )
            socksPort !in 1..MAX_PORT -> result.error("BAD_ARGS", "socksPort is out of range", null)
            xrayConfig.isNullOrBlank() && singboxConfig.isNullOrBlank() ->
                result.error("BAD_ARGS", "xrayConfig or singboxConfig is required", null)
            else -> {
                val request = ProbeEngineRequest(ctx, xrayConfig, singboxConfig, socksPort)
                Thread {
                    val failure = ProbeEngineController.start(request)
                    main.post { completeProbe(result, failure) }
                }.start()
            }
        }
    }

    private fun handleProbeStop(result: MethodChannel.Result) {
        Thread {
            val failure = ProbeEngineController.stop()
            main.post { completeProbe(result, failure) }
        }.start()
    }

    private fun completeProbe(
        result: MethodChannel.Result,
        failure: ProbeEngineFailure?,
    ) {
        if (failure == null) {
            result.success(true)
        } else {
            result.error(failure.code, failure.message, null)
        }
    }

    private fun handleProbeSites(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        val socksPort = call.argument<Int>("socksPort") ?: 0
        val urls = call.argument<List<String>>("urls") ?: emptyList()
        val timeoutMs =
            (call.argument<Int>("timeoutMs") ?: DEFAULT_SITE_TIMEOUT_MS)
                .coerceIn(MIN_SITE_TIMEOUT_MS, MAX_SITE_TIMEOUT_MS)
        if (socksPort !in 1..MAX_PORT || urls.isEmpty()) {
            val reason =
                if (urls.isEmpty() &&
                    socksPort in 1..MAX_PORT
                ) {
                    "urls must not be empty"
                } else {
                    "socksPort is out of range"
                }
            result.error("BAD_ARGS", reason, null)
            return
        }
        val native = BlackoutVpnService.isRunning && BlackoutVpnService.activeNativeTunnel
        val session = BlackoutVpnService.connectedAtMs
        val worker = SiteProbeRunner(appContext)
        if (BlackoutVpnService.isRunning && BlackoutVpnService.activeProtocolId == "dns") {
            result.success(urls.map { worker.failedSite(it, "DNS-only is not a VPN traffic test") })
            return
        }
        Thread {
            val request = SiteProbeRequest(urls, socksPort, timeoutMs, native, session)
            val outcomes = worker.run(request)
            main.post { result.success(worker.currentOutcomes(request, outcomes)) }
        }.start()
    }

    /** True for an IPv4 literal (or a colon-separated IPv6 literal). */
    private fun looksLikeIp(value: String): Boolean =
        value.isNotEmpty() &&
            (Patterns.IP_ADDRESS.matcher(value).matches() || looksLikeIpv6(value))

    // Preserve the existing narrow IPv6 fallback (no zone ids or embedded IPv4).
    private fun looksLikeIpv6(value: String): Boolean {
        val groups = value.split(':')
        return groups.size in MIN_IPV6_TEXT_GROUPS..MAX_IPV6_GROUPS &&
            groups.all { group ->
                (group.isEmpty() && value.contains("::")) ||
                    (
                        group.isNotEmpty() &&
                            group.length <= MAX_IPV6_GROUP_LENGTH &&
                            group.all { it.isDigit() || it in 'a'..'f' || it in 'A'..'F' }
                    )
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
    private var prepareResultListener: PluginRegistry.ActivityResultListener? = null
    private var permissionResultListener: PluginRegistry.RequestPermissionsResultListener? = null

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        // Idempotent re-attach: drop the previous registration before adding a
        // fresh one, so a binding that is handed to us twice never ends up with
        // two copies of the same listener.
        activityBinding?.let { previous ->
            prepareResultListener?.let { previous.removeActivityResultListener(it) }
            permissionResultListener?.let { previous.removeRequestPermissionsResultListener(it) }
        }

        val resultListener =
            PluginRegistry.ActivityResultListener { requestCode, resultCode, _ ->
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
        val permListener =
            PluginRegistry.RequestPermissionsResultListener { requestCode, _, grantResults ->
                if (requestCode == NOTIFICATION_PERMISSION_REQUEST) {
                    val granted =
                        grantResults.isNotEmpty() &&
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
