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

/** Owns mutable profile and secret bytes until the native worker joins. */
internal class OpenVpnStartPayload(
    val profile: ByteArray,
    val credentials: OpenVpnCredentials?,
) {
    fun clear() {
        profile.fill(0)
        credentials?.clear()
    }
}

/** One bounded slot; only an opaque token crosses the service-start Intent. */
internal object OpenVpnProfileHandoff {
    private var token: String? = null
    private var pending: OpenVpnStartPayload? = null

    @Synchronized
    fun stage(
        profile: String,
        credentials: OpenVpnCredentials?,
    ): String {
        check(pending == null) { "An OpenVPN handoff is pending" }
        require(profile.isNotEmpty() && profile.length <= MAX_PROFILE_BYTES)
        require(credentials == null || credentials.isValid())
        val bytes = profile.toByteArray(Charsets.UTF_8)
        if (bytes.size > MAX_PROFILE_BYTES || bytes.any { it == 0.toByte() }) {
            bytes.fill(0)
            throw IllegalArgumentException("Invalid OpenVPN profile size or encoding")
        }
        val next = UUID.randomUUID().toString()
        token = next
        pending = OpenVpnStartPayload(bytes, credentials)
        return next
    }

    @Synchronized
    fun take(expected: String): OpenVpnStartPayload? {
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

    private const val MAX_PROFILE_BYTES = 1024 * 1024
}
