package com.blackoutkit.vpn

import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

class OpenVpnCredentialHandoffTest {
    @Test
    fun certificateOnlyPayloadAndBoundedSlot() {
        val token = OpenVpnProfileHandoff.stage("fixture", null)
        try {
            org.junit.Assert.assertThrows(IllegalStateException::class.java) {
                OpenVpnProfileHandoff.stage("other", null)
            }
            val payload = checkNotNull(OpenVpnProfileHandoff.take(token))
            assertNull(payload.credentials)
            payload.clear()
            assertTrue(payload.profile.all { it == 0.toByte() })
        } finally {
            OpenVpnProfileHandoff.discard(token)
        }
        for (profile in listOf("", "a\u0000b", "é".repeat(600_000))) {
            org.junit.Assert.assertThrows(IllegalArgumentException::class.java) {
                OpenVpnProfileHandoff.stage(profile, null)
            }
        }
    }

    @Test
    fun supportsKeyOnlyAndRejectsIncompleteLogin() {
        val key = OpenVpnCredentials(ByteArray(0), ByteArray(0), byteArrayOf(1))
        assertTrue(key.isValid())
        val token = OpenVpnProfileHandoff.stage("fixture", key)
        OpenVpnProfileHandoff.discard(token)
        assertFalse(key.isValid())
        val partial = OpenVpnCredentials(byteArrayOf(1), ByteArray(0), byteArrayOf(2))
        assertFalse(partial.isValid())
        partial.clear()
    }

    @Test
    fun consumesOnlyMatchingTokenOnce() {
        val credentials = OpenVpnCredentials(byteArrayOf(1), byteArrayOf(2))
        val token = OpenVpnProfileHandoff.stage("fixture", credentials)
        try {
            assertNull(OpenVpnProfileHandoff.take("wrong"))
            val payload = checkNotNull(OpenVpnProfileHandoff.take(token))
            assertSame(credentials, payload.credentials)
            assertTrue(payload.profile.contentEquals("fixture".toByteArray()))
            payload.clear()
            assertTrue(payload.profile.all { it == 0.toByte() })
            assertNull(OpenVpnProfileHandoff.take(token))
        } finally {
            OpenVpnProfileHandoff.discard(token)
            credentials.clear()
        }
        assertFalse(credentials.isValid())
    }

    @Test
    fun discardWipesAndDoesNotTouchNewOwner() {
        val first = OpenVpnCredentials(byteArrayOf(1), byteArrayOf(2))
        val old = OpenVpnProfileHandoff.stage("fixture", first)
        OpenVpnProfileHandoff.discard(old)
        assertFalse(first.isValid())
        val second = OpenVpnCredentials(byteArrayOf(3), byteArrayOf(4))
        val next = OpenVpnProfileHandoff.stage("fixture", second)
        try {
            OpenVpnProfileHandoff.discard(old)
            assertTrue(second.isValid())
        } finally {
            OpenVpnProfileHandoff.discard(next)
        }
        assertFalse(second.isValid())
    }
}
