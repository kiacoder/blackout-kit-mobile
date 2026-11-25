package com.blackoutkit.vpn

private const val FIRST_BACKEND_HANDLE = 7
private const val SECOND_BACKEND_HANDLE = 8
private const val IPV4_SOCKET_FD = 11
private const val IPV6_SOCKET_FD = 12
private const val FIRST_TUN_FD = 30
private const val SECOND_TUN_FD = 31

private class FakeNative : NativeTunnelLifecycle.Backend {
    var result = FIRST_BACKEND_HANDLE
    var unresolved = false
    var failStop = false
    var closed = false
    var failHealth = false
    var sockets = listOf(IPV4_SOCKET_FD, IPV6_SOCKET_FD)
    val calls = mutableListOf<String>()

    override fun turnOn(
        fd: Int,
        settings: String,
    ): Int {
        calls.add("on:$fd")
        if (unresolved) throw UnsatisfiedLinkError("synthetic")
        return result
    }

    override fun turnOff(handle: Int) {
        calls.add("off:$handle")
        check(!failStop) { "synthetic" }
    }

    override fun sockets(handle: Int) = sockets

    override fun isClosed(handle: Int): Boolean {
        if (failHealth) throw UnsatisfiedLinkError("synthetic-private-diagnostic")
        return closed
    }
}

fun main() {
    var count = 0

    fun test(
        name: String,
        action: () -> Unit,
    ) {
        action()
        count++
        println("PASS $name")
    }
    test("protect both sockets; close exactly once") {
        val owner = NativeTunnelLifecycle()
        val native = FakeNative()
        val protected = mutableListOf<Int>()
        check(
            owner.start(native, "synthetic", { FIRST_TUN_FD }, { error("double close") }, {
                protected.add(it)
                true
            }),
        )
        check(protected == listOf(IPV4_SOCKET_FD, IPV6_SOCKET_FD))
        owner.stop()
        owner.stop()
        check(native.calls == listOf("on:30", "off:7"))
    }
    test("failed native start already consumed FD") {
        val owner = NativeTunnelLifecycle()
        val native = FakeNative().apply { result = -1 }
        check(!owner.start(native, "", { FIRST_TUN_FD }, { error("double close") }, { error("protect failed start") }))
        owner.stop()
        check(native.calls == listOf("on:30"))
    }
    test("unresolved entry closes undelivered FD") {
        val owner = NativeTunnelLifecycle()
        val native = FakeNative().apply { unresolved = true }
        val closed = mutableListOf<Int>()
        check(!owner.start(native, "", { FIRST_TUN_FD }, { closed.add(it) }, { true }))
        check(closed == listOf(FIRST_TUN_FD))
        owner.stop()
        check(native.calls.size == 1)
    }
    test("protect failure tears down started native device") {
        val owner = NativeTunnelLifecycle()
        val native = FakeNative()
        check(!owner.start(native, "", { FIRST_TUN_FD }, { error("double close") }, { it == IPV4_SOCKET_FD }))
        check(native.calls == listOf("on:30", "off:7"))
        owner.stop()
        check(native.calls.size == 2)
    }
    test("no sockets fails closed") {
        val owner = NativeTunnelLifecycle()
        val native = FakeNative().apply { sockets = listOf(-1, -1) }
        check(!owner.start(native, "", { FIRST_TUN_FD }, {}, { error("bad socket") }))
        check(native.calls.last() == "off:7")
    }
    test("single address family allowed") {
        val owner = NativeTunnelLifecycle()
        val native = FakeNative().apply { sockets = listOf(-1, IPV6_SOCKET_FD) }
        check(
            owner.start(native, "", { FIRST_TUN_FD }, {}, {
                check(it == IPV6_SOCKET_FD)
                true
            }),
        )
        owner.stop()
    }
    test("second start cannot detach or overwrite live owner") {
        val owner = NativeTunnelLifecycle()
        val native = FakeNative()
        check(owner.start(native, "", { FIRST_TUN_FD }, {}, { true }))
        check(!owner.start(FakeNative(), "", { error("leaked duplicate") }, {}, { true }))
        owner.stop()
        check(native.calls.last() == "off:7")
    }
    test("failed stop retains handle and blocks replacement") {
        val owner = NativeTunnelLifecycle()
        val native = FakeNative().apply { failStop = true }
        check(owner.start(native, "", { FIRST_TUN_FD }, {}, { true }))
        val stopFailure = runCatching { owner.stop() }.exceptionOrNull()
        check(stopFailure is IllegalStateException) { "expected stop failure" }
        check(!owner.start(FakeNative(), "", { error("replacement detached") }, {}, { true }))
        native.failStop = false
        owner.stop()
        check(native.calls.count { it == "off:7" } == 2)
    }
    test("restart switches backend only after stop") {
        val owner = NativeTunnelLifecycle()
        val wg = FakeNative()
        val awg = FakeNative().apply { result = SECOND_BACKEND_HANDLE }
        check(owner.start(wg, "", { FIRST_TUN_FD }, {}, { true }))
        owner.stop()
        check(owner.start(awg, "", { SECOND_TUN_FD }, {}, { true }))
        owner.stop()
        check(wg.calls == listOf("on:30", "off:7"))
        check(awg.calls == listOf("on:31", "off:8"))
    }
    test("protection exception is redacted and cleaned") {
        val owner = NativeTunnelLifecycle()
        val native = FakeNative()
        check(!owner.start(native, "", { FIRST_TUN_FD }, {}, { throw IllegalStateException("secret") }))
        check(!owner.lastError.orEmpty().contains("secret"))
        check(native.calls.last() == "off:7")
    }
    test("health reports close without implicitly releasing ownership") {
        val owner = NativeTunnelLifecycle()
        val native = FakeNative()
        check(owner.isClosed())
        check(owner.start(native, "", { FIRST_TUN_FD }, {}, { true }))
        check(!owner.isClosed())
        native.closed = true
        check(owner.isClosed())
        check(native.calls == listOf("on:30"))
        owner.stop()
        check(native.calls.last() == "off:7")
        check(owner.isClosed())
    }
    test("health ABI failure is treated as closed") {
        val owner = NativeTunnelLifecycle()
        val native = FakeNative()
        check(owner.start(native, "", { FIRST_TUN_FD }, {}, { true }))
        native.failHealth = true
        check(owner.isClosed())
        owner.stop()
    }
    test("device already closed during startup never reports success") {
        val owner = NativeTunnelLifecycle()
        val native = FakeNative().apply { closed = true }
        check(!owner.start(native, "", { FIRST_TUN_FD }, { error("double close") }, { true }))
        check(native.calls == listOf("on:30", "off:7"))
        check(owner.isClosed())
    }
    println("$count native ownership checks passed; fake backend, not JNI execution")
}
