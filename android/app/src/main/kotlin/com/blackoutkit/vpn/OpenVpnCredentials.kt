package com.blackoutkit.vpn

import java.util.UUID

/** One-shot, process-local handoff. No credentials in Android Intent extras. */
internal class OpenVpnCredentials(
    val username: ByteArray,
    val password: ByteArray,
    val keyPassword: ByteArray = ByteArray(0),
) {
    fun clear() {
        username.fill(0)
        password.fill(0)
        keyPassword.fill(0)
    }

    fun isValid(): Boolean {
        val pair = valid(username) && valid(password)
        val absent = username.isEmpty() && password.isEmpty()
        val keyValid = valid(keyPassword)
        return (pair || absent) && (keyValid || keyPassword.isEmpty()) && (pair || keyValid)
    }

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
