package com.blackoutkit.vpn

/** Conservative service-side admission for the first authenticated debug candidate.
 * The native core is still responsible for parsing and cryptographic verification.
 * Reject ambiguous syntax rather than attempting to normalize imported profiles.
 */
internal object OpenVpnCandidateProfile {
    private const val MAX_BYTES = 1024 * 1024
    private const val MAX_LINE = 4096
    private const val MAX_REMOTE_WORDS = 4
    private const val MAX_IDENTITY_WORDS = 3
    private val inline = setOf("ca", "cert", "key", "tls-auth", "tls-crypt", "tls-crypt-v2")
    private val permitted =
        setOf(
            "client",
            "tls-client",
            "dev",
            "dev-type",
            "proto",
            "remote",
            "port",
            "rport",
            "remote-random",
            "resolv-retry",
            "nobind",
            "persist-key",
            "persist-tun",
            "auth",
            "cipher",
            "data-ciphers",
            "data-ciphers-fallback",
            "auth-nocache",
            "auth-user-pass",
            "remote-cert-tls",
            "verify-x509-name",
            "tls-version-min",
            "tls-version-max",
            "tls-cipher",
            "tls-ciphersuites",
            "key-direction",
            "verb",
            "mute",
            "connect-retry",
            "connect-retry-max",
            "connect-timeout",
            "ping",
            "ping-restart",
            "keepalive",
            "tun-mtu",
            "mssfix",
            "pull",
            "redirect-gateway",
            "route",
            "route-ipv6",
            "route-metric",
            "dhcp-option",
            "block-ipv6",
            "float",
            "explicit-exit-notify",
            "reneg-sec",
        )
    private val staticKeys = setOf("tls-auth", "tls-crypt", "tls-crypt-v2")
    private val tag = Regex("^<(/?)([a-z0-9-]+)>$")
    private val safe = Regex("[A-Za-z0-9_:.+/=,@% -]+")
    private val blockText = Regex("[A-Za-z0-9+/=:, -]+")

    fun admits(profile: String): Boolean =
        try {
            require(profile.length <= MAX_BYTES)
            require(profile.toByteArray(Charsets.UTF_8).size <= MAX_BYTES)
            val state = Admission()
            profile.lineSequence().forEach(state::line)
            state.complete()
        } catch (_: IllegalArgumentException) {
            false
        }

    private class Admission {
        private val seen = mutableSetOf<String>()
        private var block: String? = null
        private var hasContent = false
        private var remote = false
        private var tun = false
        private var server = false
        private var interactive = false
        private var exactIdentity = false

        fun line(raw: String) {
            require(raw.length <= MAX_LINE)
            require(raw.all { it in ' '..'~' || it == '\t' })
            val line = raw.trim()
            if (line.isEmpty()) return
            val match = tag.matchEntire(line)
            if (block != null) {
                if (match != null) {
                    require(match.groupValues[1] == "/" && match.groupValues[2] == block && hasContent)
                    block = null
                } else if (!(block in staticKeys && line.startsWith("#"))) {
                    require(blockText.matches(line))
                    hasContent = true
                }
            } else if (match != null) {
                val name = match.groupValues[2]
                require(match.groupValues[1].isEmpty() && name in inline && seen.add(name))
                block = name
                hasContent = false
            } else if (!line.startsWith("#") && !line.startsWith(";")) {
                directive(line)
            }
        }

        private fun directive(line: String) {
            require(safe.matches(line))
            val words = line.split(Regex(" +"))
            val key = words.first()
            require(key in permitted)
            when (key) {
                "dev", "dev-type" -> {
                    require(words == listOf(key, "tun"))
                    tun = true
                }
                "remote-cert-tls" -> {
                    require(words == listOf(key, "server"))
                    server = true
                }
                "verify-x509-name" -> {
                    require(!exactIdentity && words.size in 2..MAX_IDENTITY_WORDS)
                    require(words[1].isNotEmpty())
                    require(words.size == 2 || words[2] in setOf("name", "subject"))
                    exactIdentity = true
                }
                "auth-user-pass" -> {
                    require(words.size == 1 && !interactive)
                    interactive = true
                }
                "remote" -> {
                    require(words.size in 2..MAX_REMOTE_WORDS)
                    remote = true
                }
            }
        }

        fun complete(): Boolean = block == null && remote && tun && server && exactIdentity && authenticationValid()

        private fun authenticationValid(): Boolean {
            val cert = "cert" in seen
            val key = "key" in seen
            return "ca" in seen && cert == key && (cert || interactive)
        }
    }
}
