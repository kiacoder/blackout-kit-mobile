package com.blackoutkit.vpn

import java.io.File
import java.net.InetAddress
import java.net.ServerSocket
import java.nio.file.Files
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/** Real JVM/process/socket tests, independent of Android and Gradle/JUnit. */
fun main() {
    var passed = 0
    fun test(name: String, block: () -> Unit) {
        block()
        println("PASS $name")
        passed++
    }
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
                check(release.await(3, TimeUnit.SECONDS))
                events.add("start returned")
                true
            }, { events.add("stale completion") })
            check(entered.await(3, TimeUnit.SECONDS))
            session.stop({ events.add("stop"); stopped.countDown() })
            check(!stopped.await(50, TimeUnit.MILLISECONDS))
            release.countDown()
            check(stopped.await(3, TimeUnit.SECONDS))
            while (true) (callbacks.poll() ?: break).invoke()
            check("stale completion" !in events)
            check(events.indexOf("stop") > events.indexOf("start returned"))
        } finally { release.countDown(); session.stop({}, close = true) }
    }
    test("session cleanup failure blocks engine start") {
        val done = CountDownLatch(1)
        val session = VpnSessionExecutor({ it() })
        var started = false
        var succeeded = true
        try {
            session.start({ throw IllegalStateException("private detail") }, {
                started = true; true
            }, { succeeded = it; done.countDown() })
            check(done.await(3, TimeUnit.SECONDS))
            check(!started && !succeeded)
        } finally { session.stop({}, close = true) }
    }
    test("session stop reports cleanup failure and closed owner rejects starts") {
        val done = CountDownLatch(1)
        val session = VpnSessionExecutor({ it() })
        var cleaned = true
        session.stop({ throw UnsatisfiedLinkError() }, { current, result ->
            check(current); cleaned = result; done.countDown()
        }, close = true)
        check(done.await(3, TimeUnit.SECONDS))
        check(!cleaned)
        check(session.start({}, { true }, {}) == null)
    }
    test("native child stop does not signal an already-reaped PID") {
        check(NativeChildStop({ 0 }, { error("TERM after reap") }, { error("KILL after reap") }).stop(42))
    }
    test("native child stop escalates with bounded failure") {
        var clock = 0L
        val signals = mutableListOf<String>()
        val stopped = NativeChildStop({ -1 }, { signals.add("TERM") }, { signals.add("KILL") },
            { clock += it * 1_000_000 }, { clock }).stop(42, 50)
        check(!stopped && signals == listOf("TERM", "KILL"))
        check(clock == 100_000_000L)
    }
    test("native child stop restores interrupt after forced cleanup") {
        var alive = true
        var sleeps = 0
        val stopper = NativeChildStop({ if (alive) -1 else 0 }, {}, { alive = false }, {
            sleeps++; throw InterruptedException()
        })
        try {
            check(stopper.stop(42, 50))
            check(!alive && sleeps == 1 && Thread.currentThread().isInterrupted)
        } finally { Thread.interrupted() }
    }
    test("native child stop handles a real process without blocking waitpid") {
        val child = ProcessBuilder("/bin/sh", "-c", "exec sleep 30").start()
        try {
            val stopper = NativeChildStop({ if (child.isAlive) -1 else child.exitValue() },
                { child.destroy() }, { child.destroyForcibly(); Unit })
            check(stopper.stop(42, 100))
            check(!child.isAlive)
        } finally { child.destroyForcibly().waitFor() }
    }
    val runner = BoundedEngineCommand()
    test("command success") { check(runner.execute(listOf("/bin/sh", "-c", "exit 0")).succeeded) }
    test("command nonzero") { check(runner.execute(listOf("/bin/sh", "-c", "exit 7")).exitCode == 7) }
    test("missing executable") { check(runner.execute(listOf("/does/not/exist")).launchFailed) }
    test("silent hung command is killed at deadline") {
        val start = System.nanoTime()
        check(runner.execute(listOf("/bin/sh", "-c", "exec sleep 30"), 100).timedOut)
        check((System.nanoTime() - start) / 1_000_000 < 2000)
    }
    test("unbounded diagnostic producer cannot fill pipe or memory") {
        check(runner.execute(listOf("/bin/sh", "-c", "while :; do printf 'SECRET_DIAGNOSTIC_1234567890'; done"), 100).timedOut)
    }
    test("interruption kills child and restores interrupt flag") {
        val complete = CountDownLatch(1)
        var outcome: CommandOutcome? = null
        var restored = false
        val thread = Thread {
            outcome = runner.execute(listOf("/bin/sh", "-c", "exec sleep 30"), 30000)
            restored = Thread.currentThread().isInterrupted
            complete.countDown()
        }
        thread.start()
        Thread.sleep(100)
        thread.interrupt()
        check(complete.await(2, TimeUnit.SECONDS))
        check(outcome?.interrupted == true && restored)
    }
    test("no credential-bearing diagnostics in result") {
        val result = runner.execute(listOf("/bin/sh", "-c", "echo private_key=SECRET; exit 1"))
        check(!result.toString().contains("SECRET"))
    }
    test("sing-box command contract") {
        val cmd = EngineCommands.SING_BOX.check(File("/engine"), File("/private/config.json"))
        check(cmd == listOf("/engine", "check", "-c", "/private/config.json"))
    }
    test("Mihomo native check contract") {
        check(EngineCommands.MIHOMO.check(File("/engine"), File("/private/config.json")) ==
            listOf("/engine", "-t", "-d", "/private", "-f", "/private/config.json"))
    }
    test("Mihomo run contract does not run test mode") {
        check("-t" !in EngineCommands.MIHOMO.run(File("/engine"), File("/private/config.json")))
    }
    test("unsupported protocols cannot silently use sing-box") {
        for (protocol in listOf("wireguard", "amneziawg", "shadowtls", "hysteria", "openvpn"))
            check(EngineCommands.forProtocol(protocol) == null)
    }
    test("known protocol mapping") {
        check(EngineCommands.forProtocol("HYSTERIA2") == EngineCommands.SING_BOX)
        check(EngineCommands.forProtocol("mihomo") == EngineCommands.MIHOMO)
    }
    val directory = Files.createTempDirectory("blackout-host-test").toFile()
    try {
        val config = File(directory, "profile.json").apply { writeText("{}") }
        val checker = File(directory, "checker").apply { writeText("#!/bin/sh\nexit 0\n"); setExecutable(true) }
        val validator = NativeConfigValidator()
        test("validator success from test double is distinct from connectivity") {
            val result = validator.validate(EngineCommands.MIHOMO, checker, config)
            check(result.valid && result.code == "NATIVE_VALIDATED")
            check(result.message.contains("connectivity is not tested"))
        }
        test("validator missing engine") {
            check(validator.validate(EngineCommands.MIHOMO, File(directory, "absent"), config).code == "RUNTIME_UNAVAILABLE")
        }
        test("validator empty profile") {
            check(validator.validate(EngineCommands.MIHOMO, checker, File(directory, "empty").apply { writeText("") }).code == "INVALID_INPUT")
        }
        test("validator oversized profile") {
            val large = File(directory, "large").apply { java.io.RandomAccessFile(this, "rw").use { it.setLength(8 * 1024 * 1024 + 1) } }
            check(validator.validate(EngineCommands.MIHOMO, checker, large).code == "INVALID_INPUT")
        }
        test("native checker rejection is not success") {
            checker.writeText("#!/bin/sh\necho SECRET\nexit 23\n")
            val result = validator.validate(EngineCommands.MIHOMO, checker, config)
            check(!result.valid && result.code == "CONFIG_REJECTED" && !result.message.contains("SECRET"))
        }
        test("native checker timeout") {
            checker.writeText("#!/bin/sh\nexec sleep 30\n")
            check(validator.validate(EngineCommands.MIHOMO, checker, config, 100).code == "CHECK_TIMEOUT")
        }
    } finally { directory.deleteRecursively() }
    test("lifecycle detects exited process") {
        val process = ProcessBuilder("/bin/sh", "-c", "exit 3").start()
        process.waitFor()
        check(SubprocessLifecycle().awaitStartup(listOf(process), 10) != null)
    }
    test("lifecycle stops real process ignoring TERM") {
        val process = ProcessBuilder("/bin/sh", "-c", "trap '' TERM; echo ready; while :; do :; done").start()
        try {
            check(process.inputStream.bufferedReader().readLine() == "ready")
            SubprocessLifecycle().stop(listOf(process), 100)
            check(!process.isAlive)
        } finally { process.destroyForcibly() }
    }
    test("lifecycle preserves interrupt during cleanup") {
        val process = ProcessBuilder("/bin/sh", "-c", "exec sleep 30").start()
        try {
            Thread.currentThread().interrupt()
            SubprocessLifecycle().stop(listOf(process), 100)
            check(Thread.currentThread().isInterrupted)
        } finally {
            Thread.interrupted()
            process.destroyForcibly().waitFor()
        }
    }
    test("real loopback SOCKS handshake") {
        ServerSocket(0, 1, InetAddress.getByName("127.0.0.1")).use { server ->
            var error: Throwable? = null
            val thread = Thread {
                try {
                    server.accept().use { socket ->
                        val input = java.io.DataInputStream(socket.getInputStream())
                        val greeting = ByteArray(3)
                        input.readFully(greeting)
                        check(greeting.contentEquals(byteArrayOf(5, 1, 0)))
                        socket.getOutputStream().write(byteArrayOf(5, 0))
                    }
                } catch (failure: Throwable) { error = failure }
            }.apply { start() }
            check(LocalSocksReadiness.await("127.0.0.1", server.localPort, 1000))
            thread.join(1500)
            check(!thread.isAlive && error == null)
        }
    }
    test("unavailable SOCKS endpoint") {
        val port = ServerSocket(0).use { it.localPort }
        check(!LocalSocksReadiness.await("127.0.0.1", port, 100))
    }
    println("$passed host tests passed. No Android TUN or real VPN engine was tested.")
}
