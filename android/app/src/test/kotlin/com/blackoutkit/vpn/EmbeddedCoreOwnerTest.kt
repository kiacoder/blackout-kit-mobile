package com.blackoutkit.vpn

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

class EmbeddedCoreOwnerTest {
    @Test
    fun failedCloseRetainsOwnerAndPreventsReplacement() {
        val original = Any()
        var failClose = true
        var creations = 0
        val owner =
            EmbeddedCoreOwner<Any> {
                check(!failClose) { "synthetic close failure" }
            }
        assertTrue(owner.start({ original }, { true }))
        assertTrue(runCatching { owner.stop() }.isFailure)
        assertFalse(owner.running)
        assertSame(original, owner.current)
        assertTrue(
            runCatching {
                owner.start({
                    creations++
                    Any()
                }, { true })
            }.isFailure,
        )
        assertEquals(0, creations)
        assertSame(original, owner.current)
        failClose = false
        assertTrue(
            owner.start({
                creations++
                Any()
            }, { true }),
        )
        assertEquals(1, creations)
        owner.stop()
        assertNull(owner.current)
    }

    @Test
    fun partiallyStartedCoreIsClosedBeforeReportingFailure() {
        val created = Any()
        val closed = mutableListOf<Any>()
        val owner = EmbeddedCoreOwner<Any> { closed.add(it) }
        assertFalse(owner.start({ created }, { false }))
        assertEquals(listOf(created), closed)
        assertNull(owner.current)
        assertFalse(owner.running)
    }

    @Test
    fun failedActivationAndFailedCleanupKeepHandle() {
        val created = Any()
        val owner = EmbeddedCoreOwner<Any> { error("synthetic cleanup failure") }
        assertTrue(runCatching { owner.start({ created }, { error("synthetic activation failure") }) }.isFailure)
        assertSame(created, owner.current)
        assertFalse(owner.running)
    }

    @Test
    fun nativeBoundaryRestoresInterruption() {
        try {
            assertTrue(embeddedCall<Unit> { throw InterruptedException() }.isFailure)
            assertTrue(Thread.currentThread().isInterrupted)
        } finally {
            Thread.interrupted()
        }
    }

    @Test
    fun nativeBoundaryDoesNotSwallowFatalErrors() {
        val failure = AssertionError("synthetic invariant failure")
        assertSame(failure, runCatching { embeddedCall<Unit> { throw failure } }.exceptionOrNull())
    }
}
