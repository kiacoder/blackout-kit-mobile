package com.blackoutkit.vpn

import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

class OneShotCallbackSlotTest {
    @Test
    fun staleClearCannotEraseReplacementCallback() {
        val slot = OneShotCallbackSlot<Boolean>()
        val first: (Boolean) -> Unit = {}
        val second: (Boolean) -> Unit = {}

        slot.value = first
        val captured = slot.value
        slot.value = second

        assertFalse(slot.clear(captured))
        assertSame(second, slot.value)
    }

    @Test
    fun takeAtomicallyReturnsAndClearsCallback() {
        val slot = OneShotCallbackSlot<Boolean>()
        val callback: (Boolean) -> Unit = {}
        slot.value = callback

        assertSame(callback, slot.take())
        assertNull(slot.value)
        assertTrue(slot.take() == null)
    }
}
