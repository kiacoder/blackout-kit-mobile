package com.blackoutkit.vpn

private const val CHILD_NANOS_PER_MILLI = 1_000_000L
private const val CHILD_POLL_INTERVAL_MS = 25L

/** Bounded shutdown for launcher-owned children; poll must reap without blocking. */
internal class NativeChildStop(
    private val poll: (Int) -> Int,
    private val terminate: (Int) -> Unit,
    private val kill: (Int) -> Unit,
    private val sleep: (Long) -> Unit = { Thread.sleep(it) },
    private val now: () -> Long = System::nanoTime,
) {
    fun stop(
        pid: Int,
        graceMs: Long = 500,
    ): Boolean {
        require(pid > 0 && graceMs > 0)
        // Clear an existing interrupt while draining; restore it on every exit.
        var interrupted = Thread.interrupted()

        fun pause(remaining: Long): Boolean =
            try {
                sleep(minOf(CHILD_POLL_INTERVAL_MS, (remaining / CHILD_NANOS_PER_MILLI).coerceAtLeast(1)))
                true
            } catch (_: InterruptedException) {
                interrupted = true
                false
            }

        fun awaitExit(): Boolean {
            val deadline = now() + graceMs * CHILD_NANOS_PER_MILLI
            while (poll(pid) == -1) {
                val remaining = deadline - now()
                if (remaining <= 0 || !pause(remaining)) return false
            }
            return true
        }
        return try {
            if (poll(pid) != -1) return true // Do not signal an already-reaped PID.
            try {
                terminate(pid)
            } catch (_: Exception) {
            }
            if (awaitExit()) {
                true
            } else {
                try {
                    kill(pid)
                } catch (_: Exception) {
                }
                awaitExit()
            }
        } finally {
            if (interrupted) Thread.currentThread().interrupt()
        }
    }
}
