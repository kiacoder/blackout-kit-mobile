package com.blackoutkit.vpn

import java.io.ByteArrayOutputStream
import java.io.File
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import java.nio.ByteBuffer

private const val IMPORT_BUFFER_BYTES = 8192

/** Copies no more than [maxBytes]. False means the input exceeds the limit. */
internal fun copyBoundedImport(
    input: InputStream,
    output: OutputStream,
    maxBytes: Long,
): Boolean {
    require(maxBytes >= 0)
    val buffer = ByteArray(IMPORT_BUFFER_BYTES)
    var remaining = maxBytes
    while (remaining > 0) {
        val count = input.read(buffer, 0, minOf(remaining, buffer.size.toLong()).toInt())
        if (count == -1) return true
        if (count == 0) throw IOException("Import stream did not make progress")
        output.write(buffer, 0, count)
        remaining -= count
    }
    return input.read() == -1
}

/** Reads a bounded text document without creating a temporary file. */
internal fun readBoundedImportText(
    input: InputStream,
    maxBytes: Long,
): String? {
    val output = ByteArrayOutputStream()
    if (!copyBoundedImport(input, output, maxBytes)) return null
    return Charsets.UTF_8
        .newDecoder()
        .decode(ByteBuffer.wrap(output.toByteArray()))
        .toString()
}

private val obsoleteImportName = Regex("import--?[0-9]+\\.cfg")

/** Only obsolete app-created cache copies, never the original selected document. */
internal fun removeObsoleteImportCopies(cache: File): Boolean =
    try {
        val root = cache.canonicalFile
        val copies = root.listFiles { file -> obsoleteImportName.matches(file.name) }
        var clean = copies != null
        for (copy in copies.orEmpty()) {
            if (copy.canonicalFile != copy || !copy.isFile || !copy.delete()) {
                clean = false
            }
        }
        clean
    } catch (_: IOException) {
        false
    } catch (_: SecurityException) {
        false
    }
