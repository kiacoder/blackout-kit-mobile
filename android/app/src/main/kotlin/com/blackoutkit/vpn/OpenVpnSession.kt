package com.blackoutkit.vpn

import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

/** Owned by the serialized service worker. JNI connect blocks on a separate thread. */
internal class OpenVpnSession(
    private val backend: Backend,
    private val recoveryMs: Long = 45_000L,
    private val now: () -> Long = System::nanoTime,
    private val current: () -> Boolean,
) {
    interface Backend {
        fun run(report: (Boolean) -> Unit)

        fun reconnect(): Boolean = false

        fun cancel()

        fun release()
    }

    enum class Link {
        CONNECTED,
        RECOVERING,
        ENDED,
    }

    private val ended = CountDownLatch(1)
    private val connected = AtomicBoolean(false)
    private val stopping = AtomicBoolean(false)
    private var hasConnected = false
    private var downSince: Long? = null
    private var expired = false
    private val handover = OpenVpnNetworkChanges()
    private val worker =
        Thread({
            try {
                backend.run(::report)
            } catch (_: Exception) {
                // Never expose imported profile material in exception messages.
            } catch (_: LinkageError) {
            } finally {
                connected.set(false)
                ended.countDown()
            }
        }, "blackout-openvpn-native").apply { isDaemon = true }

    @Synchronized
    private fun report(value: Boolean) {
        if (!current() || stopping.get() || expired) return
        if (value) {
            if (deadlinePassed()) {
                expired = true
                connected.set(false)
                return
            }
            hasConnected = true
            downSince = null
        } else if (hasConnected && downSince == null) {
            downSince = now()
        }
        connected.set(value)
    }

    private fun deadlinePassed(): Boolean =
        downSince?.let { now() - it >= TimeUnit.MILLISECONDS.toNanos(recoveryMs) } ?: false

    @Synchronized
    fun link(): Link =
        when {
            !current() || stopping.get() || ended.count == 0L || expired || deadlinePassed() -> {
                expired = true
                Link.ENDED
            }
            connected.get() -> Link.CONNECTED
            else -> Link.RECOVERING
        }

    /** Called by the serialized service monitor, not the native callback thread. */
    fun observeNetworks(networks: Set<Long>?) {
        val request =
            synchronized(this) {
                hasConnected && link() != Link.ENDED && handover.observe(networks)
            }
        if (request && current() && !stopping.get()) backend.reconnect()
    }

    fun start() {
        worker.start()
    }

    fun isConnected(): Boolean = link() == Link.CONNECTED

    fun awaitConnected(timeoutMs: Long): Boolean {
        val deadline = System.nanoTime() + TimeUnit.MILLISECONDS.toNanos(timeoutMs)
        while (link() == Link.RECOVERING && System.nanoTime() < deadline) {
            ended.await(POLL_MS, TimeUnit.MILLISECONDS)
        }
        return isConnected()
    }

    /** Retain ownership if native cancellation does not settle. Never close TUN underneath JNI. */
    fun stop(timeoutMs: Long) {
        stopping.set(true)
        connected.set(false)
        backend.cancel()
        worker.join(timeoutMs)
        check(!worker.isAlive) { "OpenVPN worker cleanup pending" }
        backend.release()
    }

    private companion object {
        const val POLL_MS = 50L
    }
}

/** Two identical observations debounce transient membership changes. */
internal class OpenVpnNetworkChanges {
    private var stable: Set<Long>? = null
    private var pending: Set<Long>? = null

    fun observe(networks: Set<Long>?): Boolean =
        when {
            networks == null || networks == stable -> {
                pending = null
                false
            }
            pending != networks -> {
                pending = networks.toSet()
                false
            }
            else -> {
                val previous = stable
                stable = networks.toSet()
                pending = null
                // Do not force a reconnect into an empty network set.
                previous != null && networks.isNotEmpty()
            }
        }
}
