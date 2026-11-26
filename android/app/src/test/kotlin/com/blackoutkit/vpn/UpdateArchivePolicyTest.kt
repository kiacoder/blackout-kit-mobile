package com.blackoutkit.vpn

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File

class UpdateArchivePolicyTest {
    @get:Rule
    val temporary = TemporaryFolder()

    @Test
    fun acceptsOnlyNonemptyPrivateApk() {
        val root = temporary.newFolder("updates").canonicalFile
        val apk = File(root, "update.apk").apply { writeText("fixture") }
        assertEquals(apk, UpdateArchivePolicy.resolve(root, apk))
        assertNull(UpdateArchivePolicy.resolve(root, File(root, "missing.apk")))
        assertNull(UpdateArchivePolicy.resolve(root, File(root, "empty.apk").apply { createNewFile() }))
        assertNull(UpdateArchivePolicy.resolve(root, File(root, "wrong.txt").apply { writeText("fixture") }))
        assertNull(UpdateArchivePolicy.resolve(root, File(root, "folder.apk").apply { mkdir() }))
    }

    @Test
    fun rejectsOutsideAndTraversalPaths() {
        val root = temporary.newFolder("updates").canonicalFile
        val outside = File(root.parentFile, "outside.apk").apply { writeText("fixture") }
        assertNull(UpdateArchivePolicy.resolve(root, outside))
        assertNull(UpdateArchivePolicy.resolve(root, File(root, "../outside.apk")))
        val nested = File(root, "nested").apply { mkdir() }
        assertNull(UpdateArchivePolicy.resolve(root, File(nested, "update.apk").apply { writeText("fixture") }))
        val inside = File(root, "update.apk").apply { writeText("fixture") }
        assertNull(UpdateArchivePolicy.resolve(root, File(root, "./${inside.name}")))
    }

    @Test
    fun releaseTagSelectsOnlyExpectedPrivateFile() {
        val root = temporary.newFolder("updates").canonicalFile
        val expected = File(root, "blackout-v1.2.3.apk").apply { writeText("fixture") }
        assertEquals(expected, UpdateArchivePolicy.resolveRelease(root, "v1.2.3"))
        assertNull(UpdateArchivePolicy.resolveRelease(root, "v1.2.4"))
        for (tag in listOf("../v1.2.3", "v1.2.3.apk", "v1.2.3/extra", "file:///v1.2.3", "")) {
            assertFalse(UpdateArchivePolicy.validTag(tag))
            assertNull(UpdateArchivePolicy.resolveRelease(root, tag))
        }
    }

    @Test
    fun nativeDigestRejectsWrongSizeAndSameSizeTamper() {
        val root = temporary.newFolder("updates").canonicalFile
        val bytes = ByteArray(1024 * 1024) { 42 }
        val file = File(root, "blackout-v1.2.3.apk").apply { writeBytes(bytes) }
        val sha =
            "sha256:" +
                java.security.MessageDigest
                    .getInstance("SHA-256")
                    .digest(bytes)
                    .joinToString("") { "%02x".format(it) }
        assertTrue(UpdateArchivePolicy.matchesDigest(file, bytes.size.toLong(), sha))
        assertFalse(UpdateArchivePolicy.matchesDigest(file, bytes.size.toLong() - 1, sha))
        assertFalse(UpdateArchivePolicy.matchesDigest(file, bytes.size.toLong(), "invalid"))
        bytes[0] = 43
        file.writeBytes(bytes)
        assertFalse(UpdateArchivePolicy.matchesDigest(file, bytes.size.toLong(), sha))
    }

    @Test
    fun requiresExactNonemptySignerSet() {
        assertTrue(UpdateArchivePolicy.sameSigners(setOf("a", "b"), setOf("b", "a")))
        assertFalse(UpdateArchivePolicy.sameSigners(setOf("a"), setOf("a", "b")))
        assertFalse(UpdateArchivePolicy.sameSigners(setOf("a", "b"), setOf("a")))
        assertFalse(UpdateArchivePolicy.sameSigners(setOf("a"), setOf("b")))
        assertFalse(UpdateArchivePolicy.sameSigners(emptySet(), emptySet()))
    }
}
