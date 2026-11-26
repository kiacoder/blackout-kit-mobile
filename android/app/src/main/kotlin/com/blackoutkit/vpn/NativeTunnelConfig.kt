package com.blackoutkit.vpn

import java.net.InetAddress

/** Strict, bounded WG/AWG .conf -> UAPI translation. Never execute wg-quick hooks.
 * Not a data class: generated toString must never disclose private keys.
 * Endpoint resolution is explicit and happens before Android installs the TUN.
 */
internal class NativeTunnelConfig private constructor(
    val addresses: List<Network>,
    val routes: List<Network>,
    val dns: List<String>,
    val mtu: Int,
    private val interfaceFields: Map<String, String>,
    private val peers: List<Map<String, String>>,
) {
    class Network(
        val address: InetAddress,
        val prefix: Int,
    ) {
        fun contains(ip: InetAddress): Boolean {
            val a = address.address
            val b = ip.address
            return a.size == b.size &&
                (0 until prefix).all { bit ->
                    val offset = bit % BITS_PER_BYTE
                    val mask = 1 shl (BITS_PER_BYTE - 1 - offset)
                    val byteIndex = bit / BITS_PER_BYTE
                    val left = a[byteIndex].toInt() and mask
                    val right = b[byteIndex].toInt() and mask
                    left == right
                }
        }

        fun masked(): Network {
            val bytes = address.address.copyOf()
            for (bit in prefix until bytes.size * BITS_PER_BYTE) {
                val offset = bit % BITS_PER_BYTE
                val mask = 1 shl (BITS_PER_BYTE - 1 - offset)
                val byteIndex = bit / BITS_PER_BYTE
                bytes[byteIndex] = (bytes[byteIndex].toInt() and mask.inv()).toByte()
            }
            return Network(InetAddress.getByAddress(bytes), prefix)
        }

        fun text() = "${address.hostAddress}/$prefix"
    }

    /** Match the exact routes installed by Android; never fall back to carrier DNS. */
    fun routedDns(servers: List<String>): List<InetAddress> {
        require(servers.isNotEmpty()) { "At least one routed DNS server is required" }
        return servers.map {
            val ip = numericAddress(it)
            require(
                !ip.isAnyLocalAddress &&
                    !ip.isLoopbackAddress &&
                    !ip.isMulticastAddress &&
                    routes.any { route -> route.contains(ip) },
            ) { "DNS server must be unicast and covered by tunnel routes" }
            ip
        }
    }

    fun userspace(resolve: (String) -> InetAddress = { InetAddress.getAllByName(it).first() }): String {
        val output = StringBuilder("private_key=${keyHex(interfaceFields.getValue("privatekey"))}\n")
        interfaceFields["listenport"]?.let { output.append("listen_port=$it\n") }
        for (field in awgFields) interfaceFields[field]?.let { output.append("$field=$it\n") }
        output.append("replace_peers=true\n")
        for (peer in peers) {
            output.append("public_key=${keyHex(peer.getValue("publickey"))}\n")
            peer["presharedkey"]?.let { output.append("preshared_key=${keyHex(it)}\n") }
            peer["endpoint"]?.let {
                val (host, port) = endpoint(it)
                // Keep resolver diagnostics from escaping this boundary: JVM
                // UnknownHostException messages commonly echo the user-supplied host.
                val resolved =
                    try {
                        resolve(host)
                    } catch (_: Exception) {
                        fail()
                    }
                val ip = resolved.hostAddress ?: fail()
                output.append("endpoint=${if (ip.contains(':')) "[$ip]" else ip}:$port\n")
            }
            output.append("replace_allowed_ips=true\n")
            networks(peer.getValue("allowedips")).forEach { output.append("allowed_ip=${it.masked().text()}\n") }
            peer["persistentkeepalive"]?.let { output.append("persistent_keepalive_interval=$it\n") }
        }
        return output.toString()
    }

    companion object {
        private const val BITS_PER_BYTE = 8
        private const val BYTE_MASK = 255
        private const val IPV4_OCTETS = 4
        private const val MAX_U16 = 65535L
        private const val MAX_U32 = 4294967295L
        private const val KEY_BASE64_LENGTH = 44
        private const val KEY_SIZE_BYTES = 32
        private const val BASE64_BITS_PER_CHAR = 6
        private const val BASE64_PAD_BIT_MASK = 3
        private const val HEX_RADIX = 16
        private const val MAX_CONFIG_BYTES = 256 * 1024
        private const val MAX_PEERS = 64
        private const val MAX_FIELD_LENGTH = 4096
        private const val MAX_MTU = 9000L
        private const val MIN_IPV6_MTU = 1280
        private const val DEFAULT_MTU = 1420

        private val awgFields =
            setOf("jc", "jmin", "jmax", "s1", "s2", "s3", "s4", "h1", "h2", "h3", "h4", "i1", "i2", "i3", "i4", "i5")
        private val interfaceKeys = setOf("privatekey", "address", "dns", "mtu", "listenport")
        private val peerKeys = setOf("publickey", "presharedkey", "endpoint", "allowedips", "persistentkeepalive")

        private fun fail(): Nothing =
            throw IllegalArgumentException("Invalid or unsupported native tunnel configuration")

        private fun number(
            text: String,
            max: Long,
        ): Long {
            if (!text.matches(Regex("[0-9]+"))) fail()
            return text.toLongOrNull()?.takeIf { it in 0..max } ?: fail()
        }

        fun numericAddress(text: String): InetAddress {
            // Never send configuration address/DNS strings to a hostname resolver.
            if (!(text.matches(Regex("[0-9.]+")) || (':' in text && text.matches(Regex("[0-9a-fA-F:]+"))))) fail()
            if (':' !in text) {
                val parts = text.split('.')
                if (parts.size != IPV4_OCTETS ||
                    parts.any { it.isEmpty() || number(it, BYTE_MASK.toLong()) > BYTE_MASK }
                ) {
                    fail()
                }
            }
            return try {
                InetAddress.getByName(text)
            } catch (_: Exception) {
                fail()
            }
        }

        private fun networks(text: String): List<Network> =
            text.split(',').map {
                val parts = it.trim().split('/')
                if (parts.size != 2) fail()
                val ip = numericAddress(parts[0])
                Network(ip, number(parts[1], (ip.address.size * BITS_PER_BYTE).toLong()).toInt())
            }

        private fun endpoint(text: String): Pair<String, Int> {
            val at = text.lastIndexOf(':')
            if (at <= 0) fail()
            val rawHost = text.substring(0, at)
            val host =
                if (rawHost.startsWith('[') &&
                    rawHost.endsWith(']')
                ) {
                    rawHost.substring(1, rawHost.length - 1)
                } else {
                    rawHost
                }
            if (host.isEmpty()) fail()
            if (host.any { it.isWhitespace() || it == '/' || it == '@' }) fail()
            if (':' in host && !rawHost.startsWith('[')) fail()
            val port = number(text.substring(at + 1), MAX_U16).toInt()
            if (port == 0) fail()
            return host to port
        }

        // java.util.Base64 is API26; this decoder keeps the API24 path independent
        // of Android stubs/desugaring and requires canonical 32-byte key encoding.
        private fun keyHex(text: String): String {
            val alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
            if (text.length != KEY_BASE64_LENGTH || text.last() != '=') fail()
            var bits = 0
            var value = 0
            val bytes = ArrayList<Int>(KEY_SIZE_BYTES)
            for (char in text.dropLast(1)) {
                val digit = alphabet.indexOf(char)
                if (digit < 0) fail()
                value = (value shl BASE64_BITS_PER_CHAR) or digit
                bits += BASE64_BITS_PER_CHAR
                if (bits >= BITS_PER_BYTE) {
                    bits -= BITS_PER_BYTE
                    bytes.add((value ushr bits) and BYTE_MASK)
                }
            }
            if (bytes.size != KEY_SIZE_BYTES || (value and BASE64_PAD_BIT_MASK) != 0) fail()
            return bytes.joinToString("") { it.toString(HEX_RADIX).padStart(2, '0') }
        }

        fun parse(
            raw: String,
            amnezia: Boolean,
        ): NativeTunnelConfig {
            if (raw.toByteArray(Charsets.UTF_8).size > MAX_CONFIG_BYTES || raw.contains('\u0000')) fail()
            val (interfaceFields, peers) = SectionParser(amnezia).parse(raw)
            if (keyHex(interfaceFields["privatekey"] ?: fail()).all { it == '0' }) fail()
            val addresses = networks(interfaceFields["address"] ?: fail())
            val dns = interfaceFields["dns"]?.split(',')?.map { numericAddress(it.trim()).hostAddress!! } ?: emptyList()
            val mtu = validateInterfaceOptions(interfaceFields)
            val routes = validatePeers(peers)
            return NativeTunnelConfig(addresses, routes, dns, mtu, interfaceFields, peers)
        }

        private class SectionParser(
            amnezia: Boolean,
        ) {
            private val allowedInterfaceKeys = interfaceKeys + (if (amnezia) awgFields else emptySet())
            private val interfaceFields = linkedMapOf<String, String>()
            private val peers = ArrayList<MutableMap<String, String>>()
            private var current: MutableMap<String, String>? = null
            private var seenInterface = false

            fun parse(raw: String): Pair<Map<String, String>, List<Map<String, String>>> {
                for (line in raw.lineSequence()) {
                    consume(line.substringBefore('#').trim())
                }
                if (!seenInterface || peers.isEmpty()) fail()
                return interfaceFields to peers
            }

            private fun consume(text: String) {
                when {
                    text.isEmpty() -> Unit
                    text.equals("[Interface]", true) -> openInterface()
                    text.equals("[Peer]", true) -> openPeer()
                    else -> parseField(text)
                }
            }

            private fun openInterface() {
                if (seenInterface || peers.isNotEmpty()) fail()
                seenInterface = true
                current = interfaceFields
            }

            private fun openPeer() {
                if (!seenInterface || peers.size >= MAX_PEERS) fail()
                val peer = linkedMapOf<String, String>()
                peers.add(peer)
                current = peer
            }

            private fun parseField(text: String) {
                val target = current ?: fail()
                val allowed = if (target === interfaceFields) allowedInterfaceKeys else peerKeys
                val at = text.indexOf('=')
                if (at <= 0) fail()
                val key = text.substring(0, at).trim().lowercase()
                val value = text.substring(at + 1).trim()
                if (key !in allowed || target.containsKey(key)) fail()
                if (value.isEmpty() || value.length > MAX_FIELD_LENGTH) fail()
                target[key] = value
            }
        }

        private fun validateInterfaceOptions(interfaceFields: Map<String, String>): Int {
            val mtu =
                interfaceFields["mtu"]?.let { number(it, MAX_MTU).toInt().also { n -> if (n < MIN_IPV6_MTU) fail() } }
                    ?: DEFAULT_MTU
            interfaceFields["listenport"]?.let { number(it, MAX_U16) }
            for (key in listOf(
                "jc",
                "jmin",
                "jmax",
                "s1",
                "s2",
                "s3",
                "s4",
            )) {
                interfaceFields[key]?.let { number(it, MAX_U16) }
            }
            for (key in listOf("h1", "h2", "h3", "h4")) {
                interfaceFields[key]?.let {
                    val range = it.split('-')
                    if (range.size !in 1..2) fail()
                    val values = range.map { n -> number(n, MAX_U32) }
                    if (values.size == 2 && values[0] > values[1]) fail()
                }
            }
            return mtu
        }

        private fun validatePeers(peers: List<Map<String, String>>): List<Network> {
            val publicKeys = HashSet<String>()
            return peers.flatMap { peer ->
                val publicKey = keyHex(peer["publickey"] ?: fail())
                if (publicKey.all { it == '0' } || !publicKeys.add(publicKey)) fail()
                peer["presharedkey"]?.let { keyHex(it) }
                peer["endpoint"]?.let { endpoint(it) }
                peer["persistentkeepalive"]?.let { number(it, MAX_U16) }
                networks(peer["allowedips"] ?: fail()).map { it.masked() }
            }
        }
    }
}
