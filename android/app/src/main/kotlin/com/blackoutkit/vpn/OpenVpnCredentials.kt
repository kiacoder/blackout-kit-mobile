package com.blackoutkit.vpn

import java.util.UUID

/** One-shot, process-local handoff. No credentials in Android Intent extras. */
internal class OpenVpnCredentials(
    val username: ByteArray,
    val password: ByteArray,
) {
    fun clear() {
        username.fill(0)
        password.fill(0)
    }

    fun isValid(): Boolean = valid(username) && valid(password)

    private fun valid(bytes: ByteArray): Boolean =
        bytes.isNotEmpty() && bytes.size <= MAX_BYTES && bytes.none { it == 0.toByte() }

    companion object {
        private const val MAX_BYTES = 4096
    }
}

internal object OpenVpnCredentialHandoff {
    private var token: String? = null
    private var pending: OpenVpnCredentials? = null

    @Synchronized
    fun stage(credentials: OpenVpnCredentials): String {
        check(pending == null) { "An authentication handoff is pending" }
        require(credentials.isValid()) { "Invalid OpenVPN credentials" }
        val next = UUID.randomUUID().toString()
        token = next
        pending = credentials
        return next
    }

    @Synchronized
    fun take(expected: String): OpenVpnCredentials? {
        if (expected != token) return null
        val result = pending
        token = null
        pending = null
        return result
    }

    @Synchronized
    fun discard(expected: String) {
        take(expected)?.clear()
    }
}
