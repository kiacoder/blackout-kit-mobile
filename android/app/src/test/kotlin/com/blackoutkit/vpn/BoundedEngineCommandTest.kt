package com.blackoutkit.vpn

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream

class BoundedEngineCommandTest {
    @get:Rule
    val folder = TemporaryFolder()

    private class ResistantProcess : Process() {
        var alive = true

        override fun getOutputStream() = ByteArrayOutputStream()

        override fun getInputStream() = ByteArrayInputStream(byteArrayOf())

        override fun getErrorStream() = ByteArrayInputStream(byteArrayOf())

        override fun waitFor(): Int = exitValue()

        override fun exitValue(): Int {
            if (alive) throw IllegalThreadStateException()
            return 0
        }

        override fun destroy() = Unit
    }

    @Test
    fun unresolvedCheckerRetainsFileAndRejectsAnotherLaunchUntilStopped() {
        val child = ResistantProcess()
        var launches = 0
        val runner =
            BoundedEngineCommand(
                launch = {
                    launches++
                    child
                },
                waitFor = { process, _ -> !ProcessCompat.isAlive(process) },
                forceStop = {},
            )
        val owner = TransientEngineConfig(runner::releaseConfig)
        val file = owner.stage(folder.root, "synthetic")
        val failed = runner.execute(listOf("checker"), 1, file)
        assertTrue(failed.timedOut)
        assertTrue(failed.cleanupPending)
        assertFalse(failed.succeeded)
        assertTrue(runCatching { owner.release() }.isFailure)
        assertTrue(file.exists())
        assertTrue(runner.execute(listOf("checker"), 1).cleanupPending)
        assertEquals(1, launches)
        child.alive = false
        owner.release()
        assertFalse(file.exists())
        assertTrue(runner.execute(listOf("checker"), 1).succeeded)
        assertEquals(2, launches)
    }

    @Test
    fun interruptionRestoresFlagAfterAttemptingCleanup() {
        val child = ResistantProcess()
        val runner =
            BoundedEngineCommand(
                launch = { child },
                waitFor = { process, _ ->
                    if (ProcessCompat.isAlive(process)) throw InterruptedException()
                    true
                },
                forceStop = { child.alive = false },
            )
        try {
            val result = runner.execute(listOf("checker"), 1)
            assertTrue(result.interrupted)
            assertFalse(result.cleanupPending)
            assertTrue(Thread.currentThread().isInterrupted)
        } finally {
            Thread.interrupted()
        }
    }
}
