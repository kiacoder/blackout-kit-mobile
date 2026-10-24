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

    /** Descriptor slot the native launcher duplicates the TUN fd into. */
    private const val FD_SLOT = 3

    /** Always required: the bridge between the TUN fd and the loopback proxy. */
    private const val TUN2SOCKS = "libtun2socks.so"

    /**
     * Loads libfdlauncher.so, built from android/app/src/main/cpp.
     *
     * Java's ProcessBuilder can only map descriptors 0/1/2, and the TUN fd
     * VpnService hands back is installed through Binder with FD_CLOEXEC set,
     * so a subprocess never sees it - the engine would fail with EBADF the
     * moment it touched the tunnel. The native helper forks, dup2()s the
     * descriptor to slot 3 and execs the engine, which is the only way a
     * subprocess can carry the tunnel. The Xray engine does not need this:
     * it takes the fd in-process over JNI.
     */
    private external fun nativeSpawnWithFd(
        path: String, args: Array<String>, fd: Int, logPath: String,
    ): Int

    /** -1 while the child runs, otherwise its exit code. */
    private external fun nativePollPid(pid: Int): Int

    /** Blocks until the child is gone; same codes as [nativePollPid]. */
    private external fun nativeWaitPid(pid: Int): Int

    /** Sends a signal to a launcher-started child (SIGTERM/SIGKILL). */
    private external fun nativeKillPid(pid: Int, signal: Int): Int

    @Volatile
    private var nativeLoaded = false

    /**
     * Loads the launcher once. Every native call site is guarded by
     * [nativeLoaded] because UnsatisfiedLinkError is an Error, not an
     * Exception - it would escape the catch blocks and take the app down.
     */
    private fun loadNative() {
        if (nativeLoaded) return
        try {
            System.loadLibrary("fdlauncher")
            nativeLoaded = true
        } catch (e: UnsatisfiedLinkError) {
            nativeLoaded = false
            Log.w(TAG, "fdlauncher native library unavailable: ${e.message}")
        }
    }

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
        "anytls" to "libsingbox.so",
        "shadowtls" to "libsingbox.so",
        "amneziawg" to "libsingbox.so",
        "warp" to "libsingbox.so",
    )

    @Volatile
    var lastError: String? = null
        private set

    private var tun2socksProcess: Process? = null

    /** Pid of the tun2socks child started through the native launcher (-1: none). */
    @Volatile
    private var tun2socksPid: Int = -1
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
            // readText() blocks until the stream closes, so the checker gets a
            // hard timeout as well: a wedged `sing-box check` used to hang the
            // connect path indefinitely, past the Dart-side timeout, with the
            // thread stuck and no way to recover but killing the app.
            val checkOutput = check.inputStream.bufferedReader().use { it.readText() }
            val checkDone = check.waitFor(20, java.util.concurrent.TimeUnit.SECONDS)
            if (!checkDone) {
                check.destroyForcibly()
                lastError = "sing-box check timed out after 20s - the engine may be damaged"
                Log.e(TAG, lastError!!)
                return false
            }
            if (check.exitValue() != 0) {
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

            // tun2socks needs the TUN descriptor itself. ProcessBuilder cannot
            // deliver it (see nativeSpawnWithFd), so the launcher forks,
            // duplicates the fd to slot FD_SLOT and execs the binary. The exit
            // code is polled by the monitor thread below, like sing-box's.
            loadNative()
            if (!nativeLoaded) {
                lastError = "The native fd launcher is unavailable in this build, so the " +
                    "tunnel's file descriptor cannot be handed to the engine."
                stop()
                return false
            }
            tun2socksPid = nativeSpawnWithFd(
                tun2socksPath.absolutePath,
                arrayOf(
                    tun2socksPath.absolutePath,
                    // DOUBLE dashes are mandatory here. This build parses its
                    // options with go-flags, where a single dash means a
                    // shorthand cluster: "-mtu" is read as "-m -t -u" and dies
                    // with `unknown shorthand flag: 'm' in -mtu` (and "-device"
                    // is read as "-d evice", silently swallowing the value).
                    // The device is a URI, not a bare descriptor: "fd://<n>"
                    // selects the fdbased driver, which opens that descriptor -
                    // the launcher dup2()s the tun fd to exactly FD_SLOT.
                    "--device", "fd://$FD_SLOT",
                    "--proxy", "socks5://127.0.0.1:$socksPort",
                    "--mtu", BlackoutVpnService.VPN_MTU.toString(),
                    "--loglevel", "info",
                ),
                tunFd,
                engineLog.absolutePath,
            )
            if (tun2socksPid <= 0) {
                lastError = "Could not start tun2socks (native launcher refused). " +
                    engineLogTail(engineLog)
                stop()
                return false
            }

            if (anyChildDied()) {
                lastError = "tun2socks exited during startup (code ${tun2socksExitCode()})." +
                    engineLogTail(engineLog)
                stop()
                return false
            }
            val children = listOfNotNull(engineProcess, tun2socksProcess)
            val startupError = lifecycle.awaitStartup(children, startupWaitMs)
            if (startupError != null) {
                lastError = startupError + engineLogTail(engineLog)
                stop()
                return false
            }
            // awaitStartup only watches Process children; tun2socks is a
            // launcher-started pid, so re-check it here. Without this a dead
            // tun2socks surfaced as a misleading SOCKS-handshake timeout.
            if (anyChildDied()) {
                lastError = "tun2socks exited during startup (code ${tun2socksExitCode()}). " +
                    engineLogTail(engineLog)
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
                    // tun2socks was started through the native launcher, so it
                    // is not a Process the lifecycle helper can see.
                    if (nativeLoaded && tun2socksPid > 0 &&
                        nativePollPid(tun2socksPid) != -1) {
                        val reason = "tun2socks exited unexpectedly (code ${tun2socksExitCode()})."
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

    /**
     * True when the launcher-started tun2socks child has exited. -1 from
     * [nativePollPid] means "still running", anything else is a status.
     */
    private fun anyChildDied(): Boolean =
        nativeLoaded && tun2socksPid > 0 && nativePollPid(tun2socksPid) != -1

    /** Exit code of the launcher-started tun2socks child, reaped if needed. */
    private fun tun2socksExitCode(): Int =
        if (nativeLoaded && tun2socksPid > 0) nativePollPid(tun2socksPid) else -1

    fun stop() {
        intentionalStop.set(true)
        monitorThread?.interrupt()
        monitorThread = null
        lifecycle.stop(listOfNotNull(tun2socksProcess, engineProcess))
        tun2socksProcess = null
        engineProcess = null
        // tun2socks runs as a launcher-started child: terminate it, then reap
        // it so it cannot linger as a zombie holding the tunnel down.
        if (nativeLoaded && tun2socksPid > 0) {
            val pid = tun2socksPid
            tun2socksPid = -1
            try {
                nativeKillPid(pid, android.system.OsConstants.SIGTERM)
                var waited = 0
                while (nativePollPid(pid) == -1 && waited < 500) {
                    Thread.sleep(25)
                    waited += 25
                }
                if (nativePollPid(pid) == -1) {
                    nativeKillPid(pid, android.system.OsConstants.SIGKILL)
                }
                nativeWaitPid(pid)
            } catch (e: Throwable) {
                Log.w(TAG, "could not stop tun2socks pid $pid: ${e.message}")
            }
        }
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

    /** Directory the engine reads its config from; the probe writes here too. */
    internal fun configDirectory(context: Context): File = configDir(context)

    private fun configDir(context: Context): File =
        File(context.filesDir, "engine").apply { mkdirs() }
}
