package com.blackoutkit.vpn

import android.content.Context
import java.io.File
import java.io.IOException

/** No generated toString: configuration documents can contain credentials. */
internal class ProbeEngineRequest(
    val context: Context,
    val xrayConfig: String?,
    val singboxConfig: String?,
    val socksPort: Int,
)

internal data class ProbeEngineFailure(
    val code: String,
    val message: String,
)

/** Process-wide headless engine ownership, independent of a Flutter plugin instance. */
internal object ProbeEngineController {
    private const val READY_TIMEOUT_MS = 8_000
    private const val CLEANUP_TIMEOUT_MS = 500L
    private const val MAX_PROBE_CONFIG_BYTES = 8 * 1024 * 1024
    private var probeProcess: Process? = null
    private val configOwner = TransientEngineConfig()
    private val sessionOwner = Any()

    @Synchronized
    fun start(request: ProbeEngineRequest): ProbeEngineFailure? {
        val cleanup = stop()
        return cleanup ?: if (EngineSessionAdmission.process.claim(sessionOwner)) {
            startOwned(request)
        } else {
            ProbeEngineFailure("BUSY", "Disconnect the VPN or finish pending engine cleanup before probing.")
        }
    }

    private fun startOwned(request: ProbeEngineRequest): ProbeEngineFailure? {
        var completed = false
        val failure =
            try {
                val result =
                    if (!request.singboxConfig.isNullOrBlank()) {
                        startSingboxProbe(request)
                    } else {
                        startXrayProbe(request)
                    }
                completed = true
                result
            } finally {
                if (!completed) stop()
            }
        // Keep the lease if cleanup fails. A later stop can retry it.
        return if (failure == null) null else stop() ?: failure
    }

    @Synchronized
    fun stop(): ProbeEngineFailure? {
        if (!EngineSessionAdmission.process.owns(sessionOwner)) return null
        return try {
            stopSingboxProbe()
            XrayEngine.stop()
            EngineSessionAdmission.process.release(sessionOwner)
            null
        } catch (_: IllegalStateException) {
            cleanupFailure()
        } catch (_: SecurityException) {
            cleanupFailure()
        } catch (_: LinkageError) {
            cleanupFailure()
        }
    }

    private fun startXrayProbe(request: ProbeEngineRequest): ProbeEngineFailure? =
        try {
            if (XrayEngine.startProxyOnly(request.context, requireNotNull(request.xrayConfig))) {
                null
            } else {
                startFailure(XrayEngine.lastError ?: "The Xray core failed to start")
            }
        } catch (_: IllegalStateException) {
            cleanupFailure()
        }

    private fun startSingboxProbe(request: ProbeEngineRequest): ProbeEngineFailure? {
        val engine = File(request.context.applicationInfo.nativeLibraryDir, "libsingbox.so")
        val config = requireNotNull(request.singboxConfig)
        return when {
            !engine.isFile || !engine.canExecute() -> startFailure("sing-box is not bundled or executable")
            config.toByteArray(Charsets.UTF_8).size > MAX_PROBE_CONFIG_BYTES ->
                startFailure("Probe configuration exceeds the 8 MiB engine limit.")
            else -> prepareAndLaunch(request, engine, config)
        }
    }

    private fun prepareAndLaunch(
        request: ProbeEngineRequest,
        engine: File,
        config: String,
    ): ProbeEngineFailure? =
        try {
            val dir = EngineRunner.configDirectory(request.context)
            val file = configOwner.stage(dir, config)
            val validation = NativeConfigValidator().validate(EngineCommands.SING_BOX, engine, file)
            if (!validation.valid) {
                configOwner.release()
                startFailure(validation.message)
            } else {
                launch(engine, file, request.socksPort)
            }
        } catch (_: IOException) {
            cleanupAfterFailure("Probe configuration or process could not be opened.")
        } catch (_: SecurityException) {
            cleanupAfterFailure("Probe configuration or process access denied.")
        } catch (_: IllegalStateException) {
            cleanupFailure()
        }

    private fun launch(
        engine: File,
        file: File,
        port: Int,
    ): ProbeEngineFailure? {
        val process = ProcessCompat.startQuietly(EngineCommands.SING_BOX.run(engine, file))
        probeProcess = process
        val ready = LocalSocksReadiness.await("127.0.0.1", port, READY_TIMEOUT_MS)
        return if (ready && ProcessCompat.isAlive(process)) {
            null
        } else {
            val died = !ProcessCompat.isAlive(process)
            try {
                stopSingboxProbe()
                startFailure(
                    if (died) {
                        "sing-box exited during startup. Native diagnostics are withheld."
                    } else {
                        "sing-box did not open the local SOCKS listener within 8s."
                    },
                )
            } catch (_: IllegalStateException) {
                cleanupFailure()
            } catch (_: SecurityException) {
                cleanupFailure()
            }
        }
    }

    private fun stopSingboxProbe() {
        probeProcess?.let { process ->
            SubprocessLifecycle().stop(listOf(process), graceMs = CLEANUP_TIMEOUT_MS)
            check(!ProcessCompat.isAlive(process)) { "Probe cleanup did not complete within its deadline." }
            probeProcess = null
        }
        configOwner.release()
    }

    private fun cleanupAfterFailure(message: String): ProbeEngineFailure =
        try {
            stopSingboxProbe()
            startFailure(message)
        } catch (_: IllegalStateException) {
            cleanupFailure()
        } catch (_: SecurityException) {
            cleanupFailure()
        }

    private fun cleanupFailure() = ProbeEngineFailure("PROBE_STOP_FAILED", "Previous probe cleanup failed.")
}

private fun startFailure(message: String) = ProbeEngineFailure("PROBE_START_FAILED", message)
