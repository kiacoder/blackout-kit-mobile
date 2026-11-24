package com.blackoutkit.vpn

import org.junit.Assert.*
import org.junit.Test
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors

class GoRuntimeAdmissionTest {
    @Test fun discoveryDoesNotClaimRuntime() {
        val gate = GoRuntimeAdmission()
        assertTrue(gate.allows(GoRuntimeAdmission.Family.EMBEDDED))
        assertTrue(gate.allows(GoRuntimeAdmission.Family.NATIVE_TUNNELS))
        assertNull(gate.current())
    }

    @Test fun runtimeClaimIsStickyInBothDirections() {
        for (family in GoRuntimeAdmission.Family.values()) {
            val gate = GoRuntimeAdmission()
            val other = GoRuntimeAdmission.Family.values().first { it != family }
            assertTrue(gate.claim(family))
            assertTrue(gate.claim(family))
            assertFalse(gate.allows(other))
            assertFalse(gate.claim(other))
            assertEquals(family, gate.current())
        }
    }

    @Test fun concurrentClaimsCannotLoadTwoFamilies() {
        val gate = GoRuntimeAdmission()
        val start = CountDownLatch(1)
        val executor = Executors.newFixedThreadPool(2)
        try {
            val claims = GoRuntimeAdmission.Family.values().map { family ->
                executor.submit<Boolean> { start.await(); gate.claim(family) }
            }
            start.countDown()
            assertEquals(1, claims.count { it.get() })
        } finally {
            executor.shutdownNow()
        }
    }
}
