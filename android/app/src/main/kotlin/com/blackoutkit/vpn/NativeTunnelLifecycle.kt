package com.blackoutkit.vpn

/** Testable ownership boundary. A resolved turnOn consumes fd on every return.
 * Only an unresolved JNI entry leaves the detached fd for the caller to close.
 */
internal class NativeTunnelLifecycle {
    interface Backend {
        fun turnOn(fd: Int, settings: String): Int
        fun turnOff(handle: Int)
        fun sockets(handle: Int): List<Int>
        fun isClosed(handle: Int): Boolean
    }
    private var handle = -1
    private var backend: Backend? = null
    var lastError: String? = null
        private set

    @Synchronized fun start(next: Backend, settings: String, detach: () -> Int,
        closeUndelivered: (Int) -> Unit, protect: (Int) -> Boolean): Boolean {
        lastError = null
        if (handle >= 0) { lastError = "A native tunnel is already active"; return false }
        val fd = detach()
        val started = try { next.turnOn(fd, settings) } catch (_: LinkageError) {
            closeUndelivered(fd)
            lastError = "Native tunnel entry point is unavailable"
            return false
        }
        if (started < 0) { lastError = "Native tunnel rejected configuration or could not start"; return false }
        handle = started
        backend = next
        try {
            val sockets = next.sockets(handle)
            check(sockets.any { it >= 0 })
            for (socket in sockets) if (socket >= 0) check(protect(socket))
            check(!next.isClosed(handle))
            return true
        } catch (_: Exception) {
            lastError = "Native tunnel stopped or its sockets could not be protected"
        } catch (_: LinkageError) {
            lastError = "Native tunnel socket entry point is unavailable"
        }
        stop()
        return false
    }

    /** Closed/unknown means fail closed, not a claim about handshake or reachability. */
    @Synchronized fun isClosed(): Boolean {
        if (handle < 0) return true
        return try { backend!!.isClosed(handle) }
        catch (_: Exception) { true }
        catch (_: LinkageError) { true }
    }

    @Synchronized fun stop() {
        if (handle < 0) return
        // Retain ownership if cleanup throws; never start a replacement over it.
        backend!!.turnOff(handle)
        handle = -1
        backend = null
    }
}
