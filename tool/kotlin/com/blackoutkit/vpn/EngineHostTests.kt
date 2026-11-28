package com.blackoutkit.vpn

import java.io.File
import java.net.InetAddress
import java.net.ServerSocket
import java.nio.file.Files
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

private const val LATCH_TIMEOUT_SECONDS = 3L
private const val SERIALIZATION_WAIT_MS = 50L
private const val TEST_PID = 42
private const val NANOS_PER_MS = 1_000_000L
private const val SYNTHETIC_GRACE_MS = 50L
private const val REAL_CHILD_GRACE_MS = 100L
private const val EXPECTED_ESCALATION_NS = 100_000_000L
private const val NONZERO_EXIT_CODE = 7
private const val CHECK_TIMEOUT_MS = 100L
private const val MAX_CLEANUP_MS = 2000L
private const val INTERRUPT_COMMAND_TIMEOUT_MS = 30_000L
private const val INTERRUPT_STARTUP_WAIT_MS = 100L
private const val OVERSIZED_PROFILE_BYTES = 8L * 1024 * 1024 + 1
private const val OUTPUT_TEST_TIMEOUT_MS = 3000L
private const val STARTUP_CHECK_MS = 10L
private const val SOCKS_GREETING_SIZE = 3
private const val SOCKS_VERSION = 5
private const val SOCKS_READY_TIMEOUT_MS = 1000
private const val SOCKS_JOIN_TIMEOUT_MS = 1500L
private const val SOCKS_REFUSED_TIMEOUT_MS = 100
private const val DIRECT_READY_TEST_MS = 100L

/** Real JVM/process/socket tests, independent of Android and Gradle/JUnit. */
fun main() {
    var passed = 0

    fun test(
        name: String,
        block: () -> Unit,
    ) {
        block()
        println("PASS $name")
        passed++
    }
    sessionCases(::test)
    sessionFailureCases(::test)
    nativeChildCases(::test)
    commandCases(::test)
    commandContractCases(::test)
    validatorCases(::test)
    processLifecycleCases(::test)
    socksCases(::test)
    directSessionCases(::test)
    println("$passed host tests passed. No Android TUN or real VPN engine was tested.")
}

private fun sessionCases(test: (String, () -> Unit) -> Unit) {
    test("session stop serializes behind blocked start and suppresses stale completion") {
        val entered = CountDownLatch(1)
        val release = CountDownLatch(1)
        val stopped = CountDownLatch(1)
        val callbacks = java.util.concurrent.ConcurrentLinkedQueue<() -> Unit>()
        val events = java.util.concurrent.CopyOnWriteArrayList<String>()
        val session = VpnSessionExecutor({ callbacks.add(it) })
        try {
            session.start({ events.add("cleanup") }, {
                entered.countDown()
                check(release.await(LATCH_TIMEOUT_SECONDS, TimeUnit.SECONDS))
                events.add("start returned")
                true
            }, { events.add("stale completion") })
            check(entered.await(LATCH_TIMEOUT_SECONDS, TimeUnit.SECONDS))
            session.stop({
                events.add("stop")
                stopped.countDown()
            })
            check(!stopped.await(SERIALIZATION_WAIT_MS, TimeUnit.MILLISECONDS))
            release.countDown()
            check(stopped.await(LATCH_TIMEOUT_SECONDS, TimeUnit.SECONDS))
            while (true) (callbacks.poll() ?: break).invoke()
            check("stale completion" !in events)
            check(events.indexOf("stop") > events.indexOf("start returned"))
        } finally {
            release.countDown()
            session.stop({}, close = true)
        }
    }
}

private fun sessionFailureCases(test: (String, () -> Unit) -> Unit) {
    test("session cleanup failure blocks engine start") {
        val done = CountDownLatch(1)
        val session = VpnSessionExecutor({ it() })
        var started = false
        var succeeded = true
        try {
            session.start({ throw IllegalStateException("private detail") }, {
                started = true
                true
            }, {
                succeeded = it
                done.countDown()
            })
            check(done.await(LATCH_TIMEOUT_SECONDS, TimeUnit.SECONDS))
            check(!started && !succeeded)
        } finally {
            session.stop({}, close = true)
        }
    }
    test("session stop reports cleanup failure and closed owner rejects starts") {
        val done = CountDownLatch(1)
        val session = VpnSessionExecutor({ it() })
        var cleaned = true
        session.stop({ throw UnsatisfiedLinkError() }, { current, result ->
            check(current)
            cleaned = result
            done.countDown()
        }, close = true)
        check(done.await(LATCH_TIMEOUT_SECONDS, TimeUnit.SECONDS))
        check(!cleaned)
        check(session.start({}, { true }, {}) == null)
    }
}

private fun nativeChildCases(test: (String, () -> Unit) -> Unit) {
    test("native child stop does not signal an already-reaped PID") {
        check(NativeChildStop({ 0 }, { error("TERM after reap") }, { error("KILL after reap") }).stop(TEST_PID))
    }
    test("native child stop escalates with bounded failure") {
        var clock = 0L
        val signals = mutableListOf<String>()
        val stopped =
            NativeChildStop(
                { -1 },
                { signals.add("TERM") },
                { signals.add("KILL") },
                { clock += it * NANOS_PER_MS },
                { clock },
            ).stop(TEST_PID, SYNTHETIC_GRACE_MS)
        check(!stopped && signals == listOf("TERM", "KILL"))
        check(clock == EXPECTED_ESCALATION_NS)
    }
    test("native child stop restores interrupt after forced cleanup") {
        var alive = true
        var sleeps = 0
        val stopper =
            NativeChildStop({ if (alive) -1 else 0 }, {}, { alive = false }, {
                sleeps++
                throw InterruptedException()
            })
        try {
            check(stopper.stop(TEST_PID, SYNTHETIC_GRACE_MS))
            check(!alive && sleeps == 1 && Thread.currentThread().isInterrupted)
        } finally {
            Thread.interrupted()
        }
    }
    test("native child stop handles a real process without blocking waitpid") {
        val child = ProcessBuilder("/bin/sh", "-c", "exec sleep 30").start()
        try {
            val stopper =
                NativeChildStop(
                    { if (child.isAlive) -1 else child.exitValue() },
                    { child.destroy() },
                    {
                        child.destroyForcibly()
                        Unit
                    },
                )
            check(stopper.stop(TEST_PID, REAL_CHILD_GRACE_MS))
            check(!child.isAlive)
        } finally {
            child.destroyForcibly().waitFor()
        }
    }
}

private fun commandCases(test: (String, () -> Unit) -> Unit) {
    val runner = BoundedEngineCommand()
    test("command success") { check(runner.execute(listOf("/bin/sh", "-c", "exit 0")).succeeded) }
    test("command nonzero") { check(runner.execute(listOf("/bin/sh", "-c", "exit 7")).exitCode == NONZERO_EXIT_CODE) }
    test("missing executable") { check(runner.execute(listOf("/does/not/exist")).launchFailed) }
    test("silent hung command is killed at deadline") {
        val start = System.nanoTime()
        check(runner.execute(listOf("/bin/sh", "-c", "exec sleep 30"), CHECK_TIMEOUT_MS).timedOut)
        check((System.nanoTime() - start) / NANOS_PER_MS < MAX_CLEANUP_MS)
    }
    test("unbounded diagnostic producer cannot fill pipe or memory") {
        check(
            runner
                .execute(
                    listOf("/bin/sh", "-c", "while :; do printf 'SECRET_DIAGNOSTIC_1234567890'; done"),
                    CHECK_TIMEOUT_MS,
                ).timedOut,
        )
    }
    test("interruption kills child and restores interrupt flag") {
        val complete = CountDownLatch(1)
        var outcome: CommandOutcome? = null
        var restored = false
        val thread =
            Thread {
                outcome = runner.execute(listOf("/bin/sh", "-c", "exec sleep 30"), INTERRUPT_COMMAND_TIMEOUT_MS)
                restored = Thread.currentThread().isInterrupted
                complete.countDown()
            }
        thread.start()
        Thread.sleep(INTERRUPT_STARTUP_WAIT_MS)
        thread.interrupt()
        check(complete.await(2, TimeUnit.SECONDS))
        check(outcome?.interrupted == true && restored)
    }
    test("no credential-bearing diagnostics in result") {
        val result = runner.execute(listOf("/bin/sh", "-c", "echo private_key=SECRET; exit 1"))
        check(!result.toString().contains("SECRET"))
    }
}

private fun commandContractCases(test: (String, () -> Unit) -> Unit) {
    test("sing-box command contract") {
        val cmd = EngineCommands.SING_BOX.check(File("/engine"), File("/private/config.json"))
        check(cmd == listOf("/engine", "check", "-c", "/private/config.json"))
    }
    test("Mihomo native check contract") {
        check(
            EngineCommands.MIHOMO.check(File("/engine"), File("/private/config.json")) ==
                listOf("/engine", "-t", "-d", "/private", "-f", "/private/config.json"),
        )
    }
    test("Mihomo run contract does not run test mode") {
        check("-t" !in EngineCommands.MIHOMO.run(File("/engine"), File("/private/config.json")))
    }
    test("unsupported protocols cannot silently use sing-box") {
        for (protocol in listOf("wireguard", "amneziawg", "shadowtls", "hysteria", "openvpn")) {
            check(EngineCommands.forProtocol(protocol) == null)
        }
    }
    test("known protocol mapping") {
        check(EngineCommands.forProtocol("HYSTERIA2") == EngineCommands.SING_BOX)
        check(EngineCommands.forProtocol("mihomo") == EngineCommands.MIHOMO)
    }
}

private fun validatorCases(test: (String, () -> Unit) -> Unit) {
    val directory = Files.createTempDirectory("blackout-host-test").toFile()
    try {
        val config = File(directory, "profile.json").apply { writeText("{}") }
        val checker =
            File(directory, "checker").apply {
                writeText("#!/bin/sh\nexit 0\n")
                setExecutable(true)
            }
        val validator = NativeConfigValidator()
        test("validator success from test double is distinct from connectivity") {
            val result = validator.validate(EngineCommands.MIHOMO, checker, config)
            check(result.valid && result.code == "NATIVE_VALIDATED")
            check(result.message.contains("connectivity is not tested"))
        }
        test("validator missing engine") {
            check(
                validator.validate(EngineCommands.MIHOMO, File(directory, "absent"), config).code ==
                    "RUNTIME_UNAVAILABLE",
            )
        }
        test("validator empty profile") {
            check(
                validator
                    .validate(
                        EngineCommands.MIHOMO,
                        checker,
                        File(directory, "empty").apply { writeText("") },
                    ).code == "INVALID_INPUT",
            )
        }
        test("validator oversized profile") {
            val large =
                File(directory, "large").apply {
                    java.io.RandomAccessFile(this, "rw").use { it.setLength(OVERSIZED_PROFILE_BYTES) }
                }
            check(validator.validate(EngineCommands.MIHOMO, checker, large).code == "INVALID_INPUT")
        }
        test("native checker rejection is not success") {
            checker.writeText("#!/bin/sh\necho SECRET\nexit 23\n")
            val result = validator.validate(EngineCommands.MIHOMO, checker, config)
            check(!result.valid && result.code == "CONFIG_REJECTED" && !result.message.contains("SECRET"))
        }
        test("native checker drains large output without exposing diagnostics") {
            checker.writeText("#!/bin/sh\nhead -c 1048576 /dev/zero\nexit 0\n")
            val result = validator.validate(EngineCommands.MIHOMO, checker, config, OUTPUT_TEST_TIMEOUT_MS)
            check(result.valid && result.code == "NATIVE_VALIDATED")
        }
        test("native checker timeout") {
            checker.writeText("#!/bin/sh\nexec sleep 30\n")
            check(validator.validate(EngineCommands.MIHOMO, checker, config, CHECK_TIMEOUT_MS).code == "CHECK_TIMEOUT")
        }
    } finally {
        directory.deleteRecursively()
    }
}

private fun processLifecycleCases(test: (String, () -> Unit) -> Unit) {
    test("lifecycle detects exited process") {
        val process = ProcessBuilder("/bin/sh", "-c", "exit 3").start()
        process.waitFor()
        check(SubprocessLifecycle().awaitStartup(listOf(process), STARTUP_CHECK_MS) != null)
    }
    test("lifecycle stops real process ignoring TERM") {
        val process = ProcessBuilder("/bin/sh", "-c", "trap '' TERM; echo ready; while :; do :; done").start()
        try {
            check(process.inputStream.bufferedReader().readLine() == "ready")
            SubprocessLifecycle().stop(listOf(process), REAL_CHILD_GRACE_MS)
            check(!process.isAlive)
        } finally {
            process.destroyForcibly()
        }
    }
    test("lifecycle preserves interrupt during cleanup") {
        val process = ProcessBuilder("/bin/sh", "-c", "exec sleep 30").start()
        try {
            Thread.currentThread().interrupt()
            SubprocessLifecycle().stop(listOf(process), REAL_CHILD_GRACE_MS)
            check(Thread.currentThread().isInterrupted)
        } finally {
            Thread.interrupted()
            process.destroyForcibly().waitFor()
        }
    }
}

private fun socksCases(test: (String, () -> Unit) -> Unit) {
    test("real loopback SOCKS handshake") {
        ServerSocket(0, 1, InetAddress.getByName("127.0.0.1")).use { server ->
            var error: Throwable? = null
            val thread =
                Thread {
                    try {
                        server.accept().use { socket ->
                            val input = java.io.DataInputStream(socket.getInputStream())
                            val greeting = ByteArray(SOCKS_GREETING_SIZE)
                            input.readFully(greeting)
                            check(greeting.contentEquals(byteArrayOf(SOCKS_VERSION.toByte(), 1, 0)))
                            socket.getOutputStream().write(byteArrayOf(SOCKS_VERSION.toByte(), 0))
                        }
                    } catch (failure: java.io.IOException) {
                        error = failure
                    } catch (failure: IllegalStateException) {
                        error = failure
                    }
                }.apply { start() }
            check(LocalSocksReadiness.await("127.0.0.1", server.localPort, SOCKS_READY_TIMEOUT_MS))
            thread.join(SOCKS_JOIN_TIMEOUT_MS)
            check(!thread.isAlive && error == null)
        }
    }
    test("unavailable SOCKS endpoint") {
        val port = ServerSocket(0).use { it.localPort }
        check(!LocalSocksReadiness.await("127.0.0.1", port, SOCKS_REFUSED_TIMEOUT_MS))
    }
}

private fun directSessionCases(test: (String, () -> Unit) -> Unit) {
    test("direct readiness requires a valid marker and live child") {
        val directory = Files.createTempDirectory("direct-ready").toFile().canonicalFile
        try {
            val marker = directory.resolve("session-123.json.tun-ready")
            check(!MihomoDirectReadiness.await(marker, DIRECT_READY_TEST_MS) { true })
            marker.writeText("invalid")
            check(!MihomoDirectReadiness.await(marker, DIRECT_READY_TEST_MS) { true })
            marker.writeText("ready\n")
            check(!MihomoDirectReadiness.await(marker, DIRECT_READY_TEST_MS) { false })
            check(MihomoDirectReadiness.await(marker, DIRECT_READY_TEST_MS) { true })
        } finally {
            directory.deleteRecursively()
        }
    }
    test("direct cleanup is scoped to generated session files") {
        val directory = Files.createTempDirectory("direct-cleanup").toFile().canonicalFile
        try {
            val config = directory.resolve("session-123.json").apply { writeText("synthetic") }
            val marker = directory.resolve("session-123.json.tun-ready").apply { writeText("ready") }
            val unrelated = directory.resolve("session-other.json").apply { writeText("keep") }
            removeDirectMihomoSessions(directory)
            check(!config.exists() && !marker.exists() && unrelated.exists())
            val replaced = directory.resolve("session-456.json").apply { mkdir() }
            check(runCatching { removeDirectMihomoSessions(directory) }.isFailure)
            check(replaced.isDirectory)
        } finally {
            directory.deleteRecursively()
        }
    }
}
