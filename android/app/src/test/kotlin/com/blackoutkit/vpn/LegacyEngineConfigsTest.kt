package com.blackoutkit.vpn

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeNoException
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.IOException
import java.nio.file.Files

class LegacyEngineConfigsTest {
    @get:Rule
    val folder = TemporaryFolder()

    @Test
    fun directCleanupDeletesOnlyGeneratedSessionNames() {
        val direct = folder.newFolder("direct").canonicalFile
        val config = direct.resolve("session-123.json").apply { writeText("fixture") }
        val marker = direct.resolve("session-123.json.tun-ready").apply { writeText("ready") }
        val cache = direct.resolve("cache.db").apply { writeText("fixture") }
        val unrelated = direct.resolve("session-other.json").apply { writeText("fixture") }
        val other = folder.newFile("session-123.json")
        removeDirectMihomoSessions(direct)
        assertFalse(config.exists())
        assertFalse(marker.exists())
        assertTrue(cache.exists())
        assertTrue(unrelated.exists())
        assertTrue(other.exists())
    }

    @Test
    fun directCleanupRefusesSubstitutedDirectory() {
        val direct = folder.newFolder("direct").canonicalFile
        val substituted = direct.resolve("session-123.json").apply { mkdir() }
        assertTrue(runCatching { removeDirectMihomoSessions(direct) }.isFailure)
        assertTrue(substituted.isDirectory)
    }

    @Test
    fun deletesOnlyTheThreeRetiredFixedNames() {
        val obsolete = listOf("singbox.json", "mihomo.json", "singbox-probe.json").map { folder.newFile(it) }
        val current = folder.newFile("session-123.json")
        val unrelated = folder.newFile("unrelated.json")
        removeLegacyEngineConfigs(folder.root)
        assertTrue(obsolete.none { it.exists() })
        assertTrue(current.exists())
        assertTrue(unrelated.exists())
        removeLegacyEngineConfigs(folder.root)
    }

    @Test
    fun neverRecursivelyRemovesDirectory() {
        val directory = folder.newFolder("singbox.json")
        val sentinel = directory.resolve("keep.json")
        sentinel.writeText("synthetic")
        assertTrue(runCatching { removeLegacyEngineConfigs(folder.root) }.isFailure)
        assertTrue(sentinel.exists())
        assertFalse(directory.isFile)
    }

    @Test
    fun refusesReplacementDirectoryLinkBeforeDeletingAnything() {
        val target = folder.newFolder("unrelated")
        val sentinel = target.resolve("singbox.json")
        sentinel.writeText("synthetic")
        val link = folder.root.resolve("engine")
        try {
            Files.createSymbolicLink(link.toPath(), target.toPath())
        } catch (e: IOException) {
            // Windows hosts may lack the privilege to create symlinks.
            assumeNoException(e)
        } catch (e: UnsupportedOperationException) {
            assumeNoException(e)
        }
        assertTrue(runCatching { removeLegacyEngineConfigs(link) }.isFailure)
        assertTrue(sentinel.isFile)
        assertTrue(runCatching { TransientEngineConfig().stage(link, "synthetic") }.isFailure)
        assertTrue(sentinel.readText() == "synthetic")
    }
}
