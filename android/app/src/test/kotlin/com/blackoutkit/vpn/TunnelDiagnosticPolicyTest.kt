package com.blackoutkit.vpn

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import java.io.StringReader

class TunnelDiagnosticPolicyTest {
    @Test
    fun acceptsOnlyExactDiagnosticEndpoints() {
        assertEquals("api.ipify.org", TunnelDiagnosticPolicy.target("https://api.ipify.org")?.host)
        assertEquals("ipwho.is", TunnelDiagnosticPolicy.target("https://ipwho.is")?.host)
        for (url in listOf(
            "http://ipwho.is",
            "https://ipwho.is.evil.invalid",
            "https://ipwho.is@evil.invalid",
            "https://evil.invalid",
            "https://ipwho.is:8443",
            "https://ipwho.is?extra=1",
            "https://127.0.0.1",
            "",
        )) {
            assertNull(url, TunnelDiagnosticPolicy.target(url))
        }
    }

    @Test
    fun rejectsOversizedResponsesInsteadOfTruncating() {
        assertEquals("fixture", TunnelDiagnosticPolicy.readBody(StringReader("fixture")))
        val limit = "x".repeat(32 * 1024)
        assertEquals(limit, TunnelDiagnosticPolicy.readBody(StringReader(limit)))
        assertNull(TunnelDiagnosticPolicy.readBody(StringReader(limit + "x")))
    }
}
