package com.blackoutkit.vpn

import java.io.File
import java.io.IOException

/** Only obsolete fixed names, never current session files or arbitrary cache contents. */
internal fun removeLegacyEngineConfigs(directory: File) {
    val root = directory.canonicalFile
    for (name in listOf("singbox.json", "mihomo.json", "singbox-probe.json")) {
        val candidate = File(root, name)
        if (!candidate.exists()) continue
        if (candidate.canonicalFile != candidate || !candidate.isFile || !candidate.delete()) {
            throw IOException("Legacy engine configuration cleanup failed")
        }
    }
}
