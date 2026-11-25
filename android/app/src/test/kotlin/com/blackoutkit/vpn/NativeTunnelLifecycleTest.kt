package com.blackoutkit.vpn

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

/** Unit tests of production ownership logic, not Android/JNI execution. */
class NativeTunnelLifecycleTest {
    private class Backend : NativeTunnelLifecycle.Backend {
        var closed = false
        var startResult = 4
        var unresolved = false
        var stopFails = false
        var statusFails = false
        var stops = 0

        override fun turnOn(
            fd: Int,
            settings: String,
        ): Int {
            if (unresolved) throw UnsatisfiedLinkError("private diagnostic")
            return startResult
        }

        override fun turnOff(handle: Int) {
            stops++
            check(!stopFails) { "private diagnostic" }
        }

        override fun sockets(handle: Int) = listOf(10, 11)

        override fun isClosed(handle: Int): Boolean {
            if (statusFails) throw UnsatisfiedLinkError("private diagnostic")
            return closed
        }
    }

    @Test fun closureAndUnknownHealthDoNotLoseOwnership() {
        val owner = NativeTunnelLifecycle()
        val backend = Backend()
        assertTrue(owner.isClosed())
        assertTrue(owner.start(backend, "", { 30 }, { fail("double close") }, { true }))
        assertFalse(owner.isClosed())
        backend.closed = true
        assertTrue(owner.isClosed())
        backend.statusFails = true
        assertTrue(owner.isClosed())
        assertEquals(0, backend.stops)
        owner.stop()
        owner.stop()
        assertEquals(1, backend.stops)
    }

    @Test fun initiallyClosedDeviceIsNeverReportedStarted() {
        val owner = NativeTunnelLifecycle()
        val backend = Backend().apply { closed = true }
        assertFalse(owner.start(backend, "", { 30 }, { fail("double close") }, { true }))
        assertEquals(1, backend.stops)
    }

    @Test fun missingEntryClosesOnlyTheUndeliveredDuplicate() {
        val owner = NativeTunnelLifecycle()
        val backend = Backend().apply { unresolved = true }
        val closed = mutableListOf<Int>()
        assertFalse(owner.start(backend, "", { 30 }, { closed.add(it) }, { true }))
        assertEquals(listOf(30), closed)
        assertFalse(owner.lastError!!.contains("private diagnostic"))
        assertEquals(0, backend.stops)
    }

    @Test fun protectionFailureClosesNativeHandleNotTransferredFd() {
        val owner = NativeTunnelLifecycle()
        val backend = Backend()
        assertFalse(owner.start(backend, "", { 30 }, { fail("double close") }, { it == 10 }))
        assertEquals(1, backend.stops)
        assertTrue(owner.isClosed())
    }

    @Test fun failedCleanupPreventsReplacementUntilItSucceeds() {
        val owner = NativeTunnelLifecycle()
        val backend = Backend().apply { stopFails = true }
        assertTrue(owner.start(backend, "", { 30 }, {}, { true }))
        try {
            owner.stop()
            fail("Expected cleanup failure")
        } catch (_: IllegalStateException) {
        }
        assertFalse(owner.start(Backend(), "", { error("Replacement detached before cleanup") }, {}, { true }))
        backend.stopFails = false
        owner.stop()
        assertEquals(2, backend.stops)
        assertTrue(owner.isClosed())
    }

    @Test fun failedNativeStartConsumesTransferredFdWithoutExtraClose() {
        val owner = NativeTunnelLifecycle()
        val backend = Backend().apply { startResult = -1 }
        assertFalse(
            owner.start(backend, "", {
                30
            }, { fail("native already owns fd") }, { error("protect after failed start") }),
        )
        assertEquals(0, backend.stops)
        assertTrue(owner.isClosed())
    }

    @Test fun missingSocketsFailClosedAndStopNativeHandle() {
        val owner = NativeTunnelLifecycle()
        val backend =
            object : NativeTunnelLifecycle.Backend {
                var stops = 0

                override fun turnOn(
                    fd: Int,
                    settings: String,
                ) = 7

                override fun turnOff(handle: Int) {
                    stops++
                }

                override fun sockets(handle: Int) = listOf(-1, -1)

                override fun isClosed(handle: Int) = false
            }
        assertFalse(
            owner.start(backend, "", { 30 }, { fail("double close") }, { error("no socket should be protected") }),
        )
        assertEquals(1, backend.stops)
        assertTrue(owner.isClosed())
    }

    @Test fun singleAddressFamilySocketIsEnough() {
        val owner = NativeTunnelLifecycle()
        val backend =
            object : NativeTunnelLifecycle.Backend {
                override fun turnOn(
                    fd: Int,
                    settings: String,
                ) = 7

                override fun turnOff(handle: Int) {
                    // This fake represents a backend that has already closed.
                }

                override fun sockets(handle: Int) = listOf(-1, 12)

                override fun isClosed(handle: Int) = false
            }
        val protected = mutableListOf<Int>()
        assertTrue(
            owner.start(backend, "", { 30 }, { fail("double close") }, {
                protected.add(it)
                true
            }),
        )
        assertEquals(listOf(12), protected)
        owner.stop()
    }

    @Test fun secondStartCannotDetachOrReplaceLiveBackend() {
        val owner = NativeTunnelLifecycle()
        val first = Backend()
        assertTrue(owner.start(first, "", { 30 }, {}, { true }))
        assertFalse(owner.start(Backend(), "", { error("replacement detached") }, {}, { true }))
        assertEquals("A native tunnel is already active", owner.lastError)
        owner.stop()
        assertEquals(1, first.stops)
    }

    @Test fun protectionExceptionIsRedactedAndCleansNativeHandle() {
        val owner = NativeTunnelLifecycle()
        val backend = Backend()
        assertFalse(owner.start(backend, "", { 30 }, {}, { throw IllegalStateException("secret diagnostic") }))
        assertFalse(owner.lastError.orEmpty().contains("secret"))
        assertEquals(1, backend.stops)
        assertTrue(owner.isClosed())
    }

    @Test fun restartMaySwitchBackendOnlyAfterSuccessfulStop() {
        val owner = NativeTunnelLifecycle()
        val wg = Backend()
        val awg = Backend().apply { startResult = 8 }
        assertTrue(owner.start(wg, "", { 30 }, {}, { true }))
        owner.stop()
        assertTrue(owner.start(awg, "", { 31 }, {}, { true }))
        owner.stop()
        assertEquals(1, wg.stops)
        assertEquals(1, awg.stops)
        assertTrue(owner.isClosed())
    }
}
