package com.blackoutkit.vpn

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class LegacyEngineConfigsTest {
    @get:Rule
    val folder = TemporaryFolder()

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
}
