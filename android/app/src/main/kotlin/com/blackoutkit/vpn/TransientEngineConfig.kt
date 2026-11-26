package com.blackoutkit.vpn

import java.io.File
import java.io.IOException

/**
 * Owns one credential-bearing configuration in an app-private directory.
 * The caller must stop its native reader before releasing the file.
 * A failed deletion retains ownership for a subsequent cleanup attempt.
 */
internal class TransientEngineConfig(
    private val canRelease: (File) -> Boolean = BoundedEngineCommand.process::releaseConfig,
) {
    private var owned: File? = null

    fun stage(
        directory: File,
        text: String,
    ): File {
        check(owned == null) { "Previous engine configuration still needs cleanup" }
        if (!directory.isDirectory && !directory.mkdirs()) {
            throw IOException("Cannot create private engine directory")
        }
        val file = File.createTempFile("session-", ".json", directory)
        owned = file
        file.writeText(text)
        return file
    }

    fun release() {
        val file = owned ?: return
        check(canRelease(file)) { "Engine checker still owns configuration" }
        check(file.delete() || !file.exists()) { "Engine configuration cleanup failed" }
        owned = null
    }
}
