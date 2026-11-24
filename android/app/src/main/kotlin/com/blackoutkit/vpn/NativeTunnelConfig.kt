package com.blackoutkit.vpn

import java.net.InetAddress

/** Strict, bounded WG/AWG .conf -> UAPI translation. Never execute wg-quick hooks.
 * Not a data class: generated toString must never disclose private keys.
 * Endpoint resolution is explicit and happens before Android installs the TUN.
 */
internal class NativeTunnelConfig private constructor(
    val addresses: List<Network>, val routes: List<Network>, val dns: List<String>,
    val mtu: Int, private val interfaceFields: Map<String, String>,
    private val peers: List<Map<String, String>>,
) {
    class Network(val address: InetAddress, val prefix: Int) {
        fun contains(ip: InetAddress): Boolean {
            val a = address.address; val b = ip.address
            if (a.size != b.size) return false
            for (bit in 0 until prefix) {
                val mask = 1 shl (7 - (bit % 8))
                if ((a[bit / 8].toInt() and mask) != (b[bit / 8].toInt() and mask)) return false
            }
            return true
        }
        fun masked(): Network {
            val bytes = address.address.copyOf()
            for (bit in prefix until bytes.size * 8) {
                bytes[bit / 8] = (bytes[bit / 8].toInt() and (1 shl (7 - (bit % 8))).inv()).toByte()
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
            require(!ip.isAnyLocalAddress && !ip.isLoopbackAddress && !ip.isMulticastAddress &&
                routes.any { route -> route.contains(ip) }) { "DNS server must be unicast and covered by tunnel routes" }
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
                val resolved = try { resolve(host) } catch (_: Exception) { fail() }
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
        private val awgFields = setOf("jc", "jmin", "jmax", "s1", "s2", "s3", "s4", "h1", "h2", "h3", "h4", "i1", "i2", "i3", "i4", "i5")
        private val interfaceKeys = setOf("privatekey", "address", "dns", "mtu", "listenport")
        private val peerKeys = setOf("publickey", "presharedkey", "endpoint", "allowedips", "persistentkeepalive")
        private fun fail(): Nothing = throw IllegalArgumentException("Invalid or unsupported native tunnel configuration")
        private fun number(text: String, max: Long): Long {
            if (!text.matches(Regex("[0-9]+"))) fail()
            return text.toLongOrNull()?.takeIf { it in 0..max } ?: fail()
        }
        fun numericAddress(text: String): InetAddress {
            // Never send configuration address/DNS strings to a hostname resolver.
            if (!(text.matches(Regex("[0-9.]+")) || (':' in text && text.matches(Regex("[0-9a-fA-F:]+"))))) fail()
            if (':' !in text) {
                val parts = text.split('.')
                if (parts.size != 4 || parts.any { it.isEmpty() || number(it, 255) > 255 }) fail()
            }
            return try { InetAddress.getByName(text) } catch (_: Exception) { fail() }
        }
        private fun networks(text: String): List<Network> = text.split(',').map {
            val parts = it.trim().split('/')
            if (parts.size != 2) fail()
            val ip = numericAddress(parts[0])
            Network(ip, number(parts[1], (ip.address.size * 8).toLong()).toInt())
        }
        private fun endpoint(text: String): Pair<String, Int> {
            val at = text.lastIndexOf(':')
            if (at <= 0) fail()
            val rawHost = text.substring(0, at)
            val host = if (rawHost.startsWith('[') && rawHost.endsWith(']')) rawHost.substring(1, rawHost.length - 1) else rawHost
            if (host.isEmpty() || host.any { it.isWhitespace() } || ('/' in host) || ('@' in host)) fail()
            if (':' in host && !rawHost.startsWith('[')) fail()
            val port = number(text.substring(at + 1), 65535).toInt()
            if (port == 0) fail()
            return host to port
        }
        // java.util.Base64 is API26; this decoder keeps the API24 path independent
        // of Android stubs/desugaring and requires canonical 32-byte key encoding.
        private fun keyHex(text: String): String {
            val alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
            if (text.length != 44 || text.last() != '=') fail()
            var bits = 0; var value = 0
            val bytes = ArrayList<Int>(32)
            for (char in text.dropLast(1)) {
                val digit = alphabet.indexOf(char)
                if (digit < 0) fail()
                value = (value shl 6) or digit; bits += 6
                if (bits >= 8) { bits -= 8; bytes.add((value ushr bits) and 255) }
            }
            if (bytes.size != 32 || (value and 3) != 0) fail()
            return bytes.joinToString("") { it.toString(16).padStart(2, '0') }
        }
        fun parse(raw: String, amnezia: Boolean): NativeTunnelConfig {
            if (raw.toByteArray(Charsets.UTF_8).size > 256 * 1024 || raw.contains('\u0000')) fail()
            val interfaceFields = linkedMapOf<String, String>()
            val peers = ArrayList<MutableMap<String, String>>()
            var current: MutableMap<String, String>? = null
            var seenInterface = false
            for (line in raw.lineSequence()) {
                val text = line.substringBefore('#').trim()
                if (text.isEmpty()) continue
                if (text.equals("[Interface]", true)) {
                    if (seenInterface || peers.isNotEmpty()) fail()
                    seenInterface = true; current = interfaceFields; continue
                }
                if (text.equals("[Peer]", true)) {
                    if (!seenInterface || peers.size >= 64) fail()
                    current = linkedMapOf(); peers.add(current); continue
                }
                val target = current ?: fail()
                val at = text.indexOf('='); if (at <= 0) fail()
                val key = text.substring(0, at).trim().lowercase()
                val value = text.substring(at + 1).trim()
                val allowed = if (target === interfaceFields) interfaceKeys + (if (amnezia) awgFields else emptySet()) else peerKeys
                if (key !in allowed || target.containsKey(key) || value.isEmpty() || value.length > 4096) fail()
                target[key] = value
            }
            if (!seenInterface || peers.isEmpty()) fail()
            if (keyHex(interfaceFields["privatekey"] ?: fail()).all { it == '0' }) fail()
            val addresses = networks(interfaceFields["address"] ?: fail())
            val dns = interfaceFields["dns"]?.split(',')?.map { numericAddress(it.trim()).hostAddress!! } ?: emptyList()
            val mtu = interfaceFields["mtu"]?.let { number(it, 9000).toInt().also { n -> if (n < 1280) fail() } } ?: 1420
            interfaceFields["listenport"]?.let { number(it, 65535) }
            for (key in listOf("jc", "jmin", "jmax", "s1", "s2", "s3", "s4")) interfaceFields[key]?.let { number(it, 65535) }
            for (key in listOf("h1", "h2", "h3", "h4")) interfaceFields[key]?.let {
                val range = it.split('-'); if (range.size !in 1..2) fail()
                val values = range.map { n -> number(n, 4294967295L) }
                if (values.size == 2 && values[0] > values[1]) fail()
            }
            val publicKeys = HashSet<String>()
            val routes = peers.flatMap { peer ->
                val publicKey = keyHex(peer["publickey"] ?: fail())
                if (publicKey.all { it == '0' } || !publicKeys.add(publicKey)) fail()
                peer["presharedkey"]?.let { keyHex(it) }
                peer["endpoint"]?.let { endpoint(it) }
                peer["persistentkeepalive"]?.let { number(it, 65535) }
                networks(peer["allowedips"] ?: fail()).map { it.masked() }
            }
            return NativeTunnelConfig(addresses, routes, dns, mtu, interfaceFields, peers)
        }
    }
}
