package com.blackoutkit.vpn

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.concurrent.CountDownLatch
import java.util.concurrent.atomic.AtomicInteger
import kotlin.concurrent.thread

class EngineSessionAdmissionTest {
    @Test
    fun cleanupFailureRetainsAdmissionAndForeignReleaseDoesNothing() {
        val admission = EngineSessionAdmission()
        val service = Any()
        val probe = Any()
        assertTrue(admission.claim(service))
        assertFalse(admission.claim(probe))
        admission.release(probe)
        assertTrue(admission.owns(service))
        assertFalse(admission.claim(probe))
        admission.release(service)
        assertTrue(admission.claim(probe))
        assertFalse(admission.owns(service))
    }

    @Test
    fun concurrentClaimsAdmitExactlyOneOwner() {
        val admission = EngineSessionAdmission()
        val start = CountDownLatch(1)
        val winners = AtomicInteger()
        val threads =
            List(8) {
                thread {
                    start.await()
                    if (admission.claim(Any())) winners.incrementAndGet()
                }
            }
        start.countDown()
        threads.forEach { it.join() }
        org.junit.Assert.assertEquals(1, winners.get())
    }
}
