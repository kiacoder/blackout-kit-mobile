package com.blackoutkit.vpn

import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class OpenVpnAppPolicyTest {
    private val self = "com.blackoutkit.test"
    private val pushed = listOf(NativeTunnelConfig.numericAddress("10.77.0.1"))

    @Test
    fun defaultPreservesPushedDnsAndNoAppExclusions() {
        val policy = OpenVpnAppPolicy.create(self, emptyList(), emptyList(), null)
        assertEquals(emptyList<String>(), policy.allowed)
        assertEquals(emptyList<String>(), policy.disallowed)
        assertEquals(pushed, policy.effectiveDns(pushed))
    }

    @Test
    fun explicitDnsReplacesRatherThanAppends() {
        val policy = OpenVpnAppPolicy.create(self, emptyList(), emptyList(), listOf("192.0.2.53", "192.0.2.53"))
        assertEquals(listOf(NativeTunnelConfig.numericAddress("192.0.2.53")), policy.effectiveDns(pushed))
    }

    @Test
    fun whitelistIncludesProbeAppAndBlacklistIsExact() {
        val allow = OpenVpnAppPolicy.create(self, listOf("example.app", "example.app"), emptyList(), null)
        assertEquals(listOf("example.app", self), allow.allowed)
        val deny = OpenVpnAppPolicy.create(self, emptyList(), listOf("example.app", "example.app"), null)
        assertEquals(listOf("example.app"), deny.disallowed)
    }

    @Test
    fun rejectsUnsafeResolvers() {
        for (value in listOf("127.0.0.1", "0.0.0.0", "169.254.1.1", "224.0.0.1", "2001:db8::53", "example.test")) {
            assertThrows(IllegalArgumentException::class.java) {
                OpenVpnAppPolicy.create(self, emptyList(), emptyList(), listOf(value))
            }
        }
        assertThrows(IllegalArgumentException::class.java) {
            OpenVpnAppPolicy.create(self, emptyList(), emptyList(), emptyList())
        }
    }

    @Test
    fun rejectsMixedOversizedOrSelfBypassPolicy() {
        assertThrows(IllegalArgumentException::class.java) {
            OpenVpnAppPolicy.create(self, listOf("example.app"), listOf("other.app"), null)
        }
        assertThrows(IllegalArgumentException::class.java) {
            OpenVpnAppPolicy.create(self, emptyList(), listOf(self), null)
        }
        assertThrows(IllegalArgumentException::class.java) {
            OpenVpnAppPolicy.create(self, List(101) { "example.app" }, emptyList(), null)
        }
    }
}
