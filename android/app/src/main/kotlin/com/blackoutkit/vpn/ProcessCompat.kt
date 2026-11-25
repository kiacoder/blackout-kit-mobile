package com.blackoutkit.vpn

import android.os.Build
import java.io.IOException

/** Process APIs available on our complete supported Android range (API 24+). */
internal object ProcessCompat {
    private const val NANOS_PER_MILLI = 1_000_000L
    private const val POLL_INTERVAL_MS = 20L
    private const val FORCIBLE_DESTROY_MIN_API = 26
    private const val DRAIN_BUFFER_BYTES = 8192

    fun isAlive(process: Process): Boolean =
        try {
            process.exitValue()
            false
        } catch (_: IllegalThreadStateException) {
            true
        }

    /** Monotonic, interruptible wait without the API 26 timed waitFor overload. */
    fun waitForExit(
        process: Process,
        timeoutMs: Long,
    ): Boolean {
        require(timeoutMs >= 0)
        val started = System.nanoTime()
        while (isAlive(process)) {
            val remaining = timeoutMs - (System.nanoTime() - started) / NANOS_PER_MILLI
            if (remaining <= 0) return !isAlive(process)
            Thread.sleep(minOf(remaining, POLL_INTERVAL_MS))
        }
        return true
    }

    fun forceStop(process: Process) {
        if (Build.VERSION.SDK_INT >= FORCIBLE_DESTROY_MIN_API) {
            process.destroyForcibly()
        } else {
            // API 24/25 exposes only destroy(). Callers must check exit and
            // retain unresolved handles; this fallback is not a kill guarantee.
            process.destroy()
        }
    }

    /** No files, shell wrapper, credentials in logs, or unbounded buffering. */
    fun startQuietly(command: List<String>): Process {
        val process = ProcessBuilder(command).redirectErrorStream(true).start()
        try {
            discardOutput(process)
            return process
        } catch (e: Exception) {
            forceStop(process)
            throw e
        }
    }

    internal fun discardOutput(process: Process): Thread =
        Thread({
            try {
                process.inputStream.use { input ->
                    val buffer = ByteArray(DRAIN_BUFFER_BYTES)
                    while (input.read(buffer) != -1) { /* discard */ }
                }
            } catch (_: IOException) {
                // pipe closed during teardown
            }
        }, "blackout-process-output").apply {
            isDaemon = true
            start()
        }
}
