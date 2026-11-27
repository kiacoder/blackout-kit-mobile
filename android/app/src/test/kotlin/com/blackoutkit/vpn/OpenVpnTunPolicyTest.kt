package com.blackoutkit.vpn

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class OpenVpnTunPolicyTest {
    private val v4 = NativeTunnelConfig.numericAddress("192.0.2.2")
    private val v6 = NativeTunnelConfig.numericAddress("2001:db8::2")
    private val dns4 = NativeTunnelConfig.numericAddress("192.0.2.53")
    private val dns6 = NativeTunnelConfig.numericAddress("2001:db8::53")
    private val default4 = NativeTunnelConfig.Network(NativeTunnelConfig.numericAddress("0.0.0.0"), 0)
    private val default6 = NativeTunnelConfig.Network(NativeTunnelConfig.numericAddress("::"), 0)
    private val partial6 = NativeTunnelConfig.Network(NativeTunnelConfig.numericAddress("2001:db8::"), 32)

    @Test
    fun acceptsFullIpv4AndDualStackOnly() {
        assertTrue(OpenVpnTunPolicy.admits(listOf(v4), listOf(default4), listOf(dns4)))
        assertTrue(OpenVpnTunPolicy.admits(listOf(v4, v6), listOf(default4, default6), listOf(dns4, dns6)))
    }

    @Test
    fun rejectsPartiallyConfiguredFamilies() {
        assertFalse(OpenVpnTunPolicy.admits(listOf(v4), listOf(default4, partial6), listOf(dns4)))
        assertFalse(OpenVpnTunPolicy.admits(listOf(v4), listOf(default4), listOf(dns6)))
        assertFalse(OpenVpnTunPolicy.admits(listOf(v4, v6), listOf(default4, partial6), listOf(dns4)))
        assertFalse(OpenVpnTunPolicy.admits(listOf(v4), listOf(default4, default6), listOf(dns4)))
        assertFalse(OpenVpnTunPolicy.admits(listOf(v6), listOf(default6), listOf(dns6)))
    }

    @Test
    fun rejectsMissingOrLinkLocalDns() {
        val local = NativeTunnelConfig.numericAddress("169.254.1.53")
        assertFalse(OpenVpnTunPolicy.admits(listOf(v4), listOf(default4), emptyList()))
        assertFalse(OpenVpnTunPolicy.admits(listOf(v4), listOf(default4), listOf(local)))
    }
}
