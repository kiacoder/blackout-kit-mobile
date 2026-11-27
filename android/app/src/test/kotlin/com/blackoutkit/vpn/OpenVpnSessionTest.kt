package com.blackoutkit.vpn

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

class OpenVpnSessionTest {
    private class Fake : OpenVpnSession.Backend {
        val entered = CountDownLatch(1)
        val finish = CountDownLatch(1)
        val released = AtomicBoolean(false)
        var cancelWorks = true

        override fun run(report: (Boolean) -> Unit) {
            report(true)
            entered.countDown()
            finish.await()
            report(false)
        }

        override fun cancel() {
            if (cancelWorks) finish.countDown()
        }

        override fun release() {
            released.set(true)
        }
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
        val session = OpenVpnSession(fake, current::get)
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
