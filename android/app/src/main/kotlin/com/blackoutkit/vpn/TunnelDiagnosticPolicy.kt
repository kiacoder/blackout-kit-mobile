package com.blackoutkit.vpn

import java.io.Reader
import java.net.URL

/** Only the app's two credential-free diagnostics may use the live SOCKS tunnel. */
internal object TunnelDiagnosticPolicy {
    const val IP_ECHO_URL = "https://api.ipify.org"
    const val GEO_LOOKUP_URL = "https://ipwho.is"
    private const val MAX_RESPONSE_CHARS = 32 * 1024

    fun target(value: String): URL? =
        when (value) {
            IP_ECHO_URL -> URL(IP_ECHO_URL)
            GEO_LOOKUP_URL -> URL(GEO_LOOKUP_URL)
            else -> null
        }

    /** Reject rather than parse a truncated or unexpectedly large payload. */
    fun readBody(reader: Reader): String? {
        val output = StringBuilder()
        val buffer = CharArray(DEFAULT_BUFFER_SIZE)
        while (true) {
            val count = reader.read(buffer)
            if (count < 0) return output.toString()
            if (count == 0 || count > MAX_RESPONSE_CHARS - output.length) return null
            output.append(buffer, 0, count)
        }
    }
}
