package com.blackoutkit.vpn

import android.net.VpnService
import android.os.ParcelFileDescriptor
import androidx.annotation.Keep
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
    private var retained: ParcelFileDescriptor? = null
    private val routes = mutableListOf<NativeTunnelConfig.Network>()
    private val dnsServers = mutableListOf<InetAddress>()
    private var addressCount = 0

    fun reset(): Boolean =
        checked {
            builder = service.Builder().setSession("OpenVPN").setBlocking(true)
            routes.clear()
            dnsServers.clear()
            addressCount = 0
        }

    fun address(
        ip: String,
        prefix: Int,
    ): Boolean =
        checked {
            require(addressCount < MAX_ENTRIES)
            val address = NativeTunnelConfig.numericAddress(ip)
            require(!address.isAnyLocalAddress && !address.isMulticastAddress && !address.isLoopbackAddress)
            require(prefix in 0..(address.address.size * BITS_PER_BYTE))
            checkNotNull(builder).addAddress(address, prefix)
            addressCount++
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
            require(addressCount > 0 && dnsServers.isNotEmpty())
            require(dnsServers.all { ip -> routes.any { it.contains(ip) } })
            dnsServers.forEach { pending.addDnsServer(it) }
            val next = checkNotNull(pending.establish())
            try {
                check(current())
                // Close the old service descriptor before transferring the new
                // duplicate, so a close failure cannot orphan a detached fd.
                retained?.close()
                retained = null
                val duplicate = next.dup()
                val detached =
                    try {
                        duplicate.detachFd()
                    } catch (failure: IllegalStateException) {
                        duplicate.close()
                        throw failure
                    }
                retained = next
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
