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
        path: String,
        args: Array<String>,
        fd: Int,
        logPath: String,
    ): Int

    /** -1 while the child runs, otherwise its exit code. */
    private external fun nativePollChild(token: Int): Int

    /** Sends a signal to a launcher-started child (SIGTERM/SIGKILL). */
    private external fun nativeSignalChild(
        token: Int,
        signal: Int,
    ): Int

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

    @Volatile
    var lastError: String? = null
        private set

    private var tun2socksProcess: Process? = null

    /** Opaque native launcher token, never an OS PID (-1: none). */
    @Volatile
    private var tun2socksToken: Int = -1
    private var engineProcess: Process? = null
    private var monitorThread: Thread? = null
    private var monitorCancelled = AtomicBoolean(true)

    @Volatile
    var onUnexpectedExit: ((String) -> Unit)? = null

    internal var processLauncher: (List<String>) -> Process = { command ->
        ProcessCompat.startQuietly(command)
    }

    // 750ms starved a cold start on real devices: loading a 47MB binary and
    // parsing a config takes 1-3s on mid-range hardware, so the startup wait
    // and the readiness probe must both allow it.
    private const val STARTUP_WAIT_MS = 3000L
    internal var startupWaitMs: Long = STARTUP_WAIT_MS
    internal var readinessProbe: (String, Int, Int) -> Boolean = LocalSocksReadiness::await
    internal var readinessPortProvider: (Context, String) -> Int = { _, config ->
        Regex("\\\"listen_port\\\"\\s*:\\s*(\\d+)")
            .find(config)
            ?.groupValues
            ?.get(1)
            ?.toIntOrNull() ?: 0
    }
    internal var lifecycle = SubprocessLifecycle()

    private const val MONITOR_INTERVAL_MS = 100L
    private const val MAX_SOCKS_PORT = 65535
    private const val SOCKS_READY_TIMEOUT_MS = 2000
    private const val MAX_ENGINE_CONFIG_BYTES = 8 * 1024 * 1024
    private const val NATIVE_LOG_WITHHELD = " Native log content is withheld because it may contain credentials."

    private class LaunchFiles(
        val spec: EngineCommands,
        val enginePath: File,
        val tun2socksPath: File,
        val configFile: File,
    )

    private val launcher = LaunchCoordinator()
    private val configOwner = TransientEngineConfig()

    fun start(
        context: Context,
        tunFd: Int,
        socksPort: Int,
        protocol: String,
        json: String,
    ): Boolean {
        lastError = null
        stop()
        if (json.isBlank() || json.toByteArray(Charsets.UTF_8).size > MAX_ENGINE_CONFIG_BYTES) {
            lastError = "Missing configuration or configuration exceeds the 8 MiB engine limit."
            return false
        }
        var started = false
        return try {
            val files = launcher.prepareLaunch(context, protocol, json)
            if (files == null) {
                false
            } else {
                launcher.validateAndLaunch(context, files, tunFd, socksPort).also { started = it }
            }
        } catch (_: java.io.IOException) {
            lastError = "Engine launch failed due to an I/O error."
            false
        } catch (_: SecurityException) {
            lastError = "Engine launch was denied."
            false
        } catch (_: InterruptedException) {
            Thread.currentThread().interrupt()
            lastError = "Engine launch was interrupted."
            false
        } catch (_: LinkageError) {
            lastError = "Native engine launcher is unavailable or incompatible."
            false
        } finally {
            // Cleanup also runs for unexpected failures propagated to the service.
            if (!started) stop()
        }
    }

    /** Owns launch orchestration; the runner retains native/process handles. */
    private class LaunchCoordinator {
        fun prepareLaunch(
            context: Context,
            protocol: String,
            json: String,
        ): LaunchFiles? {
            val spec = EngineCommands.forProtocol(protocol)
            if (spec == null) {
                lastError = "No engine is mapped for protocol '$protocol'."
                Log.w(TAG, lastError!!)
                return null
            }
            val libDir = context.applicationInfo.nativeLibraryDir
            val bridge = File(libDir, TUN2SOCKS)
            val engine = File(libDir, spec.binary)
            val absent = listOf(bridge, engine).filterNot { it.exists() }
            return if (absent.isNotEmpty()) {
                lastError =
                    buildString {
                        append("'$protocol' needs an engine that is not bundled in this build ")
                        append("(missing: ${absent.joinToString { it.name }}). ")
                        append("The tunnel was refused instead of black-holing your traffic. ")
                        append("Use a VLESS, VMess, Trojan or Shadowsocks config for now.")
                    }
                Log.w(TAG, lastError!!)
                null
            } else {
                val config = configOwner.stage(configDir(context), json)
                LaunchFiles(spec, engine, bridge, config)
            }
        }

        fun validateAndLaunch(
            context: Context,
            files: LaunchFiles,
            tunFd: Int,
            socksPort: Int,
        ): Boolean {
            val validation = NativeConfigValidator().validate(files.spec, files.enginePath, files.configFile)
            return if (!validation.valid) {
                failLaunch(validation.message)
            } else {
                launchValidated(context, files, tunFd, socksPort)
            }
        }

        private fun launchValidated(
            context: Context,
            files: LaunchFiles,
            tunFd: Int,
            socksPort: Int,
        ): Boolean {
            // Native output may contain full profiles/private keys. Discard it.
            engineProcess = processLauncher(files.spec.run(files.enginePath, files.configFile))
            loadNative()
            if (!nativeLoaded) {
                return failLaunch(
                    "The native fd launcher is unavailable in this build, so the " +
                        "tunnel's file descriptor cannot be handed to the engine.",
                )
            }
            spawnBridge(files.tun2socksPath, tunFd, socksPort)
            val startupError = bridgeStartupError()
            return if (startupError != null) {
                failLaunch(startupError)
            } else {
                verifyReadiness(context, files, tunFd, socksPort)
            }
        }

        private fun spawnBridge(
            tun2socksPath: File,
            tunFd: Int,
            socksPort: Int,
        ) {
            // ProcessBuilder cannot deliver the TUN descriptor; the launcher duplicates it.
            val engineLog = File("/dev/null")
            tun2socksToken =
                nativeSpawnWithFd(
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
                        "--device",
                        "fd://$FD_SLOT",
                        "--proxy",
                        "socks5://127.0.0.1:$socksPort",
                        "--mtu",
                        BlackoutVpnService.VPN_MTU.toString(),
                        "--loglevel",
                        "info",
                    ),
                    tunFd,
                    engineLog.absolutePath,
                )
        }

        private fun bridgeStartupError(): String? {
            if (tun2socksToken <= 0) {
                return "Could not start tun2socks (native launcher refused). " + NATIVE_LOG_WITHHELD
            }
            // Poll before and after the Process-only startup wait.
            return if (anyChildDied()) {
                "tun2socks exited during startup (code ${tun2socksExitCode()})." + NATIVE_LOG_WITHHELD
            } else {
                val startupError = lifecycle.awaitStartup(listOfNotNull(engineProcess, tun2socksProcess), startupWaitMs)
                when {
                    startupError != null -> startupError + NATIVE_LOG_WITHHELD
                    anyChildDied() ->
                        "tun2socks exited during startup (code ${tun2socksExitCode()}). " + NATIVE_LOG_WITHHELD
                    else -> null
                }
            }
        }

        private fun verifyReadiness(
            context: Context,
            files: LaunchFiles,
            tunFd: Int,
            socksPort: Int,
        ): Boolean {
            val readinessPort =
                if (files.spec == EngineCommands.MIHOMO) {
                    socksPort
                } else {
                    readinessPortProvider(context, files.configFile.readText())
                }
            val ready =
                readinessPort in 1..MAX_SOCKS_PORT &&
                    readinessProbe("127.0.0.1", readinessPort, SOCKS_READY_TIMEOUT_MS)
            if (!ready ||
                anyChildDied() ||
                lifecycle.exitedProcess(listOfNotNull(engineProcess, tun2socksProcess)) != null
            ) {
                return failLaunch(
                    "Native process exited or the local SOCKS5 readiness handshake failed." + NATIVE_LOG_WITHHELD,
                )
            }
            startMonitor()
            Log.i(
                TAG,
                "engine processes remained alive and accepted a local SOCKS5 handshake: " +
                    "${files.spec.binary}, socks=127.0.0.1:$readinessPort, tunFd=$tunFd",
            )
            return true
        }

        private fun failLaunch(reason: String): Boolean {
            lastError = reason
            return false
        }

        private fun startMonitor() {
            val cancelled = AtomicBoolean(false)
            monitorCancelled = cancelled
            val children = listOfNotNull(engineProcess, tun2socksProcess)
            val token = tun2socksToken
            val listener = onUnexpectedExit
            monitorThread =
                Thread({
                    while (!cancelled.get() && !Thread.currentThread().isInterrupted) {
                        val exited = lifecycle.exitedProcess(children)
                        if (exited != null) {
                            val reason = "Engine process exited unexpectedly (code ${runCatching {
                                exited.exitValue()
                            }.getOrNull() ?: "unknown"})."
                            if (!cancelled.get()) listener?.invoke(reason)
                            return@Thread
                        }
                        // tun2socks was started through the native launcher, so it
                        // is not a Process the lifecycle helper can see.
                        if (nativeLoaded &&
                            token > 0 &&
                            nativePollChild(token) != -1
                        ) {
                            val reason = "tun2socks exited unexpectedly (code ${nativePollChild(token)})."
                            if (!cancelled.get()) listener?.invoke(reason)
                            return@Thread
                        }
                        try {
                            Thread.sleep(MONITOR_INTERVAL_MS)
                        } catch (_: InterruptedException) {
                            return@Thread
                        }
                    }
                }, "blackout-engine-monitor").apply {
                    isDaemon = true
                    start()
                }
        }

        /**
         * True when the launcher-started tun2socks child has exited. -1 from
         * [nativePollChild] means "still running", anything else is a status.
         */
        private fun anyChildDied(): Boolean =
            nativeLoaded && tun2socksToken > 0 && nativePollChild(tun2socksToken) != -1

        /** Exit code of the launcher-started tun2socks child, reaped if needed. */
        private fun tun2socksExitCode(): Int =
            if (nativeLoaded &&
                tun2socksToken > 0
            ) {
                nativePollChild(tun2socksToken)
            } else {
                -1
            }
    }

    fun stop() {
        monitorCancelled.set(true)
        monitorThread?.interrupt()
        monitorThread = null
        var failed = false
        try {
            lifecycle.stop(listOfNotNull(tun2socksProcess, engineProcess))
            if (listOfNotNull(tun2socksProcess, engineProcess).any(ProcessCompat::isAlive)) {
                failed = true
            } else {
                tun2socksProcess = null
                engineProcess = null
            }
        } catch (_: Exception) {
            failed = true
        }
        // Poll reaps with WNOHANG; shutdown must not block the sole VPN worker.
        if (nativeLoaded && tun2socksToken > 0) {
            val token = tun2socksToken
            val stopped =
                try {
                    NativeChildStop(
                        poll = ::nativePollChild,
                        terminate = {
                            nativeSignalChild(it, android.system.OsConstants.SIGTERM)
                            Unit
                        },
                        kill = {
                            nativeSignalChild(it, android.system.OsConstants.SIGKILL)
                            Unit
                        },
                    ).stop(token)
                } catch (_: Exception) {
                    false
                } catch (_: LinkageError) {
                    false
                }
            if (stopped) tun2socksToken = -1 else failed = true
        }
        if (failed) {
            // Retain unresolved process/token handles for the next cleanup attempt.
            lastError = "Native child cleanup did not complete within its deadline."
            throw IllegalStateException(lastError)
        }
        configOwner.release()
    }

    /** Directory the engine reads its config from; the probe writes here too. */
    internal fun configDirectory(context: Context): File = configDir(context)
}

private fun configDir(context: Context): File =
    File(context.filesDir, "engine").apply {
        mkdirs()
        removeLegacyEngineConfigs(this)
    }
