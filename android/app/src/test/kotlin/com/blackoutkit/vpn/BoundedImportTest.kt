package com.blackoutkit.vpn

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.InputStream

class BoundedImportTest {
    @Test
    fun acceptsShortAndExactLimit() {
        val bytes = byteArrayOf(1, 2, 3)
        for (limit in listOf(3L, 4L)) {
            val output = ByteArrayOutputStream()
            assertTrue(copyBoundedImport(ByteArrayInputStream(bytes), output, limit))
            assertArrayEquals(bytes, output.toByteArray())
        }
    }

    @Test
    fun oversizedInputNeverWritesBeyondLimit() {
        val input = ByteArrayInputStream(byteArrayOf(1, 2, 3, 4, 5))
        val output = ByteArrayOutputStream()
        assertFalse(copyBoundedImport(input, output, 3))
        assertArrayEquals(byteArrayOf(1, 2, 3), output.toByteArray())
        assertEquals(1, input.available())
    }

    @Test
    fun endlessInputIsBounded() {
        val input =
            object : InputStream() {
                override fun read(): Int = 1
            }
        val output = ByteArrayOutputStream()
        assertFalse(copyBoundedImport(input, output, 16_384))
        assertEquals(16_384, output.size())
    }

    @Test
    fun zeroLimitAcceptsOnlyEmptyInput() {
        val output = ByteArrayOutputStream()
        assertTrue(copyBoundedImport(ByteArrayInputStream(byteArrayOf()), output, 0))
        assertFalse(copyBoundedImport(ByteArrayInputStream(byteArrayOf(1)), output, 0))
        assertEquals(0, output.size())
    }
}
