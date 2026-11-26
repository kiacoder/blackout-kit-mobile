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
    private val writeConfig: (File, String) -> Unit = { file, text -> file.writeText(text) },
) {
    private var owned: File? = null

    @Synchronized
    fun stage(
        directory: File,
        text: String,
    ): File {
        check(owned == null) { "Previous engine configuration still needs cleanup" }
        val file = File.createTempFile("session-", ".json", privateDirectory(directory))
        owned = file
        writeOwnedFile(file, text)
        return file
    }

    private fun privateDirectory(directory: File): File {
        val absolute = directory.absoluteFile
        // Android may alias the app data root. Resolve the trusted parent,
        // but do not follow a replacement link at the engine-directory name.
        val root = File(absolute.parentFile?.canonicalFile, absolute.name)
        if (root.canonicalFile != root || (!root.isDirectory && !root.mkdirs())) {
            throw IOException("Cannot create private engine directory")
        }
        return root
    }

    private fun writeOwnedFile(
        file: File,
        text: String,
    ) {
        try {
            writeConfig(file, text)
        } catch (_: IOException) {
            discardFailedWrite(file)
            throw IOException("Engine configuration write failed")
        } catch (_: SecurityException) {
            discardFailedWrite(file)
            throw SecurityException("Engine configuration write denied")
        }
    }

    private fun discardFailedWrite(file: File) {
        // No reader has received this path. Retain ownership if deletion fails.
        if (removeOwnedFile(file)) owned = null
    }

    private fun removeOwnedFile(file: File): Boolean =
        try {
            file.canonicalFile == file && (!file.exists() || (file.isFile && file.delete()))
        } catch (_: IOException) {
            false
        } catch (_: SecurityException) {
            false
        }

    @Synchronized
    fun release() {
        val file = owned ?: return
        check(canRelease(file)) { "Engine checker still owns configuration" }
        check(removeOwnedFile(file)) { "Engine configuration cleanup failed" }
        owned = null
    }
}
