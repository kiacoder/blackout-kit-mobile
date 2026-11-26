package com.blackoutkit.vpn

import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicLong

/**
 * One serialized owner of engine/TUN mutations. Requests invalidate older tickets
 * immediately, without waiting on the Android main thread for native startup.
 * A cancelled native start MUST return before its resources can be safely released;
 * this class does not pretend it can interrupt arbitrary blocking JNI code.
 */
internal class VpnSessionExecutor(
    private val dispatch: ((() -> Unit) -> Unit),
    private val worker: ExecutorService =
        Executors.newSingleThreadExecutor { task ->
            Thread(task, "blackout-vpn-session").apply { isDaemon = true }
        },
) {
    private val generation = AtomicLong()
    private val gate = Any()
    private var closed = false

    inner class Ticket internal constructor(
        private val value: Long,
    ) {
        fun isCurrent(): Boolean = generation.get() == value

        fun publish(action: () -> Unit) {
            dispatch { if (isCurrent()) action() }
        }
    }

    /** cleanup and start run only on the owner thread, never concurrently. */
    fun start(
        cleanup: () -> Unit,
        start: (Ticket) -> Boolean,
        complete: (Boolean) -> Unit,
    ): Ticket? =
        synchronized(gate) {
            if (closed) return@synchronized null
            val ticket = Ticket(generation.incrementAndGet())
            worker.execute {
                if (!ticket.isCurrent()) return@execute
                var success = false
                try {
                    cleanup()
                    if (ticket.isCurrent()) success = start(ticket)
                } catch (_: Exception) {
                    // Native error messages may contain profile secrets. The adapter
                    // owns user-safe diagnostics; the coordinator reports failure only.
                } catch (_: LinkageError) {
                    // Missing/wrong ABI native library must not kill the process.
                } finally {
                    if (!success || !ticket.isCurrent()) {
                        try {
                            cleanup()
                        } catch (_: Exception) {
                        } catch (_: LinkageError) {
                        }
                    }
                }
                ticket.publish { complete(success) }
            }
            ticket
        }

    /**
     * Stop completion always settles its OWN caller, even if a newer start was
     * requested meanwhile. The boolean tells the caller whether it may publish
     * a terminal UI state / stop the Android service without stopping that start.
     */
    fun stop(
        cleanup: () -> Unit,
        complete: (current: Boolean, cleaned: Boolean) -> Unit = { _, _ -> },
        close: Boolean = false,
    ) = synchronized(gate) {
        if (closed) return@synchronized
        val ticket = Ticket(generation.incrementAndGet())
        if (close) closed = true
        worker.execute {
            var cleaned = false
            try {
                cleanup()
                cleaned = true
            } catch (_: Exception) {
            } catch (_: LinkageError) {
            }
            dispatch { complete(ticket.isCurrent(), cleaned) }
        }
        if (close) worker.shutdown() // drain queued cleanup; never interrupt JNI
    }

    /** Late death callbacks from an old engine may not tear down a new session. */
    fun forCurrent(
        ticket: Ticket,
        action: () -> Unit,
    ) = synchronized(gate) {
        if (closed || !ticket.isCurrent()) return@synchronized
        worker.execute { if (ticket.isCurrent()) action() }
    }
}
