package com.blackoutkit.vpn

import java.io.File
import java.io.IOException

private const val CHECK_CLEANUP_MS = 500L
private const val MAX_ENGINE_CONFIG_BYTES = 8L * 1024 * 1024

/** Actual CLI contracts, not protocol counts. No shell or user-supplied executable. */
internal enum class EngineCommands(
    val binary: String,
    val configName: String,
) {
    SING_BOX("libsingbox.so", "singbox.json"),
    MIHOMO("libmihomo.so", "mihomo.json"),
    ;

    fun check(
        executable: File,
        config: File,
    ): List<String> =
        when (this) {
            SING_BOX -> listOf(executable.absolutePath, "check", "-c", config.absolutePath)
            MIHOMO -> listOf(executable.absolutePath, "-t", "-d", config.parent!!, "-f", config.absolutePath)
        }

    fun run(
        executable: File,
        config: File,
    ): List<String> =
        when (this) {
            SING_BOX -> listOf(executable.absolutePath, "run", "-c", config.absolutePath)
            MIHOMO -> listOf(executable.absolutePath, "-d", config.parent!!, "-f", config.absolutePath)
        }

    companion object {
        fun forProtocol(protocol: String): EngineCommands? =
            when (protocol.lowercase()) {
                "hysteria2", "tuic", "anytls" -> SING_BOX
                "mihomo" -> MIHOMO
                else -> null
            }
    }
}

internal data class CommandOutcome(
    val exitCode: Int? = null,
    val timedOut: Boolean = false,
    val interrupted: Boolean = false,
    val launchFailed: Boolean = false,
    val cleanupPending: Boolean = false,
) {
    val succeeded: Boolean get() = exitCode == 0 && !timedOut && !interrupted && !launchFailed && !cleanupPending
}

/**
 * Bounded native-check subprocess. Output is deliberately discarded: native
 * parsers can echo passwords, keys or complete input lines in their errors.
 * No unbounded readText, common-pool worker, or persistent diagnostic file.
 */
internal class BoundedEngineCommand(
    private val launch: (List<String>) -> Process = ProcessCompat::startQuietly,
    private val waitFor: (Process, Long) -> Boolean = ProcessCompat::waitForExit,
    private val forceStop: (Process) -> Unit = ProcessCompat::forceStop,
) {
    private class PendingCheck(
        val process: Process,
        val config: File?,
    )

    @Volatile
    private var pending: PendingCheck? = null

    @Synchronized
    fun execute(
        command: List<String>,
        timeoutMs: Long = 20_000,
        config: File? = null,
    ): CommandOutcome {
        require(command.isNotEmpty() && timeoutMs > 0)
        return if (!retryCleanup()) {
            CommandOutcome(cleanupPending = true)
        } else {
            executeOwned(command, timeoutMs, config)
        }
    }

    private fun executeOwned(
        command: List<String>,
        timeoutMs: Long,
        config: File?,
    ): CommandOutcome {
        val process =
            try {
                launch(command)
            } catch (_: IOException) {
                return CommandOutcome(launchFailed = true)
            }
        pending = PendingCheck(process, config)
        val cleaned: Boolean
        val outcome =
            try {
                if (waitFor(process, timeoutMs)) {
                    CommandOutcome(exitCode = process.exitValue())
                } else {
                    CommandOutcome(timedOut = true)
                }
            } catch (_: InterruptedException) {
                Thread.currentThread().interrupt()
                CommandOutcome(interrupted = true)
            } finally {
                cleaned = retryCleanup()
            }
        return if (cleaned) outcome else outcome.copy(cleanupPending = true)
    }

    /** Retain the exact process and file until its exit has been confirmed. */
    private fun retryCleanup(): Boolean {
        val owned = pending ?: return true
        val process = owned.process
        var interrupted = Thread.interrupted()
        return try {
            if (ProcessCompat.isAlive(process)) forceStop(process)
            if (waitFor(process, CHECK_CLEANUP_MS)) {
                pending = null
                closeStreams(process)
                true
            } else {
                false
            }
        } catch (_: InterruptedException) {
            interrupted = true
            false
        } catch (_: IllegalStateException) {
            false
        } catch (_: SecurityException) {
            false
        } finally {
            if (interrupted) Thread.currentThread().interrupt()
        }
    }

    private fun closeStreams(process: Process) {
        try {
            process.outputStream.close()
            process.errorStream.close()
        } catch (_: IOException) {
            // The drain thread owns stdout; never close it from this thread.
        }
    }

    /** Callers must not delete a file still owned by a checker. */
    fun releaseConfig(file: File): Boolean {
        if (pending?.config != file) return true
        return synchronized(this) {
            pending?.config != file || retryCleanup()
        }
    }

    companion object {
        val process = BoundedEngineCommand()
    }
}

internal data class NativeValidation(
    val valid: Boolean,
    val code: String,
    val message: String,
)

internal class NativeConfigValidator(
    private val commands: BoundedEngineCommand = BoundedEngineCommand.process,
) {
    fun validate(
        engine: EngineCommands,
        executable: File,
        config: File,
        timeoutMs: Long = 20_000,
    ): NativeValidation {
        if (!executable.isFile || !executable.canExecute()) {
            return NativeValidation(
                false,
                "RUNTIME_UNAVAILABLE",
                "The selected native engine is not installed or executable.",
            )
        }
        return if (!config.isFile || config.length() == 0L || config.length() > MAX_ENGINE_CONFIG_BYTES) {
            NativeValidation(
                false,
                "INVALID_INPUT",
                "Engine configuration is missing, empty or larger than 8 MiB.",
            )
        } else {
            validationOutcome(commands.execute(engine.check(executable, config), timeoutMs, config))
        }
    }

    private fun validationOutcome(result: CommandOutcome): NativeValidation =
        when {
            result.succeeded ->
                NativeValidation(
                    true,
                    "NATIVE_VALIDATED",
                    "The installed engine accepted the configuration; connectivity is not tested.",
                )
            result.cleanupPending ->
                NativeValidation(
                    false,
                    "CHECK_CLEANUP_PENDING",
                    "Previous engine checker has not stopped. Retry after cleanup.",
                )
            result.timedOut -> NativeValidation(false, "CHECK_TIMEOUT", "Engine configuration validation timed out.")
            result.interrupted -> NativeValidation(false, "CANCELLED", "Engine configuration validation was cancelled.")
            result.launchFailed ->
                NativeValidation(
                    false,
                    "LAUNCH_FAILED",
                    "Could not launch the engine configuration checker.",
                )
            else ->
                NativeValidation(
                    false,
                    "CONFIG_REJECTED",
                    "The installed engine rejected the configuration (exit ${result.exitCode}). " +
                        "Raw diagnostics are withheld to protect credentials.",
                )
        }
}
