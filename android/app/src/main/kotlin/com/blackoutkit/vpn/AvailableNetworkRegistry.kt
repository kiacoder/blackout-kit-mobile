package com.blackoutkit.vpn

/** Thread-safe observation cache; a late callback cannot repopulate a closed registry. */
internal class AvailableNetworkRegistry<T : Any> {
    private val networks = linkedSetOf<T>()
    private var closed = false

    @Synchronized
    fun available(network: T) {
        if (!closed) networks.add(network)
    }

    @Synchronized
    fun lost(network: T) {
        networks.remove(network)
    }

    @Synchronized
    fun snapshot(): List<T> = networks.toList()

    @Synchronized
    fun close() {
        closed = true
        networks.clear()
    }
}
