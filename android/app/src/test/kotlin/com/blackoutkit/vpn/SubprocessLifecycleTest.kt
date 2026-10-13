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
        val thread = Thread {
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

    private class FakeProcess(var alive: Boolean, private val code: Int = 0) : Process() {
        override fun getOutputStream(): OutputStream = ByteArrayOutputStream()
        override fun getInputStream(): InputStream = ByteArrayInputStream(byteArrayOf())
        override fun getErrorStream(): InputStream = ByteArrayInputStream(byteArrayOf())
        override fun waitFor(): Int { alive = false; return code }
        override fun waitFor(timeout: Long, unit: TimeUnit): Boolean { alive = false; return true }
        override fun exitValue(): Int = if (alive) throw IllegalThreadStateException() else code
        override fun destroy() { alive = false }
        override fun isAlive(): Boolean = alive
    }
}
