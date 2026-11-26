package com.blackoutkit.vpn

import org.junit.Assert.assertEquals
import org.junit.Test

class AvailableNetworkRegistryTest {
    @Test
    fun tracksAvailableAndLostNetworksWithoutDuplicates() {
        val registry = AvailableNetworkRegistry<String>()
        registry.available("wifi")
        registry.available("cellular")
        registry.available("wifi")
        assertEquals(listOf("wifi", "cellular"), registry.snapshot())
        val previous = registry.snapshot()
        registry.lost("wifi")
        registry.lost("unknown")
        assertEquals(listOf("cellular"), registry.snapshot())
        assertEquals(listOf("wifi", "cellular"), previous)
    }

    @Test
    fun closeRejectsLateCallbacksAndIsIdempotent() {
        val registry = AvailableNetworkRegistry<String>()
        registry.available("wifi")
        registry.close()
        registry.available("cellular")
        registry.lost("wifi")
        registry.close()
        assertEquals(emptyList<String>(), registry.snapshot())
    }
}
