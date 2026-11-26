package com.blackoutkit.vpn

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.IOException

class TransientEngineConfigTest {
    @get:Rule
    val folder = TemporaryFolder()

    @Test
    fun releaseRemovesConfigurationAndNextSessionUsesNewPath() {
        val owner = TransientEngineConfig()
        val first = owner.stage(folder.root, "synthetic-first")
        assertEquals("synthetic-first", first.readText())
        owner.release()
        assertFalse(first.exists())
        val second = owner.stage(folder.root, "synthetic-second")
        assertNotEquals(first, second)
        assertEquals("synthetic-second", second.readText())
        owner.release()
        owner.release()
        assertFalse(second.exists())
    }

    @Test
    fun activeConfigurationCannotBeReplaced() {
        val owner = TransientEngineConfig()
        val first = owner.stage(folder.root, "synthetic-original")
        assertTrue(runCatching { owner.stage(folder.root, "replacement") }.isFailure)
        assertEquals("synthetic-original", first.readText())
        owner.release()
    }

    @Test
    fun partialWriteIsDiscardedAndRawErrorIsNotPropagated() {
        var first = true
        val owner =
            TransientEngineConfig(writeConfig = { file, text ->
                file.writeText(text)
                if (first) {
                    first = false
                    throw IOException("synthetic-sensitive-error")
                }
            })
        val failure = runCatching { owner.stage(folder.root.canonicalFile, "synthetic-config") }.exceptionOrNull()
        assertEquals("Engine configuration write failed", failure?.message)
        assertTrue(
            folder.root
                .listFiles()
                .orEmpty()
                .isEmpty(),
        )
        val next = owner.stage(folder.root.canonicalFile, "next-config")
        assertEquals("next-config", next.readText())
        owner.release()
    }

    @Test
    fun failedWriteCleanupRetainsOwnership() {
        val owner =
            TransientEngineConfig(writeConfig = { file, _ ->
                check(file.delete() && file.mkdir())
                throw IOException("synthetic-write-error")
            })
        assertTrue(runCatching { owner.stage(folder.root.canonicalFile, "synthetic") }.isFailure)
        val replaced =
            folder.root
                .listFiles()
                .orEmpty()
                .single()
        assertTrue(replaced.isDirectory)
        assertTrue(runCatching { owner.stage(folder.root.canonicalFile, "next") }.isFailure)
        assertTrue(runCatching { owner.release() }.isFailure)
        assertTrue(replaced.delete())
        owner.release()
    }

    @Test
    fun failedDeletionRetainsOwnershipForRetry() {
        val owner = TransientEngineConfig()
        val file = owner.stage(folder.root, "synthetic-config")
        assertTrue(file.delete())
        assertTrue(file.mkdir())
        val child = file.resolve("child")
        child.writeText("synthetic")
        assertTrue(runCatching { owner.release() }.isFailure)
        assertTrue(runCatching { owner.stage(folder.root, "replacement") }.isFailure)
        assertTrue(child.delete())
        // A replaced directory is never deleted by the config owner.
        assertTrue(runCatching { owner.release() }.isFailure)
        assertTrue(file.isDirectory)
        assertTrue(file.delete())
        owner.release()
        assertFalse(file.exists())
    }
}
