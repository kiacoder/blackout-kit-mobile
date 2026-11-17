package com.blackoutkit.vpn

private class FakeNative : NativeTunnelLifecycle.Backend {
    var result = 7
    var unresolved = false
    var failStop = false
    var closed = false
    var failHealth = false
    var sockets = listOf(11, 12)
    val calls = mutableListOf<String>()
    override fun turnOn(fd: Int, settings: String): Int {
        calls.add("on:$fd")
        if (unresolved) throw UnsatisfiedLinkError("synthetic")
        return result
    }
    override fun turnOff(handle: Int) {
        calls.add("off:$handle")
        if (failStop) throw IllegalStateException("synthetic")
    }
    override fun sockets(handle: Int) = sockets
    override fun isClosed(handle: Int): Boolean {
        if (failHealth) throw UnsatisfiedLinkError("synthetic-private-diagnostic")
        return closed
    }
}

fun main() {
    var count = 0
    fun test(name: String, action: () -> Unit) { action(); count++; println("PASS $name") }
    test("protect both sockets; close exactly once") {
        val owner = NativeTunnelLifecycle(); val native = FakeNative(); val protected = mutableListOf<Int>()
        check(owner.start(native, "synthetic", { 30 }, { error("double close") }, { protected.add(it); true }))
        check(protected == listOf(11, 12)); owner.stop(); owner.stop()
        check(native.calls == listOf("on:30", "off:7"))
    }
    test("failed native start already consumed FD") {
        val owner = NativeTunnelLifecycle(); val native = FakeNative().apply { result = -1 }
        check(!owner.start(native, "", { 30 }, { error("double close") }, { error("protect failed start") }))
        owner.stop(); check(native.calls == listOf("on:30"))
    }
    test("unresolved entry closes undelivered FD") {
        val owner = NativeTunnelLifecycle(); val native = FakeNative().apply { unresolved = true }; val closed = mutableListOf<Int>()
        check(!owner.start(native, "", { 30 }, { closed.add(it) }, { true }))
        check(closed == listOf(30)); owner.stop(); check(native.calls.size == 1)
    }
    test("protect failure tears down started native device") {
        val owner = NativeTunnelLifecycle(); val native = FakeNative()
        check(!owner.start(native, "", { 30 }, { error("double close") }, { it == 11 }))
        check(native.calls == listOf("on:30", "off:7")); owner.stop(); check(native.calls.size == 2)
    }
    test("no sockets fails closed") {
        val owner = NativeTunnelLifecycle(); val native = FakeNative().apply { sockets = listOf(-1, -1) }
        check(!owner.start(native, "", { 30 }, {}, { error("bad socket") }))
        check(native.calls.last() == "off:7")
    }
    test("single address family allowed") {
        val owner = NativeTunnelLifecycle(); val native = FakeNative().apply { sockets = listOf(-1, 12) }
        check(owner.start(native, "", { 30 }, {}, { check(it == 12); true })); owner.stop()
    }
    test("second start cannot detach or overwrite live owner") {
        val owner = NativeTunnelLifecycle(); val native = FakeNative()
        check(owner.start(native, "", { 30 }, {}, { true }))
        check(!owner.start(FakeNative(), "", { error("leaked duplicate") }, {}, { true }))
        owner.stop(); check(native.calls.last() == "off:7")
    }
    test("failed stop retains handle and blocks replacement") {
        val owner = NativeTunnelLifecycle(); val native = FakeNative().apply { failStop = true }
        check(owner.start(native, "", { 30 }, {}, { true }))
        try { owner.stop(); error("expected stop failure") } catch (_: IllegalStateException) {}
        check(!owner.start(FakeNative(), "", { error("replacement detached") }, {}, { true }))
        native.failStop = false; owner.stop(); check(native.calls.count { it == "off:7" } == 2)
    }
    test("restart switches backend only after stop") {
        val owner = NativeTunnelLifecycle(); val wg = FakeNative(); val awg = FakeNative().apply { result = 8 }
        check(owner.start(wg, "", { 30 }, {}, { true })); owner.stop()
        check(owner.start(awg, "", { 31 }, {}, { true })); owner.stop()
        check(wg.calls == listOf("on:30", "off:7")); check(awg.calls == listOf("on:31", "off:8"))
    }
    test("protection exception is redacted and cleaned") {
        val owner = NativeTunnelLifecycle(); val native = FakeNative()
        check(!owner.start(native, "", { 30 }, {}, { throw IllegalStateException("secret") }))
        check(!owner.lastError.orEmpty().contains("secret")); check(native.calls.last() == "off:7")
    }
    test("health reports close without implicitly releasing ownership") {
        val owner = NativeTunnelLifecycle(); val native = FakeNative()
        check(owner.isClosed())
        check(owner.start(native, "", { 30 }, {}, { true }))
        check(!owner.isClosed()); native.closed = true; check(owner.isClosed())
        check(native.calls == listOf("on:30")); owner.stop()
        check(native.calls.last() == "off:7"); check(owner.isClosed())
    }
    test("health ABI failure is treated as closed") {
        val owner = NativeTunnelLifecycle(); val native = FakeNative()
        check(owner.start(native, "", { 30 }, {}, { true }))
        native.failHealth = true; check(owner.isClosed()); owner.stop()
    }
    test("device already closed during startup never reports success") {
        val owner = NativeTunnelLifecycle(); val native = FakeNative().apply { closed = true }
        check(!owner.start(native, "", { 30 }, { error("double close") }, { true }))
        check(native.calls == listOf("on:30", "off:7")); check(owner.isClosed())
    }
    println("$count native ownership checks passed; fake backend, not JNI execution")
}
