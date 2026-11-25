package com.blackoutkit.vpn

/**
 * Go c-shared libraries cannot safely be assumed to coexist in one process.
 * The Xray/libbox AAR shares one runtime; native WG/AWG shares another.
 * Claim before any JNI call, and never release: stopping a tunnel does not
 * unload the Go runtime. Failed initialization also retains the claim.
 */
internal class GoRuntimeAdmission {
    enum class Family { EMBEDDED, NATIVE_TUNNELS }

    private var owner: Family? = null

    @Synchronized fun allows(family: Family): Boolean = owner == null || owner == family

    @Synchronized fun claim(family: Family): Boolean {
        if (!allows(family)) return false
        owner = family
        return true
    }

    @Synchronized fun current(): Family? = owner

    companion object {
        val process = GoRuntimeAdmission()
        const val RESTART_REQUIRED =
            "Another VPN runtime is loaded. Fully restart the app before switching runtime families."
    }
}
