package com.blackoutkit.vpn

import java.net.InetSocketAddress
import java.net.Socket

internal object LocalSocksReadiness {
    /** How long to wait between attempts while the engine is still binding. */
    private const val RETRY_INTERVAL_MS = 100L

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
    fun await(host: String, port: Int, timeoutMs: Int): Boolean {
        val deadline = System.currentTimeMillis() + timeoutMs.coerceAtLeast(0)
        while (true) {
            val remaining = deadline - System.currentTimeMillis()
            if (remaining <= 0) return false
            val attemptBudget = minOf(remaining, 750L).toInt().coerceAtLeast(1)
            if (attempt(host, port, attemptBudget)) return true
            val left = deadline - System.currentTimeMillis()
            if (left <= RETRY_INTERVAL_MS) return false
            try {
                Thread.sleep(RETRY_INTERVAL_MS)
            } catch (interrupted: InterruptedException) {
                Thread.currentThread().interrupt()
                return false
            }
        }
    }

    /** One SOCKS5 greeting. False on refusal, timeout or a bad reply. */
    private fun attempt(host: String, port: Int, timeoutMs: Int): Boolean {
        return try {
            Socket().use { socket ->
                socket.connect(InetSocketAddress(host, port), timeoutMs)
                socket.soTimeout = timeoutMs
                val output = socket.getOutputStream()
                val input = socket.getInputStream()
                output.write(byteArrayOf(0x05, 0x01, 0x00))
                output.flush()
                val version = input.read()
                val method = input.read()
                version == 0x05 && method == 0x00
            }
        } catch (_: Exception) {
            false
        }
    }
}
