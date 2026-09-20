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

        const val ACTION_CONNECT = "com.blackoutkit.vpn.CONNECT"
        const val ACTION_DISCONNECT = "com.blackoutkit.vpn.DISCONNECT"

        const val EXTRA_PROTOCOL = "protocol"
        const val EXTRA_DISPLAY_NAME = "displayName"
        const val EXTRA_SOCKS_PORT = "socksPort"
        const val EXTRA_DNS = "dns"
        const val EXTRA_DNS_SERVERS = "dnsServers"
        const val EXTRA_ALLOWED_APPS = "allowedApps"
        const val EXTRA_DISALLOWED_APPS = "disallowedApps"

        /** Hold the interface open if the engine dies, instead of falling back. */
        const val EXTRA_HOLD_ON_ENGINE_FAILURE = "holdTunnelOnEngineFailure"

        /** Full Xray JSON document, built by the Dart side. */
        const val EXTRA_XRAY_CONFIG = "xrayConfig"

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
        private const val VPN_MTU = 1500
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
         * One-shot hook the plugin uses to resolve its MethodChannel call only
         * after establish() has actually succeeded or failed.
         */
        @Volatile
        var connectResultCallback: ((Boolean) -> Unit)? = null

        /** Pushes status strings to Dart over the plugin's channel. */
        @Volatile
        var statusListener: ((String) -> Unit)? = null

        private val mainHandler = Handler(Looper.getMainLooper())
    }

    private var tun: ParcelFileDescriptor? = null
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
    private fun onEngineDied(reason: String) {
        mainHandler.post {
            lastError = reason
            if (holdTunnelOnFailure && tun != null) {
                isRunning = false
                Log.w(TAG, "engine died - holding the tunnel open to block traffic: $reason")
                notifyStatus("blocked")
                return@post
            }
            Log.w(TAG, "engine died - tearing the tunnel down: $reason")
            teardown()
            notifyStatus("error")
            stopSelf()
        }
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_DISCONNECT) {
            teardown()
            stopSelf()
            return START_NOT_STICKY
        }

        // Must happen promptly and on the main thread, so it stays here.
        startForegroundCompat()

        val protocol = intent?.getStringExtra(EXTRA_PROTOCOL) ?: "unknown"
        val displayName = intent?.getStringExtra(EXTRA_DISPLAY_NAME) ?: "Blackout Kit"
        val socksPort = intent?.getIntExtra(EXTRA_SOCKS_PORT, DEFAULT_SOCKS_PORT)
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

        Thread({
            val ok = establish(
                protocol = protocol,
                displayName = displayName,
                socksPort = socksPort,
                dnsServers = dnsServers,
                allowed = allowed,
                disallowed = disallowed,
                holdOnFailure = holdOnFailure,
                xrayConfig = xrayConfig
            )

            mainHandler.post {
                connectResultCallback?.invoke(ok)
                connectResultCallback = null
                if (!ok) {
                    teardown()
                    stopSelf()
                }
            }
        }, "blackout-establish").start()

        return START_NOT_STICKY
    }

    private fun establish(
        protocol: String,
        displayName: String,
        socksPort: Int,
        dnsServers: List<String>,
        allowed: List<String>,
        disallowed: List<String>,
        holdOnFailure: Boolean,
        xrayConfig: String?
    ): Boolean {
        if (tun != null) teardown()

        return try {
            val builder = Builder()
                .setSession(displayName)
                .setMtu(VPN_MTU)
                .addAddress(VPN_ADDRESS_V4, VPN_PREFIX_V4)
                .addRoute("0.0.0.0", 0)

            // DNS leak prevention: every resolver the tunnel advertises is one
            // we control. The system resolver is never offered, so queries
            // cannot silently fall back to the carrier.
            for (server in dnsServers) {
                try {
                    builder.addDnsServer(server)
                } catch (e: Exception) {
                    Log.w(TAG, "rejected DNS server '$server': ${e.message}")
                }
            }

            // NOTE: deliberately no setBlocking(). The Xray tun inbound reads
            // the fd through Go's runtime poller, which requires the descriptor
            // to stay in its default (non-blocking) mode. Forcing blocking mode
            // here makes the core start and then never see a packet.

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                builder.setMetered(false)
            }

            // Split tunneling. Android rejects a uid that appears in both lists,
            // so allowed takes precedence and disallowed is ignored when it is set.
            val appList = if (allowed.isNotEmpty()) allowed else disallowed
            val useAllowedList = allowed.isNotEmpty()
            for (pkg in appList) {
                try {
                    if (useAllowedList) builder.addAllowedApplication(pkg)
                    else builder.addDisallowedApplication(pkg)
                } catch (e: Exception) {
                    Log.w(TAG, "split tunneling rejected $pkg: ${e.message}")
                }
            }

            // Never route our own traffic back into the tunnel: the proxy
            // connection to the server is dialled from this very process, and
            // looping it back into the TUN would deadlock the tunnel.
            //
            // CONSEQUENCE — read before adding any in-app network probe.
            // This makes every socket opened by this app bypass the tunnel, in
            // both split-tunneling modes:
            //   * disallow-list mode: we add ourselves to the disallowed list;
            //   * allow-list mode: only the listed packages are tunneled and we
            //     are not among them (the call below throws and is caught).
            // So a `Socket.connect` or `HttpClient` request made from Dart
            // measures the *physical* path, not the tunnel. A probe like that
            // cannot detect a dead tunnel — it reports healthy as long as the
            // device has any internet at all. That is exactly why
            // `HealthMonitorService` was removed rather than wired up.
            //
            // To probe through the tunnel, dial the core's loopback inbound
            // instead: the SOCKS listener on `DEFAULT_SOCKS_PORT` (see
            // [XrayConfigBuilder.socksPort] on the Dart side). Requests sent
            // there enter Xray and leave via the proxy outbound, so the
            // observed exit address is the tunnel's.
            try {
                builder.addDisallowedApplication(packageName)
            } catch (e: Exception) {
                Log.w(TAG, "could not exclude self: ${e.message}")
            }

            val fd = builder.establish()
            if (fd == null) {
                lastError = "establish() returned null - VPN consent missing or revoked"
                Log.e(TAG, lastError!!)
                notifyStatus("error")
                return false
            }
            tun = fd

            // Arm the kill switch before the engine starts, so a crash during
            // startup is caught too.
            holdTunnelOnFailure = holdOnFailure
            XrayEngine.unexpectedStopListener = { reason -> onEngineDied(reason) }

            // The engine must be up before we claim success, otherwise all
            // traffic would be black-holed by the default route just installed.
            val engineOk = startEngine(protocol, xrayConfig, fd.fd, socksPort)
            if (!engineOk) {
                if (lastError == null) {
                    lastError = "Engine failed to start for protocol '$protocol'"
                }
                Log.e(TAG, lastError!!)
                notifyStatus("error")
                return false
            }

            activeProtocol = protocol
            activeName = displayName
            isRunning = true
            lastError = null
            Log.i(TAG, "tunnel up: $displayName ($protocol) tun=${fd.fd} socks=$socksPort")
            notifyStatus("connected")
            true
        } catch (e: Exception) {
            lastError = "establish failed: ${e.message}"
            Log.e(TAG, lastError, e)
            notifyStatus("error")
            false
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
        protocol: String,
        xrayConfig: String?,
        tunFd: Int,
        socksPort: Int
    ): Boolean {
        val isXrayFamily = protocol.lowercase() in XRAY_PROTOCOLS

        if (isXrayFamily) {
            if (xrayConfig.isNullOrBlank()) {
                lastError = "No Xray config was supplied for protocol '$protocol'"
                Log.e(TAG, lastError!!)
                return false
            }
            return XrayEngine.start(this, xrayConfig, tunFd)
        }

        if (!xrayConfig.isNullOrBlank()) {
            Log.w(TAG, "ignoring an Xray config supplied for non-Xray '$protocol'")
        }
        return EngineRunner.start(
            context = this,
            tunFd = tunFd,
            socksPort = socksPort,
            protocol = protocol
        )
    }

    /** The system revoked our tunnel (another VPN took over, or the user disabled it). */
    override fun onRevoke() {
        Log.w(TAG, "onRevoke - tunnel was revoked by the system")
        lastError = "VPN was revoked by the system"
        teardown()
        notifyStatus("disconnected")
        super.onRevoke()
    }

    override fun onDestroy() {
        teardown()
        super.onDestroy()
    }

    private fun teardown() {
        XrayEngine.unexpectedStopListener = null
        holdTunnelOnFailure = false
        XrayEngine.stop()
        EngineRunner.stop()
        try {
            tun?.close()
        } catch (e: Exception) {
            Log.w(TAG, "error closing tun: ${e.message}")
        }
        tun = null
        isRunning = false
        activeProtocol = null
        activeName = null
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
    }

    private fun notifyStatus(status: String) {
        statusListener?.invoke(status)
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java) ?: return
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "VPN status",
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = "Shown while the Blackout Kit tunnel is active"
            setShowBadge(false)
        }
        manager.createNotificationChannel(channel)
    }

    private fun buildNotification(): Notification {
        val openApp = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
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
        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }
}
