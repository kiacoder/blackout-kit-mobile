package com.blackoutkit.vpn

import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

class OpenVpnCredentialHandoffTest {
    @Test
    fun supportsKeyOnlyAndRejectsIncompleteLogin() {
        val key = OpenVpnCredentials(ByteArray(0), ByteArray(0), byteArrayOf(1))
        assertTrue(key.isValid())
        val token = OpenVpnCredentialHandoff.stage(key)
        OpenVpnCredentialHandoff.discard(token)
        assertFalse(key.isValid())
        val partial = OpenVpnCredentials(byteArrayOf(1), ByteArray(0), byteArrayOf(2))
        assertFalse(partial.isValid())
        partial.clear()
    }

    @Test
    fun consumesOnlyMatchingTokenOnce() {
        val credentials = OpenVpnCredentials(byteArrayOf(1), byteArrayOf(2))
        val token = OpenVpnCredentialHandoff.stage(credentials)
        try {
            assertNull(OpenVpnCredentialHandoff.take("wrong"))
            assertSame(credentials, OpenVpnCredentialHandoff.take(token))
            assertNull(OpenVpnCredentialHandoff.take(token))
        } finally {
            OpenVpnCredentialHandoff.discard(token)
            credentials.clear()
        }
        assertFalse(credentials.isValid())
    }

    @Test
    fun discardWipesAndDoesNotTouchNewOwner() {
        val first = OpenVpnCredentials(byteArrayOf(1), byteArrayOf(2))
        val old = OpenVpnCredentialHandoff.stage(first)
        OpenVpnCredentialHandoff.discard(old)
        assertFalse(first.isValid())
        val second = OpenVpnCredentials(byteArrayOf(3), byteArrayOf(4))
        val next = OpenVpnCredentialHandoff.stage(second)
        try {
            OpenVpnCredentialHandoff.discard(old)
            assertTrue(second.isValid())
        } finally {
            OpenVpnCredentialHandoff.discard(next)
        }
        assertFalse(second.isValid())
    }
}
