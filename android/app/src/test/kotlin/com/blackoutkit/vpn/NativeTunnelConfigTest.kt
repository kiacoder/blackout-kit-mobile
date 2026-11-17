package com.blackoutkit.vpn

import org.junit.Assert.*
import org.junit.Test
import java.util.Base64

/** JVM parser tests; no Android interface or live credentials. */
class NativeTunnelConfigTest {
    // Synthetic bytes only; JDK Base64 is used in tests, not API24 production code.
    private val key = Base64.getEncoder().encodeToString(ByteArray(32) { 1 })
    private val zero = Base64.getEncoder().encodeToString(ByteArray(32))
    private fun profile() = """
        [Interface]
        PrivateKey = $key
        Address = 10.0.0.2/32
        [Peer]
        PublicKey = $key
        Endpoint = example.invalid:51820
        AllowedIPs = 10.0.0.129/24
    """.trimIndent()
    private fun reject(text: String) {
        try { NativeTunnelConfig.parse(text, false); fail("Expected profile rejection") }
        catch (e: IllegalArgumentException) { assertFalse(e.message.orEmpty().contains(key)) }
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
        try { config.routedDns(listOf("192.0.2.53")); fail("Expected uncovered DNS rejection") }
        catch (e: IllegalArgumentException) { assertFalse(e.message.orEmpty().contains("192.0.2.53")) }
    }

    @Test fun defaultRouteDoesNotPermitLoopbackOrMulticastDns() {
        val config = NativeTunnelConfig.parse(profile().replace("10.0.0.129/24", "0.0.0.0/0, ::/0"), false)
        for (dns in listOf(emptyList(), listOf("127.0.0.1"), listOf("0.0.0.0"), listOf("ff02::1"))) {
            try { config.routedDns(dns); fail("Expected unsafe DNS rejection") }
            catch (_: IllegalArgumentException) {}
        }
    }
}
