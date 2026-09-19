package com.blackoutkit.vpn

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import android.util.Log

/**
 * The real Android VPN tunnel for Blackout Kit.
 *
 * This class owns the TUN interface. It does not speak any proxy protocol itself:
 * the bundled engine (xray-core / sing-box) listens on a loopback SOCKS port and
 * [EngineRunner] bridges the TUN file descriptor to it.
 *
 * Lifecycle:
 *   connect    -> startForeground -> establish() -> EngineRunner.start()
 *   disconnect -> EngineRunner.stop() -> teardown() -> stopSelf()
 *   revoked    -> onRevoke() -> teardown() -> notify Dart
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
        const val EXTRA_ALLOWED_APPS = "allowedApps"
        const val EXTRA_DISALLOWED_APPS = "disallowedApps"

        private const val CHANNEL_ID = "blackout_vpn"
        private const val NOTIFICATION_ID = 1001

        private const val VPN_ADDRESS_V4 = "10.111.222.1"
        private const val VPN_MTU = 1500
        private const val DEFAULT_DNS = "1.1.1.1"

        const val DEFAULT_SOCKS_PORT = 10808

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
    }

    private var tun: ParcelFileDescriptor? = null
    private var activeProtocol: String? = null
    private var activeName: String? = null

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

        startForegroundCompat()

        val ok = establish(
            protocol = intent?.getStringExtra(EXTRA_PROTOCOL) ?: "unknown",
            displayName = intent?.getStringExtra(EXTRA_DISPLAY_NAME) ?: "Blackout Kit",
            socksPort = intent?.getIntExtra(EXTRA_SOCKS_PORT, DEFAULT_SOCKS_PORT)
                ?: DEFAULT_SOCKS_PORT,
            dns = intent?.getStringExtra(EXTRA_DNS) ?: DEFAULT_DNS,
            allowed = intent?.getStringArrayListExtra(EXTRA_ALLOWED_APPS) ?: emptyList(),
            disallowed = intent?.getStringArrayListExtra(EXTRA_DISALLOWED_APPS) ?: emptyList()
        )

        connectResultCallback?.invoke(ok)
        connectResultCallback = null

        if (!ok) {
            teardown()
            stopSelf()
        }
        return START_NOT_STICKY
    }

    private fun establish(
        protocol: String,
        displayName: String,
        socksPort: Int,
        dns: String,
        allowed: List<String>,
        disallowed: List<String>
    ): Boolean {
        if (tun != null) teardown()

        return try {
            val builder = Builder()
                .setSession(displayName)
                .setMtu(VPN_MTU)
                .addAddress(VPN_ADDRESS_V4, 32)
                .addRoute("0.0.0.0", 0)
                .addDnsServer(dns)
                .setBlocking(true)

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

            // Never route our own traffic back into the tunnel.
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

            // The engine must be up before we claim success, otherwise all traffic
            // would be black-holed by the default route we just installed.
            val engineOk = EngineRunner.start(
                context = this,
                tunFd = fd.fd,
                socksPort = socksPort,
                protocol = protocol
            )
            if (!engineOk) {
                lastError = EngineRunner.lastError
                    ?: "Engine failed to start for protocol '$protocol'"
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
