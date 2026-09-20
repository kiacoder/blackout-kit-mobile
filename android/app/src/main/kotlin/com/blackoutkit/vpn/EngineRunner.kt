package com.blackoutkit.vpn

import android.content.Context
import android.util.Log
import java.io.File

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
 * ## Current status: not yet functional
 *
 * The `jniLibs/<abi>/lib*.so` binaries this class expects are **not bundled in
 * the repository**. It is kept because the packaging contract is sound and the
 * failure mode is correct, but every protocol routed here currently fails with
 * an explicit "binaries are not bundled" error rather than pretending to
 * connect.
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

    fun start(context: Context, tunFd: Int, socksPort: Int, protocol: String): Boolean {
        lastError = null
        stop()

        val libDir = context.applicationInfo.nativeLibraryDir
        val engineName = ENGINE_FOR_PROTOCOL[protocol]

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
            engineProcess = ProcessBuilder(
                enginePath.absolutePath, "run", "-c", configFile.absolutePath
            ).redirectErrorStream(true).start()

            tun2socksProcess = ProcessBuilder(
                tun2socksPath.absolutePath,
                "-fd", tunFd.toString(),
                "-socks", "127.0.0.1:$socksPort"
            ).redirectErrorStream(true).start()

            Log.i(TAG, "engine up: $engineName, socks=127.0.0.1:$socksPort, tunFd=$tunFd")
            true
        } catch (e: Exception) {
            lastError = "Engine launch failed: ${e.message}"
            Log.e(TAG, lastError, e)
            stop()
            false
        }
    }

    fun stop() {
        for (process in listOf(tun2socksProcess, engineProcess)) {
            try {
                process?.destroy()
            } catch (e: Exception) {
                Log.w(TAG, "failed to stop engine process: ${e.message}")
            }
        }
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
