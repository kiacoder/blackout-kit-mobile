package com.blackoutkit.vpn

import android.os.Build
import java.io.IOException

/** Process APIs available on our complete supported Android range (API 24+). */
internal object ProcessCompat {
    fun isAlive(process: Process): Boolean = try {
        process.exitValue()
        false
    } catch (_: IllegalThreadStateException) {
        true
    }

    /** Monotonic, interruptible wait without the API 26 timed waitFor overload. */
    fun waitForExit(process: Process, timeoutMs: Long): Boolean {
        require(timeoutMs >= 0)
        val started = System.nanoTime()
        while (isAlive(process)) {
            val remaining = timeoutMs - (System.nanoTime() - started) / 1_000_000
            if (remaining <= 0) return !isAlive(process)
            Thread.sleep(minOf(remaining, 20))
        }
        return true
    }

    fun forceStop(process: Process) {
        if (Build.VERSION.SDK_INT >= 26) {
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
                    val buffer = ByteArray(8192)
                    while (input.read(buffer) != -1) { /* discard */ }
                }
            } catch (_: IOException) { /* pipe closed during teardown */ }
        }, "blackout-process-output").apply { isDaemon = true; start() }
}
