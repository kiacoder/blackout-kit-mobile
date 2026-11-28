package com.blackoutkit.vpn

import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class MihomoRoutePolicyTest {
    @Test
    fun strictResolverValidation() {
        assertEquals(1, MihomoRoutePolicy.dns(listOf("192.0.2.53", "192.0.2.53")).size)
        for (bad in listOf("example.test", "::1", "2001:db8::1", "127.0.0.1", "169.254.1.1", "224.0.0.1", "0.0.0.0")) {
            assertThrows(IllegalArgumentException::class.java) {
                MihomoRoutePolicy.dns(listOf("192.0.2.53", bad))
            }
        }
        assertThrows(IllegalArgumentException::class.java) { MihomoRoutePolicy.dns(emptyList()) }
    }

    @Test
    fun rejectsMixedListsAndRecursiveEngineUid() {
        MihomoRoutePolicy.checkApps("self", listOf("fixture"), emptyList())
        MihomoRoutePolicy.checkApps("self", emptyList(), listOf("fixture"))
        assertThrows(IllegalArgumentException::class.java) {
            MihomoRoutePolicy.checkApps("self", listOf("self"), emptyList())
        }
        assertThrows(IllegalArgumentException::class.java) {
            MihomoRoutePolicy.checkApps("self", listOf("a"), listOf("b"))
        }
    }
}
