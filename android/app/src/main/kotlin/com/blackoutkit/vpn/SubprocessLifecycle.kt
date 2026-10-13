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

    fun stop(processes: List<Process>) {
        for (process in processes.asReversed()) {
            if (isAlive(process)) process.destroy()
        }
    }

    fun waitForExit(process: Process, timeoutMs: Long): Boolean = waitFor(process, timeoutMs)
}
