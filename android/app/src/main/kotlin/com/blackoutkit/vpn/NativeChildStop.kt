package com.blackoutkit.vpn

/** Bounded shutdown for launcher-owned children; poll must reap without blocking. */
internal class NativeChildStop(
    private val poll: (Int) -> Int,
    private val terminate: (Int) -> Unit,
    private val kill: (Int) -> Unit,
    private val sleep: (Long) -> Unit = { Thread.sleep(it) },
    private val now: () -> Long = System::nanoTime,
) {
    fun stop(pid: Int, graceMs: Long = 500): Boolean {
        require(pid > 0 && graceMs > 0)
        // Clear an existing interrupt while draining; restore it on every exit.
        var interrupted = Thread.interrupted()
        fun awaitExit(): Boolean {
            val deadline = now() + graceMs * 1_000_000
            while (poll(pid) == -1) {
                val remaining = deadline - now()
                if (remaining <= 0) return false
                try { sleep(minOf(25, (remaining / 1_000_000).coerceAtLeast(1))) }
                catch (_: InterruptedException) { interrupted = true; return false }
            }
            return true
        }
        return try {
            if (poll(pid) != -1) return true // Do not signal an already-reaped PID.
            try { terminate(pid) } catch (_: Exception) { }
            if (awaitExit()) return true
            try { kill(pid) } catch (_: Exception) { }
            awaitExit()
        } finally {
            if (interrupted) Thread.currentThread().interrupt()
        }
    }
}
