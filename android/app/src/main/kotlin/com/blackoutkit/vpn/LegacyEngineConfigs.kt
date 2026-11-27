package com.blackoutkit.vpn

import android.os.Build
import java.io.File
import java.io.IOException
import java.nio.file.Files

private const val NIO_MIN_API = 26

/** Canonical checks cover Android API 24 and 25; newer APIs can also detect dangling links. */
internal fun isPrivateEnginePath(file: File): Boolean =
    file.canonicalFile == file &&
        (Build.VERSION.SDK_INT < NIO_MIN_API || !Files.isSymbolicLink(file.toPath()))

/** Resolve the trusted parent, not a substituted engine-directory symlink. */
internal fun privateEngineDirectory(directory: File): File {
    val absolute = directory.absoluteFile
    val root = File(absolute.parentFile?.canonicalFile, absolute.name)
    if (!isPrivateEnginePath(root) || (!root.isDirectory && !root.mkdirs())) {
        throw IOException("Cannot create private engine directory")
    }
    return root
}

/** Only obsolete fixed names, never current session files or arbitrary cache contents. */
internal fun removeLegacyEngineConfigs(directory: File) {
    val root = privateEngineDirectory(directory)
    for (name in listOf("singbox.json", "mihomo.json", "singbox-probe.json")) {
        val candidate = File(root, name)
        if (!candidate.exists()) continue
        if (!isPrivateEnginePath(candidate) || !candidate.isFile || !candidate.delete()) {
            throw IOException("Legacy engine configuration cleanup failed")
        }
    }
}
