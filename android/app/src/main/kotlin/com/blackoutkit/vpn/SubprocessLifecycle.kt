package com.blackoutkit.vpn

/** Process lifecycle rules shared by the Android runner and JVM tests. */
internal class SubprocessLifecycle(
    private val isAlive: (Process) -> Boolean = { it.isAlive },
    private val waitFor: (Process, Long) -> Boolean = { process, timeout ->
        process.waitFor(timeout, java.util.concurrent.TimeUnit.MILLISECONDS)
    },
    private val sleep: (Long) -> Unit = { Thread.sleep(it) },
) {
    fun awaitStartup(processes: List<Process>, timeoutMs: Long, pollMs: Long = 50): String? {
        val deadline = System.nanoTime() + timeoutMs * 1_000_000
        while (System.nanoTime() < deadline) {
            val exited = processes.firstOrNull { !isAlive(it) }
            if (exited != null) {
                return try {
                    "Engine process exited during startup (code ${exited.exitValue()})."
                } catch (_: IllegalThreadStateException) {
                    "Engine process exited during startup."
                }
            }
            val remainingMs = ((deadline - System.nanoTime()).coerceAtLeast(0) / 1_000_000)
            if (remainingMs == 0L) break
            sleep(minOf(pollMs, remainingMs))
        }
        return if (processes.all(isAlive)) null else "Engine process exited during startup."
    }

    fun exitedProcess(processes: List<Process>): Process? = processes.firstOrNull { !isAlive(it) }

    /** Bounded TERM -> KILL cleanup; never discard a live process after TERM. */
    fun stop(processes: List<Process>, graceMs: Long = 500) {
        val children = processes.asReversed().distinct()
        var interrupted = false
        // Signal every child first so their grace periods can overlap.
        for (process in children) {
            if (isAlive(process)) process.destroy()
        }
        for (process in children) {
            try {
                if (isAlive(process) && !waitFor(process, graceMs)) {
                    process.destroyForcibly()
                    waitFor(process, graceMs)
                }
            } catch (_: InterruptedException) {
                // A monitor interrupt must not leave a core holding a SOCKS
                // port. Continue cleanup, then restore the caller's flag.
                interrupted = true
                if (isAlive(process)) process.destroyForcibly()
            }
        }
        if (interrupted) Thread.currentThread().interrupt()
    }

    fun waitForExit(process: Process, timeoutMs: Long): Boolean = waitFor(process, timeoutMs)
}
