package com.blackoutkit.vpn

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.InputStream
import java.io.OutputStream
import java.util.concurrent.TimeUnit

class SubprocessLifecycleTest {
    @Test
    fun startupFailsWhenChildExitsImmediately() {
        val exited = FakeProcess(alive = false, code = 17)
        val lifecycle = SubprocessLifecycle(isAlive = { it.isAlive })

        val error = lifecycle.awaitStartup(listOf(exited), timeoutMs = 100, pollMs = 1)

        assertEquals("Engine process exited during startup (code 17).", error)
    }

    @Test
    fun startupPassesWhenAllChildrenRemainAliveUntilDeadline() {
        val engine = FakeProcess(alive = true)
        val bridge = FakeProcess(alive = true)
        val lifecycle = SubprocessLifecycle(isAlive = { it.isAlive }, sleep = {})

        assertNull(lifecycle.awaitStartup(listOf(engine, bridge), timeoutMs = 1, pollMs = 1))
    }

    @Test
    fun localSocksReadinessCompletesHandshakeWithoutPublicNetwork() {
        val server = java.net.ServerSocket(0, 1, java.net.InetAddress.getByName("127.0.0.1"))
        val thread =
            Thread {
                server.accept().use { socket ->
                    val greeting = ByteArray(3)
                    socket.getInputStream().read(greeting)
                    assertEquals(listOf<Byte>(0x05, 0x01, 0x00), greeting.toList())
                    socket.getOutputStream().write(byteArrayOf(0x05, 0x00))
                }
            }.apply { start() }

        try {
            assertEquals(true, LocalSocksReadiness.await("127.0.0.1", server.localPort, 1000))
        } finally {
            thread.join(1000)
            server.close()
        }
    }

    @Test
    fun authenticatedReadinessRequiresRfc1929AndExactCredentials() {
        val auth = MihomoLocalAuth.create()
        val other = MihomoLocalAuth.create()
        assertEquals(false, auth.password == other.password)
        assertEquals(64, auth.password.length)
        val server = java.net.ServerSocket(0, 1, java.net.InetAddress.getByName("127.0.0.1"))
        val matched =
            java.util.concurrent.atomic
                .AtomicBoolean(false)
        val thread =
            Thread {
                server.accept().use { socket ->
                    val input = java.io.DataInputStream(socket.getInputStream())
                    val greeting = ByteArray(3)
                    input.readFully(greeting)
                    socket.getOutputStream().write(byteArrayOf(5, 2))
                    val packet = ByteArray(auth.packet().size)
                    input.readFully(packet)
                    matched.set(greeting.contentEquals(byteArrayOf(5, 1, 2)) && packet.contentEquals(auth.packet()))
                    socket.getOutputStream().write(byteArrayOf(1, if (matched.get()) 0 else 1))
                }
            }.apply { start() }
        try {
            assertEquals(true, LocalSocksReadiness.awaitAuthenticated("127.0.0.1", server.localPort, 1000, auth))
            assertEquals(true, matched.get())
        } finally {
            server.close()
            thread.join(1000)
        }
    }

    @Test
    fun authenticatedReadinessRejectsNoAuthDowngrade() {
        val server = java.net.ServerSocket(0, 1, java.net.InetAddress.getByName("127.0.0.1"))
        val thread =
            Thread {
                server.accept().use { socket ->
                    java.io.DataInputStream(socket.getInputStream()).readFully(ByteArray(3))
                    socket.getOutputStream().write(byteArrayOf(5, 0))
                }
            }.apply { start() }
        try {
            assertEquals(
                false,
                LocalSocksReadiness.awaitAuthenticated(
                    "127.0.0.1",
                    server.localPort,
                    100,
                    MihomoLocalAuth.create(),
                ),
            )
        } finally {
            server.close()
            thread.join(1000)
        }
    }

    @Test
    fun localSocksReadinessRejectsUnavailableEndpoint() {
        val server = java.net.ServerSocket(0, 1, java.net.InetAddress.getByName("127.0.0.1"))
        val port = server.localPort
        server.close()

        assertEquals(false, LocalSocksReadiness.await("127.0.0.1", port, 100))
    }

    @Test
    fun monitorDetectsLaterProcessExit() {
        val engine = FakeProcess(alive = false, code = 2)
        val bridge = FakeProcess(alive = true)
        val lifecycle = SubprocessLifecycle(isAlive = { it.isAlive })

        assertNotNull(lifecycle.exitedProcess(listOf(engine, bridge)))
    }

    @Test
    fun stopEscalatesWhenChildIgnoresTerminate() {
        val child = FakeProcess(alive = true, ignoreTerminate = true)
        val lifecycle =
            SubprocessLifecycle(
                waitFor = { process, _ -> !process.isAlive },
                forceStop = { it.destroyForcibly() },
            )
        lifecycle.stop(listOf(child), graceMs = 1)
        assertEquals(true, child.forced)
        assertEquals(false, child.isAlive)
    }

    @Test
    fun stopCleansUpWhenWaitIsInterrupted() {
        val child = FakeProcess(alive = true, ignoreTerminate = true)
        val lifecycle =
            SubprocessLifecycle(
                waitFor = { _, _ -> throw InterruptedException() },
                forceStop = { it.destroyForcibly() },
            )
        try {
            lifecycle.stop(listOf(child))
            assertEquals(true, child.forced)
            assertEquals(true, Thread.currentThread().isInterrupted)
        } finally {
            Thread.interrupted()
        }
    }

    @Test
    fun interruptedWaitStillConfirmsExitAfterEscalation() {
        val child = FakeProcess(alive = true, ignoreTerminate = true)
        var waits = 0
        val lifecycle =
            SubprocessLifecycle(
                waitFor = { process, _ ->
                    waits++
                    if (waits == 1) throw InterruptedException()
                    !process.isAlive
                },
                forceStop = { it.destroyForcibly() },
            )
        try {
            lifecycle.stop(listOf(child))
            assertEquals(2, waits)
            assertEquals(false, child.isAlive)
            assertEquals(true, Thread.currentThread().isInterrupted)
        } finally {
            Thread.interrupted()
        }
    }

    @Test
    fun cleanupFailureDoesNotLoseCallerInterrupt() {
        val child = FakeProcess(alive = true, ignoreTerminate = true)
        val lifecycle =
            SubprocessLifecycle(
                waitFor = { _, _ -> false },
                forceStop = { throw SecurityException("synthetic") },
            )
        Thread.currentThread().interrupt()
        try {
            val result = runCatching { lifecycle.stop(listOf(child)) }
            assertEquals(true, result.isFailure)
            assertEquals(true, child.isAlive)
            assertEquals(true, Thread.currentThread().isInterrupted)
        } finally {
            Thread.interrupted()
        }
    }

    @Test
    fun compatibleWaitRecognizesExitedAndRunningProcesses() {
        val child = FakeProcess(alive = true, code = 7)
        assertEquals(true, ProcessCompat.isAlive(child))
        assertEquals(false, ProcessCompat.waitForExit(child, 0))
        child.destroy()
        assertEquals(true, ProcessCompat.waitForExit(child, 0))
        assertEquals(false, ProcessCompat.isAlive(child))
        assertEquals(7, child.exitValue())
    }

    @Test
    fun compatibleWaitPreservesBoundedTimeout() {
        val child = FakeProcess(alive = true)
        assertEquals(false, ProcessCompat.waitForExit(child, 20))
        assertEquals(true, ProcessCompat.isAlive(child))
    }

    @Test
    fun compatibleWaitIsInterruptible() {
        val child = FakeProcess(alive = true)
        Thread.currentThread().interrupt()
        try {
            try {
                ProcessCompat.waitForExit(child, 1000)
                org.junit.Assert.fail("Expected InterruptedException")
            } catch (_: InterruptedException) {
            }
        } finally {
            Thread.interrupted()
        }
    }

    @Test
    fun outputDrainerConsumesLargeStream() {
        val input = ByteArrayInputStream(ByteArray(1024 * 1024))
        val child = FakeProcess(alive = false, input = input)
        val drainer = ProcessCompat.discardOutput(child)
        drainer.join(1000)
        assertEquals(false, drainer.isAlive)
        assertEquals(0, input.available())
    }

    private class FakeProcess(
        var alive: Boolean,
        private val code: Int = 0,
        private val ignoreTerminate: Boolean = false,
        private val input: InputStream = ByteArrayInputStream(byteArrayOf()),
    ) : Process() {
        override fun getOutputStream(): OutputStream = ByteArrayOutputStream()

        override fun getInputStream(): InputStream = input

        override fun getErrorStream(): InputStream = ByteArrayInputStream(byteArrayOf())

        override fun waitFor(): Int {
            alive = false
            return code
        }

        override fun waitFor(
            timeout: Long,
            unit: TimeUnit,
        ): Boolean {
            alive = false
            return true
        }

        override fun exitValue(): Int = if (alive) throw IllegalThreadStateException() else code

        var forced = false

        override fun destroy() {
            if (!ignoreTerminate) alive = false
        }

        override fun destroyForcibly(): Process {
            forced = true
            alive = false
            return this
        }

        override fun isAlive(): Boolean = alive
    }
}
