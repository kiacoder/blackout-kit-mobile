package com.blackoutkit.vpn

import java.io.File

/** Passive packaged capabilities; never load or claim a native runtime. */
internal class EngineCatalogue(
    private val directory: File?,
    private val owner: GoRuntimeAdmission.Family?,
    nativeEnabled: Boolean,
    mihomoEnabled: Boolean,
    openVpnEnabled: Boolean = false,
) {
    private fun bundled(name: String) = directory?.let { File(it, name).isFile } == true

    private val embeddedAllowed = owner != GoRuntimeAdmission.Family.NATIVE_TUNNELS
    private val nativeAllowed = owner != GoRuntimeAdmission.Family.EMBEDDED
    private val embeddedBundled = bundled("libgojni.so")
    private val xrayAvailable = embeddedAllowed && embeddedBundled
    private val singboxSubprocess = listOf("libsingbox.so", "libtun2socks.so", "libfdlauncher.so").all(::bundled)
    private val singboxAvailable = xrayAvailable || singboxSubprocess
    private val nativeBundled = nativeEnabled && bundled("libblackout-tunnels.so")
    private val nativeCandidate = nativeBundled && nativeAllowed
    private val mihomoAvailable =
        mihomoEnabled &&
            listOf("libmihomo.so", "libtun2socks.so", "libfdlauncher.so").all {
                directory?.let { dir -> File(dir, it).canExecute() } == true
            }

    private val openVpnAvailable = openVpnEnabled && bundled("libopenvpn-candidate.so")

    private val xrayProtocols = listOf("vless", "vmess", "trojan", "shadowsocks", "wireguard")
    private val singboxProtocols = listOf("hysteria2", "tuic", "anytls")

    private fun restartRequired(): List<String> =
        buildList {
            if (nativeBundled && !nativeAllowed) {
                add("amneziawg")
                if (!xrayAvailable) add("wireguard")
            }
            if (embeddedBundled && !embeddedAllowed) {
                addAll(xrayProtocols.filter { it != "wireguard" || !nativeCandidate })
                if (!singboxSubprocess) addAll(singboxProtocols)
            }
        }

    private fun unavailableProtocols(): List<String> =
        buildList {
            if (!openVpnAvailable) add("openvpn")
            addAll(listOf("psiphon", "shadowtls", "warp", "sni", "mhrv"))
            if (!nativeCandidate) add("amneziawg")
            if (!singboxAvailable) addAll(singboxProtocols)
        }

    fun report(): Map<String, Any?> =
        mapOf(
            "nativeWireguardAvailable" to nativeCandidate,
            "nativeAmneziawgAvailable" to nativeCandidate,
            "runtimeRestartRequired" to (nativeBundled && embeddedBundled && owner != null),
            "restartRequiredProtocols" to restartRequired(),
            "capabilitySource" to "packaged",
            "mihomoAvailable" to mihomoAvailable,
            "openVpnAvailable" to openVpnAvailable,
            "xrayAvailable" to xrayAvailable,
            "xrayVersion" to null,
            "xrayProtocols" to xrayProtocols,
            "singboxAvailable" to singboxAvailable,
            "singboxVersion" to null,
            // Only protocols the Dart configuration builder can actually describe.
            "singboxProtocols" to
                if (singboxAvailable) {
                    singboxProtocols
                } else {
                    emptyList<String>()
                },
            "unavailableProtocols" to unavailableProtocols(),
            "configurableProtocols" to listOf("sni", "mhrv"),
            "endpointGatedProtocols" to listOf("sni", "mhrv"),
        )
}
