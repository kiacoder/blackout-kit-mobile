package com.blackoutkit.vpn

import android.net.VpnService
import android.os.ParcelFileDescriptor
import androidx.annotation.Keep
import java.net.Inet4Address
import java.net.Inet6Address
import java.net.InetAddress

/**
 * Private full-tunnel candidate. The core owns only the detached duplicate.
 * The service-side descriptor stays open across reconnects until the worker joins.
 */
@Keep
internal class OpenVpnTunCallbacks(
    private val service: VpnService,
    private val current: () -> Boolean,
    private val report: (Boolean) -> Unit,
) {
    private var builder: VpnService.Builder? = null

    @Volatile
    private var retained: ParcelFileDescriptor? = null
    private val routes = mutableListOf<NativeTunnelConfig.Network>()
    private val dnsServers = mutableListOf<InetAddress>()
    private val addresses = mutableListOf<InetAddress>()

    fun reset(): Boolean =
        checked {
            builder = service.Builder().setSession("OpenVPN").setBlocking(false)
            routes.clear()
            dnsServers.clear()
            addresses.clear()
        }

    fun address(
        ip: String,
        prefix: Int,
    ): Boolean =
        checked {
            require(addresses.size < MAX_ENTRIES)
            val address = NativeTunnelConfig.numericAddress(ip)
            require(!address.isAnyLocalAddress && !address.isMulticastAddress && !address.isLoopbackAddress)
            require(prefix in 0..(address.address.size * BITS_PER_BYTE))
            checkNotNull(builder).addAddress(address, prefix)
            addresses.add(address)
        }

    fun route(
        ip: String,
        prefix: Int,
    ): Boolean =
        checked {
            require(routes.size < MAX_ENTRIES)
            val address = NativeTunnelConfig.numericAddress(ip)
            require(prefix in 0..(address.address.size * BITS_PER_BYTE))
            val route = NativeTunnelConfig.Network(address, prefix).masked()
            checkNotNull(builder).addRoute(route.address, route.prefix)
            routes.add(route)
        }

    fun dns(ip: String): Boolean =
        checked {
            require(dnsServers.size < MAX_DNS)
            val address = NativeTunnelConfig.numericAddress(ip)
            require(!address.isAnyLocalAddress && !address.isMulticastAddress && !address.isLoopbackAddress)
            dnsServers.add(address)
        }

    fun mtu(value: Int): Boolean =
        checked {
            require(value in MIN_MTU..MAX_MTU)
            checkNotNull(builder).setMtu(value)
        }

    fun protect(fd: Int): Boolean = current() && fd >= 0 && service.protect(fd)

    fun establish(): Int =
        try {
            check(current())
            val pending = checkNotNull(builder)
            builder = null
            require(OpenVpnTunPolicy.admits(addresses, routes, dnsServers))
            dnsServers.forEach { pending.addDnsServer(it) }
            val next = checkNotNull(pending.establish())
            try {
                check(current())
                // establish() replaces the Android interface. Retain the new
                // descriptor before any fallible close/dup so a failure cannot
                // silently remove its routes while recovery is still active.
                val previous = retained
                retained = next
                previous?.close()
                val duplicate = next.dup()
                val detached =
                    try {
                        duplicate.detachFd()
                    } catch (failure: IllegalStateException) {
                        duplicate.close()
                        throw failure
                    }
                detached
            } finally {
                if (retained !== next) next.close()
            }
        } catch (_: Exception) {
            -1
        }

    fun connected(value: Boolean) {
        if (current()) report(value)
    }

    val hasTunnel: Boolean
        get() = retained != null

    /** Call only after the native worker has exited. */
    fun closeAfterJoin() {
        retained?.close()
        retained = null
        builder = null
    }

    private inline fun checked(action: () -> Unit): Boolean =
        try {
            if (!current()) {
                false
            } else {
                action()
                true
            }
        } catch (_: Exception) {
            false
        }

    private companion object {
        const val BITS_PER_BYTE = 8
        const val MIN_MTU = 1280
        const val MAX_MTU = 9000
        const val MAX_ENTRIES = 256
        const val MAX_DNS = 16
    }
}

/** Validate the actual platform address families before installing the interface. */
internal object OpenVpnTunPolicy {
    fun admits(
        addresses: List<InetAddress>,
        routes: List<NativeTunnelConfig.Network>,
        dns: List<InetAddress>,
    ): Boolean {
        val full4 = routes.any { it.address is Inet4Address && it.prefix == 0 }
        val full6 = routes.any { it.address is Inet6Address && it.prefix == 0 }
        val address4 = addresses.any { it is Inet4Address }
        val address6 = addresses.any { it is Inet6Address }
        val uses6 = address6 || routes.any { it.address is Inet6Address } || dns.any { it is Inet6Address }
        val safe6 = !uses6 || (address6 && full6)
        return full4 &&
            address4 &&
            safe6 &&
            dns.isNotEmpty() &&
            dns.all { ip -> !ip.isLinkLocalAddress && routes.any { it.contains(ip) } }
    }
}
