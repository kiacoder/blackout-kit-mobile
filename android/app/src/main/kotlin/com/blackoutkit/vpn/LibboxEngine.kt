package com.blackoutkit.vpn

import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.os.Build
import android.util.Log
import libbox.BoxService
import libbox.InterfaceUpdateListener
import libbox.Libbox
import libbox.NetworkInterface
import libbox.NetworkInterfaceIterator
import libbox.Notification
import libbox.PlatformInterface
import libbox.TunOptions
import libbox.WIFIState

private const val LIBBOX_OTHER_INTERFACE = 4

/**
 * In-process libbox core (embedded sing-box, no subprocess).
 *
 * Android uses the libbox bindings in the merged libcores.aar. Its exact
 * sing-box source revision is not established by the embedded build metadata.
 * Do not assume grammar parity with the iOS build or standalone executable.
 * [BlackoutVpnService] passes the established TUN fd to this engine, which
 * answers libbox's [PlatformInterface.openTun] with it.
 *
 * Ordering in [BlackoutVpnService.startEngine]: BlackoutCoreEngine (the
 * in-house Rust core) is still preferred, then this, then the subprocess
 * [EngineRunner] as the last-resort fallback.
 *
 * Unlike [EngineRunner] there is no child process to monitor, so there is
 * no unexpected-exit thread here; a core that stops moving packets is
 * caught by the Dart-side recurring liveness watchdog
 * (ConnectionController._startLivenessWatchdog), same as for XrayEngine.
 */
object LibboxEngine {
    private const val TAG = "LibboxEngine"

    @Volatile
    var lastError: String? = null
        private set

    /** Clears the previous failure so a stale message is never misattributed. */
    fun resetLastError() {
        lastError = null
    }

    private val owner =
        EmbeddedCoreOwner<BoxService> { current ->
            embeddedCall { current.close() }.getOrElse { failure ->
                lastError = "Embedded sing-box cleanup failed; retry cleanup before starting another core"
                Log.w(TAG, "libbox close failed: ${failure.javaClass.simpleName}")
                error(lastError!!)
            }
        }

    /**
     * A version is returned only when the generated bindings respond. Do not
     * substitute a compile-time guess here: callers use this probe to decide
     * whether the embedded runtime is actually loadable on this ABI.
     */
    fun version(): String? =
        try {
            if (GoRuntimeAdmission.process.claim(GoRuntimeAdmission.Family.EMBEDDED)) {
                Libbox.version()?.takeIf { it.isNotBlank() && it != "unknown" }
            } else {
                null
            }
        } catch (e: LinkageError) {
            Log.w(TAG, "libbox version probe failed: ${e.javaClass.simpleName}")
            null
        }

    /** True only when a libbox call successfully reaches the embedded runtime. */
    fun isAvailable(): Boolean =
        try {
            GoRuntimeAdmission.process.claim(GoRuntimeAdmission.Family.EMBEDDED) &&
                Libbox.version() != null
        } catch (e: LinkageError) {
            Log.w(TAG, "libbox availability probe failed: ${e.javaClass.simpleName}")
            false
        }

    /**
     * Starts the embedded core. The core dups the fd it receives via
     * [openTun][LibboxPlatform.openTun], so [tunFd] stays owned by the
     * VpnService and is closed by its usual [teardown][BlackoutVpnService.teardown].
     */
    fun start(
        vpnService: BlackoutVpnService,
        tunFd: Int,
        configJson: String,
    ): Boolean {
        lastError = null
        if (!GoRuntimeAdmission.process.claim(GoRuntimeAdmission.Family.EMBEDDED)) {
            lastError = GoRuntimeAdmission.RESTART_REQUIRED
            return false
        }
        return owner.start(
            create = { createService(vpnService, tunFd, configJson) },
            activate = ::startService,
        )
    }

    private fun createService(
        vpnService: BlackoutVpnService,
        tunFd: Int,
        configJson: String,
    ): BoxService? =
        embeddedCall { Libbox.newService(configJson, LibboxPlatform(vpnService, tunFd)) }.getOrElse { failure ->
            lastError =
                if (failure is LinkageError) {
                    "Embedded sing-box runtime is unavailable or incompatible"
                } else {
                    "libbox config rejected"
                }
            Log.w(TAG, "libbox creation failed: ${failure.javaClass.simpleName}")
            null
        }

    private fun startService(svc: BoxService): Boolean =
        embeddedCall { svc.start() }.fold(
            onSuccess = {
                Log.i(TAG, "libbox core started")
                true
            },
            onFailure = { failure ->
                lastError = "libbox core failed to start"
                Log.w(TAG, "libbox core start failed: ${failure.javaClass.simpleName}")
                false
            },
        )

    fun stop() {
        owner.stop()
    }

    fun isRunning(): Boolean = owner.running
}

/**
 * The platform answers libbox's Android questions with what this app
 * already knows: the TUN fd from VpnService.Builder.establish(), fd
 * protection via VpnService.protect(), and the device's real networks
 * from ConnectivityManager.
 */
@SuppressLint("MissingPermission")
private class LibboxPlatform(
    private val vpnService: BlackoutVpnService,
    private val tunFd: Int,
) : LibboxPlatformPolicy() {
    private val cm = vpnService.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager

    override fun openTun(options: TunOptions): Int {
        Log.i(
            "LibboxPlatform",
            "openTun: mtu=${options.mtu}, autoRoute=${options.autoRoute}, strictRoute=${options.strictRoute}",
        )
        return tunFd
    }

    override fun usePlatformAutoDetectInterfaceControl(): Boolean = true

    /** sing-box binds outbound sockets to the physical network: protect them from our own VPN. */
    override fun autoDetectInterfaceControl(fd: Int) {
        if (!vpnService.protect(fd)) {
            throw java.io.IOException("protect(fd) failed")
        }
    }

    private var monitorCallback: ConnectivityManager.NetworkCallback? = null

    override fun startDefaultInterfaceMonitor(listener: InterfaceUpdateListener) {
        try {
            val callback =
                object : ConnectivityManager.NetworkCallback() {
                    override fun onAvailable(network: Network) {
                        reportDefaultInterface(listener, network)
                    }

                    override fun onCapabilitiesChanged(
                        network: Network,
                        capabilities: NetworkCapabilities,
                    ) {
                        reportDefaultInterface(listener, network)
                    }
                }
            monitorCallback = callback
            cm.registerDefaultNetworkCallback(callback)
        } catch (_: SecurityException) {
            Log.w("LibboxPlatform", "Default interface monitoring denied")
        } catch (_: IllegalArgumentException) {
            Log.w("LibboxPlatform", "Default interface monitor rejected")
        }
    }

    private fun reportDefaultInterface(
        listener: InterfaceUpdateListener,
        network: Network,
    ) {
        try {
            val link = cm.getLinkProperties(network) ?: return
            val name = link.interfaceName ?: return
            val idx =
                try {
                    java.net.NetworkInterface
                        .getByName(name)
                        ?.index ?: -1
                } catch (_: java.net.SocketException) {
                    -1
                } catch (_: SecurityException) {
                    -1
                }
            listener.updateDefaultInterface(name, idx, false, false)
        } catch (_: SecurityException) {
            Log.w("LibboxPlatform", "Interface reporting denied")
        } catch (_: LinkageError) {
            Log.w("LibboxPlatform", "Native interface listener unavailable")
        }
    }

    override fun closeDefaultInterfaceMonitor(listener: InterfaceUpdateListener) {
        val callback = monitorCallback ?: return
        monitorCallback = null
        try {
            cm.unregisterNetworkCallback(callback)
        } catch (_: IllegalArgumentException) {
            Log.w("LibboxPlatform", "interface monitor was not registered")
        } catch (_: SecurityException) {
            Log.w("LibboxPlatform", "interface monitor close denied")
        }
    }

    @Suppress("DEPRECATION")
    override fun getInterfaces(): NetworkInterfaceIterator {
        val list = mutableListOf<NetworkInterface>()
        try {
            for (network in cm.allNetworks) {
                describeNetwork(cm, network)?.let(list::add)
            }
        } catch (_: SecurityException) {
            Log.w("LibboxPlatform", "interface enumeration denied")
        }
        return InterfaceIterator(list)
    }

    override fun packageNameByUid(uid: Int): String = vpnService.packageManager.getNameForUid(uid) ?: ""

    @Suppress("DEPRECATION")
    override fun uidByPackageName(packageName: String): Int =
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                vpnService.packageManager.getPackageUid(packageName, PackageManager.PackageInfoFlags.of(0))
            } else {
                // The pre-33 overload is required on the supported API 24-32 range.
                vpnService.packageManager.getPackageUid(packageName, 0)
            }
        } catch (_: PackageManager.NameNotFoundException) {
            -1
        } catch (_: SecurityException) {
            -1
        }

    override fun writeLog(message: String?) {
        // Native diagnostics can contain destinations, identifiers or secrets.
        // Lifecycle status is reported separately; never forward raw messages.
    }
}

/** Fixed platform policy, separate from Android network and package queries. */
private abstract class LibboxPlatformPolicy : PlatformInterface {
    override fun underNetworkExtension(): Boolean = false

    override fun includeAllNetworks(): Boolean = false

    override fun readWIFIState(): WIFIState? = null

    override fun clearDNSCache() {
        // Android owns DNS caching; this platform adapter has no cache to clear.
    }

    override fun sendNotification(notification: Notification?) {
        // The foreground-service notification is managed by BlackoutVpnService.
    }

    override fun useProcFS(): Boolean = false

    override fun findConnectionOwner(
        ipProtocol: Int,
        sourceAddress: String?,
        sourcePort: Int,
        destinationAddress: String?,
        destinationPort: Int,
    ): Int = -1
}

/** Describe only an internet-capable network with a named interface. */
@Suppress("DEPRECATION")
private fun describeNetwork(
    cm: ConnectivityManager,
    network: Network,
): NetworkInterface? {
    val link = cm.getLinkProperties(network)
    val caps = cm.getNetworkCapabilities(network)
    val name = link?.interfaceName
    if (name == null || caps == null || !caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)) {
        return null
    }
    return NetworkInterface().apply {
        index =
            try {
                java.net.NetworkInterface
                    .getByName(name)
                    ?.index ?: -1
            } catch (_: java.net.SocketException) {
                -1
            } catch (_: SecurityException) {
                -1
            }
        this.name = name
        mtu = 0
        addresses = EmptyStringIterator
        dnsServer = EmptyStringIterator
        flags = 0
        type =
            when {
                caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> 1
                caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> 2
                else -> LIBBOX_OTHER_INTERFACE
            }
    }
}

/** Empty iterator for fields the platform layer is allowed to leave blank. */
private object EmptyStringIterator : libbox.StringIterator {
    override fun hasNext(): Boolean = false

    override fun len(): Int = 0

    override fun next(): String = ""
}

private class InterfaceIterator(
    private val items: List<NetworkInterface>,
) : NetworkInterfaceIterator {
    private var index = 0

    override fun hasNext(): Boolean = index < items.size

    override fun next(): NetworkInterface = items[index++]
}
