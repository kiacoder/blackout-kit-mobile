package com.blackoutkit.vpn

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.InputStream

class BoundedImportTest {
    @get:Rule
    val folder = TemporaryFolder()

    @Test
    fun obsoleteImportCleanupOnlyRemovesMatchingRegularFiles() {
        val old = folder.newFile("import-123.cfg")
        val other = folder.newFile("other.cfg")
        val userNamed = folder.newFile("import-example.cfg")
        val nested = folder.newFolder("subfolder")
        val nestedCopy = nested.resolve("import-456.cfg").apply { writeText("fixture") }
        val directory = folder.newFolder("import-789.cfg")

        assertFalse(removeObsoleteImportCopies(folder.root))
        assertFalse(old.exists())
        assertTrue(other.isFile)
        assertTrue(userNamed.isFile)
        assertTrue(nestedCopy.isFile)
        assertTrue(directory.isDirectory)
        assertTrue(directory.delete())
        assertTrue(removeObsoleteImportCopies(folder.root))
    }

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
    fun boundedTextPreservesUnicodeAndRejectsOversizedDocuments() {
        val text = "config-فارسی-中文"
        val bytes = text.toByteArray(Charsets.UTF_8)
        assertEquals(text, readBoundedImportText(ByteArrayInputStream(bytes), bytes.size.toLong()))
        assertEquals(null, readBoundedImportText(ByteArrayInputStream(bytes), bytes.size.toLong() - 1))
    }

    @Test(expected = java.nio.charset.CharacterCodingException::class)
    fun malformedUtf8IsNotAccepted() {
        readBoundedImportText(ByteArrayInputStream(byteArrayOf(0xc3.toByte(), 0x28)), 2)
    }

    @Test
    fun zeroLimitAcceptsOnlyEmptyInput() {
        val output = ByteArrayOutputStream()
        assertTrue(copyBoundedImport(ByteArrayInputStream(byteArrayOf()), output, 0))
        assertFalse(copyBoundedImport(ByteArrayInputStream(byteArrayOf(1)), output, 0))
        assertEquals(0, output.size())
    }
}
