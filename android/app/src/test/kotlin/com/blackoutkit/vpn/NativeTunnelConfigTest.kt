package com.blackoutkit.vpn

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.util.Base64

/** JVM parser tests; no Android interface or live credentials. */
class NativeTunnelConfigTest {
    // Synthetic bytes only; JDK Base64 is used in tests, not API24 production code.
    private val key = Base64.getEncoder().encodeToString(ByteArray(32) { 1 })
    private val zero = Base64.getEncoder().encodeToString(ByteArray(32))

    private fun profile() =
        """
        [Interface]
        PrivateKey = $key
        Address = 10.0.0.2/32
        [Peer]
        PublicKey = $key
        Endpoint = example.invalid:51820
        AllowedIPs = 10.0.0.129/24
        """.trimIndent()

    private fun reject(text: String) {
        try {
            NativeTunnelConfig.parse(text, false)
            fail("Expected profile rejection")
        } catch (
            e: IllegalArgumentException,
        ) {
            assertFalse(e.message.orEmpty().contains(key))
        }
    }

    @Test fun routesAreMaskedButInterfaceAddressesAreNot() {
        val config = NativeTunnelConfig.parse(profile(), false)
        assertEquals("10.0.0.2/32", config.addresses.single().text())
        assertEquals("10.0.0.0/24", config.routes.single().text())
        val uapi = config.userspace { NativeTunnelConfig.numericAddress("192.0.2.1") }
        assertTrue(uapi.contains("allowed_ip=10.0.0.0/24\n"))
        assertFalse(config.toString().contains(key))
    }

    @Test fun zeroIdentitiesRejectedButDisabledPskAllowed() {
        reject(profile().replace("PrivateKey = $key", "PrivateKey = $zero"))
        reject(profile().replace("PublicKey = $key", "PublicKey = $zero"))
        NativeTunnelConfig.parse(profile() + "\nPresharedKey = $zero", false)
    }

    @Test fun duplicatePeerCannotSilentlyReplaceRoutes() {
        reject(profile() + "\n[Peer]\nPublicKey = $key\nAllowedIPs = 192.0.2.0/24")
    }

    @Test fun dnsMustBeCoveredByInstalledRoutes() {
        val config = NativeTunnelConfig.parse(profile(), false)
        assertEquals(1, config.routedDns(listOf("10.0.0.1")).size)
        try {
            config.routedDns(listOf("192.0.2.53"))
            fail("Expected uncovered DNS rejection")
        } catch (
            e: IllegalArgumentException,
        ) {
            assertFalse(e.message.orEmpty().contains("192.0.2.53"))
        }
    }

    @Test fun defaultRouteDoesNotPermitLoopbackOrMulticastDns() {
        val config = NativeTunnelConfig.parse(profile().replace("10.0.0.129/24", "0.0.0.0/0, ::/0"), false)
        for (dns in listOf(emptyList(), listOf("127.0.0.1"), listOf("0.0.0.0"), listOf("ff02::1"))) {
            try {
                config.routedDns(dns)
                fail("Expected unsafe DNS rejection")
            } catch (_: IllegalArgumentException) {
            }
        }
    }

    @Test fun endpointResolverFailureDoesNotEchoHostnameOrResolverDiagnostic() {
        val config = NativeTunnelConfig.parse(profile(), false)
        try {
            config.userspace { throw IllegalStateException("resolver leaked example.invalid") }
            fail("Expected resolution failure")
        } catch (e: IllegalArgumentException) {
            assertEquals("Invalid or unsupported native tunnel configuration", e.message)
            assertFalse(e.message.orEmpty().contains("example.invalid"))
            assertFalse(e.message.orEmpty().contains("resolver leaked"))
        }
    }

    @Test fun ipv6EndpointIsBracketedInUserspaceConfig() {
        val config = NativeTunnelConfig.parse(profile(), false)
        val uapi = config.userspace { NativeTunnelConfig.numericAddress("2001:db8::1") }
        assertTrue(uapi.contains("endpoint=[2001:db8:0:0:0:0:0:1]:51820\n"))
    }

    @Test fun awgFieldsRemainProtocolGated() {
        val awg =
            profile().replace(
                "Address = 10.0.0.2/32",
                "S4 = 25\nH1 = 1-100\nAddress = 10.0.0.2/32",
            )
        reject(awg)
        val uapi =
            NativeTunnelConfig
                .parse(awg, true)
                .userspace { NativeTunnelConfig.numericAddress("192.0.2.1") }
        assertTrue(uapi.contains("s4=25\n"))
        assertTrue(uapi.contains("h1=1-100\n"))
    }

    @Test fun unsafeOrUnsupportedProfileSyntaxIsRejected() {
        for (candidate in listOf(
            profile().replace("Address =", "PostUp = run-command\nAddress ="),
            profile() + "\nTable = off",
            profile().replace(":51820", ":65536"),
            profile() + "\u0000",
        )) {
            reject(candidate)
        }
    }
}
