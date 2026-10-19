package com.blackoutkit.vpn

import android.content.Context
import android.util.Log
import java.io.File
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Subprocess-based engine runner, for protocols the in-process Xray core
 * cannot serve.
 *
 *   TUN fd  <->  tun2socks  <->  127.0.0.1:<socksPort>  <->  sing-box
 *
 * Xray-family protocols (vless / vmess / trojan / shadowsocks) do **not** come
 * through here — [XrayEngine] links them straight into the process and Xray
 * binds the TUN itself, so no SOCKS hop is needed.
 *
 * The native libraries are bundled for the packaged ARM ABIs. This only
 * establishes that subprocesses can be launched; it does not prove tunnel traffic
 * is working. The runner therefore checks both process liveness during startup
 * and watches both children for unexpected exit.
 *
 * Binaries are named `lib*.so` on purpose: Android only permits `exec()` from
 * `nativeLibraryDir` (API 29+ blocks execution from `filesDir`), and the APK
 * packaging step only extracts files matching that pattern.
 *
 * This runner refuses to bring a tunnel up when its engine is missing, rather
 * than installing a default route that would black-hole all traffic.
 */
object EngineRunner {
    private const val TAG = "EngineRunner"

    /** Always required: the bridge between the TUN fd and the loopback proxy. */
    private const val TUN2SOCKS = "libtun2socks.so"

    /**
     * Protocol -> engine binary that can carry it.
     *
     * Xray protocols are intentionally absent: they are handled in-process by
     * [XrayEngine]. Listing them here would route them to a binary that does
     * not exist.
     *
     * `wireguard` is in that group too. It used to be listed here and so was
     * refused with "no engine is bundled"; the bundled core in fact contains
     * `xray.proxy.wireguard`, and [XrayEngine] now serves it directly.
     */
    private val ENGINE_FOR_PROTOCOL = mapOf(
        "hysteria2" to "libsingbox.so",
        "tuic" to "libsingbox.so",
        "amneziawg" to "libsingbox.so",
        "warp" to "libsingbox.so",
    )

    @Volatile
    var lastError: String? = null
        private set

    private var tun2socksProcess: Process? = null
    private var engineProcess: Process? = null
    private var monitorThread: Thread? = null
    private val intentionalStop = AtomicBoolean(false)
    @Volatile
    var onUnexpectedExit: ((String) -> Unit)? = null

    internal var processLauncher: (List<String>) -> Process = { command ->
        ProcessBuilder(command).redirectErrorStream(true).start()
    }
    // 750ms starved a cold start on real devices: loading a 47MB binary and
    // parsing a config takes 1-3s on mid-range hardware, so the startup wait
    // and the readiness probe must both allow it.
    internal var startupWaitMs: Long = 3000
    internal var readinessProbe: (String, Int, Int) -> Boolean = LocalSocksReadiness::await
    internal var readinessPortProvider: (Context, String) -> Int = { _, config ->
        Regex("\\\"listen_port\\\"\\s*:\\s*(\\d+)").find(config)
            ?.groupValues?.get(1)?.toIntOrNull() ?: 0
    }
    internal var lifecycle = SubprocessLifecycle()

    private fun engineLogTail(log: File): String = try {
        val tail = log.readText().takeLast(600)
        if (tail.isBlank()) "" else "\nengine log: $tail"
    } catch (_: Exception) {
        ""
    }

    fun start(context: Context, tunFd: Int, socksPort: Int, protocol: String): Boolean {
        lastError = null
        stop()

        val libDir = context.applicationInfo.nativeLibraryDir
        // Lower-cased for the same reason BlackoutVpnService lower-cases before
        // its own set lookup: the map keys are lowercase, and a caller that
        // ever passes "Hysteria2" would otherwise get a misleading "no engine
        // is mapped" refusal.
        val engineName = ENGINE_FOR_PROTOCOL[protocol.lowercase()]

        if (engineName == null) {
            lastError = "No engine is mapped for protocol '$protocol'."
            Log.w(TAG, lastError!!)
            return false
        }

        val tun2socksPath = File(libDir, TUN2SOCKS)
        val enginePath = File(libDir, engineName)
        val absent = listOf(tun2socksPath, enginePath).filterNot { it.exists() }

        if (absent.isNotEmpty()) {
            lastError = buildString {
                append("'$protocol' needs an engine that is not bundled in this build ")
                append("(missing: ${absent.joinToString { it.name }}). ")
                append("The tunnel was refused instead of black-holing your traffic. ")
                append("Use a VLESS, VMess, Trojan or Shadowsocks config for now.")
            }
            Log.w(TAG, lastError!!)
            return false
        }

        val configFile = File(configDir(context), "singbox.json")
        if (!configFile.exists()) {
            lastError = "No sing-box config has been written yet."
            Log.w(TAG, lastError!!)
            return false
        }

        return try {
            intentionalStop.set(false)

            // Validate the config with sing-box's own checker BEFORE launching.
            // A config the engine cannot parse (unknown fields, bad TLS material)
            // used to surface as a generic readiness timeout; the checker names
            // the exact offending field instead.
            val check = ProcessBuilder(
                listOf(enginePath.absolutePath, "check", "-c", configFile.absolutePath)
            ).redirectErrorStream(true).start()
            val checkOutput = check.inputStream.bufferedReader().readText()
            if (check.waitFor() != 0) {
                lastError = "sing-box rejected the configuration: " + checkOutput.takeLast(500) +
                    (if (checkOutput.contains("amnezia", ignoreCase = true))
                        " [this build does not support the AmneziaWG junk-packet block]"
                    else "")
                Log.e(TAG, lastError!!)
                return false
            }

            // Engine + tun2socks output goes to a file, not a pipe: unread pipes
            // fill up and deadlock the engine mid-run, and the file gives the
            // failure paths below something concrete to report.
            val engineLog = File(configDir(context), "engine.log")
            val logRedirect = ProcessBuilder.Redirect.appendTo(engineLog)

            engineProcess = ProcessBuilder(
                listOf(enginePath.absolutePath, "run", "-c", configFile.absolutePath)
            ).redirectErrorStream(true).redirectOutput(logRedirect).start()

            tun2socksProcess = ProcessBuilder(
                listOf(
                    tun2socksPath.absolutePath,
                    "-fd", tunFd.toString(),
                    "-socks", "127.0.0.1:$socksPort"
                )
            ).redirectErrorStream(true).redirectOutput(logRedirect).start()

            val children = listOfNotNull(engineProcess, tun2socksProcess)
            val startupError = lifecycle.awaitStartup(children, startupWaitMs)
            if (startupError != null) {
                lastError = startupError + engineLogTail(engineLog)
                stop()
                return false
            }
            val readinessPort = readinessPortProvider(context, configFile.readText())
            if (readinessPort !in 1..65535 || !readinessProbe("127.0.0.1", readinessPort, 2000)) {
                lastError = "sing-box did not accept a local SOCKS5 readiness handshake." + engineLogTail(engineLog)
                stop()
                return false
            }

            monitorThread = Thread({
                while (!intentionalStop.get()) {
                    val childrenNow = listOfNotNull(engineProcess, tun2socksProcess)
                    val exited = lifecycle.exitedProcess(childrenNow)
                    if (exited != null) {
                        val reason = "Engine process exited unexpectedly (code ${runCatching { exited.exitValue() }.getOrNull() ?: "unknown"})."
                        lastError = reason
                        if (!intentionalStop.get()) onUnexpectedExit?.invoke(reason)
                        return@Thread
                    }
                    try {
                        Thread.sleep(100)
                    } catch (_: InterruptedException) {
                        return@Thread
                    }
                }
            }, "blackout-engine-monitor").apply { isDaemon = true; start() }

            Log.i(TAG, "engine processes remained alive and accepted a local SOCKS5 handshake: $engineName, socks=127.0.0.1:$readinessPort, tunFd=$tunFd")
            true
        } catch (e: Exception) {
            lastError = "Engine launch failed: ${e.message}"
            Log.e(TAG, lastError, e)
            stop()
            false
        }
    }

    fun stop() {
        intentionalStop.set(true)
        monitorThread?.interrupt()
        monitorThread = null
        lifecycle.stop(listOfNotNull(tun2socksProcess, engineProcess))
        tun2socksProcess = null
        engineProcess = null
    }

    /** Called by Dart before connect() for a subprocess-backed engine. */
    fun writeConfig(context: Context, json: String): Boolean {
        return try {
            val dir = configDir(context)
            File(dir, "singbox.json").writeText(json)
            true
        } catch (e: Exception) {
            lastError = "Could not write engine config: ${e.message}"
            Log.e(TAG, lastError, e)
            false
        }
    }

    private fun configDir(context: Context): File =
        File(context.filesDir, "engine").apply { mkdirs() }
}
