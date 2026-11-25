package com.blackoutkit.vpn

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.util.Log

/**
 * The real Android VPN tunnel for Blackout Kit.
 *
 * This class owns the TUN interface. It does not speak any proxy protocol
 * itself: it hands the file descriptor to whichever engine can use it.
 *
 *   Xray family (vless / vmess / trojan / shadowsocks)
 *       -> [XrayEngine], which binds the fd through Xray's native `tun` inbound
 *   everything else (hysteria2 / tuic / wireguard / ...)
 *       -> [EngineRunner], which bridges the fd to a loopback SOCKS port
 *
 * Lifecycle:
 *   connect    -> startForeground -> establish() -> engine start
 *   disconnect -> engine stop -> teardown() -> stopSelf()
 *   revoked    -> onRevoke() -> teardown() -> notify Dart
 *
 * The whole establish sequence runs on a worker thread. `startLoop` on the
 * native core can take a moment, and doing it on the main thread risks an ANR
 * on slower devices.
 */
class BlackoutVpnService : VpnService() {
    companion object {
        private const val TAG = "BlackoutVpnService"
        private const val NATIVE_MONITOR_INTERVAL_MS = 2000L

        private const val PREFS = "blackout_vpn_state"
        private const val KEY_HELD_BLOCKING = "held_blocking"

        // / Invoked once the tunnel has actually been torn down. Used by the
        // / plugin to acknowledge a disconnect only after the interface is gone.
        @Volatile
        var onTeardownComplete: ((Boolean) -> Unit)? = null

        const val ACTION_CONNECT = "com.blackoutkit.vpn.CONNECT"
        const val ACTION_DISCONNECT = "com.blackoutkit.vpn.DISCONNECT"

        const val EXTRA_PROTOCOL = "protocol"
        const val EXTRA_DISPLAY_NAME = "displayName"
        const val EXTRA_SOCKS_PORT = "socksPort"
        const val EXTRA_DNS = "dns"
        const val EXTRA_DNS_SERVERS = "dnsServers"

        /**
         * DNS-only session: advertise the resolvers, route nothing.
         *
         * No core is started and no route is added, so ordinary traffic keeps
         * using the physical network; only name lookups move to the chosen
         * resolver. That is the "change only my DNS" case, which previously
         * required a full tunnel.
         */
        const val EXTRA_DNS_ONLY = "dnsOnly"
        const val EXTRA_ALLOWED_APPS = "allowedApps"
        const val EXTRA_DISALLOWED_APPS = "disallowedApps"

        /** Hold the interface open if the engine dies, instead of falling back. */
        const val EXTRA_HOLD_ON_ENGINE_FAILURE = "holdTunnelOnEngineFailure"

        /** Full Xray JSON document, built by the Dart side. */
        const val EXTRA_XRAY_CONFIG = "xrayConfig"

        /** Full sing-box JSON document, built by the Dart side. */
        const val EXTRA_SINGBOX_CONFIG = "singboxConfig"
        const val EXTRA_NATIVE_TUNNEL_CONFIG = "nativeTunnelConfig"
        const val EXTRA_MIHOMO_CONFIG = "mihomoConfig"

        /**
         * Full sing-box JSON document built in libbox mode (tun inbound) by
         * the Dart side, for the in-process libbox core. Absent on platforms
         * without an embedded libbox core.
         */
        const val EXTRA_LIBBOX_CONFIG = "libboxConfig"

        private const val CHANNEL_ID = "blackout_vpn"
        private const val NOTIFICATION_ID = 1001

        /**
         * Interface address for the TUN. Must share a subnet with the gateway
         * the Xray `tun` inbound advertises (10.111.222.2/30), otherwise the
         * replies the core writes back into the tunnel are not accepted by the
         * interface and every connection stalls.
         */
        private const val VPN_ADDRESS_V4 = "10.111.222.1"
        private const val VPN_PREFIX_V4 = 30

        /**
         * MTU of the TUN interface.
         *
         * 1400, not 1500. Every inner packet is re-encapsulated: TCP-based
         * cores add IP+TCP (~40) and a TLS record with its AEAD tag (~29-45),
         * UDP-based cores (hysteria2, TUIC, QUIC) add a QUIC packet header and
         * its own AEAD tag on top of that. A 1500-byte inner packet therefore
         * leaves no room and the outer datagram either fragments (UDP - and
         * fragmented UDP is widely dropped) or stalls on a PMTU blackhole.
         *
         * The symptom is not an error: big pages stop halfway, YouTube spins,
         * uploads hang. 1400 leaves ~100 bytes of headroom, which covers the
         * worst case (QUIC inside UDP). WireGuard outbounds in this app
         * already default to 1420 for the same reason - see xray_config.dart.
         */
        internal const val VPN_MTU = 1400
        private const val DEFAULT_DNS = "1.1.1.1"

        const val DEFAULT_SOCKS_PORT = 10808

        /** Protocols served by the bundled in-process Xray core. */
        private val XRAY_PROTOCOLS =
            setOf("vless", "vmess", "trojan", "shadowsocks", "wireguard")

        /** Current tunnel state, readable from the plugin without binding. */
        @Volatile
        var isRunning: Boolean = false
            private set

        /** Last failure, surfaced to Dart so the UI can show a real reason. */
        @Volatile
        var lastError: String? = null
            private set

        /**
         * Identity of the live tunnel, readable from the plugin without
         * binding.
         *
         * Needed for state reconciliation: Android may kill the Flutter
         * process while this foreground service keeps the tunnel up, so a
         * reopened app must be able to ask "is a tunnel running, and which
         * config is it?" and adopt it instead of showing "not connected"
         * under a live VPN notification icon.
         */
        @Volatile
        var activeProtocolId: String? = null
            private set

        @Volatile
        var activeDisplayName: String? = null
            private set

        /** Wall-clock start of the current tunnel, for uptime restoration. */
        @Volatile
        var connectedAtMs: Long = 0L
            private set

        /**
         * One-shot hook the plugin uses to resolve its MethodChannel call only
         * after establish() has actually succeeded or failed.
         *
         * Android may invoke onRevoke() off the main thread, so capture/clear
         * operations use an atomic slot rather than a racy read-then-write.
         */
        private val connectResultSlot = OneShotCallbackSlot<Boolean>()
        var connectResultCallback: ((Boolean) -> Unit)?
            get() = connectResultSlot.value
            set(value) {
                connectResultSlot.value = value
            }

        private fun takeConnectResultCallback(): ((Boolean) -> Unit)? = connectResultSlot.take()

        private fun clearConnectResultCallback(expected: ((Boolean) -> Unit)?) {
            connectResultSlot.clear(expected)
        }

        /** Pushes status strings to Dart over the plugin's channel. */
        @Volatile
        var statusListener: ((String) -> Unit)? = null

        @Volatile
        var activeNativeTunnel: Boolean = false
            private set

        private val mainHandler = Handler(Looper.getMainLooper())
    }

    private val sessions = VpnSessionExecutor(dispatch = { action -> mainHandler.post { action() } })
    private var tun: ParcelFileDescriptor? = null

    /**
     * The engine's own duplicate of the tun descriptor. Kept so teardown can
     * close it: without this every connect leaked one descriptor in the app
     * process, and after enough reconnects the process runs out of them.
     */
    private var engineTunFd: ParcelFileDescriptor? = null

    @Volatile
    private var cleanupPending = false

    @Volatile private var nativeMonitor: Runnable? = null
    private var activeProtocol: String? = null
    private var activeName: String? = null

    /**
     * When true, the interface is deliberately left open after the engine dies
     * so packets are dropped instead of leaking onto the unprotected network.
     */
    @Volatile
    private var holdTunnelOnFailure = false

    /**
     * The proxy engine stopped on its own.
     *
     * With the kill switch off this is just a failure: report it and tear the
     * tunnel down so the user is back on plain connectivity.
     *
     * With it on, the correct behaviour is the opposite of tearing down. The
     * interface stays up with no engine behind it, which black-holes traffic —
     * that *is* a userspace kill switch. Dropping the interface here would
     * instantly restore the very leak the user asked to prevent.
     */
    private fun onEngineDied(
        reason: String,
        ticket: VpnSessionExecutor.Ticket,
    ) {
        sessions.forCurrent(ticket) {
            lastError = reason
            if (holdTunnelOnFailure && tun != null) {
                isRunning = false
                getSharedPreferences(PREFS, MODE_PRIVATE)
                    .edit()
                    .putBoolean(KEY_HELD_BLOCKING, true)
                    .apply()
                ticket.publish { notifyStatus("blocked") }
            } else {
                var cleaned = false
                try {
                    teardown()
                    cleaned = true
                } catch (_: Exception) {
                } catch (_: LinkageError) {
                }
                ticket.publish {
                    notifyStatus("error")
                    if (cleaned) finishService()
                }
            }
        }
    }

    /** Poll only the closed channel, never native settings/keys. JNI runs on
     * the serialized session worker, not the UI thread. This is liveness only:
     * no handshake or traffic success is inferred from an open device.
     */
    private fun startNativeMonitor(ticket: VpnSessionExecutor.Ticket) {
        val poll =
            object : Runnable {
                override fun run() {
                    if (nativeMonitor !== this || !ticket.isCurrent()) return
                    val self = this
                    sessions.forCurrent(ticket) {
                        if (NativeTunnelEngine.isClosed()) {
                            // Close the native handle even when the service keeps
                            // its own TUN duplicate for the requested kill switch.
                            var cleaned = false
                            try {
                                NativeTunnelEngine.stop()
                                cleaned = true
                            } catch (_: Exception) {
                            } catch (_: LinkageError) {
                            }
                            ticket.publish { if (nativeMonitor === self) nativeMonitor = null }
                            onEngineDied(
                                if (cleaned) {
                                    "Native tunnel closed unexpectedly"
                                } else {
                                    "Native tunnel failed; cleanup is pending"
                                },
                                ticket,
                            )
                        } else {
                            ticket.publish {
                                if (nativeMonitor === self) mainHandler.postDelayed(self, NATIVE_MONITOR_INTERVAL_MS)
                            }
                        }
                    }
                }
            }
        nativeMonitor?.let { mainHandler.removeCallbacks(it) }
        nativeMonitor = poll
        mainHandler.postDelayed(poll, NATIVE_MONITOR_INTERVAL_MS)
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        // A tunnel held for traffic blocking survives the process: restore the
        // flag so the app reports "blocked" instead of "stopped".
        //
        // ...it does NOT, actually: the flag survives, the TUNNEL does not.
        // If this onCreate runs with the marker set, the previous process died
        // while holding the interface - and the interface, its file descriptor
        // and the black-holing died with it (the service is START_NOT_STICKY,
        // so nothing restarted). Resurrecting isRunning=true here made the app
        // adopt a phantom "blocked" tunnel: the UI showed a live session and
        // reconcile() reported a connection that carried nothing. Clear the
        // stale marker; a genuine hold is always within the lifetime of the
        // instance that set it, where `tun` already tracks the truth.
        val held =
            getSharedPreferences(PREFS, MODE_PRIVATE)
                .getBoolean(KEY_HELD_BLOCKING, false)
        if (held) {
            Log.w(
                TAG,
                "stale held-blocking marker from a previous process - " +
                    "the tunnel died with it, clearing instead of reporting 'blocked'",
            )
            getSharedPreferences(PREFS, MODE_PRIVATE)
                .edit()
                .putBoolean(KEY_HELD_BLOCKING, false)
                .apply()
        }
    }

    override fun onStartCommand(
        intent: Intent?,
        flags: Int,
        startId: Int,
    ): Int {
        if (intent?.action == ACTION_DISCONNECT) {
            val completion = onTeardownComplete
            onTeardownComplete = null
            sessions.stop(cleanup = ::teardown, complete = { current, cleaned ->
                completion?.invoke(cleaned)
                if (current) {
                    notifyStatus(if (cleaned) "disconnected" else "error")
                    if (cleaned) finishService(startId)
                }
            })
            return START_NOT_STICKY
        }

        // Must happen promptly and on the main thread, so it stays here.
        startForegroundCompat()

        startRequestedSession(StartRequest(intent), startId)
        return START_NOT_STICKY
    }

    // Deliberately not a data class: engine configuration strings may contain credentials.
    private class StartRequest(
        intent: Intent?,
    ) {
        val protocol = intent?.getStringExtra(EXTRA_PROTOCOL) ?: "unknown"
        val displayName = intent?.getStringExtra(EXTRA_DISPLAY_NAME) ?: "Blackout Kit"
        val socksPort =
            intent?.getIntExtra(EXTRA_SOCKS_PORT, DEFAULT_SOCKS_PORT)
                ?: DEFAULT_SOCKS_PORT
        val dns = intent?.getStringExtra(EXTRA_DNS) ?: DEFAULT_DNS
        val dnsServers =
            intent?.getStringArrayListExtra(EXTRA_DNS_SERVERS)?.takeIf { it.isNotEmpty() }
                ?: arrayListOf(dns)
        val holdOnFailure =
            intent?.getBooleanExtra(EXTRA_HOLD_ON_ENGINE_FAILURE, false) ?: false
        val allowed = intent?.getStringArrayListExtra(EXTRA_ALLOWED_APPS) ?: emptyList()
        val disallowed =
            intent?.getStringArrayListExtra(EXTRA_DISALLOWED_APPS) ?: emptyList()
        val xrayConfig = intent?.getStringExtra(EXTRA_XRAY_CONFIG)
        val singboxConfig = intent?.getStringExtra(EXTRA_SINGBOX_CONFIG)
        val mihomoConfig = intent?.getStringExtra(EXTRA_MIHOMO_CONFIG)
        val libboxConfig = intent?.getStringExtra(EXTRA_LIBBOX_CONFIG)
        val nativeConfig = intent?.getStringExtra(EXTRA_NATIVE_TUNNEL_CONFIG)

        init {
            intent?.removeExtra(EXTRA_NATIVE_TUNNEL_CONFIG)
        }

        val dnsOnly = intent?.getBooleanExtra(EXTRA_DNS_ONLY, false) ?: false
    }

    private fun startRequestedSession(
        request: StartRequest,
        startId: Int,
    ) {
        // Capture this request's callback; a late start may not consume a
        // later connection's callback. Ticket checks also run at UI delivery.
        val completion = connectResultCallback
        sessions.start(cleanup = ::teardown, start = { ticket ->
            when {
                request.dnsOnly -> establishDnsOnly(request.dnsServers, request.displayName, ticket)
                request.nativeConfig != null -> establishNative(request, request.nativeConfig, ticket)
                else -> establish(request, ticket)
            }
        }, complete = { ok ->
            clearConnectResultCallback(completion)
            completion?.invoke(ok)
            if (!ok) {
                notifyStatus("error")
                if (!cleanupPending) finishService(startId)
            }
        })
    }

    /** Native IP tunnel: never send WG/AWG through a SOCKS/proxy TUN adapter. */
    private fun establishNative(
        request: StartRequest,
        raw: String,
        ticket: VpnSessionExecutor.Ticket,
    ): Boolean {
        lastError = null
        return try {
            if (!NativeTunnelEngine.available(request.protocol)) {
                setupFailure(
                    ticket,
                    NativeTunnelEngine.lastError ?: "Native tunnel library is unavailable or incompatible",
                )
            } else {
                // Resolve endpoints before establishing routes.
                val config = NativeTunnelConfig.parse(raw, request.protocol == "amneziawg")
                val settings = config.userspace()
                ticket.isCurrent() && activateNative(request, config, settings, ticket)
            }
        } catch (_: Exception) {
            setupFailure(
                ticket,
                "Native tunnel setup failed: check profile, routed DNS, app exclusions and VPN consent",
            )
        } catch (_: LinkageError) {
            setupFailure(ticket, "Native tunnel library is unavailable or incompatible")
        }
    }

    private fun nativeBuilder(
        request: StartRequest,
        config: NativeTunnelConfig,
    ): Builder {
        val builder = Builder().setSession(request.displayName).setMtu(config.mtu)
        config.addresses.forEach { builder.addAddress(it.address, it.prefix) }
        config.routes.forEach { builder.addRoute(it.address, it.prefix) }
        // Reject uncovered DNS rather than allowing carrier fallback.
        config.routedDns(request.dnsServers).forEach { builder.addDnsServer(it) }
        // Native IP engines protect their transport sockets individually.
        if (request.allowed.isNotEmpty()) {
            (request.allowed + packageName).distinct().forEach { builder.addAllowedApplication(it) }
        } else {
            request.disallowed.distinct().forEach { builder.addDisallowedApplication(it) }
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) builder.setMetered(false)
        return builder
    }

    private fun activateNative(
        request: StartRequest,
        config: NativeTunnelConfig,
        settings: String,
        ticket: VpnSessionExecutor.Ticket,
    ): Boolean {
        val fd = nativeBuilder(request, config).establish() ?: error("No TUN")
        tun = fd
        holdTunnelOnFailure = request.holdOnFailure
        return if (!NativeTunnelEngine.start(this, request.protocol, fd, settings)) {
            setupFailure(ticket, NativeTunnelEngine.lastError ?: "Native engine failed to start")
        } else {
            publishNativeConnected(request, ticket)
        }
    }

    private fun publishNativeConnected(
        request: StartRequest,
        ticket: VpnSessionExecutor.Ticket,
    ): Boolean {
        if (!ticket.isCurrent()) return false
        activeNativeTunnel = true
        activeProtocol = request.protocol
        activeName = request.displayName
        activeProtocolId = request.protocol
        activeDisplayName = request.displayName
        connectedAtMs = System.currentTimeMillis()
        isRunning = true
        ticket.publish {
            startNativeMonitor(ticket)
            notifyStatus("connected")
        }
        return true
    }

    private fun setupFailure(
        ticket: VpnSessionExecutor.Ticket,
        message: String,
    ): Boolean {
        lastError = message
        Log.w(TAG, message)
        ticket.publish { notifyStatus("error") }
        return false
    }

    private fun establish(
        request: StartRequest,
        ticket: VpnSessionExecutor.Ticket,
    ): Boolean {
        lastError = null
        if (request.protocol == "mihomo" && request.allowed.contains(packageName)) {
            lastError = "Mihomo's subprocess must remain outside its VPN. Remove Blackout from the allowed-app list."
            return false
        }
        return try {
            val builder = configureProxyBuilder(request, ticket)
            if (builder == null) false else openProxyTunnel(builder, request, ticket)
        } catch (_: IllegalArgumentException) {
            setupFailure(ticket, "VPN configuration rejected.")
        } catch (_: IllegalStateException) {
            setupFailure(ticket, lastError ?: "VPN setup or engine cleanup failed.")
        } catch (_: SecurityException) {
            setupFailure(ticket, "VPN permission denied.")
        } catch (_: java.io.IOException) {
            setupFailure(ticket, "VPN setup I/O failed.")
        }
    }

    private fun configureProxyBuilder(
        request: StartRequest,
        ticket: VpnSessionExecutor.Ticket,
    ): Builder? {
        val displayName = request.displayName
        val dnsServers = request.dnsServers
        val allowed = request.allowed
        val disallowed = request.disallowed
        val builder =
            Builder()
                .setSession(displayName)
                .setMtu(VPN_MTU)
                .addAddress(VPN_ADDRESS_V4, VPN_PREFIX_V4)
                .addRoute("0.0.0.0", 0)
                // IPv6 blackhole (kill switch for v6): route ::/0 into the TUN
                // WITHOUT giving the interface an IPv6 address. v6 packets
                // enter the tunnel, find no v6 netstack on the other side, and
                // are dropped — nothing bypasses the tunnel on dual-stack
                // networks. Apps fall back to IPv4 per Happy Eyeballs and that
                // traffic is proxied normally. Adding a real v6 address
                // instead would require the core's tun inbound to be verified
                // v6-capable on hardware first; leaking was not an option.
                .addRoute("::", 0)

        // DNS leak prevention: every resolver the tunnel advertises is one
        // we control. The system resolver is never offered, so queries
        // cannot silently fall back to the carrier.
        val acceptedDns = addDnsServers(builder, dnsServers)
        // Every server was refused. Establishing anyway would give Android
        // an interface with no DNS at all, and the system would quietly
        // fall back to the carrier's resolver while the UI still says leak
        // prevention is on — a silent leak is worse than a failed connect.
        if (dnsServers.isNotEmpty() && acceptedDns == 0) {
            lastError = "Every DNS server was rejected by Android " +
                "($dnsServers). Refusing to build a tunnel that would " +
                "silently fall back to the carrier resolver."
            Log.e(TAG, lastError!!)
            ticket.publish { notifyStatus("error") }
            return null
        }

        // NOTE: deliberately no setBlocking(). The Xray tun inbound reads
        // the fd through Go's runtime poller, which requires the descriptor
        // to stay in its default (non-blocking) mode. Forcing blocking mode
        // here makes the core start and then never see a packet.

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            builder.setMetered(false)
        }

        configureProxyAppRouting(builder, allowed, disallowed)

        return builder
    }

    private fun openProxyTunnel(
        builder: Builder,
        request: StartRequest,
        ticket: VpnSessionExecutor.Ticket,
    ): Boolean {
        val fd = builder.establish()
        if (fd == null) {
            lastError = "establish() returned null - VPN consent missing or revoked"
            Log.e(TAG, lastError!!)
            ticket.publish { notifyStatus("error") }
            return false
        }
        return activateProxyTunnel(fd, request, ticket) && publishProxyConnected(fd, request, ticket)
    }

    private fun activateProxyTunnel(
        fd: ParcelFileDescriptor,
        request: StartRequest,
        ticket: VpnSessionExecutor.Ticket,
    ): Boolean {
        val protocol = request.protocol
        tun = fd
        // The serialized session executor must finish old ownership cleanup first.
        check(engineTunFd == null) { "Previous engine descriptor is still owned" }

        // Arm the kill switch before the engine starts, so a crash during
        // startup is caught too.
        holdTunnelOnFailure = request.holdOnFailure
        XrayEngine.unexpectedStopListener = { reason -> onEngineDied(reason, ticket) }
        EngineRunner.onUnexpectedExit = { reason -> onEngineDied(reason, ticket) }

        // The Xray tun inbound takes OWNERSHIP of the fd it is handed and
        // closes it when the core stops. Handing it the raw fd of `tun`
        // means teardown()'s later close() targets a recycled descriptor.
        // The engine gets its own dup and closes only that.
        val engineFd =
            try {
                // dup(), NOT fromFd(): fromFd wraps the SAME descriptor without
                // duplicating it, so the engine's close() and teardown()'s
                // close() would hit one descriptor twice - and the second close
                // would land on whatever descriptor number the kernel had since
                // recycled.
                fd.dup()
            } catch (e: java.io.IOException) {
                Log.e(TAG, "could not duplicate the tun fd: ${e.message}")
                lastError = "Could not duplicate the tun fd: ${e.message}"
                ticket.publish { notifyStatus("error") }
                return false
            }

        // The engine must be up before we claim success, otherwise all
        // traffic would be black-holed by the default route just installed.
        engineTunFd = engineFd
        val engineOk =
            startEngine(request, engineFd.fd)
        return if (!engineOk) {
            // The engine sets its own lastError with the REAL reason
            // ("Xray core rejected the configuration: ..."). It used to
            // stay trapped in XrayEngine while the UI got this generic
            // fallback, making remote debugging impossible.
            lastError = lastError ?: when {
                protocol.lowercase() in XRAY_PROTOCOLS -> XrayEngine.lastError
                protocol == "mihomo" -> EngineRunner.lastError
                else -> LibboxEngine.lastError ?: EngineRunner.lastError
            } ?: "Engine failed to start for protocol '$protocol'"
            Log.e(TAG, lastError!!)
            // Startup failure does not prove the native engine released the fd.
            // The session executor stops the engine before releasing descriptors.
            ticket.publish { notifyStatus("error") }
            false
        } else {
            true
        }
    }

    private fun publishProxyConnected(
        fd: ParcelFileDescriptor,
        request: StartRequest,
        ticket: VpnSessionExecutor.Ticket,
    ): Boolean {
        val protocol = request.protocol
        val displayName = request.displayName
        val socksPort = request.socksPort
        if (!ticket.isCurrent()) return false
        activeProtocol = protocol
        activeName = displayName
        isRunning = true
        activeProtocolId = protocol
        activeDisplayName = displayName
        connectedAtMs = System.currentTimeMillis()
        lastError = null
        Log.i(TAG, "tunnel up: $displayName ($protocol) tun=${fd.fd} socks=$socksPort")
        ticket.publish { notifyStatus("connected") }
        return true
    }

    private fun addDnsServers(
        builder: Builder,
        servers: List<String>,
    ): Int {
        var accepted = 0
        for (server in servers) {
            try {
                builder.addDnsServer(server)
                accepted++
            } catch (_: IllegalArgumentException) {
                Log.w(TAG, "Android rejected a DNS server")
            }
        }
        return accepted
    }

    private fun configureProxyAppRouting(
        builder: Builder,
        allowed: List<String>,
        disallowed: List<String>,
    ) {
        // Android prohibits mixing allow and deny lists; allow takes precedence.
        val useAllowedList = allowed.isNotEmpty()
        val appList = if (useAllowedList) allowed else disallowed
        for (pkg in appList) {
            try {
                if (useAllowedList) {
                    builder.addAllowedApplication(pkg)
                } else {
                    builder.addDisallowedApplication(pkg)
                }
            } catch (_: android.content.pm.PackageManager.NameNotFoundException) {
                Log.w(TAG, "Split tunneling package not installed")
            }
        }
        if (!useAllowedList) {
            try {
                builder.addDisallowedApplication(packageName)
            } catch (_: android.content.pm.PackageManager.NameNotFoundException) {
                Log.w(TAG, "Could not exclude self from VPN")
            }
        }
    }

    /**
     * Picks the engine for [protocol].
     *
     * The Dart side decides which engine a config belongs to and sends
     * [xrayConfig] only for Xray protocols, so the presence of that extra is
     * the contract. An Xray protocol arriving without a config is a bug in the
     * caller, not a reason to fall through to an engine that cannot serve it.
     */
    private fun startEngine(
        request: StartRequest,
        tunFd: Int,
    ): Boolean =
        when {
            request.protocol == "mihomo" -> startMihomo(request, tunFd)
            request.protocol.lowercase() in XRAY_PROTOCOLS -> startXray(request, tunFd)
            else -> startSingbox(request, tunFd)
        }

    private fun startMihomo(
        request: StartRequest,
        tunFd: Int,
    ): Boolean {
        val protocol = request.protocol
        val mihomoConfig = request.mihomoConfig
        return when {
            !BuildConfig.ENABLE_EXPERIMENTAL_MIHOMO || mihomoConfig.isNullOrBlank() -> {
                lastError = "Mihomo is experimental and disabled, or its configuration is missing."
                false
            }
            !EngineRunner.writeConfig(this, mihomoConfig, protocol) -> {
                lastError = "Could not store the Mihomo configuration."
                false
            }
            else -> EngineRunner.start(this, tunFd, request.socksPort, protocol)
        }
    }

    private fun startXray(
        request: StartRequest,
        tunFd: Int,
    ): Boolean {
        val xrayConfig = request.xrayConfig
        if (xrayConfig.isNullOrBlank()) {
            lastError = "No Xray config was supplied for protocol '${request.protocol}'"
            Log.e(TAG, lastError!!)
            return false
        }
        return XrayEngine.start(this, xrayConfig, tunFd)
    }

    private fun startSingbox(
        request: StartRequest,
        tunFd: Int,
    ): Boolean {
        val protocol = request.protocol
        val libboxConfig = request.libboxConfig
        if (!request.xrayConfig.isNullOrBlank()) {
            Log.w(TAG, "ignoring an Xray config supplied for non-Xray '$protocol'")
        }

        // A non-Xray protocol MUST arrive with its config document.
        //
        // This used to be `if (!singboxConfig.isNullOrBlank() && !writeConfig(...))`,
        // so a null config skipped the write entirely and EngineRunner.start()
        // loaded whatever singbox.json was already on disk - the previous
        // session's server, under the new protocol's name. The tunnel came up
        // and reported "connected" while running the wrong proxy.
        // The Rust core scaffolding is bundled, but its TCP outbound dispatcher
        // still refuses the supported sing-box protocols. Do not route a user
        // tunnel into it until its selected protocol has a tested end-to-end
        // data path. Libbox is the production in-process sing-box runtime here.
        if (BlackoutCoreEngine.isLoaded) {
            Log.d(TAG, "Rust core is bundled but not enabled for '$protocol' until its outbound is implemented")
        }

        // In-process libbox core before the subprocess fallback: same sing-box
        // grammar (same pinned version), but the core runs inside this process
        // and takes the TUN fd directly - no tun2socks, no fdlauncher.
        LibboxEngine.resetLastError()
        if (libboxConfig.isNullOrBlank()) {
            Log.w(TAG, "no libbox-mode config supplied for '$protocol' (older Dart caller?)")
        } else if (LibboxEngine.start(this, tunFd, libboxConfig)) {
            Log.i(TAG, "Starting protocol '$protocol' via in-process libbox core")
            return true
        } else {
            Log.w(TAG, "LibboxEngine failed, falling back to EngineRunner: ${LibboxEngine.lastError}")
        }

        return startSingboxSubprocess(request, tunFd)
    }

    private fun startSingboxSubprocess(
        request: StartRequest,
        tunFd: Int,
    ): Boolean {
        val protocol = request.protocol
        val singboxConfig = request.singboxConfig
        return when {
            singboxConfig.isNullOrBlank() -> {
                lastError =
                    "No sing-box config was supplied for protocol '$protocol'; " +
                    "refusing to start an engine on a stale config file."
                Log.e(TAG, lastError!!)
                false
            }
            !EngineRunner.writeConfig(this, singboxConfig) -> {
                lastError = EngineRunner.lastError ?: "Could not write the sing-box config."
                Log.e(TAG, lastError!!)
                false
            }
            else ->
                EngineRunner.start(
                    context = this,
                    tunFd = tunFd,
                    socksPort = request.socksPort,
                    protocol = protocol,
                )
        }
    }

    /**
     * DNS-only session: advertise the resolvers and route nothing.
     *
     * The interface is created so Android adopts these resolvers for every app,
     * but no route is added — so ordinary traffic keeps using the physical
     * network and only name lookups move. The tun descriptor is held open
     * (nothing reads it) purely to keep the interface, and with it the DNS
     * setting, alive; `teardown()` closes it as usual.
     *
     * This exists because changing DNS used to require a full tunnel: a user
     * who only wanted a different resolver had to have a config and route all
     * their traffic through a server to get it.
     */
    private fun establishDnsOnly(
        dnsServers: List<String>,
        displayName: String,
        ticket: VpnSessionExecutor.Ticket,
    ): Boolean =
        try {
            val builder =
                Builder()
                    .setSession(displayName)
                    .setMtu(VPN_MTU)
                    .addAddress(VPN_ADDRESS_V4, VPN_PREFIX_V4)
            if (addDnsServers(builder, dnsServers) == 0) {
                setupFailure(ticket, "No usable DNS server was accepted.")
            } else {
                openDnsInterface(builder, displayName, ticket)
            }
        } catch (_: IllegalArgumentException) {
            setupFailure(ticket, "DNS-only configuration was rejected.")
        } catch (_: IllegalStateException) {
            setupFailure(ticket, "DNS-only interface could not be established.")
        } catch (_: SecurityException) {
            setupFailure(ticket, "VPN consent is missing or revoked.")
        }

    private fun openDnsInterface(
        builder: Builder,
        displayName: String,
        ticket: VpnSessionExecutor.Ticket,
    ): Boolean {
        // Deliberately NO addRoute(): DNS-only is not a traffic tunnel.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) builder.setMetered(false)
        val fd = builder.establish() ?: return setupFailure(ticket, "VPN consent missing or revoked")
        tun = fd
        return if (ticket.isCurrent()) {
            activeProtocol = "dns"
            activeName = displayName
            isRunning = true
            activeProtocolId = "dns"
            activeDisplayName = displayName
            connectedAtMs = System.currentTimeMillis()
            lastError = null
            ticket.publish { notifyStatus("connected") }
            true
        } else {
            false
        }
    }

    /** The system revoked our tunnel (another VPN took over, or the user disabled it). */
    override fun onRevoke() {
        lastError = "VPN was revoked by the system"
        val completion = takeConnectResultCallback()
        if (completion != null) {
            // Android does not guarantee onRevoke() runs on the main thread.
            mainHandler.post { completion(false) }
        }
        sessions.stop(cleanup = ::teardown, complete = { current, cleaned ->
            if (current) {
                notifyStatus(if (cleaned) "disconnected" else "error")
                if (cleaned) finishService()
            }
        })
        super.onRevoke()
    }

    override fun onDestroy() {
        // A startup still in native code must finish on its owner thread
        // before cleanup; never close its TUN concurrently on the main thread.
        sessions.stop(cleanup = ::teardown, close = true)
        super.onDestroy()
    }

    private fun teardown() {
        nativeMonitor?.let { mainHandler.removeCallbacks(it) }
        nativeMonitor = null
        XrayEngine.unexpectedStopListener = null
        EngineRunner.onUnexpectedExit = null
        holdTunnelOnFailure = false
        cleanupPending = true
        isRunning = false
        activeNativeTunnel = false
        val stopped =
            stopEnginesBeforeRelease(
                stops =
                    listOf(
                        XrayEngine::stop,
                        EngineRunner::stop,
                        BlackoutCoreEngine::stop,
                        LibboxEngine::stop,
                        NativeTunnelEngine::stop,
                    ),
                release = ::releaseTunnelDescriptors,
            )
        if (!stopped) {
            lastError = "A native engine could not be stopped cleanly. Retry disconnect before reconnecting."
            error(lastError!!)
        }
        cleanupPending = false
        // The held-blocking marker describes a live tunnel; once the interface
        // is gone the state is "stopped" again, not "blocked".
        getSharedPreferences(PREFS, MODE_PRIVATE)
            .edit()
            .putBoolean(KEY_HELD_BLOCKING, false)
            .apply()
        activeProtocol = null
        activeName = null
        activeProtocolId = null
        activeDisplayName = null
        connectedAtMs = 0L
    }

    private fun releaseTunnelDescriptors() {
        var failed = false
        try {
            engineTunFd?.close()
        } catch (e: java.io.IOException) {
            failed = true
            Log.w(TAG, "Engine descriptor close failed: ${e.javaClass.simpleName}")
        } finally {
            engineTunFd = null
        }
        try {
            tun?.close()
        } catch (e: java.io.IOException) {
            failed = true
            Log.w(TAG, "Tunnel descriptor close failed: ${e.javaClass.simpleName}")
        } finally {
            tun = null
        }
        if (failed) {
            lastError = "A VPN descriptor could not be closed cleanly."
            error(lastError!!)
        }
    }

    /** Called on the main thread only after this request's cleanup settled. */
    private fun finishService(startId: Int? = null) {
        // minSdk is 24, so the integer overload is always available.
        stopForeground(STOP_FOREGROUND_REMOVE)
        if (startId == null) stopSelf() else stopSelfResult(startId)
    }

    private fun notifyStatus(status: String) {
        statusListener?.invoke(status)
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java) ?: return
        if (manager.getNotificationChannel(CHANNEL_ID) == null) {
            val channel =
                NotificationChannel(
                    CHANNEL_ID,
                    "VPN status",
                    NotificationManager.IMPORTANCE_LOW,
                ).apply {
                    description = "Shown while the Blackout Kit tunnel is active"
                    setShowBadge(false)
                }
            manager.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(): Notification {
        val openApp =
            PendingIntent.getActivity(
                this,
                0,
                Intent(this, MainActivity::class.java),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )

        val builder =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Notification.Builder(this, CHANNEL_ID)
            } else {
                @Suppress("DEPRECATION")
                Notification.Builder(this)
            }

        return builder
            .setContentTitle("Blackout Kit")
            .setContentText("Tunnel active${activeName?.let { " - $it" } ?: ""}")
            .setSmallIcon(R.drawable.ic_vpn_notification)
            .setContentIntent(openApp)
            .setOngoing(true)
            .build()
    }

    private fun startForegroundCompat() {
        val notification = buildNotification()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }
}
