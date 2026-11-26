package com.blackoutkit.vpn

import java.io.InputStream
import java.io.OutputStream
import java.security.MessageDigest

/** Verify the exact bytes delivered to a destination before committing them. */
internal object VerifiedApkStream {
    private const val MIN_BYTES = 1024L * 1024
    private const val MAX_BYTES = 256L * 1024 * 1024
    private val digestPattern = Regex("^sha256:[a-f0-9]{64}$")

    fun validMetadata(
        bytes: Long,
        digest: String,
    ): Boolean = bytes in MIN_BYTES..MAX_BYTES && digestPattern.matches(digest)

    fun copy(
        input: InputStream,
        output: OutputStream,
        expectedBytes: Long,
        expectedDigest: String,
    ): Boolean {
        if (!validMetadata(expectedBytes, expectedDigest)) return false
        val hash = MessageDigest.getInstance("SHA-256")
        val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
        var remaining = expectedBytes
        while (remaining > 0) {
            val count = input.read(buffer, 0, minOf(buffer.size.toLong(), remaining).toInt())
            if (count <= 0) break
            output.write(buffer, 0, count)
            hash.update(buffer, 0, count)
            remaining -= count
        }
        return remaining == 0L &&
            input.read() == -1 &&
            "sha256:" + hash.digest().joinToString("") { "%02x".format(it) } == expectedDigest
    }
}
