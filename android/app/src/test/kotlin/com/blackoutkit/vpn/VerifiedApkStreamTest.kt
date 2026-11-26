package com.blackoutkit.vpn

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.ByteArrayOutputStream
import java.security.MessageDigest

class VerifiedApkStreamTest {
    private val bytes = ByteArray(1024 * 1024) { 42 }
    private val digest =
        "sha256:" + MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }

    @Test
    fun exactBytesAreCopiedAndVerified() {
        val output = ByteArrayOutputStream()
        assertTrue(VerifiedApkStream.copy(bytes.inputStream(), output, bytes.size.toLong(), digest))
        assertArrayEquals(bytes, output.toByteArray())
    }

    @Test
    fun rejectsTruncatedOversizedAndTamperedStreams() {
        val length = bytes.size.toLong()
        assertFalse(
            VerifiedApkStream.copy(bytes.copyOf(bytes.size - 1).inputStream(), ByteArrayOutputStream(), length, digest),
        )
        val output = ByteArrayOutputStream()
        assertFalse(VerifiedApkStream.copy((bytes + 0.toByte()).inputStream(), output, length, digest))
        assertEquals(bytes.size, output.size())
        val modified = bytes.copyOf().apply { this[0] = 1 }
        assertFalse(VerifiedApkStream.copy(modified.inputStream(), ByteArrayOutputStream(), length, digest))
    }

    @Test
    fun rejectsInvalidMetadataBeforeWriting() {
        val output = ByteArrayOutputStream()
        assertFalse(VerifiedApkStream.copy(bytes.inputStream(), output, bytes.size.toLong(), "invalid"))
        assertFalse(VerifiedApkStream.copy(bytes.inputStream(), output, 1, digest))
        assertEquals(0, output.size())
    }

    @Test
    fun rejectsEqualAndOlderVersionCodes() {
        assertTrue(UpdateArchivePolicy.isNewerVersion(2063, 2064))
        assertFalse(UpdateArchivePolicy.isNewerVersion(2063, 2063))
        assertFalse(UpdateArchivePolicy.isNewerVersion(2063, 2062))
        assertFalse(UpdateArchivePolicy.isNewerVersion(0, 2064))
    }
}
