package com.blackoutkit.vpn

import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

/** Owned by the serialized service worker. JNI connect blocks on a separate thread. */
internal class OpenVpnSession(
    private val backend: Backend,
    private val current: () -> Boolean,
) {
    interface Backend {
        fun run(report: (Boolean) -> Unit)

        fun cancel()

        fun release()
    }

    private val ended = CountDownLatch(1)
    private val connected = AtomicBoolean(false)
    private val stopping = AtomicBoolean(false)
    private val worker =
        Thread({
            try {
                backend.run { value -> connected.set(value && current() && !stopping.get()) }
            } catch (_: Exception) {
                // Never expose imported profile material in exception messages.
            } catch (_: LinkageError) {
            } finally {
                connected.set(false)
                ended.countDown()
            }
        }, "blackout-openvpn-native").apply { isDaemon = true }

    fun start() {
        worker.start()
    }

    fun isConnected(): Boolean = connected.get() && ended.count != 0L && current() && !stopping.get()

    fun awaitConnected(timeoutMs: Long): Boolean {
        val deadline = System.nanoTime() + TimeUnit.MILLISECONDS.toNanos(timeoutMs)
        while (waitingForConnection() && System.nanoTime() < deadline) {
            ended.await(POLL_MS, TimeUnit.MILLISECONDS)
        }
        return isConnected()
    }

    private fun waitingForConnection(): Boolean = current() && ended.count != 0L && !isConnected()

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
