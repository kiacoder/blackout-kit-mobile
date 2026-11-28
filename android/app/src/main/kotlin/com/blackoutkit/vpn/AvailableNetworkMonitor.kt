package com.blackoutkit.vpn

import android.annotation.SuppressLint
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.util.Log

/** A passive observer, not a request to create or bind a network. */
@SuppressLint("MissingPermission")
internal class AvailableNetworkMonitor(
    private val manager: ConnectivityManager,
) {
    private val registry = AvailableNetworkRegistry<Network>()
    private val callback =
        object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                registry.available(network)
            }

            override fun onLost(network: Network) {
                registry.lost(network)
            }
        }
    private var registered = false

    @Volatile
    private var closed = false

    @Synchronized
    fun start() {
        if (closed || registered) return
        try {
            val request =
                NetworkRequest
                    .Builder()
                    .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
                    .removeCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN)
                    .removeCapability(NetworkCapabilities.NET_CAPABILITY_NOT_RESTRICTED)
                    .removeCapability(NetworkCapabilities.NET_CAPABILITY_TRUSTED)
                    .build()
            manager.registerNetworkCallback(request, callback)
            registered = true
        } catch (_: SecurityException) {
            Log.w("AvailableNetworks", "Network observation denied")
        } catch (_: IllegalArgumentException) {
            Log.w("AvailableNetworks", "Network observation rejected")
        }
    }

    /** Initial callbacks are asynchronous. The active network is a safe initial snapshot. */
    fun snapshot(): List<Network> {
        if (closed) return emptyList()
        val observed = registry.snapshot()
        return if (observed.isEmpty()) {
            try {
                listOfNotNull(manager.activeNetwork)
            } catch (_: SecurityException) {
                emptyList()
            }
        } else {
            observed
        }
    }

    /** Passive physical-network membership, never the VPN's own network.
     * Null means observation is unavailable, not that all networks disappeared.
     */
    @Synchronized
    fun underlyingSnapshot(): Set<Long>? {
        if (closed || !registered) return null
        return try {
            registry
                .snapshot()
                .filter { network ->
                    manager.getNetworkCapabilities(network)?.let {
                        it.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) &&
                            it.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN)
                    } == true
                }.map { it.networkHandle }
                .toSet()
        } catch (_: SecurityException) {
            null
        }
    }

    @Synchronized
    fun close() {
        if (closed) return
        closed = true
        registry.close()
        if (registered) {
            registered = false
            try {
                manager.unregisterNetworkCallback(callback)
            } catch (_: IllegalArgumentException) {
                Log.w("AvailableNetworks", "Network observer already unregistered")
            } catch (_: SecurityException) {
                Log.w("AvailableNetworks", "Network observer cleanup denied")
            }
        }
    }
}
