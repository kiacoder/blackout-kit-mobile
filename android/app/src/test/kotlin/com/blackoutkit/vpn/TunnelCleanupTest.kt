package com.blackoutkit.vpn

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class TunnelCleanupTest {
    @Test
    fun failedStopDoesNotReleaseDescriptorsAndStillAttemptsOtherStops() {
        val events = mutableListOf<String>()
        val stopped =
            stopEnginesBeforeRelease(
                listOf(
                    {
                        events.add("first")
                        error("synthetic failure")
                    },
                    {
                        events.add("second")
                        Unit
                    },
                ),
            ) { events.add("release") }
        assertFalse(stopped)
        assertEquals(listOf("first", "second"), events)
    }

    @Test
    fun successfulRetryReleasesAfterAllStops() {
        val events = mutableListOf<String>()
        var fail = true
        val stops =
            listOf<() -> Unit>(
                {
                    events.add("first")
                    check(!fail)
                },
                {
                    events.add("second")
                    Unit
                },
            )
        assertFalse(stopEnginesBeforeRelease(stops) { events.add("release") })
        fail = false
        assertTrue(stopEnginesBeforeRelease(stops) { events.add("release") })
        assertEquals(listOf("first", "second", "first", "second", "release"), events)
    }

    @Test
    fun linkageFailureAlsoBlocksRelease() {
        assertFalse(
            stopEnginesBeforeRelease(listOf({ throw UnsatisfiedLinkError("synthetic") })) {
                error("must not release")
            },
        )
    }
}
