package com.blackoutkit.vpn

import org.junit.Assert.*
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
        override fun turnOn(fd: Int, settings: String): Int {
            if (unresolved) throw UnsatisfiedLinkError("private diagnostic")
            return startResult
        }
        override fun turnOff(handle: Int) {
            stops++
            if (stopFails) throw IllegalStateException("private diagnostic")
        }
        override fun sockets(handle: Int) = listOf(10, 11)
        override fun isClosed(handle: Int): Boolean {
            if (statusFails) throw UnsatisfiedLinkError("private diagnostic")
            return closed
        }
    }

    @Test fun closureAndUnknownHealthDoNotLoseOwnership() {
        val owner = NativeTunnelLifecycle(); val backend = Backend()
        assertTrue(owner.isClosed())
        assertTrue(owner.start(backend, "", { 30 }, { fail("double close") }, { true }))
        assertFalse(owner.isClosed())
        backend.closed = true
        assertTrue(owner.isClosed())
        backend.statusFails = true
        assertTrue(owner.isClosed())
        assertEquals(0, backend.stops)
        owner.stop(); owner.stop()
        assertEquals(1, backend.stops)
    }

    @Test fun initiallyClosedDeviceIsNeverReportedStarted() {
        val owner = NativeTunnelLifecycle(); val backend = Backend().apply { closed = true }
        assertFalse(owner.start(backend, "", { 30 }, { fail("double close") }, { true }))
        assertEquals(1, backend.stops)
    }

    @Test fun missingEntryClosesOnlyTheUndeliveredDuplicate() {
        val owner = NativeTunnelLifecycle(); val backend = Backend().apply { unresolved = true }
        val closed = mutableListOf<Int>()
        assertFalse(owner.start(backend, "", { 30 }, { closed.add(it) }, { true }))
        assertEquals(listOf(30), closed)
        assertFalse(owner.lastError!!.contains("private diagnostic"))
        assertEquals(0, backend.stops)
    }

    @Test fun protectionFailureClosesNativeHandleNotTransferredFd() {
        val owner = NativeTunnelLifecycle(); val backend = Backend()
        assertFalse(owner.start(backend, "", { 30 }, { fail("double close") }, { it == 10 }))
        assertEquals(1, backend.stops)
        assertTrue(owner.isClosed())
    }

    @Test fun failedCleanupPreventsReplacementUntilItSucceeds() {
        val owner = NativeTunnelLifecycle(); val backend = Backend().apply { stopFails = true }
        assertTrue(owner.start(backend, "", { 30 }, {}, { true }))
        try { owner.stop(); fail("Expected cleanup failure") } catch (_: IllegalStateException) {}
        assertFalse(owner.start(Backend(), "", { error("Replacement detached before cleanup") }, {}, { true }))
        backend.stopFails = false; owner.stop()
        assertEquals(2, backend.stops)
        assertTrue(owner.isClosed())
    }
}
