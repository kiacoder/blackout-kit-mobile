package com.blackoutkit.vpn

private const val PROCESS_NANOS_PER_MILLI = 1_000_000L

/** Process lifecycle rules shared by the Android runner and JVM tests. */
internal class SubprocessLifecycle(
    private val isAlive: (Process) -> Boolean = ProcessCompat::isAlive,
    private val waitFor: (Process, Long) -> Boolean = ProcessCompat::waitForExit,
    private val sleep: (Long) -> Unit = { Thread.sleep(it) },
    private val forceStop: (Process) -> Unit = ProcessCompat::forceStop,
) {
    fun awaitStartup(
        processes: List<Process>,
        timeoutMs: Long,
        pollMs: Long = 50,
    ): String? {
        val deadline = System.nanoTime() + timeoutMs * PROCESS_NANOS_PER_MILLI
        while (System.nanoTime() < deadline) {
            val exited = processes.firstOrNull { !isAlive(it) }
            if (exited != null) {
                return try {
                    "Engine process exited during startup (code ${exited.exitValue()})."
                } catch (_: IllegalThreadStateException) {
                    "Engine process exited during startup."
                }
            }
            val remainingMs = ((deadline - System.nanoTime()).coerceAtLeast(0) / PROCESS_NANOS_PER_MILLI)
            if (remainingMs == 0L) break
            sleep(minOf(pollMs, remainingMs))
        }
        return if (processes.all(isAlive)) null else "Engine process exited during startup."
    }

    fun exitedProcess(processes: List<Process>): Process? = processes.firstOrNull { !isAlive(it) }

    /** Bounded TERM -> KILL cleanup; never discard a live process after TERM. */
    fun stop(
        processes: List<Process>,
        graceMs: Long = 500,
    ) {
        val children = processes.asReversed().distinct()
        var interrupted = Thread.interrupted()

        fun awaitExit(process: Process): Boolean =
            try {
                waitFor(process, graceMs)
            } catch (_: InterruptedException) {
                interrupted = true
                false
            }

        try {
            // Signal every child first so their grace periods can overlap.
            for (process in children) {
                if (isAlive(process)) process.destroy()
            }
            for (process in children) {
                if (isAlive(process) && !awaitExit(process) && isAlive(process)) {
                    forceStop(process)
                    // Even on interruption, attempt to confirm exit after
                    // escalation. Callers retain handles if a child is alive.
                    awaitExit(process)
                }
            }
        } finally {
            if (interrupted) Thread.currentThread().interrupt()
        }
    }

    fun waitForExit(
        process: Process,
        timeoutMs: Long,
    ): Boolean = waitFor(process, timeoutMs)
}
