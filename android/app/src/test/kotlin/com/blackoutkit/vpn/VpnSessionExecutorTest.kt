package com.blackoutkit.vpn

import org.junit.Assert.assertEquals
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

        val ticket =
            executor.start(
                cleanup = {},
                start = {
                    started.countDown()
                    true
                },
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

        val first =
            executor.start(
                cleanup = {},
                start = {
                    firstStarted.countDown()
                    true
                },
                complete = {},
            ) ?: error("executor refused first start")
        assertTrue(firstStarted.await(2, TimeUnit.SECONDS))

        executor.start(
            cleanup = {},
            start = {
                secondStarted.countDown()
                true
            },
            complete = {},
        ) ?: error("executor refused second start")
        assertTrue(secondStarted.await(2, TimeUnit.SECONDS))

        executor.forCurrent(first) {
            staleRan.countDown()
        }

        assertFalse("stale ticket callback ran after a newer generation", staleRan.await(250, TimeUnit.MILLISECONDS))
        executor.stop(cleanup = {}, close = true)
    }

    @Test
    fun stopDuringBlockingStartWaitsAndThenCleansInOwnerOrder() {
        val executor = VpnSessionExecutor(dispatch = { it() })
        val enteredStart = CountDownLatch(1)
        val releaseStart = CountDownLatch(1)
        val stopComplete = CountDownLatch(1)
        val events = mutableListOf<String>()

        executor.start(
            cleanup = { events.add("cleanup") },
            start = {
                events.add("start")
                enteredStart.countDown()
                assertTrue(releaseStart.await(2, TimeUnit.SECONDS))
                true
            },
            complete = { events.add("stale-complete") },
        ) ?: error("executor refused start")

        assertTrue(enteredStart.await(2, TimeUnit.SECONDS))
        executor.stop(
            cleanup = { events.add("stop-cleanup") },
            complete = { _, cleaned ->
                assertTrue(cleaned)
                events.add("stop-complete")
                stopComplete.countDown()
            },
            close = true,
        )

        assertFalse(
            "stop raced cleanup against blocking native start",
            stopComplete.await(150, TimeUnit.MILLISECONDS),
        )
        releaseStart.countDown()
        assertTrue(stopComplete.await(2, TimeUnit.SECONDS))
        assertEquals(
            listOf("cleanup", "start", "cleanup", "stop-cleanup", "stop-complete"),
            events,
        )
    }

    @Test
    fun stopCompletionSettlesItsCallerEvenAfterNewerStartExists() {
        val executor = VpnSessionExecutor(dispatch = { it() })
        val blockerEntered = CountDownLatch(1)
        val releaseBlocker = CountDownLatch(1)
        val stopSettled = CountDownLatch(1)
        var stopWasCurrent = true
        var stopWasCleaned = false

        executor.start(
            cleanup = {},
            start = {
                blockerEntered.countDown()
                assertTrue(releaseBlocker.await(2, TimeUnit.SECONDS))
                true
            },
            complete = {},
        ) ?: error("executor refused blocker")
        assertTrue(blockerEntered.await(2, TimeUnit.SECONDS))

        executor.stop(
            cleanup = {},
            complete = { current, cleaned ->
                stopWasCurrent = current
                stopWasCleaned = cleaned
                stopSettled.countDown()
            },
        )
        executor.start(
            cleanup = {},
            start = { true },
            complete = {},
        ) ?: error("executor refused replacement")

        releaseBlocker.countDown()
        assertTrue(stopSettled.await(2, TimeUnit.SECONDS))
        assertFalse("older stop must not claim it still owns terminal UI state", stopWasCurrent)
        assertTrue(stopWasCleaned)
        executor.stop(cleanup = {}, close = true)
    }
}
