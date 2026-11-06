package com.blackoutkit.vpn

import android.annotation.SuppressLint
import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
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
import java.util.concurrent.atomic.AtomicBoolean

/**
 * In-process libbox core (embedded sing-box, no subprocess).
 *
 * This is the Android twin of the iOS tunnel extension's libbox core: the
 * same libbox.aar grammar (pinned sing-box v1.11.4, matching the bundled
 * libsingbox.so), but instead of the tunnel extension handing over a TUN
 * fd, [BlackoutVpnService] passes the fd it established and this engine
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

    private var service: BoxService? = null
    private val running = AtomicBoolean(false)

    /**
     * A version is returned only when the generated bindings respond. Do not
     * substitute a compile-time guess here: callers use this probe to decide
     * whether the embedded runtime is actually loadable on this ABI.
     */
    fun version(): String? = try {
        Libbox.version()?.takeIf { it.isNotBlank() && it != "unknown" }
    } catch (e: Throwable) {
        Log.w(TAG, "libbox version probe failed: ${e.javaClass.simpleName}: ${e.message}")
        null
    }

    /** True only when a libbox call successfully reaches the embedded runtime. */
    fun isAvailable(): Boolean = try {
        Libbox.version() != null
    } catch (e: Throwable) {
        Log.w(TAG, "libbox availability probe failed: ${e.javaClass.simpleName}: ${e.message}")
        false
    }

    /**
     * Starts the embedded core. The core dups the fd it receives via
     * [openTun][LibboxPlatform.openTun], so [tunFd] stays owned by the
     * VpnService and is closed by its usual [teardown][BlackoutVpnService.teardown].
     */
    fun start(vpnService: BlackoutVpnService, tunFd: Int, configJson: String): Boolean {
        if (running.get()) {
            Log.w(TAG, "start() while already running - stopping the old service first")
            stop()
        }
        lastError = null
        val svc = try {
            Libbox.newService(configJson, LibboxPlatform(vpnService, tunFd))
        } catch (e: Exception) {
            lastError = "libbox config rejected: ${e.message}"
            Log.e(TAG, lastError!!, e)
            return false
        }
        try {
            svc.start()
        } catch (e: Exception) {
            lastError = "libbox core failed to start: ${e.message}"
            Log.e(TAG, lastError!!, e)
            try {
                svc.close()
            } catch (closeError: Exception) {
                Log.w(TAG, "closing a failed core also failed: ${closeError.message}")
            }
            return false
        }
        service = svc
        running.set(true)
        Log.i(TAG, "libbox core started (version ${version()})")
        return true
    }

    fun stop() {
        val svc = service ?: return
        service = null
        running.set(false)
        try {
            svc.close()
        } catch (e: Exception) {
            Log.w(TAG, "libbox close error: ${e.message}")
        }
        Log.i(TAG, "libbox core stopped")
    }

    fun isRunning(): Boolean = running.get()
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
    private val tunFd: Int
) : PlatformInterface {
    private val cm = vpnService.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager

    override fun openTun(options: TunOptions): Int {
        Log.i(
            "LibboxPlatform",
            "openTun: mtu=${options.mtu}, autoRoute=${options.autoRoute}, strictRoute=${options.strictRoute}"
        )
        return tunFd
    }

    override fun usePlatformAutoDetectInterfaceControl(): Boolean = true

    /** sing-box binds outbound sockets to the physical network: protect them from our own VPN. */
    override fun autoDetectInterfaceControl(fd: Int) {
        if (!vpnService.protect(fd)) {
            throw Exception("protect(fd) failed")
        }
    }

    private var monitorCallback: ConnectivityManager.NetworkCallback? = null

    override fun startDefaultInterfaceMonitor(listener: InterfaceUpdateListener) {
        try {
            val callback = object : ConnectivityManager.NetworkCallback() {
                override fun onAvailable(network: Network) {
                    reportDefaultInterface(listener, network)
                }

                override fun onCapabilitiesChanged(network: Network, capabilities: NetworkCapabilities) {
                    reportDefaultInterface(listener, network)
                }
            }
            monitorCallback = callback
            cm.registerDefaultNetworkCallback(callback)
        } catch (e: Exception) {
            Log.w("LibboxPlatform", "default interface monitor unavailable: ${e.message}")
        }
    }

    private fun reportDefaultInterface(listener: InterfaceUpdateListener, network: Network) {
        try {
            val link = cm.getLinkProperties(network) ?: return
            val name = link.interfaceName ?: return
            val idx = try { java.net.NetworkInterface.getByName(name)?.index ?: -1 } catch (_: Exception) { -1 }
            listener.updateDefaultInterface(name, idx, false, false)
        } catch (e: Exception) {
            Log.w("LibboxPlatform", "interface report failed: ${e.message}")
        }
    }

    override fun closeDefaultInterfaceMonitor(listener: InterfaceUpdateListener) {
        val callback = monitorCallback ?: return
        monitorCallback = null
        try {
            cm.unregisterNetworkCallback(callback)
        } catch (e: Exception) {
            Log.w("LibboxPlatform", "interface monitor close failed: ${e.message}")
        }
    }

    @Suppress("DEPRECATION")
    override fun getInterfaces(): NetworkInterfaceIterator {
        val list = mutableListOf<NetworkInterface>()
        try {
            for (network in cm.allNetworks) {
                val link = cm.getLinkProperties(network) ?: continue
                val caps = cm.getNetworkCapabilities(network) ?: continue
                if (!caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)) continue
                val iface = NetworkInterface()
                val name = link.interfaceName ?: continue
                iface.index = try {
                    java.net.NetworkInterface.getByName(name)?.index ?: -1
                } catch (_: Exception) { -1 }
                iface.name = name
                iface.mtu = 0
                iface.addresses = EmptyStringIterator
                iface.dnsServer = EmptyStringIterator
                iface.flags = 0
                iface.type = when {
                    caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> 1
                    caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> 2
                    else -> 4
                }
                list.add(iface)
            }
        } catch (e: Exception) {
            Log.w("LibboxPlatform", "interface enumeration failed: ${e.message}")
        }
        return InterfaceIterator(list)
    }

    override fun underNetworkExtension(): Boolean = false

    override fun includeAllNetworks(): Boolean = false

    override fun readWIFIState(): WIFIState? = null

    override fun clearDNSCache() {}

    override fun sendNotification(notification: Notification?) {
        // The foreground-service notification is managed by BlackoutVpnService.
    }

    override fun useProcFS(): Boolean = false

    override fun findConnectionOwner(
        ipProtocol: Int,
        sourceAddress: String?,
        sourcePort: Int,
        destinationAddress: String?,
        destinationPort: Int
    ): Int = -1

    override fun packageNameByUid(uid: Int): String =
        vpnService.packageManager.getNameForUid(uid) ?: ""

    @Suppress("DEPRECATION")
    override fun uidByPackageName(packageName: String): Int = try {
        vpnService.packageManager.getPackageUid(packageName, 0)
    } catch (e: Exception) {
        -1
    }

    override fun writeLog(message: String?) {
        Log.i("Libbox", message ?: "")
    }
}

/** Empty iterator for fields the platform layer is allowed to leave blank. */
private object EmptyStringIterator : libbox.StringIterator {
    override fun hasNext(): Boolean = false
    override fun len(): Int = 0
    override fun next(): String = ""
}

private class InterfaceIterator(private val items: List<NetworkInterface>) :
    NetworkInterfaceIterator {
    private var index = 0
    override fun hasNext(): Boolean = index < items.size
    override fun next(): NetworkInterface = items[index++]
}
