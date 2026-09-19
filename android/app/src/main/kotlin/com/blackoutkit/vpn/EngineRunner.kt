package com.blackoutkit.vpn

import android.content.Context
import android.util.Log
import java.io.File

/**
 * Owns the packet-forwarding engine that sits behind the TUN interface.
 *
 *   TUN fd  <->  tun2socks  <->  127.0.0.1:<socksPort>  <->  xray-core / sing-box
 *
 * Binaries are shipped under `android/app/src/main/jniLibs/<abi>/` named `lib*.so`.
 * That naming is deliberate: Android only lets an app execute files from
 * `nativeLibraryDir` (API 29+ blocks exec from filesDir), and the packaging step
 * only extracts files matching `lib*.so`.
 *
 * This runner refuses to bring a tunnel up when its engine is missing, rather
 * than installing a default route that would black-hole all traffic.
 */
object EngineRunner {
    private const val TAG = "EngineRunner"

    /** Always required: the bridge between the TUN fd and the loopback proxy. */
    private const val TUN2SOCKS = "libtun2socks.so"

    /** Protocol -> engine binary that can carry it. */
    private val ENGINE_FOR_PROTOCOL = mapOf(
        "vless" to "libxray.so",
        "vmess" to "libxray.so",
        "trojan" to "libxray.so",
        "shadowsocks" to "libxray.so",
        "hysteria2" to "libsingbox.so",
        "tuic" to "libsingbox.so",
        "wireguard" to "libsingbox.so",
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
            lastError = "No engine is mapped for protocol '$protocol' yet."
            Log.w(TAG, lastError!!)
            return false
        }

        val tun2socksPath = File(libDir, TUN2SOCKS)
        val enginePath = File(libDir, engineName)
        val absent = listOf(tun2socksPath, enginePath).filterNot { it.exists() }

        if (absent.isNotEmpty()) {
            lastError = buildString {
                append("Engine binaries are not bundled yet for '$protocol' ")
                append("(missing: ${absent.joinToString { it.name }}). ")
                append("Tunnel refused rather than black-holing traffic.")
            }
            Log.w(TAG, lastError!!)
            return false
        }

        val configFile = File(File(context.filesDir, "engine").apply { mkdirs() }, "config.json")
        if (!configFile.exists()) {
            lastError = "No engine config has been written yet."
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

    /** Called by Dart once it has generated a config, before connect(). */
    fun writeConfig(context: Context, json: String): Boolean {
        return try {
            val dir = File(context.filesDir, "engine").apply { mkdirs() }
            File(dir, "config.json").writeText(json)
            true
        } catch (e: Exception) {
            lastError = "Could not write engine config: ${e.message}"
            Log.e(TAG, lastError, e)
            false
        }
    }
}
