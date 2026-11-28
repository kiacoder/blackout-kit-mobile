package com.blackoutkit.vpn

import android.os.Build
import java.io.File
import java.io.IOException
import java.nio.file.Files

private const val NIO_MIN_API = 26

/** Canonical checks cover Android API 24 and 25; newer APIs can detect dangling links.
 * The local JVM's mock Android SDK reports zero; use its available NIO API.
 */
internal fun isPrivateEnginePath(file: File): Boolean =
    file.canonicalFile == file &&
        (Build.VERSION.SDK_INT in 1 until NIO_MIN_API || !Files.isSymbolicLink(file.toPath()))

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

/**
 * Only the direct-Mihomo runner uses this dedicated directory. Call after
 * stopping the owned child, never on the shared engine/probe directory.
 * The native child has a parent-death guard; a previous app process cannot
 * intentionally retain the TUN. Unknown files and directories are untouched.
 */
internal fun removeDirectMihomoSessions(directory: File) {
    val root = privateEngineDirectory(directory)
    val entries = root.listFiles() ?: throw IOException("Cannot inspect direct engine directory")
    val session = Regex("session--?[0-9]+\\.json(\\.tun-ready)?")
    for (file in entries.filter { session.matches(it.name) }) {
        if (!isPrivateEnginePath(file) || !file.isFile || !file.delete()) {
            throw IOException("Stale direct engine session cleanup failed")
        }
    }
}
