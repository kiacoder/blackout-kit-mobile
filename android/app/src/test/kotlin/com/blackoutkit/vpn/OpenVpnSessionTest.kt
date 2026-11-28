package com.blackoutkit.vpn

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong

class OpenVpnSessionTest {
    private class Fake : OpenVpnSession.Backend {
        val entered = CountDownLatch(1)
        val finish = CountDownLatch(1)
        val released = AtomicBoolean(false)
        var cancelWorks = true
        var reconnects = 0
        lateinit var notifyLink: (Boolean) -> Unit

        override fun run(report: (Boolean) -> Unit) {
            notifyLink = report
            report(true)
            entered.countDown()
            finish.await()
            report(false)
        }

        override fun reconnect(): Boolean {
            reconnects++
            return true
        }

        override fun cancel() {
            if (cancelWorks) finish.countDown()
        }

        override fun release() {
            released.set(true)
        }
    }

    @Test
    fun debouncesNetworkMembershipAndIgnoresUnknownObservations() {
        val changes = OpenVpnNetworkChanges()
        assertFalse(changes.observe(setOf(1L)))
        assertFalse(changes.observe(setOf(1L)))
        assertFalse(changes.observe(setOf(1L, 2L)))
        assertFalse(changes.observe(setOf(1L)))
        assertFalse(changes.observe(setOf(2L)))
        assertFalse(changes.observe(null))
        assertFalse(changes.observe(setOf(2L)))
        assertTrue(changes.observe(setOf(2L)))
        assertFalse(changes.observe(setOf(2L)))
    }

    @Test
    fun restorationFromEmptyRequestsRecoveryOnlyOnce() {
        val changes = OpenVpnNetworkChanges()
        changes.observe(setOf(1L))
        changes.observe(setOf(1L))
        assertFalse(changes.observe(emptySet()))
        assertFalse(changes.observe(emptySet()))
        assertFalse(changes.observe(setOf(1L)))
        assertTrue(changes.observe(setOf(1L)))
        assertFalse(changes.observe(setOf(1L)))
    }

    @Test
    fun handoverReusesWorkerAndNeverRequestsAfterTicketInvalidation() {
        val fake = Fake()
        val current = AtomicBoolean(true)
        val session = OpenVpnSession(fake, current = current::get)
        session.start()
        try {
            assertTrue(fake.entered.await(1, TimeUnit.SECONDS))
            repeat(2) { session.observeNetworks(setOf(1L)) }
            repeat(2) { session.observeNetworks(setOf(2L)) }
            assertEquals(1, fake.reconnects)
            assertFalse(fake.released.get())
            fake.notifyLink(false)
            repeat(2) { session.observeNetworks(setOf(3L)) }
            assertEquals(2, fake.reconnects)
            current.set(false)
            repeat(2) { session.observeNetworks(setOf(4L)) }
            assertEquals(2, fake.reconnects)
        } finally {
            session.stop(1000)
        }
    }

    @Test
    fun recoveringWorkerCanRestoreConnectionWithoutRelease() {
        val fake = Fake()
        val now = AtomicLong(0)
        val session = OpenVpnSession(fake, recoveryMs = 100, now = now::get) { true }
        session.start()
        try {
            assertTrue(fake.entered.await(1, TimeUnit.SECONDS))
            fake.notifyLink(false)
            assertEquals(OpenVpnSession.Link.RECOVERING, session.link())
            assertFalse(fake.released.get())
            now.set(TimeUnit.MILLISECONDS.toNanos(70))
            fake.notifyLink(true)
            assertEquals(OpenVpnSession.Link.CONNECTED, session.link())
            fake.notifyLink(false)
            now.set(TimeUnit.MILLISECONDS.toNanos(120))
            assertEquals(OpenVpnSession.Link.RECOVERING, session.link())
        } finally {
            session.stop(1000)
        }
        assertTrue(fake.released.get())
    }

    @Test
    fun repeatedDownEventsDoNotExtendDeadlineAndLateSuccessIsRejected() {
        val fake = Fake()
        val now = AtomicLong(0)
        val session = OpenVpnSession(fake, recoveryMs = 100, now = now::get) { true }
        session.start()
        try {
            assertTrue(fake.entered.await(1, TimeUnit.SECONDS))
            fake.notifyLink(false)
            now.set(TimeUnit.MILLISECONDS.toNanos(90))
            fake.notifyLink(false)
            now.set(TimeUnit.MILLISECONDS.toNanos(101))
            fake.notifyLink(true)
            assertEquals(OpenVpnSession.Link.ENDED, session.link())
            assertFalse(session.isConnected())
            assertFalse(fake.released.get())
        } finally {
            session.stop(1000)
        }
        assertTrue(fake.released.get())
    }

    @Test
    fun exitedWorkerDoesNotWaitForRecoveryWindow() {
        val fake = Fake()
        val session = OpenVpnSession(fake) { true }
        session.start()
        assertTrue(fake.entered.await(1, TimeUnit.SECONDS))
        fake.finish.countDown()
        session.stop(1000)
        assertEquals(OpenVpnSession.Link.ENDED, session.link())
    }

    @Test
    fun stopJoinsBeforeRelease() {
        val fake = Fake()
        val session = OpenVpnSession(fake) { true }
        session.start()
        try {
            assertTrue(session.awaitConnected(1000))
            assertFalse(fake.released.get())
        } finally {
            session.stop(1000)
        }
        assertTrue(fake.released.get())
        assertFalse(session.isConnected())
    }

    @Test
    fun cancelledTicketNeverReportsConnected() {
        val fake = Fake()
        val current = AtomicBoolean(true)
        val session = OpenVpnSession(fake, current = current::get)
        session.start()
        try {
            assertTrue(fake.entered.await(1, TimeUnit.SECONDS))
            current.set(false)
            assertFalse(session.awaitConnected(1000))
        } finally {
            session.stop(1000)
        }
    }

    @Test
    fun timedOutStopRetainsNativeOwnership() {
        val fake = Fake().apply { cancelWorks = false }
        val session = OpenVpnSession(fake) { true }
        session.start()
        try {
            assertTrue(fake.entered.await(1, TimeUnit.SECONDS))
            val failed = runCatching { session.stop(10) }.isFailure
            assertTrue(failed)
            assertFalse(fake.released.get())
            assertFalse(session.isConnected())
        } finally {
            fake.finish.countDown()
            session.stop(1000)
        }
        assertTrue(fake.released.get())
    }
}
