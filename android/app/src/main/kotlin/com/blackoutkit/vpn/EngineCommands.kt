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
) {
    val succeeded: Boolean get() = exitCode == 0 && !timedOut && !interrupted && !launchFailed
}

/**
 * Bounded native-check subprocess. Output is deliberately discarded: native
 * parsers can echo passwords, keys or complete input lines in their errors.
 * No unbounded readText, common-pool worker, or persistent diagnostic file.
 */
internal class BoundedEngineCommand {
    fun execute(
        command: List<String>,
        timeoutMs: Long = 20_000,
    ): CommandOutcome {
        require(command.isNotEmpty() && timeoutMs > 0)
        val process =
            try {
                ProcessCompat.startQuietly(command)
            } catch (_: IOException) {
                return CommandOutcome(launchFailed = true)
            }
        var interrupted = false
        return try {
            if (!ProcessCompat.waitForExit(process, timeoutMs)) {
                CommandOutcome(timedOut = true)
            } else {
                CommandOutcome(exitCode = process.exitValue())
            }
        } catch (_: InterruptedException) {
            interrupted = true
            CommandOutcome(interrupted = true)
        } finally {
            if (ProcessCompat.isAlive(process)) ProcessCompat.forceStop(process)
            try {
                // The drain thread owns stdout; never close it from this
                // thread, even after exit (a descendant may hold the pipe).
                if (ProcessCompat.waitForExit(process, CHECK_CLEANUP_MS)) {
                    process.outputStream.close()
                    process.errorStream.close()
                }
            } catch (_: InterruptedException) {
                interrupted = true
            } catch (_: IOException) {
            }
            if (interrupted) Thread.currentThread().interrupt()
        }
    }
}

internal data class NativeValidation(
    val valid: Boolean,
    val code: String,
    val message: String,
)

internal class NativeConfigValidator(
    private val commands: BoundedEngineCommand = BoundedEngineCommand(),
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
        if (!config.isFile || config.length() == 0L || config.length() > MAX_ENGINE_CONFIG_BYTES) {
            return NativeValidation(
                false,
                "INVALID_INPUT",
                "Engine configuration is missing, empty or larger than 8 MiB.",
            )
        }
        val result = commands.execute(engine.check(executable, config), timeoutMs)
        return when {
            result.succeeded ->
                NativeValidation(
                    true,
                    "NATIVE_VALIDATED",
                    "The installed engine accepted the configuration; connectivity is not tested.",
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
}
