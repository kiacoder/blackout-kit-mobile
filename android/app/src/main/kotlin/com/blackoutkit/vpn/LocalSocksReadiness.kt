package com.blackoutkit.vpn

import java.net.InetSocketAddress
import java.net.Socket
import java.security.SecureRandom
import java.util.concurrent.TimeUnit

internal object LocalSocksReadiness {
    /** How long to wait between attempts while the engine is still binding. */
    private const val RETRY_INTERVAL_MS = 100L
    private const val ATTEMPT_TIMEOUT_MS = 750L
    private const val SOCKS_VERSION = 0x05
    private const val NO_AUTH_METHOD = 0x00

    /**
     * Waits for a SOCKS5 listener on [host]:[port], polling until [timeoutMs].
     *
     * Despite the name, this used to make exactly ONE connection attempt with
     * the full timeout. A refused connection fails in microseconds, so an
     * engine that had not yet bound its port - every cold start on a slower
     * device - was reported as "failed to start" almost immediately. The
     * method now keeps trying until the deadline, which is what its callers
     * have always assumed it did.
     */
    fun await(
        host: String,
        port: Int,
        timeoutMs: Int,
    ): Boolean = awaitAuthenticated(host, port, timeoutMs, null)

    fun awaitAuthenticated(
        host: String,
        port: Int,
        timeoutMs: Int,
        auth: MihomoLocalAuth?,
    ): Boolean {
        val deadline = TimeUnit.NANOSECONDS.toMillis(System.nanoTime()) + timeoutMs.coerceAtLeast(0)
        var remaining = deadline - TimeUnit.NANOSECONDS.toMillis(System.nanoTime())
        while (remaining > 0) {
            val attemptBudget = minOf(remaining, ATTEMPT_TIMEOUT_MS).toInt().coerceAtLeast(1)
            if (attempt(host, port, attemptBudget, auth)) return true
            if (deadline - TimeUnit.NANOSECONDS.toMillis(System.nanoTime()) <= RETRY_INTERVAL_MS ||
                !pauseBeforeRetry()
            ) {
                break
            }
            remaining = deadline - TimeUnit.NANOSECONDS.toMillis(System.nanoTime())
        }
        return false
    }

    private fun pauseBeforeRetry(): Boolean =
        try {
            Thread.sleep(RETRY_INTERVAL_MS)
            true
        } catch (_: InterruptedException) {
            Thread.currentThread().interrupt()
            false
        }

    /** One SOCKS5 greeting. False on refusal, timeout or a bad reply. */
    private fun attempt(
        host: String,
        port: Int,
        timeoutMs: Int,
        auth: MihomoLocalAuth?,
    ): Boolean =
        try {
            Socket().use { socket ->
                socket.connect(InetSocketAddress(host, port), timeoutMs)
                socket.soTimeout = timeoutMs
                val output = socket.getOutputStream()
                val input = socket.getInputStream()
                val requested = if (auth == null) NO_AUTH_METHOD else 2
                output.write(byteArrayOf(SOCKS_VERSION.toByte(), 0x01, requested.toByte()))
                output.flush()
                val version = input.read()
                val method = input.read()
                version == SOCKS_VERSION &&
                    method == requested &&
                    (auth == null || authenticate(socket, auth))
            }
        } catch (_: Exception) {
            false
        }

    private fun authenticate(
        socket: Socket,
        auth: MihomoLocalAuth,
    ): Boolean {
        val request = auth.packet()
        return try {
            socket.getOutputStream().write(request)
            socket.getOutputStream().flush()
            val input = socket.getInputStream()
            input.read() == 1 && input.read() == 0
        } finally {
            request.fill(0)
        }
    }
}

/** Session-local random credentials, never derived from imported proxy passwords. */
internal class MihomoLocalAuth private constructor(
    val password: String,
) {
    fun uri(port: Int): String = "socks5://blackout:$password@127.0.0.1:$port"

    fun entry(): String = "blackout:$password"

    fun packet(): ByteArray {
        val user = "blackout".toByteArray(Charsets.US_ASCII)
        val secret = password.toByteArray(Charsets.US_ASCII)
        return byteArrayOf(1, user.size.toByte()) + user +
            byteArrayOf(secret.size.toByte()) + secret
    }

    companion object {
        private const val SECRET_BYTES = 32
        private const val BYTE_MASK = 0xff

        fun create(): MihomoLocalAuth {
            val bytes = ByteArray(SECRET_BYTES)
            SecureRandom().nextBytes(bytes)
            return try {
                MihomoLocalAuth(bytes.joinToString("") { "%02x".format(it.toInt() and BYTE_MASK) })
            } finally {
                bytes.fill(0)
            }
        }
    }
}

/** Readiness requires a fresh private native marker and a still-owned live child. */
internal object MihomoDirectReadiness {
    private const val POLL_MS = 50L
    private const val MARKER = "ready\n"

    fun await(
        file: java.io.File,
        timeoutMs: Long,
        alive: () -> Boolean,
    ): Boolean {
        val deadline = System.nanoTime() + TimeUnit.MILLISECONDS.toNanos(timeoutMs)
        while (System.nanoTime() < deadline && alive()) {
            if (isReady(file)) return alive()
            Thread.sleep(POLL_MS)
        }
        return false
    }

    private fun isReady(file: java.io.File): Boolean =
        try {
            isPrivateEnginePath(file) &&
                file.isFile &&
                file.length() == MARKER.length.toLong() &&
                file.readText() == MARKER
        } catch (_: java.io.IOException) {
            false
        } catch (_: SecurityException) {
            false
        }
}
