package com.blackoutkit.vpn

import android.util.Log

/**
 * Direct JNI bridge to the in-house native Rust core (libblackout_core.so).
 *
 * Implements the C-ABI declared in include/blackout_core.h.
 * Runs in-process: takes the TUN file descriptor directly from
 * VpnService.Builder.establish() without needing fdlauncher, fork(), or dup2 hacks.
 */
object BlackoutCoreEngine {
    private const val TAG = "BlackoutCoreEngine"
    private const val ERROR_BUFFER_BYTES = 512

    @Volatile
    var isLoaded = false
        private set

    @Volatile
    var lastError: String? = null
        private set

    init {
        try {
            System.loadLibrary("blackout_core")
            isLoaded = true
            Log.i(TAG, "libblackout_core.so loaded successfully")
        } catch (e: UnsatisfiedLinkError) {
            isLoaded = false
            Log.w(TAG, "libblackout_core.so not bundled or not yet built: ${e.message}")
        }
    }

    // These six names are exported JNI ABI symbols in native/blackout-core/src/jni.rs.
    @Suppress("ktlint:standard:function-naming", "FunctionNaming")
    external fun blackout_init(logLevel: Int): Int

    @Suppress("ktlint:standard:function-naming", "FunctionNaming")
    external fun blackout_start(
        tunFd: Int,
        configJson: String,
    ): Int

    @Suppress("ktlint:standard:function-naming", "FunctionNaming")
    external fun blackout_stop(): Int

    @Suppress("ktlint:standard:function-naming", "FunctionNaming")
    external fun blackout_is_running(): Boolean

    @Suppress("ktlint:standard:function-naming", "FunctionNaming")
    external fun blackout_version(): String

    @Suppress("ktlint:standard:function-naming", "FunctionNaming")
    external fun blackout_get_last_error(
        buffer: ByteArray,
        maxLen: Int,
    ): Int

    fun start(
        tunFd: Int,
        configJson: String,
    ): Boolean {
        if (!isLoaded) {
            lastError = "Native in-house core is not loaded"
            return false
        }
        val initResult = blackout_init(2)
        if (initResult != 0) {
            lastError = "Native core initialization failed: code $initResult"
            Log.e(TAG, lastError!!)
            return false
        }
        val rc = blackout_start(tunFd, configJson)
        if (rc != 0) {
            val buf = ByteArray(ERROR_BUFFER_BYTES)
            val len = blackout_get_last_error(buf, buf.size)
            lastError = if (len > 0) String(buf, 0, len).trimEnd('\u0000') else "Core start error: code $rc"
            Log.e(TAG, "blackout_start failed: $lastError")
            return false
        }
        lastError = null
        return true
    }

    fun stop() {
        if (isLoaded) {
            blackout_stop()
        }
    }

    fun isRunning(): Boolean = if (isLoaded) blackout_is_running() else false
}
