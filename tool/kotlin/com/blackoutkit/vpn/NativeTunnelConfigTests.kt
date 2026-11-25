package com.blackoutkit.vpn

private const val TEST_KEY_BYTES = 32

fun main() {
    var passed = 0

    fun test(
        name: String,
        block: () -> Unit,
    ) {
        block()
        passed++
        println("PASS $name")
    }

    validConfigCases(::test)
    invalidConfigCases(::test)
    peerIdentityCases(::test)
    dnsCases(::test)
    println("$passed parser checks passed; not Android integration tests")
}

private const val TEST_KEY = "AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQE="
private val config =
    """
    [Interface]
    PrivateKey = $TEST_KEY
    Address = 10.0.0.2/32, fd00::2/128
    DNS = 10.0.0.1
    [Peer]
    PublicKey = $TEST_KEY
    Endpoint = example.invalid:51820
    AllowedIPs = 0.0.0.0/0, ::/0
    PersistentKeepalive = 25
    """.trimIndent()

private fun reject(
    text: String,
    awg: Boolean = false,
) {
    try {
        NativeTunnelConfig.parse(text, awg)
        error("Accepted invalid config")
    } catch (
        e: IllegalArgumentException,
    ) {
        check(!e.message.orEmpty().contains(TEST_KEY))
    }
}

private fun validConfigCases(test: (String, () -> Unit) -> Unit) {
    test("dual-stack config and endpoint resolution") {
        val parsed = NativeTunnelConfig.parse(config, false)
        val uapi = parsed.userspace { NativeTunnelConfig.numericAddress("192.0.2.1") }
        check(parsed.addresses.size == 2 && parsed.routes.size == 2)
        check("endpoint=192.0.2.1:51820\n" in uapi)
        check("private_key=${"01".repeat(TEST_KEY_BYTES)}\n" in uapi)
        check(!parsed.toString().contains(TEST_KEY))
    }
    test("IPv6 endpoint bracketing") {
        check(
            "endpoint=[" in
                NativeTunnelConfig.parse(config, false).userspace { NativeTunnelConfig.numericAddress("2001:db8::1") },
        )
    }
    test("AWG and WG remain distinct") {
        val awg = config.replace("Address =", "S4 = 25\nH1 = 1-100\nAddress =")
        reject(awg)
        check(
            "s4=25\n" in
                NativeTunnelConfig.parse(awg, true).userspace { NativeTunnelConfig.numericAddress("192.0.2.1") },
        )
    }
}

private fun invalidConfigCases(test: (String, () -> Unit) -> Unit) {
    test("hooks rejected") { reject(config.replace("Address =", "PostUp = run-command\nAddress =")) }
    test("duplicate keys rejected") { reject(config.replace("Address =", "PrivateKey = $TEST_KEY\nAddress =")) }
    test("bad key rejected") { reject(config.replace(TEST_KEY, "invalid")) }
    test("noncanonical key rejected") { reject(config.replace(TEST_KEY, TEST_KEY.dropLast(2) + "B=")) }
    test("hostname address rejected") { reject(config.replace("10.0.0.2/32", "host.invalid/32")) }
    test("hostname DNS rejected") { reject(config.replace("DNS = 10.0.0.1", "DNS = host.invalid")) }
    test("prefix bounds") { reject(config.replace("10.0.0.2/32", "10.0.0.2/33")) }
    test("port bounds") { reject(config.replace(":51820", ":65536")) }
    test("MTU bounds") { reject(config.replace("Address =", "MTU = 12\nAddress =")) }
    test("NUL rejected") { reject(config + "\u0000") }
    test("unknown field rejected") { reject(config + "\nTable = off") }
    test("network containment") {
        val route = NativeTunnelConfig.parse(config, false).addresses.first()
        check(route.contains(NativeTunnelConfig.numericAddress("10.0.0.2")))
        check(!route.contains(NativeTunnelConfig.numericAddress("10.0.0.3")))
    }
}

private fun peerIdentityCases(test: (String, () -> Unit) -> Unit) {
    val zero = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="
    test("zero private key cannot clear the interface identity") {
        reject(config.replace("PrivateKey = $TEST_KEY", "PrivateKey = $zero"))
    }
    test("zero public key rejected") { reject(config.replace("PublicKey = $TEST_KEY", "PublicKey = $zero")) }
    test("zero preshared key still represents disabled PSK") {
        NativeTunnelConfig.parse(config + "\nPresharedKey = $zero", false)
    }
    test("duplicate peer cannot overwrite earlier allowed IPs") {
        reject(config + "\n[Peer]\nPublicKey = $TEST_KEY\nAllowedIPs = 192.0.2.0/24")
    }
    test("route host bits masked without changing interface address") {
        val parsed = NativeTunnelConfig.parse(config.replace("0.0.0.0/0", "192.0.2.129/24"), false)
        check(parsed.routes.first().text() == "192.0.2.0/24")
        check(parsed.addresses.first().text() == "10.0.0.2/32")
        check("allowed_ip=192.0.2.0/24\n" in parsed.userspace { NativeTunnelConfig.numericAddress("192.0.2.1") })
    }
    test("signed numeric fields rejected") {
        reject(config.replace("PersistentKeepalive = 25", "PersistentKeepalive = +25"))
    }
}

private fun dnsCases(test: (String, () -> Unit) -> Unit) {
    test("dual-stack routed DNS accepted") {
        val parsed = NativeTunnelConfig.parse(config, false)
        check(parsed.routedDns(listOf("10.0.0.1", "2001:db8::1")).size == 2)
    }
    test("DNS outside split routes rejected without disclosing input") {
        val parsed = NativeTunnelConfig.parse(config.replace("0.0.0.0/0, ::/0", "10.0.0.0/24"), false)
        try {
            parsed.routedDns(listOf("192.0.2.53"))
            error("Accepted uncovered DNS")
        } catch (
            e: IllegalArgumentException,
        ) {
            check(!e.message.orEmpty().contains("192.0.2.53"))
        }
    }
    test("empty and non-unicast DNS refused") {
        val parsed = NativeTunnelConfig.parse(config, false)
        for (dns in listOf(emptyList(), listOf("0.0.0.0"), listOf("127.0.0.1"), listOf("ff02::1"))) {
            try {
                parsed.routedDns(dns)
                error("Accepted unsafe DNS")
            } catch (_: IllegalArgumentException) {
            }
        }
    }
}
