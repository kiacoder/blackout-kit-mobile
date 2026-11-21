package com.blackoutkit.vpn

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

class VpnSessionExecutorTest {
    @Test
    fun nestedForCurrentCompletesWithoutDeadlock() {
        val executor = VpnSessionExecutor(dispatch = { it() })
        val started = CountDownLatch(1)
        val nested = CountDownLatch(1)

        val ticket = executor.start(
            cleanup = {},
            start = { started.countDown(); true },
            complete = {},
        ) ?: error("executor refused start")

        assertTrue(started.await(2, TimeUnit.SECONDS))

        executor.forCurrent(ticket) {
            executor.forCurrent(ticket) {
                nested.countDown()
            }
        }

        assertTrue("nested forCurrent callback did not complete", nested.await(2, TimeUnit.SECONDS))
        executor.stop(cleanup = {}, close = true)
    }

    @Test
    fun staleTicketCannotPublishAfterNewGenerationStarts() {
        val executor = VpnSessionExecutor(dispatch = { it() })
        val firstStarted = CountDownLatch(1)
        val secondStarted = CountDownLatch(1)
        val staleRan = CountDownLatch(1)

        val first = executor.start(
            cleanup = {},
            start = { firstStarted.countDown(); true },
            complete = {},
        ) ?: error("executor refused first start")
        assertTrue(firstStarted.await(2, TimeUnit.SECONDS))

        executor.start(
            cleanup = {},
            start = { secondStarted.countDown(); true },
            complete = {},
        ) ?: error("executor refused second start")
        assertTrue(secondStarted.await(2, TimeUnit.SECONDS))

        executor.forCurrent(first) {
            staleRan.countDown()
        }

        assertFalse("stale ticket callback ran after a newer generation", staleRan.await(250, TimeUnit.MILLISECONDS))
        executor.stop(cleanup = {}, close = true)
    }
}
